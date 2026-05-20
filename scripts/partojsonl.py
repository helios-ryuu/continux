#!/usr/bin/env python3
"""Convert NYC TLC Yellow Taxi Parquet rows into JSONL for Vector."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

COLUMNS = {
    "tpep_pickup_datetime": "pickup_time",
    "PULocationID": "pu_location_id",
    "DOLocationID": "do_location_id",
    "fare_amount": "fare_amount",
    "trip_distance": "trip_distance",
}


def json_value(value: Any) -> Any:
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return value


def convert(input_path: Path, output_path: Path, batch_size: int, limit: int | None) -> int:
    import pyarrow.parquet as pq

    parquet = pq.ParquetFile(input_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    written = 0
    with output_path.open("w", encoding="utf-8") as out:
        for batch in parquet.iter_batches(batch_size=batch_size, columns=list(COLUMNS)):
            data = batch.to_pydict()
            row_count = len(next(iter(data.values()), []))

            for index in range(row_count):
                record = {
                    target: json_value(data[source][index])
                    for source, target in COLUMNS.items()
                }

                if record["pickup_time"] is None or record["pu_location_id"] is None:
                    continue

                out.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")))
                out.write("\n")
                written += 1

                if limit is not None and written >= limit:
                    return written

    return written


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert NYC TLC Yellow Taxi Parquet to JSONL for Vector."
    )
    parser.add_argument("input", type=Path, help="Input yellow_tripdata_YYYY-MM.parquet")
    parser.add_argument("output", type=Path, help="Output JSONL file read by Vector")
    parser.add_argument("--batch-size", type=int, default=65536)
    parser.add_argument("--limit", type=int, default=None, help="Optional max rows for a smoke run")
    args = parser.parse_args()

    written = convert(args.input, args.output, args.batch_size, args.limit)
    print(f"Wrote {written} rows to {args.output}")


if __name__ == "__main__":
    main()
