from __future__ import annotations

import re

from .common import SourceResult, TableParser, build_record, compact_text, parse_datetime_cells, read_url_text

SOURCE_ID = "iwamizawa_official"
SOURCE_NAME = "岩見沢市公式ヒグマ出没情報"
SOURCE_TYPE = "official_html_table"
DEFAULT_URL = "https://www.city.iwamizawa.hokkaido.jp/soshiki/nomuka/sangyo/1/17320.html"
AREA_KEYWORDS = ["栗沢町", "栗丘", "最上"]


def fetch(page_url: str = DEFAULT_URL) -> SourceResult:
    html = read_url_text(page_url)
    parser = TableParser(page_url)
    parser.feed(html)
    default_year = _default_fiscal_year(html)

    records = []
    for table in parser.tables:
        if not _has_expected_header(table):
            continue
        for row in table[1:]:
            if record := _record_from_row(row, page_url, default_year):
                records.append(record)

    if not records:
        raise RuntimeError("岩見沢市の表から長沼町周辺の出没情報を抽出できませんでした。")

    return SourceResult(SOURCE_ID, SOURCE_NAME, SOURCE_TYPE, page_url, records)


def _default_fiscal_year(html: str) -> int | None:
    match = re.search(r"令和(\d+)年度", html)
    if not match:
        return None
    return 2018 + int(match.group(1))


def _has_expected_header(table: list[list[dict]]) -> bool:
    if not table:
        return False
    text = " ".join(str(cell.get("text", "")) for cell in table[0])
    return ("日時" in text or ("月日" in text and "時間" in text)) and all(label in text for label in ["場所", "内容"])


def _record_from_row(row: list[dict], page_url: str, default_year: int | None) -> dict | None:
    if len(row) < 5:
        return None
    if "令和" in str(row[1].get("text", "")) or "年" in str(row[1].get("text", "")):
        date, time = parse_datetime_cells(str(row[1].get("text", "")), "", default_year=default_year)
        location_index = 2
        description_index = 3
    else:
        date, time = parse_datetime_cells(str(row[1].get("text", "")), str(row[2].get("text", "")), default_year=default_year)
        location_index = 3
        description_index = 4
    location_text = compact_text(str(row[location_index].get("text", "")))
    if not date or not location_text:
        return None
    if not any(keyword in location_text for keyword in AREA_KEYWORDS):
        return None
    description = compact_text(str(row[description_index].get("text", "")))
    return build_record(
        source_id=SOURCE_ID,
        date=date,
        time=time,
        municipality="岩見沢市",
        area="栗沢町" if "栗沢町" in location_text else "",
        location_text=location_text,
        description=description,
        source_name=SOURCE_NAME,
        source_url=page_url,
        source_type=SOURCE_TYPE,
    )
