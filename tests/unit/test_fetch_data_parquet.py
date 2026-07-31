import importlib.util
import tempfile
import unittest
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[2]


def load_module(module_name: str, relative_path: str):
    module_path = ROOT / relative_path
    spec = importlib.util.spec_from_file_location(module_name, module_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class FetchDataParquetTests(unittest.TestCase):
    def test_fetch_data_supports_local_parquet_files(self) -> None:
        config_module = load_module("ingestion_config_loader", "pipeline/ingestion/config_loader.py")
        fetch_module = load_module("ingestion_fetch_data", "pipeline/ingestion/fetch_data.py")

        with tempfile.TemporaryDirectory() as tmp_dir:
            parquet_path = Path(tmp_dir) / "sample.parquet"
            expected = pd.DataFrame({"id": [1, 2], "name": ["Alice", "Bob"]})
            expected.to_parquet(parquet_path, index=False)

            source_config = config_module.SourceConfig(
                type="parquet",
                source=str(parquet_path),
                primary_key="id",
                destination_table="sample_table",
                required_columns=["id", "name"],
            )

            dataframe = fetch_module.fetch_data(source_config)

            self.assertEqual(dataframe.shape[0], 2)
            self.assertEqual(list(dataframe.columns), ["id", "name"])
            self.assertEqual(dataframe.iloc[0]["name"], "Alice")


if __name__ == "__main__":
    unittest.main()
