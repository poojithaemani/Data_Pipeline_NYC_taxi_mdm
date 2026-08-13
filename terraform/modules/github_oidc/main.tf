############################################
# GitHub Actions authentication via OIDC
#
# No access keys. GitHub mints a short-lived OIDC token for each workflow run
# and AWS exchanges it for temporary credentials. The security boundary is the
# trust policy: the sub claim pins which repository, and which context within
# it, may assume each role.
#
# Two roles rather than one, because the blast radius differs by an order of
# magnitude:
#
#   plan   assumable from any pull request, read-only
#   apply  assumable only from the protected "production" environment, write
#
# A pull request from a fork can therefore never reach the apply role, and the
# plan role cannot change anything even if a workflow is compromised.
############################################

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  oidc_host  = "token.actions.githubusercontent.com"

  # GitHub emits the subject claim in one of two shapes. The classic form is
  # "repo:owner/name:context". The newer form embeds the immutable numeric
  # account and repository IDs - "repo:owner@1234/name@5678:context" - so that
  # renaming an account or repository cannot be used to impersonate it.
  #
  # Which form arrives is GitHub's decision, not ours, and it can change. Both
  # exact strings are therefore accepted. StringEquals matches on any element
  # of the list, so this is still an exact match against this repository - it
  # is not a wildcard and does not widen the trust boundary.
  plan_subjects = compact([
    "repo:${var.github_repository}:pull_request",
    var.github_repository_immutable != "" ? "repo:${var.github_repository_immutable}:pull_request" : "",
  ])

  apply_subjects = compact([
    "repo:${var.github_repository}:environment:${var.apply_environment}",
    var.github_repository_immutable != "" ? "repo:${var.github_repository_immutable}:environment:${var.apply_environment}" : "",
  ])
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://${local.oidc_host}"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = var.thumbprint_list

  tags = {
    Name        = "${var.project_name}-github-oidc"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

############################################
# Trust policies
############################################

# Any pull request against the repository. Scoped by sub to this repository -
# a workflow in any other repository presents a different sub and is refused.
data "aws_iam_policy_document" "plan_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = local.plan_subjects
    }
  }
}

# Only the "production" GitHub environment, whose required reviewers gate the
# job. The environment name is part of the sub claim, so approval is enforced
# by AWS's trust policy rather than by convention alone.
data "aws_iam_policy_document" "apply_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = local.apply_subjects
    }
  }
}

############################################
# Plan role - read only
############################################

resource "aws_iam_role" "plan" {
  name               = "${var.project_name}-gha-plan"
  description        = "Assumed by GitHub Actions pull-request runs to produce a read-only Terraform plan"
  assume_role_policy = data.aws_iam_policy_document.plan_assume.json

  # A plan takes minutes; there is no reason for the credential to outlive it.
  max_session_duration = 3600

  tags = {
    Name        = "${var.project_name}-gha-plan"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/ReadOnlyAccess"
}

# ReadOnlyAccess covers reading every resource but not decrypting anything, and
# a plan needs to read the state object. Locking is not granted: the plan
# workflow runs with -lock=false precisely so it cannot block an operator.
data "aws_iam_policy_document" "plan_state" {
  statement {
    sid       = "ReadStateObject"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = ["arn:${local.partition}:s3:::${var.tfstate_bucket_name}/*"]
  }

  statement {
    sid       = "ListStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketVersioning"]
    resources = ["arn:${local.partition}:s3:::${var.tfstate_bucket_name}"]
  }

  # Reading tags and configuration of KMS-encrypted resources during refresh.
  statement {
    sid       = "DecryptProjectKey"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "plan_state" {
  name   = "${aws_iam_role.plan.name}-state"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan_state.json
}

############################################
# Apply role - write, gated by the environment
############################################

resource "aws_iam_role" "apply" {
  name               = "${var.project_name}-gha-apply"
  description        = "Assumed by the protected ${var.apply_environment} environment to apply Terraform changes"
  assume_role_policy = data.aws_iam_policy_document.apply_assume.json

  max_session_duration = 3600

  tags = {
    Name        = "${var.project_name}-gha-apply"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# PowerUserAccess covers every service this platform uses but deliberately
# excludes IAM, so the role cannot mint privilege for itself. The IAM it
# genuinely needs is granted below, narrowed to this project's own names.
resource "aws_iam_role_policy_attachment" "apply_poweruser" {
  role       = aws_iam_role.apply.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/PowerUserAccess"
}

data "aws_iam_policy_document" "apply_extra" {
  # Terraform manages this project's own roles and policies, so apply must be
  # able to too - but only those whose names carry the project prefix. It
  # cannot touch an unrelated role, and it cannot attach AdministratorAccess
  # to something outside the prefix.
  statement {
    sid    = "ManageProjectIamPrincipals"
    effect = "Allow"

    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PassRole",
    ]

    resources = [
      "arn:${local.partition}:iam::${local.account_id}:role/${var.project_name}*",
      "arn:${local.partition}:iam::${local.account_id}:role/${var.iam_secondary_prefix}*",
    ]
  }

  statement {
    sid    = "ManageProjectIamPolicies"
    effect = "Allow"

    actions = [
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:TagPolicy",
      "iam:UntagPolicy",
    ]

    resources = [
      "arn:${local.partition}:iam::${local.account_id}:policy/${var.project_name}*",
      "arn:${local.partition}:iam::${local.account_id}:policy/${var.iam_secondary_prefix}*",
    ]
  }

  # The configuration manages the OIDC provider that this very role trusts, so
  # a plan that touches it must not fail on a permissions error.
  statement {
    sid    = "ManageGithubOidcProvider"
    effect = "Allow"

    actions = [
      "iam:GetOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:TagOpenIDConnectProvider",
      "iam:UntagOpenIDConnectProvider",
    ]

    resources = [
      "arn:${local.partition}:iam::${local.account_id}:oidc-provider/${local.oidc_host}",
    ]
  }

  # Apply writes state and takes the S3 lock object.
  statement {
    sid       = "WriteState"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:GetObjectVersion"]
    resources = ["arn:${local.partition}:s3:::${var.tfstate_bucket_name}/*"]
  }

  statement {
    sid       = "ListStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketVersioning"]
    resources = ["arn:${local.partition}:s3:::${var.tfstate_bucket_name}"]
  }
}

resource "aws_iam_role_policy" "apply_extra" {
  name   = "${aws_iam_role.apply.name}-extra"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply_extra.json
}
