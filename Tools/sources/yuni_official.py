from __future__ import annotations

from .common import SourceResult, TableParser, build_record, compact_text, parse_datetime_cells, read_url_text

SOURCE_ID = "yuni_official"
SOURCE_NAME = "由仁町公式ヒグマ出没情報"
SOURCE_TYPE = "official_html_table"
DEFAULT_URL = "https://www.town.yuni.lg.jp/newstopics/9573"


def fetch(page_url: str = DEFAULT_URL) -> SourceResult:
    parser = TableParser(page_url)
    parser.feed(read_url_text(page_url))

    records = []
    for table in parser.tables:
        if not _has_expected_header(table):
            continue
        for row in table[1:]:
            if record := _record_from_row(row, page_url):
                records.append(record)

    if not records:
        raise RuntimeError("由仁町の表から出没情報を抽出できませんでした。")

    return SourceResult(SOURCE_ID, SOURCE_NAME, SOURCE_TYPE, page_url, records)


def _has_expected_header(table: list[list[dict]]) -> bool:
    if not table:
        return False
    text = " ".join(str(cell.get("text", "")) for cell in table[0])
    return all(label in text for label in ["年月日", "発見時間", "場所", "内容"])


def _record_from_row(row: list[dict], page_url: str) -> dict | None:
    if len(row) < 4:
        return None
    date, time = parse_datetime_cells(str(row[0].get("text", "")), str(row[1].get("text", "")))
    if not date:
        return None
    location_text = compact_text(str(row[2].get("text", "")))
    description = compact_text(str(row[3].get("text", "")))
    if not location_text or not description:
        return None
    return build_record(
        source_id=SOURCE_ID,
        date=date,
        time=time,
        municipality="由仁町",
        location_text=location_text,
        description=description,
        source_name=SOURCE_NAME,
        source_url=page_url,
        source_type=SOURCE_TYPE,
    )
