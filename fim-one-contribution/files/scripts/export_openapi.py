#!/usr/bin/env python3
"""Export the FastAPI OpenAPI spec.

Two flavours, because ``web/app.py`` deliberately publishes only part of the
API. It hides every route and then re-enables a 16-entry ``_PUBLIC_API``
allowlist, so the default export is the *public* API document that ships to
``docs/openapi.json`` — 12 paths out of the 427 routes the app registers.

``--internal`` lifts that filter and exports the whole surface (351 paths,
294 schemas). It is a developer artifact for generating frontend types from
the backend's own declarations; it is not published anywhere, and the public
spec is left byte-identical.

Usage::

    uv run python scripts/export_openapi.py                    # public -> docs/openapi.json
    uv run python scripts/export_openapi.py --internal         # full   -> frontend/openapi.json
    uv run python scripts/export_openapi.py --internal --out /tmp/spec.json
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from fastapi import FastAPI

ROOT = Path(__file__).resolve().parent.parent
PUBLIC_OUT = ROOT / "docs" / "openapi.json"
INTERNAL_OUT = ROOT / "frontend" / "openapi.json"


def unhide_routes(app: FastAPI) -> int:
    """Re-enable ``include_in_schema`` on every route and drop the cached spec.

    ``create_app()`` installs a ``custom_openapi()`` that memoises its result
    on ``app.openapi_schema``, so the cache has to be cleared or the hidden
    routes stay hidden no matter what the flags say.

    Returns:
        The number of routes that were flipped, for the summary line.
    """
    from fastapi.routing import APIRoute

    flipped = 0
    for route in app.routes:
        if isinstance(route, APIRoute) and not route.include_in_schema:
            route.include_in_schema = True
            flipped += 1
    app.openapi_schema = None
    return flipped


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument(
        "--internal",
        action="store_true",
        help="export every route, not just the public API allowlist",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=None,
        help=(
            "destination file (default: docs/openapi.json, "
            "or frontend/openapi.json with --internal)"
        ),
    )
    args = parser.parse_args(argv)

    from fim_one.web.app import create_app

    app = create_app()
    flipped = unhide_routes(app) if args.internal else 0
    spec = app.openapi()

    out: Path = args.out or (INTERNAL_OUT if args.internal else PUBLIC_OUT)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(spec, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    paths = len(spec.get("paths", {}))
    schemas = len(spec.get("components", {}).get("schemas", {}))
    flavour = "internal" if args.internal else "public"
    print(f"Exported {flavour} spec: {paths} paths, {schemas} schemas -> {out}")
    if args.internal and flipped:
        print(f"  ({flipped} routes un-hidden from the _PUBLIC_API allowlist)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
