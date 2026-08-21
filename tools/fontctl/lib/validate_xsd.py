from __future__ import annotations

import json
import sys
from pathlib import Path


def diagnostic(code: str, message: str, file: Path, line: int = 0, column: int = 0) -> dict:
    return {
        "severity": "error",
        "code": code,
        "message": message,
        "file": str(file),
        "line": line,
        "column": column,
    }


def main() -> int:
    if len(sys.argv) != 3:
        print(json.dumps({"ok": False, "helperError": "usage"}))
        return 64

    schema_path = Path(sys.argv[1]).resolve()
    catalog_path = Path(sys.argv[2]).resolve()
    try:
        from lxml import etree
    except Exception as exc:  # pragma: no cover - exercised by Node fallback diagnostics
        print(json.dumps({"ok": False, "helperError": f"lxml unavailable: {exc}"}))
        return 69

    parser = etree.XMLParser(
        resolve_entities=False,
        no_network=True,
        load_dtd=False,
        recover=False,
        huge_tree=False,
    )
    diagnostics: list[dict] = []
    try:
        schema_document = etree.parse(str(schema_path), parser)
        schema = etree.XMLSchema(schema_document)
    except (OSError, etree.XMLSyntaxError, etree.XMLSchemaParseError) as exc:
        diagnostics.append(
            diagnostic(
                "XSD_SCHEMA_INVALID",
                f"fonts.xsd 无法加载：{exc}",
                schema_path,
                getattr(exc, "lineno", 0) or 0,
                getattr(exc, "offset", 0) or 0,
            )
        )
        print(json.dumps({"ok": False, "diagnostics": diagnostics}, ensure_ascii=False))
        return 0

    try:
        catalog_document = etree.parse(str(catalog_path), parser)
    except (OSError, etree.XMLSyntaxError) as exc:
        diagnostics.append(
            diagnostic(
                "XML_SYNTAX",
                f"fonts.xml 不是合法 XML：{exc}",
                catalog_path,
                getattr(exc, "lineno", 0) or 0,
                getattr(exc, "offset", 0) or 0,
            )
        )
        print(json.dumps({"ok": False, "diagnostics": diagnostics}, ensure_ascii=False))
        return 0

    if not schema.validate(catalog_document):
        for entry in schema.error_log:
            diagnostics.append(
                diagnostic(
                    "XSD_INVALID",
                    entry.message,
                    catalog_path,
                    entry.line or 0,
                    entry.column or 0,
                )
            )

    print(
        json.dumps(
            {"ok": not diagnostics, "diagnostics": diagnostics},
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
