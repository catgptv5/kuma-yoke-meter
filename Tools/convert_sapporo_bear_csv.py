#!/usr/bin/env python3
"""Build the integrated bear sightings feed for the app and GitHub Pages."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Callable

from sources import (
    chitose_official,
    iwamizawa_official,
    kitahiroshima_official,
    kuriyama_official,
    sapporo_ckan,
    sapporo_official,
    yuni_official,
)
from sources.common import SourceResult, dedupe_records, latest_date, now_jst_iso, source_error

DEFAULT_OUTPUT = Path("KumaYokeMeter/Resources/bear_sightings.json")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="自治体公式情報を統合して、くま避けメーター用JSONへ変換します。"
    )
    parser.add_argument(
        "--dataset-api-url",
        default=sapporo_ckan.DEFAULT_DATASET_API_URL,
        help="札幌市CKANのpackage_show API URL",
    )
    parser.add_argument("--url", help="札幌市CKAN CSVを直接指定する場合のURL")
    parser.add_argument("--input", type=Path, help="札幌市CKAN CSVをローカルファイルから読む場合のパス")
    parser.add_argument("--official-page-url", default=sapporo_official.DEFAULT_URL, help="札幌市公式ページURL")
    parser.add_argument("--skip-official-page", action="store_true", help="札幌市公式ページの補助取得をスキップ")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT, help="出力JSONのパス")
    parser.add_argument("--metadata-output", type=Path, help="配信用メタデータJSONの出力先")
    return parser.parse_args()


def build_feed(args: argparse.Namespace) -> dict[str, object]:
    generated_at = now_jst_iso()
    source_jobs: list[tuple[str, str, str, str, Callable[[], SourceResult]]] = [
        (
            sapporo_ckan.SOURCE_ID,
            sapporo_ckan.SOURCE_NAME,
            sapporo_ckan.SOURCE_TYPE,
            args.url or args.dataset_api_url,
            lambda: sapporo_ckan.fetch(
                dataset_api_url=args.dataset_api_url,
                csv_url=args.url,
                csv_text=args.input.read_text(encoding="utf-8-sig") if args.input else None,
            ),
        ),
    ]

    if not args.skip_official_page:
        source_jobs.append(
            (
                sapporo_official.SOURCE_ID,
                sapporo_official.SOURCE_NAME,
                sapporo_official.SOURCE_TYPE,
                args.official_page_url,
                lambda: sapporo_official.fetch(args.official_page_url),
            )
        )

    source_jobs.extend(
        [
            (yuni_official.SOURCE_ID, yuni_official.SOURCE_NAME, yuni_official.SOURCE_TYPE, yuni_official.DEFAULT_URL, yuni_official.fetch),
            (kuriyama_official.SOURCE_ID, kuriyama_official.SOURCE_NAME, kuriyama_official.SOURCE_TYPE, kuriyama_official.DEFAULT_URL, kuriyama_official.fetch),
            (iwamizawa_official.SOURCE_ID, iwamizawa_official.SOURCE_NAME, iwamizawa_official.SOURCE_TYPE, iwamizawa_official.DEFAULT_URL, iwamizawa_official.fetch),
            (
                kitahiroshima_official.SOURCE_ID,
                kitahiroshima_official.SOURCE_NAME,
                kitahiroshima_official.SOURCE_TYPE,
                kitahiroshima_official.DEFAULT_URL,
                kitahiroshima_official.fetch,
            ),
            (chitose_official.SOURCE_ID, chitose_official.SOURCE_NAME, chitose_official.SOURCE_TYPE, chitose_official.DEFAULT_URL, chitose_official.fetch),
        ]
    )

    results = [_run_source(job, generated_at) for job in source_jobs]
    records = dedupe_records([record for result in results for record in result.records])
    records.sort(key=lambda item: (str(item.get("date", "")), str(item.get("time", ""))), reverse=True)

    errors = [
        {
            "sourceId": result.source_id,
            "message": result.error,
            "occurredAt": generated_at,
        }
        for result in results
        if result.status != "ok" and result.error
    ]

    return {
        "schemaVersion": 3,
        "generatedAt": generated_at,
        "latestSightingDate": latest_date(records),
        "recordCount": len(records),
        "sources": [_source_summary(result) for result in results],
        "errors": errors,
        "records": records,
    }


def _run_source(job: tuple[str, str, str, str, Callable[[], SourceResult]], occurred_at: str) -> SourceResult:
    source_id, name, source_type, source_url, fetcher = job
    try:
        return fetcher()
    except Exception as error:  # noqa: BLE001 - one source should not stop the feed.
        print(f"Warning: {source_id} failed: {error}", file=sys.stderr)
        return source_error(source_id, name, source_type, source_url, error)


def _source_summary(result: SourceResult) -> dict[str, object]:
    summary: dict[str, object] = {
        "id": result.source_id,
        "name": result.name,
        "sourceType": result.source_type,
        "sourceUrl": result.source_url,
        "sourceURL": result.source_url,
        "status": result.status,
        "latestSightingDate": latest_date(result.records),
        "recordCount": len(result.records),
    }
    if result.error:
        summary["error"] = result.error
    if result.extra:
        summary.update(result.extra)
    return summary


def main() -> int:
    args = parse_args()
    feed = build_feed(args)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(feed, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    if args.metadata_output:
        metadata = {key: value for key, value in feed.items() if key != "records"}
        args.metadata_output.parent.mkdir(parents=True, exist_ok=True)
        args.metadata_output.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"Wrote {feed['recordCount']} sightings to {args.output}")
    print(f"Latest sighting date: {feed['latestSightingDate']}")
    for source in feed["sources"]:
        print(
            f"- {source['id']}: {source['recordCount']} records, "
            f"latest={source['latestSightingDate']}, status={source['status']}"
        )
    if feed["errors"]:
        print(f"Completed with {len(feed['errors'])} source warning(s).", file=sys.stderr)
    if args.metadata_output:
        print(f"Wrote metadata to {args.metadata_output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
