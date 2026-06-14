from __future__ import annotations

import re
import html

from .common import SourceResult, build_record, compact_text, extract_ll_from_url, parse_japanese_date, parse_japanese_time, read_url_text

SOURCE_ID = "kitahiroshima_official"
SOURCE_NAME = "北広島市公式ヒグマ出没情報"
SOURCE_TYPE = "official_html_text"
DEFAULT_URL = "https://www.city.kitahiroshima.hokkaido.jp/hotnews/detail/00134027.html"


def fetch(page_url: str = DEFAULT_URL) -> SourceResult:
    page_html = read_url_text(page_url)
    records = _records_from_raw_html(page_html, page_url)

    if not records:
        raise RuntimeError("北広島市ページから出没情報を抽出できませんでした。")

    return SourceResult(SOURCE_ID, SOURCE_NAME, SOURCE_TYPE, page_url, records)


def _records_from_raw_html(page_html: str, page_url: str) -> list[dict]:
    records = []
    date_sections = re.finditer(
        r"<h4[^>]*>.*?(令和[^<]+?日[^<]*).*?</h4>(.*?)(?=<h4|<h3|<h2|$)",
        page_html,
        flags=re.DOTALL,
    )
    for section in date_sections:
        date = parse_japanese_date(section.group(1))
        if not date:
            continue
        for line_html in re.split(r"<br\s*/?>", section.group(2)):
            if "ヒグマ" not in line_html and "クマ" not in line_html and "熊" not in line_html:
                continue
            links = [html.unescape(link) for link in re.findall(r'href="([^"]+)"', line_html)]
            text = compact_text(re.sub(r"<[^>]+>", " ", line_html))
            if record := _record_from_text(text, links, date, page_url):
                records.append(record)
    return records


def _record_from_text(text: str, links: object, date: str, page_url: str) -> dict | None:
    if not re.search(r"\d{1,2}時\s*\d{1,2}分", text):
        return None
    time = parse_japanese_time(text)
    location_text = _extract_location(text)
    if not location_text:
        return None

    latitude, longitude = None, None
    if isinstance(links, list):
        for link in links:
            latitude, longitude = extract_ll_from_url(str(link))
            if latitude is not None and longitude is not None:
                break

    return build_record(
        source_id=SOURCE_ID,
        date=date,
        time=time,
        municipality="北広島市",
        location_text=location_text,
        description=text,
        latitude=latitude,
        longitude=longitude,
        source_name=SOURCE_NAME,
        source_url=page_url,
        source_type=SOURCE_TYPE,
    )


def _extract_location(text: str) -> str:
    cleaned = text.replace("、", "，")
    match = re.search(r"(?:頃|ごろ)[:,，]\s*(.+?)(?:において|で、|でヒグマ|付近で|周辺で)", cleaned)
    if match:
        return compact_text(match.group(1))
    match = re.search(r"(北広島市[^，。]+)", cleaned)
    if match:
        return compact_text(match.group(1))
    return ""
