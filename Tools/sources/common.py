from __future__ import annotations

import hashlib
import html
import re
import urllib.request
import unicodedata
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from html.parser import HTMLParser
from urllib.parse import urljoin, unquote

JST = timezone(timedelta(hours=9))


@dataclass
class SourceResult:
    source_id: str
    name: str
    source_type: str
    source_url: str
    records: list[dict]
    status: str = "ok"
    error: str | None = None
    extra: dict | None = None


def now_jst_iso() -> str:
    return datetime.now(JST).isoformat()


def compact_text(value: str) -> str:
    return re.sub(r"\s+", " ", html.unescape(value)).strip()


def normalize_text(value: str) -> str:
    normalized = unicodedata.normalize("NFKC", compact_text(value))
    normalized = normalized.replace("熊", "ヒグマ").replace("頃", "ごろ")
    return re.sub(r"[\s　、,。．.・]", "", normalized)


def read_url_text(url: str) -> str:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "kuma-yoke-meter/0.1 (+https://github.com/catgptv5/kuma-yoke-meter)"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read().decode("utf-8-sig")


def source_error(source_id: str, name: str, source_type: str, source_url: str, error: Exception) -> SourceResult:
    return SourceResult(
        source_id=source_id,
        name=name,
        source_type=source_type,
        source_url=source_url,
        records=[],
        status="failed",
        error=str(error),
    )


def latest_date(records: list[dict]) -> str | None:
    dates = [record.get("date") for record in records if record.get("date")]
    return max(dates) if dates else None


def event_type_from_text(text: str) -> str:
    if any(keyword in text for keyword in ["被害", "襲", "負傷", "食害", "侵入"]):
        return "damage"
    if any(keyword in text for keyword in ["足跡", "フン", "糞", "痕跡", "爪痕"]):
        return "trace"
    if any(keyword in text for keyword in ["カメラ", "撮影"]):
        return "camera"
    if "捕獲" in text:
        return "capture"
    if "らしき" in text:
        return "possible_sighting"
    if any(keyword in text for keyword in ["目撃", "確認", "出没"]):
        return "sighting"
    return "other"


def infer_accuracy(location_text: str, has_coordinates: bool) -> tuple[str, int]:
    if has_coordinates:
        return "exact", 100
    if any(keyword in location_text for keyword in ["番地", "付近", "交差点", "バス停", "橋", "公園", "ゴルフ場", "施設", "センター", "神社", "PA"]):
        return "facility", 800
    if any(keyword in location_text for keyword in ["国道", "道道", "町道", "道路", "線沿い", "道路上"]):
        return "road", 1500
    if any(keyword in location_text for keyword in ["地区", "町", "市", "字"]):
        return "district", 3000
    return "unknown", 10000


MANUAL_GEOCODES = {
    "由仁町川端地区": (42.892776, 141.938703, "district", 3000),
    "由仁町本三川地区": (42.965, 141.840, "district", 3000),
    "栗沢町最上": (43.11824, 141.748615, "district", 3000),
    "栗山町御園": (43.005202, 141.87756, "district", 3000),
    "御園地区": (43.005202, 141.87756, "district", 3000),
    "栗山町桜山": (43.055, 141.840, "district", 3000),
    "桜山地区": (43.055, 141.840, "district", 3000),
    "栗山町滝下": (42.950, 141.950, "district", 3000),
    "滝下地区": (42.950, 141.950, "district", 3000),
    "栗山町緑丘": (43.060, 141.820, "district", 3000),
    "緑丘地区": (43.060, 141.820, "district", 3000),
    "北広島市島松": (42.927795, 141.54797, "district", 3000),
    "島松": (42.927795, 141.54797, "district", 3000),
}


def apply_manual_geocode(location_text: str, latitude: float | None = None, longitude: float | None = None) -> tuple[float | None, float | None, str, int]:
    if latitude is not None and longitude is not None:
        accuracy, meters = infer_accuracy(location_text, has_coordinates=True)
        return latitude, longitude, accuracy, meters

    for key, value in MANUAL_GEOCODES.items():
        if key in location_text:
            return value

    accuracy, meters = infer_accuracy(location_text, has_coordinates=False)
    return None, None, accuracy, meters


def make_record_id(source_id: str, date: str, municipality: str, location_text: str, description: str) -> str:
    raw = "|".join([source_id, date, municipality, normalize_text(location_text), normalize_text(description)])
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()[:16]


def build_record(
    *,
    source_id: str,
    date: str,
    time: str,
    municipality: str,
    location_text: str,
    description: str,
    source_name: str,
    source_url: str,
    source_type: str = "official_html_table",
    area: str | None = None,
    latitude: float | None = None,
    longitude: float | None = None,
    fetched_at: str | None = None,
) -> dict:
    latitude, longitude, location_accuracy, location_accuracy_meters = apply_manual_geocode(
        location_text,
        latitude=latitude,
        longitude=longitude,
    )
    description = compact_text(description)
    location_text = compact_text(location_text)
    record = {
        "id": make_record_id(source_id, date, municipality, location_text, description),
        "date": date,
        "time": compact_text(time),
        "municipality": municipality,
        "area": area or infer_area(location_text, municipality),
        "locationText": location_text,
        "description": description,
        "eventType": event_type_from_text(description + " " + location_text),
        "latitude": latitude,
        "longitude": longitude,
        "locationAccuracy": location_accuracy,
        "locationAccuracyMeters": location_accuracy_meters,
        "sourceName": source_name,
        "sourceUrl": source_url,
        "sourceURL": source_url,
        "sourceType": source_type,
        "fetchedAt": fetched_at or now_jst_iso(),
        # Compatibility with the first iOS model.
        "ward": area or municipality,
        "place": location_text,
        "detail": description,
        "sourceYear": int(date[:4]),
    }
    return record


def infer_area(location_text: str, municipality: str) -> str:
    text = location_text.replace(municipality, "")
    for pattern in [r"([^\s　、,。()（）]+地区)", r"(栗沢町[^\s　、,。()（）]+)", r"(島松)", r"(水明郷)", r"(泉沢)", r"(支寒内)", r"(西森)", r"(美々)", r"(真町)"]:
        match = re.search(pattern, text)
        if match:
            return match.group(1)
    return ""


ERA_BASE_YEAR = {"令和": 2018, "平成": 1988}


def parse_japanese_date(text: str, default_year: int | None = None) -> str | None:
    text = unicodedata.normalize("NFKC", compact_text(text))
    text = re.sub(r"年\s*[\(（]\d{4}年[\)）]\s*", "年", text)
    match = re.search(r"(令和|平成)(元|\d+)年\s*(\d{1,2})月\s*(\d{1,2})日", text)
    if match:
        era, year_text, month, day = match.groups()
        year = 1 if year_text == "元" else int(year_text)
        return f"{ERA_BASE_YEAR[era] + year:04d}-{int(month):02d}-{int(day):02d}"

    match = re.search(r"(\d{4})年\s*(\d{1,2})月\s*(\d{1,2})日", text)
    if match:
        year, month, day = match.groups()
        return f"{int(year):04d}-{int(month):02d}-{int(day):02d}"

    match = re.search(r"(\d{1,2})月\s*(\d{1,2})日", text)
    if match and default_year:
        month, day = match.groups()
        return f"{default_year:04d}-{int(month):02d}-{int(day):02d}"

    return None


def parse_japanese_time(text: str) -> str:
    text = unicodedata.normalize("NFKC", compact_text(text))
    period = ""
    if "午前" in text:
        period = "午前"
    elif "午後" in text:
        period = "午後"
    match = re.search(r"(\d{1,2})時\s*(?:(\d{1,2})分?)?", text)
    if not match:
        return compact_text(text)
    hour = int(match.group(1))
    minute = int(match.group(2) or 0)
    if period == "午後" and hour != 12:
        hour += 12
    if period == "午前" and hour == 12:
        hour = 0
    suffix = "ごろ" if ("ごろ" in text or "頃" in text) else ""
    return f"{hour:02d}:{minute:02d}{suffix}"


def parse_datetime_cells(date_text: str, time_text: str = "", default_year: int | None = None) -> tuple[str | None, str]:
    date = parse_japanese_date(date_text, default_year=default_year)
    time = parse_japanese_time(time_text or date_text)
    return date, time


def extract_ll_from_url(url: str) -> tuple[float | None, float | None]:
    decoded = unquote(url)
    match = re.search(r"[?&]ll=([0-9.]+)[,%2C]+([0-9.]+)", decoded)
    if not match:
        return None, None
    return float(match.group(1)), float(match.group(2))


class TableParser(HTMLParser):
    def __init__(self, base_url: str):
        super().__init__(convert_charrefs=True)
        self.base_url = base_url
        self.tables: list[list[list[dict]]] = []
        self._table: list[list[dict]] | None = None
        self._row: list[dict] | None = None
        self._cell: dict | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attributes = dict(attrs)
        if tag == "table":
            self._table = []
        elif tag == "tr" and self._table is not None:
            self._row = []
        elif tag in {"td", "th"} and self._row is not None:
            self._cell = {"text": [], "links": []}
        elif tag == "br" and self._cell is not None:
            self._cell["text"].append(" ")
        elif tag == "a" and self._cell is not None and attributes.get("href"):
            self._cell["links"].append(urljoin(self.base_url, attributes["href"] or ""))

    def handle_data(self, data: str) -> None:
        if self._cell is not None:
            self._cell["text"].append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag in {"td", "th"} and self._cell is not None and self._row is not None:
            self._cell["text"] = compact_text(" ".join(str(part) for part in self._cell["text"]))
            self._row.append(self._cell)
            self._cell = None
        elif tag == "tr" and self._row is not None and self._table is not None:
            if self._row:
                self._table.append(self._row)
            self._row = None
        elif tag == "table" and self._table is not None:
            self.tables.append(self._table)
            self._table = None


class TextParser(HTMLParser):
    def __init__(self, base_url: str):
        super().__init__(convert_charrefs=True)
        self.base_url = base_url
        self.blocks: list[dict] = []
        self._current: dict | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attributes = dict(attrs)
        if tag in {"h1", "h2", "h3", "h4", "p", "li"}:
            self._current = {"tag": tag, "text": [], "links": []}
        elif tag == "a" and self._current is not None and attributes.get("href"):
            self._current["links"].append(urljoin(self.base_url, attributes["href"] or ""))

    def handle_data(self, data: str) -> None:
        if self._current is not None:
            self._current["text"].append(data)

    def handle_endtag(self, tag: str) -> None:
        if self._current is not None and tag == self._current["tag"]:
            text = compact_text(" ".join(str(part) for part in self._current["text"]))
            if text:
                self.blocks.append({"tag": tag, "text": text, "links": self._current["links"]})
            self._current = None


def dedupe_records(records: list[dict]) -> list[dict]:
    seen: set[str] = set()
    deduped: list[dict] = []
    for record in records:
        key = "|".join(
            [
                str(record.get("date", "")),
                str(record.get("municipality", "")),
                normalize_text(str(record.get("locationText") or record.get("place") or "")),
                normalize_text(str(record.get("description") or record.get("detail") or "")),
            ]
        )
        if key in seen:
            continue
        seen.add(key)
        deduped.append(record)
    return deduped
