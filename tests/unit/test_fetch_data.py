import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

config_loader_path = ROOT / "pipeline" / "ingestion" / "config_loader.py"
config_spec = importlib.util.spec_from_file_location("ingestion_config_loader", config_loader_path)
config_module = importlib.util.module_from_spec(config_spec)
assert config_spec.loader is not None
config_spec.loader.exec_module(config_module)
SourceConfig = config_module.SourceConfig

fetch_data_path = ROOT / "pipeline" / "ingestion" / "fetch_data.py"
fetch_spec = importlib.util.spec_from_file_location("ingestion_fetch_data", fetch_data_path)
fetch_module = importlib.util.module_from_spec(fetch_spec)
assert fetch_spec.loader is not None
fetch_spec.loader.exec_module(fetch_module)
fetch_data = fetch_module.fetch_data


class FetchDataTests(unittest.TestCase):
    def test_fetch_data_supports_local_csv_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            csv_path = Path(tmp_dir) / "sample.csv"
            csv_path.write_text("id,name\n1,Alice\n2,Bob\n", encoding="utf-8")

            source_config = SourceConfig(
                type="csv",
                source=str(csv_path),
                primary_key="id",
                destination_table="sample_table",
                required_columns=["id", "name"],
            )

            dataframe = fetch_data(source_config)

            self.assertEqual(dataframe.shape[0], 2)
            self.assertEqual(list(dataframe.columns), ["id", "name"])
            self.assertEqual(dataframe.iloc[0]["name"], "Alice")


if __name__ == "__main__":
    unittest.main()
