#!/usr/bin/env python3
"""Convert Sapporo brown bear CSV data into JSON for the app and GitHub Pages."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_DATASET_API_URL = "https://ckan.pf-sapporo.jp/api/3/action/package_show?id=sapporo_bear_appearance"
DEFAULT_OUTPUT = Path("KumaYokeMeter/Resources/bear_sightings.json")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="札幌市ヒグマ出没情報CSVを、SwiftUIアプリで読むJSONへ変換します。"
    )
    parser.add_argument(
        "--dataset-api-url",
        default=DEFAULT_DATASET_API_URL,
        help="最新CSVを探すためのCKAN package_show API URL",
    )
    parser.add_argument("--url", help="取得するCSVのURL。指定時はCKAN API探索を使いません。")
    parser.add_argument("--input", type=Path, help="ローカルCSVを使う場合のパス")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT, help="出力JSONのパス")
    parser.add_argument("--metadata-output", type=Path, help="配信用メタデータJSONの出力先")
    return parser.parse_args()


def read_url_text(url: str) -> str:
    with urllib.request.urlopen(url, timeout=30) as response:
        return response.read().decode("utf-8-sig")


def load_dataset(api_url: str) -> dict[str, object]:
    with urllib.request.urlopen(api_url, timeout=30) as response:
        data = json.loads(response.read().decode("utf-8"))

    if not data.get("success"):
        raise RuntimeError("CKAN APIからデータセット情報を取得できませんでした。")

    result = data.get("result")
    if not isinstance(result, dict):
        raise RuntimeError("CKAN APIの応答形式が想定と違います。")
    return result


def extract_year(resource: dict[str, object]) -> int:
    text = " ".join(
        str(resource.get(key, ""))
        for key in ("name", "url", "description")
    )
    years = [int(match.group(1)) for match in re.finditer(r"(20\d{2})", text)]
    return max(years) if years else 0


def resource_position(resource: dict[str, object]) -> int:
    try:
        return int(resource.get("position") or 999)
    except (TypeError, ValueError):
        return 999


def select_latest_csv_resource(dataset: dict[str, object]) -> dict[str, object]:
    resources = dataset.get("resources")
    if not isinstance(resources, list):
        raise RuntimeError("CKAN APIのresourcesが見つかりません。")

    csv_resources = [
        resource
        for resource in resources
        if isinstance(resource, dict)
        and str(resource.get("format", "")).upper() == "CSV"
        and resource.get("url")
    ]

    if not csv_resources:
        raise RuntimeError("CSVリソースが見つかりません。")

    return sorted(
        csv_resources,
        key=lambda resource: (
            extract_year(resource),
            -resource_position(resource),
        ),
        reverse=True,
    )[0]


def read_csv_text(args: argparse.Namespace) -> tuple[str, dict[str, object]]:
    if args.input:
        return args.input.read_text(encoding="utf-8-sig"), {
            "sourceType": "local",
            "sourcePath": str(args.input),
        }

    if args.url:
        return read_url_text(args.url), {
            "sourceType": "url",
            "sourceResourceUrl": args.url,
        }

    dataset = load_dataset(args.dataset_api_url)
    resource = select_latest_csv_resource(dataset)
    csv_url = str(resource["url"])
    return read_url_text(csv_url), {
        "sourceType": "ckan",
        "datasetApiUrl": args.dataset_api_url,
        "datasetName": dataset.get("name", ""),
        "datasetTitle": dataset.get("title", ""),
        "datasetUrl": dataset.get("url", ""),
        "licenseId": dataset.get("license_id", ""),
        "licenseTitle": dataset.get("license_title", ""),
        "licenseUrl": dataset.get("license_url", ""),
        "sourceResourceId": resource.get("id", ""),
        "sourceResourceName": resource.get("name", ""),
        "sourceResourceUrl": csv_url,
        "sourceResourceLastModified": resource.get("last_modified", ""),
    }


def make_id(row: dict[str, str]) -> str:
    raw = "|".join(
        [
            row.get("日付", ""),
            row.get("時刻", ""),
            row.get("区", ""),
            row.get("出没場所", ""),
            row.get("緯度", ""),
            row.get("経度", ""),
            row.get("状況", ""),
        ]
    )
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()[:16]


def normalize_row(row: dict[str, str]) -> dict[str, object] | None:
    date = row.get("日付", "").strip()
    latitude = row.get("緯度", "").strip()
    longitude = row.get("経度", "").strip()

    if not date or not latitude or not longitude:
        return None

    try:
        lat_value = float(latitude)
        lon_value = float(longitude)
    except ValueError:
        return None

    return {
        "id": make_id(row),
        "date": date,
        "time": row.get("時刻", "").strip(),
        "ward": row.get("区", "").strip(),
        "place": row.get("出没場所", "").strip(),
        "latitude": lat_value,
        "longitude": lon_value,
        "detail": row.get("状況", "").strip(),
        "sourceYear": int(date[:4]),
    }


def main() -> int:
    args = parse_args()
    text, source_metadata = read_csv_text(args)
    rows = csv.DictReader(text.splitlines())
    sightings = [item for row in rows if (item := normalize_row(row))]
    sightings.sort(key=lambda item: (str(item["date"]), str(item["time"])), reverse=True)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(sightings, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    if args.metadata_output:
        latest_date = sightings[0]["date"] if sightings else None
        metadata = {
            "schemaVersion": 1,
            "generatedAt": datetime.now(timezone.utc).isoformat(),
            "recordCount": len(sightings),
            "latestSightingDate": latest_date,
            **source_metadata,
        }
        args.metadata_output.parent.mkdir(parents=True, exist_ok=True)
        args.metadata_output.write_text(
            json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

    print(f"Wrote {len(sightings)} sightings to {args.output}")
    if args.metadata_output:
        print(f"Wrote metadata to {args.metadata_output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
