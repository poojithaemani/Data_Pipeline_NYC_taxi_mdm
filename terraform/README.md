Terraform notes for Data_Pipeline_NYC_taxi_mdm

Security: Secrets handling

This repository intentionally does NOT store sensitive values (for example, database passwords) in version control.

How to provide sensitive Terraform variables (example: master_password):

1) Environment variable (recommended for local development)

   export TF_VAR_master_password="<your-db-password>"

   Terraform will pick up any TF_VAR_<name> environment variables as input variables.

2) terraform.tfvars.local (ignored by .gitignore)

   Create a file named terraform.tfvars.local in the terraform/ folder with your sensitive values, for example:

   master_password = "<your-db-password>"

   The repository's .gitignore already excludes *.tfvars files.

3) AWS Secrets Manager

   Store the database password in Secrets Manager and provide it to Terraform via a data source or by passing the secret value into the module at apply time. For example, you can use the AWS CLI or the console to create a secret and then provide the secret value to Terraform through environment variables or a secure CI secret.

Notes and recommendations

- Do not commit plain text secrets into the repository.
- For CI/CD, store sensitive values in the GitHub Actions secret store and pass them to Terraform as environment variables or via an encrypted variables mechanism.
- Consider adding a small Terraform data lookup for Secrets Manager in a controlled change when ready to integrate (Phase 8: Security).
