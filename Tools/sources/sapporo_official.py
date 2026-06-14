from __future__ import annotations

import re

from .common import SourceResult, TableParser, build_record, compact_text, extract_ll_from_url, read_url_text

SOURCE_ID = "sapporo_official"
SOURCE_NAME = "札幌市公式ヒグマ出没情報ページ"
SOURCE_TYPE = "official_html_table"
DEFAULT_URL = "https://www.city.sapporo.jp/kurashi/animal/choju/kuma/syutsubotsu/"
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


def fetch(page_url: str = DEFAULT_URL) -> SourceResult:
    page_html = read_url_text(page_url)
    parser = TableParser(page_url)
    parser.feed(page_html)

    records = []
    for table in parser.tables:
        if not _table_has_headers(table):
            continue
        for row in table[1:]:
            if record := _normalize_row(row, page_url):
                records.append(record)

    if not records:
        raise RuntimeError("公式ページから出没情報テーブルを抽出できませんでした。")

    return SourceResult(SOURCE_ID, SOURCE_NAME, SOURCE_TYPE, page_url, records)


def _table_has_headers(table: list[list[dict]]) -> bool:
    if not table:
        return False
    header_text = " ".join(str(cell.get("text", "")) for cell in table[0])
    return all(label in header_text for label in ["日時", "場所", "地図", "内容"])


def _normalize_row(row: list[dict], page_url: str) -> dict | None:
    if len(row) < 5:
        return None
    parsed = _parse_datetime(str(row[1].get("text", "")))
    if not parsed:
        return None

    date, time = parsed
    lat, lon = _extract_coordinate(row[3])
    if lat is None or lon is None:
        return None

    place = compact_text(str(row[2].get("text", "")))
    detail = compact_text(str(row[4].get("text", "")))
    return build_record(
        source_id=SOURCE_ID,
        date=date,
        time=time,
        municipality="札幌市",
        area=_infer_ward(place),
        location_text=place,
        description=detail,
        latitude=lat,
        longitude=lon,
        source_name=SOURCE_NAME,
        source_url=page_url,
        source_type=SOURCE_TYPE,
    )


def _parse_datetime(value: str) -> tuple[str, str] | None:
    match = re.search(
        r"(\d{4})年(\d{1,2})月(\d{1,2})日(?:（[^）]+）)?(?:\s*(\d{1,2})時(\d{1,2})分)?",
        compact_text(value),
    )
    if not match:
        return None
    year, month, day, hour, minute = match.groups()
    time = f"{int(hour):02d}:{int(minute):02d}" if hour and minute else ""
    return f"{int(year):04d}-{int(month):02d}-{int(day):02d}", time


def _extract_coordinate(cell: dict) -> tuple[float | None, float | None]:
    for link in cell.get("links", []):
        lat, lon = extract_ll_from_url(str(link))
        if lat is not None and lon is not None:
            return lat, lon
    return None, None


def _infer_ward(place: str) -> str:
    for ward in WARD_NAMES:
        if ward in place:
            return ward
    for hint, ward in WARD_HINTS.items():
        if hint in place:
            return ward
    return ""
