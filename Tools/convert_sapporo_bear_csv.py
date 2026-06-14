#!/usr/bin/env python3
"""Build the bear sightings feed for the app and GitHub Pages.

The main source is Sapporo CKAN CSV. The official Sapporo bear sightings page is
used as a supplemental source because it can be updated before CKAN CSV.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import html
import json
import math
import re
import sys
import urllib.request
from datetime import datetime, timedelta, timezone
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urljoin


DEFAULT_DATASET_API_URL = "https://ckan.pf-sapporo.jp/api/3/action/package_show?id=sapporo_bear_appearance"
DEFAULT_OFFICIAL_PAGE_URL = "https://www.city.sapporo.jp/kurashi/animal/choju/kuma/syutsubotsu/"
DEFAULT_OUTPUT = Path("KumaYokeMeter/Resources/bear_sightings.json")
JST = timezone(timedelta(hours=9))

CKAN_SOURCE_NAME = "札幌市オープンデータ CKAN"
OFFICIAL_PAGE_SOURCE_NAME = "札幌市公式ヒグマ出没情報ページ"
WARD_NAMES = ["中央区", "北区", "東区", "白石区", "厚別区", "豊平区", "清田区", "南区", "西区", "手稲区"]
WARD_HINTS = {
    "手稲": "手稲区",
    "円山": "中央区",
    "盤渓": "中央区",
    "宮の森": "中央区",
    "羊ケ丘": "豊平区",
    "羊ヶ丘": "豊平区",
    "定山渓": "南区",
    "小金湯": "南区",
    "真駒内": "南区",
    "西野": "西区",
    "平和": "西区",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="札幌市ヒグマ出没情報を、SwiftUIアプリで読むJSONへ変換します。"
    )
    parser.add_argument(
        "--dataset-api-url",
        default=DEFAULT_DATASET_API_URL,
        help="最新CSVを探すためのCKAN package_show API URL",
    )
    parser.add_argument("--url", help="取得するCSVのURL。指定時はCKAN API探索を使いません。")
    parser.add_argument("--input", type=Path, help="ローカルCSVを使う場合のパス")
    parser.add_argument("--official-page-url", default=DEFAULT_OFFICIAL_PAGE_URL, help="補助ソースにする札幌市公式ページURL")
    parser.add_argument("--skip-official-page", action="store_true", help="公式ページの補助取得をスキップ")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT, help="出力JSONのパス")
    parser.add_argument("--metadata-output", type=Path, help="配信用メタデータJSONの出力先")
    return parser.parse_args()


def read_url_text(url: str) -> str:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "kuma-yoke-meter/0.1 (+https://github.com/catgptv5/kuma-yoke-meter)"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
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
            "sourceName": CKAN_SOURCE_NAME,
            "sourceURL": str(args.input),
        }

    if args.url:
        return read_url_text(args.url), {
            "sourceType": "ckan",
            "sourceResourceUrl": args.url,
            "sourceName": CKAN_SOURCE_NAME,
            "sourceURL": args.url,
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
        "sourceName": CKAN_SOURCE_NAME,
        "sourceURL": csv_url,
    }


def compact_text(value: str) -> str:
    return re.sub(r"\s+", " ", html.unescape(value)).strip()


def normalize_for_key(value: str) -> str:
    normalized = compact_text(value).lower()
    normalized = normalized.replace("（", "(").replace("）", ")")
    normalized = normalized.replace("ｰ", "ー").replace("ケ", "ヶ")
    return re.sub(r"[\s　、,。．.・]", "", normalized)


def infer_ward(place: str) -> str:
    for ward in WARD_NAMES:
        if ward in place:
            return ward

    for hint, ward in WARD_HINTS.items():
        if hint in place:
            return ward

    return ""


def make_record_id(record: dict[str, object]) -> str:
    raw = "|".join(
        str(record.get(key, ""))
        for key in ("date", "time", "ward", "place", "latitude", "longitude", "detail")
    )
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()[:16]


def normalize_ckan_row(row: dict[str, str], source_metadata: dict[str, object]) -> dict[str, object] | None:
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

    record = {
        "date": date,
        "time": row.get("時刻", "").strip(),
        "ward": row.get("区", "").strip(),
        "place": compact_text(row.get("出没場所", "")),
        "latitude": lat_value,
        "longitude": lon_value,
        "detail": compact_text(row.get("状況", "")),
        "sourceYear": int(date[:4]),
        "sourceType": "ckan",
        "sourceName": CKAN_SOURCE_NAME,
        "sourceURL": str(source_metadata.get("sourceURL") or source_metadata.get("sourceResourceUrl") or ""),
    }
    record["id"] = make_record_id(record)
    return record


def parse_ckan_records(args: argparse.Namespace) -> tuple[list[dict[str, object]], dict[str, object]]:
    text, source_metadata = read_csv_text(args)
    rows = csv.DictReader(text.splitlines())
    records = [item for row in rows if (item := normalize_ckan_row(row, source_metadata))]
    return records, source_metadata


class TableParser(HTMLParser):
    def __init__(self, base_url: str):
        super().__init__(convert_charrefs=True)
        self.base_url = base_url
        self.tables: list[list[list[dict[str, object]]]] = []
        self._current_table: list[list[dict[str, object]]] | None = None
        self._current_row: list[dict[str, object]] | None = None
        self._current_cell: dict[str, object] | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attributes = dict(attrs)
        if tag == "table":
            self._current_table = []
        elif tag == "tr" and self._current_table is not None:
            self._current_row = []
        elif tag in {"td", "th"} and self._current_row is not None:
            self._current_cell = {"text": [], "links": []}
        elif tag == "a" and self._current_cell is not None and attributes.get("href"):
            links = self._current_cell["links"]
            assert isinstance(links, list)
            links.append(urljoin(self.base_url, attributes["href"] or ""))

    def handle_data(self, data: str) -> None:
        if self._current_cell is not None:
            text_parts = self._current_cell["text"]
            assert isinstance(text_parts, list)
            text_parts.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag in {"td", "th"} and self._current_cell is not None and self._current_row is not None:
            text_parts = self._current_cell["text"]
            assert isinstance(text_parts, list)
            self._current_cell["text"] = compact_text(" ".join(str(part) for part in text_parts))
            self._current_row.append(self._current_cell)
            self._current_cell = None
        elif tag == "tr" and self._current_row is not None and self._current_table is not None:
            if self._current_row:
                self._current_table.append(self._current_row)
            self._current_row = None
        elif tag == "table" and self._current_table is not None:
            self.tables.append(self._current_table)
            self._current_table = None


def parse_japanese_datetime(value: str) -> tuple[str, str] | None:
    match = re.search(
        r"(\d{4})年(\d{1,2})月(\d{1,2})日(?:（[^）]+）)?(?:\s*(\d{1,2})時(\d{1,2})分)?",
        compact_text(value),
    )
    if not match:
        return None

    year, month, day, hour, minute = match.groups()
    date = f"{int(year):04d}-{int(month):02d}-{int(day):02d}"
    time = f"{int(hour):02d}:{int(minute):02d}" if hour and minute else ""
    return date, time


def extract_coordinate(cell: dict[str, object]) -> tuple[float, float] | None:
    links = cell.get("links")
    if not isinstance(links, list):
        return None

    for link in links:
        match = re.search(r"[?&]ll=([0-9.]+),([0-9.]+)", str(link))
        if match:
            return float(match.group(1)), float(match.group(2))

    return None


def table_has_sighting_headers(table: list[list[dict[str, object]]]) -> bool:
    if not table:
        return False

    header_text = " ".join(str(cell.get("text", "")) for cell in table[0])
    return all(label in header_text for label in ["日時", "場所", "地図", "内容"])


def normalize_official_row(row: list[dict[str, object]], page_url: str) -> dict[str, object] | None:
    if len(row) < 5:
        return None

    parsed_datetime = parse_japanese_datetime(str(row[1].get("text", "")))
    coordinate = extract_coordinate(row[3])
    if not parsed_datetime or not coordinate:
        return None

    date, time = parsed_datetime
    place = compact_text(str(row[2].get("text", "")))
    detail = compact_text(str(row[4].get("text", "")))
    latitude, longitude = coordinate

    record = {
        "date": date,
        "time": time,
        "ward": infer_ward(place),
        "place": place,
        "latitude": latitude,
        "longitude": longitude,
        "detail": detail,
        "sourceYear": int(date[:4]),
        "sourceType": "official_page",
        "sourceName": OFFICIAL_PAGE_SOURCE_NAME,
        "sourceURL": page_url,
    }
    record["id"] = make_record_id(record)
    return record


def parse_official_page_records(page_url: str) -> list[dict[str, object]]:
    page_html = read_url_text(page_url)
    parser = TableParser(page_url)
    parser.feed(page_html)

    records: list[dict[str, object]] = []
    for table in parser.tables:
        if not table_has_sighting_headers(table):
            continue
        for row in table[1:]:
            if record := normalize_official_row(row, page_url):
                records.append(record)

    if not records:
        raise RuntimeError("公式ページから出没情報テーブルを抽出できませんでした。")

    return records


def distance_km(a: dict[str, object], b: dict[str, object]) -> float:
    lat1 = math.radians(float(a["latitude"]))
    lon1 = math.radians(float(a["longitude"]))
    lat2 = math.radians(float(b["latitude"]))
    lon2 = math.radians(float(b["longitude"]))
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    haversine = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 6_371.0 * 2 * math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine))


def is_duplicate(candidate: dict[str, object], existing: dict[str, object]) -> bool:
    if candidate["date"] != existing["date"]:
        return False

    candidate_detail = normalize_for_key(str(candidate["detail"]))
    existing_detail = normalize_for_key(str(existing["detail"]))
    candidate_place = normalize_for_key(str(candidate["place"]))
    existing_place = normalize_for_key(str(existing["place"]))

    if candidate_detail != existing_detail:
        return False

    if candidate_place == existing_place:
        return True

    return distance_km(candidate, existing) <= 0.1


def dedupe_records(records: list[dict[str, object]]) -> list[dict[str, object]]:
    deduped: list[dict[str, object]] = []
    for record in records:
        if any(is_duplicate(record, existing) for existing in deduped):
            continue
        deduped.append(record)
    return deduped


def latest_date(records: list[dict[str, object]]) -> str | None:
    if not records:
        return None
    return max(str(record["date"]) for record in records)


def source_summary(
    *,
    name: str,
    source_type: str,
    records: list[dict[str, object]],
    source_url: str,
    status: str = "ok",
    error: str | None = None,
    extra: dict[str, object] | None = None,
) -> dict[str, object]:
    summary: dict[str, object] = {
        "name": name,
        "sourceType": source_type,
        "sourceURL": source_url,
        "status": status,
        "latestSightingDate": latest_date(records),
        "recordCount": len(records),
    }
    if error:
        summary["error"] = error
    if extra:
        summary.update(extra)
    return summary


def build_feed(args: argparse.Namespace) -> dict[str, object]:
    ckan_records, ckan_metadata = parse_ckan_records(args)

    official_records: list[dict[str, object]] = []
    official_error: str | None = None
    if not args.skip_official_page:
        try:
            official_records = parse_official_page_records(args.official_page_url)
        except Exception as error:  # noqa: BLE001 - CKAN-only output should continue.
            official_error = str(error)
            print(f"Warning: official page source failed: {official_error}", file=sys.stderr)

    combined_records = dedupe_records(ckan_records + official_records)
    combined_records.sort(key=lambda item: (str(item["date"]), str(item["time"])), reverse=True)

    generated_at = datetime.now(JST).isoformat()
    ckan_summary = source_summary(
        name=CKAN_SOURCE_NAME,
        source_type="ckan",
        records=ckan_records,
        source_url=str(ckan_metadata.get("sourceURL") or ckan_metadata.get("sourceResourceUrl") or ""),
        extra={
            key: value
            for key, value in ckan_metadata.items()
            if key
            in {
                "datasetApiUrl",
                "datasetName",
                "datasetTitle",
                "datasetUrl",
                "licenseId",
                "licenseTitle",
                "licenseUrl",
                "sourceResourceId",
                "sourceResourceName",
                "sourceResourceUrl",
                "sourceResourceLastModified",
            }
        },
    )
    official_summary = source_summary(
        name=OFFICIAL_PAGE_SOURCE_NAME,
        source_type="official_page",
        records=official_records,
        source_url=args.official_page_url,
        status="failed" if official_error else "ok",
        error=official_error,
    )

    return {
        "schemaVersion": 2,
        "generatedAt": generated_at,
        "recordCount": len(combined_records),
        "latestSightingDate": latest_date(combined_records),
        "sources": [ckan_summary, official_summary],
        "records": combined_records,
    }


def main() -> int:
    args = parse_args()
    feed = build_feed(args)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(feed, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    if args.metadata_output:
        metadata = {key: value for key, value in feed.items() if key != "records"}
        args.metadata_output.parent.mkdir(parents=True, exist_ok=True)
        args.metadata_output.write_text(
            json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

    print(f"Wrote {feed['recordCount']} sightings to {args.output}")
    print(f"Latest sighting date: {feed['latestSightingDate']}")
    for source in feed["sources"]:
        print(
            f"- {source['name']}: {source['recordCount']} records, "
            f"latest={source['latestSightingDate']}, status={source['status']}"
        )
    if args.metadata_output:
        print(f"Wrote metadata to {args.metadata_output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
