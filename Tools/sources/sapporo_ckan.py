from __future__ import annotations

import csv
import json
import re
import urllib.request

from .common import SourceResult, build_record, compact_text, read_url_text

SOURCE_ID = "sapporo_ckan"
SOURCE_NAME = "札幌市オープンデータ CKAN"
SOURCE_TYPE = "ckan"
DEFAULT_DATASET_API_URL = "https://ckan.pf-sapporo.jp/api/3/action/package_show?id=sapporo_bear_appearance"


def fetch(dataset_api_url: str = DEFAULT_DATASET_API_URL, csv_url: str | None = None, csv_text: str | None = None) -> SourceResult:
    text: str
    metadata: dict[str, object]
    if csv_text is not None:
        text = csv_text
        metadata = {"sourceURL": "local"}
    elif csv_url:
        text = read_url_text(csv_url)
        metadata = {"sourceURL": csv_url, "sourceResourceUrl": csv_url}
    else:
        dataset = _load_dataset(dataset_api_url)
        resource = _select_latest_csv_resource(dataset)
        csv_url = str(resource["url"])
        text = read_url_text(csv_url)
        metadata = {
            "datasetApiUrl": dataset_api_url,
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
            "sourceURL": csv_url,
        }

    records = [_normalize_row(row, str(metadata.get("sourceURL") or "")) for row in csv.DictReader(text.splitlines())]
    return SourceResult(
        source_id=SOURCE_ID,
        name=SOURCE_NAME,
        source_type=SOURCE_TYPE,
        source_url=str(metadata.get("sourceURL") or ""),
        records=[record for record in records if record],
        extra=metadata,
    )


def _load_dataset(api_url: str) -> dict[str, object]:
    with urllib.request.urlopen(api_url, timeout=30) as response:
        data = json.loads(response.read().decode("utf-8"))
    if not data.get("success"):
        raise RuntimeError("CKAN APIからデータセット情報を取得できませんでした。")
    result = data.get("result")
    if not isinstance(result, dict):
        raise RuntimeError("CKAN APIの応答形式が想定と違います。")
    return result


def _extract_year(resource: dict[str, object]) -> int:
    text = " ".join(str(resource.get(key, "")) for key in ("name", "url", "description"))
    years = [int(match.group(1)) for match in re.finditer(r"(20\d{2})", text)]
    return max(years) if years else 0


def _resource_position(resource: dict[str, object]) -> int:
    try:
        return int(resource.get("position") or 999)
    except (TypeError, ValueError):
        return 999


def _select_latest_csv_resource(dataset: dict[str, object]) -> dict[str, object]:
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
        key=lambda resource: (_extract_year(resource), -_resource_position(resource)),
        reverse=True,
    )[0]


def _normalize_row(row: dict[str, str], source_url: str) -> dict | None:
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

    ward = row.get("区", "").strip()
    place = compact_text(row.get("出没場所", ""))
    detail = compact_text(row.get("状況", ""))
    return build_record(
        source_id=SOURCE_ID,
        date=date,
        time=row.get("時刻", "").strip(),
        municipality="札幌市",
        area=ward,
        location_text=place,
        description=detail,
        latitude=lat_value,
        longitude=lon_value,
        source_name=SOURCE_NAME,
        source_url=source_url,
        source_type=SOURCE_TYPE,
    )
