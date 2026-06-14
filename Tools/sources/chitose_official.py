from __future__ import annotations

import re

from .common import (
    SourceResult,
    TextParser,
    build_record,
    compact_text,
    parse_japanese_date,
    parse_japanese_time,
    read_url_text,
)

SOURCE_ID = "chitose_official"
SOURCE_NAME = "千歳市公式ヒグマ目撃情報"
SOURCE_TYPE = "official_html_text"
DEFAULT_URL = "https://www.city.chitose.lg.jp/c50/1002703/1002708/1006598.html"


def fetch(page_url: str = DEFAULT_URL) -> SourceResult:
    html = read_url_text(page_url)
    default_year = _default_year(html)
    parser = TextParser(page_url)
    parser.feed(html)

    records = []
    for block in parser.blocks:
        if block.get("tag") not in {"p", "li"}:
            continue
        text = compact_text(str(block.get("text", "")))
        if "クマ" not in text and "ヒグマ" not in text and "熊" not in text:
            continue
        if record := _record_from_text(text, default_year, page_url):
            records.append(record)

    if not records:
        raise RuntimeError("千歳市ページから目撃情報を抽出できませんでした。")

    return SourceResult(SOURCE_ID, SOURCE_NAME, SOURCE_TYPE, page_url, records)


def _default_year(html: str) -> int | None:
    match = re.search(r"令和(\d+)年度", html)
    if match:
        return 2018 + int(match.group(1))
    match = re.search(r"(20\d{2})年度", html)
    if match:
        return int(match.group(1))
    return None


def _record_from_text(text: str, default_year: int | None, page_url: str) -> dict | None:
    date = parse_japanese_date(text, default_year=default_year)
    if not date:
        return None
    location_text = _extract_location(text)
    if not location_text:
        return None
    return build_record(
        source_id=SOURCE_ID,
        date=date,
        time=parse_japanese_time(text),
        municipality="千歳市",
        location_text=location_text,
        description=text,
        source_name=SOURCE_NAME,
        source_url=page_url,
        source_type=SOURCE_TYPE,
    )


def _extract_location(text: str) -> str:
    cleaned = text.replace("、", "，")
    match = re.search(r"(?:頃|ごろ)[:,，]\s*(千歳市.+?)(?:でクマ|でヒグマ|で熊|上でクマ|付近で|において)", cleaned)
    if match:
        return compact_text(match.group(1))
    match = re.search(r"(千歳市[^，。]+)", cleaned)
    if match:
        return compact_text(match.group(1))
    return ""
