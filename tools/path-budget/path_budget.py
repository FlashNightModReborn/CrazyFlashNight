#!/usr/bin/env python3
"""Zero-dependency, read-only path-budget audit core (Python 3.9+).

Only reads manifests/ZIP central directories. Never checks out, extracts, renames,
runs repository code, or writes/expands a historical exception baseline.
"""
import argparse
import csv
import hashlib
import json
import stat
import sys
import time
import zipfile
from collections import Counter, defaultdict
from dataclasses import asdict, dataclass
from pathlib import Path


class AuditError(ValueError):
    pass


def utf16_units(value):
    """Count original Unicode code units; do not normalize or count UTF-8 bytes."""
    try:
        return len(value.encode("utf-16-le")) // 2
    except UnicodeEncodeError as exc:
        raise AuditError("Path contains an unpaired surrogate, not valid Unicode") from exc


def validate_path(path, directory=False):
    if not isinstance(path, str) or not path:
        raise AuditError("Every entry needs a nonempty string path")
    utf16_units(path)
    if "\0" in path:
        raise AuditError("NUL is not permitted inside a path")
    # ZIP directory terminators are syntax, not part of the extracted name.
    effective = path[:-1] if directory and path.endswith("/") else path
    if (not effective or effective.startswith(("/", "\\")) or
            (len(effective) >= 2 and effective[1] == ":")):
        raise AuditError("Expected a relative path: " + repr(path))
    if any(part in ("", ".", "..") for part in effective.split("/")):
        raise AuditError("Unsafe or ambiguous path segments: " + repr(path))
    return effective


def normalize_entry(entry):
    if isinstance(entry, str):
        entry = {"path": entry, "type": "directory" if entry.endswith("/") else "file"}
    if not isinstance(entry, dict):
        raise AuditError("Entries must be path strings or objects")
    result = dict(entry)
    kind, mode = result.get("type", "blob"), str(result.get("mode", ""))
    if kind == "tree" or kind == "directory":
        kind = "directory"
    elif kind == "commit" or mode == "160000" or kind == "gitlink":
        kind = "gitlink"
    elif mode == "120000" or kind == "symlink":
        kind = "symlink"
    elif kind in ("blob", "file"):
        kind = "file"
    else:
        raise AuditError("Unsupported entry type: " + repr(kind))
    raw = result.get("path")
    result.update(path=raw, effective_path=validate_path(raw, kind == "directory"),
                  type=kind, mode=mode, sha=result.get("sha"),
                  category=result.get("category", "unknown"))
    if not isinstance(result["category"], str):
        raise AuditError("Entry category must be a string")
    if "already_projected" in result and not isinstance(result["already_projected"], bool):
        raise AuditError("already_projected must be boolean")
    return result


def parse_git_ls_tree_nul(data):
    """Parse `git ls-tree -r -t -z --full-tree SHA`, not quoted display output."""
    if data and not data.endswith(b"\0"):
        raise AuditError("Git ls-tree input must end with NUL; it may be truncated")
    entries = []
    for record in data.split(b"\0")[:-1]:
        try:
            header, name = record.split(b"\t", 1)
            mode, kind, sha = header.decode("ascii").split(" ")
            path = name.decode("utf-8", errors="strict")
        except (ValueError, UnicodeError) as exc:
            raise AuditError("Invalid NUL ls-tree record (invalid UTF-8 is unsupported and must be reviewed)") from exc
        if (len(sha) not in (40, 64) or any(c not in "0123456789abcdefABCDEF" for c in sha)
                or kind not in ("tree", "blob", "commit")
                or mode not in ("040000", "100644", "100755", "120000", "160000")
                or (kind == "tree") != (mode == "040000")
                or (kind == "commit") != (mode == "160000")):
            raise AuditError("Invalid ls-tree mode/type/object ID")
        entries.append({"path": path, "type": kind, "mode": mode, "sha": sha})
    return entries


def strict_json(data):
    """JSON data only: reject duplicate keys and non-standard NaN/Infinity."""
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise AuditError("Duplicate JSON key: " + repr(key))
            result[key] = value
        return result
    def bad_constant(value):
        raise AuditError("Non-standard JSON constant: " + value)
    try:
        return json.loads(data, object_pairs_hook=pairs, parse_constant=bad_constant)
    except (UnicodeError, ValueError) as exc:
        raise AuditError("Invalid strict UTF-8 JSON: " + str(exc)) from exc


def read_json(path):
    try:
        value = strict_json(Path(path).read_text(encoding="utf-8"))
        if not isinstance(value, dict):
            raise AuditError("Expected a JSON object: " + str(path))
        return value
    except (OSError, ValueError) as exc:
        raise AuditError("Cannot read JSON %s: %s" % (path, exc)) from exc


def load_manifest(path, fmt="manifest", metadata=None):
    # ZIP parsing seeks only the central directory. Do not read/hash the whole
    # archive: assets may be many GB and are outside the scan cost.
    raw = None if fmt == "zip" else Path(path).read_bytes()
    meta = dict(metadata or {})
    if fmt == "manifest":
        try:
            manifest = strict_json(raw.decode("utf-8"))
        except (UnicodeError, ValueError) as exc:
            raise AuditError("Manifest is not valid UTF-8 JSON") from exc
        if not isinstance(manifest, dict):
            raise AuditError("Manifest must be an object")
    elif fmt == "git-ls-tree-nul":
        manifest = dict(meta, schema_version=1, entries=parse_git_ls_tree_nul(raw))
    elif fmt == "archive-list":
        try:
            entries = strict_json(raw.decode("utf-8"))
        except (UnicodeError, ValueError) as exc:
            raise AuditError("Archive list must be a JSON array, not newline/space-split names") from exc
        if not isinstance(entries, list):
            raise AuditError("Archive list must be a JSON array")
        manifest = dict(meta, schema_version=1, entries=entries)
    elif fmt == "zip":
        try:
            entries = []
            with zipfile.ZipFile(path) as archive:
                for info in archive.infolist():
                    mode = info.external_attr >> 16
                    kind = "directory" if info.is_dir() else "symlink" if stat.S_ISLNK(mode) else "file"
                    entries.append({"path": info.orig_filename, "type": kind,
                                    "mode": oct(mode), "sha": None,
                                    "zip_utf8_flag": bool(info.flag_bits & 0x800)})
        except (OSError, zipfile.BadZipFile) as exc:
            raise AuditError("Cannot read ZIP central directory: " + str(exc)) from exc
        manifest = dict(meta, schema_version=1, entries=entries)
        # Parsing a ZIP central directory proves completeness only for that ZIP,
        # never for build outputs not present or nested archives not expanded.
        manifest["completeness"] = dict(meta.get("completeness", {}), complete=True,
                                          truncated=False, expected_entries=len(entries))
        manifest["source"] = dict(meta.get("source", {}), kind="zip-central-directory",
                                  central_directory_only=True, archive_bytes=Path(path).stat().st_size)
    else:
        raise AuditError("Unsupported format: " + fmt)
    manifest["input_sha256"] = hashlib.sha256(raw).hexdigest() if raw is not None else None
    return manifest


@dataclass(frozen=True)
class Policy:
    relative_limit: int = 200
    root_units: int = 60  # Model excludes its join separator.
    full_visible_limit: int = 240
    segment_limit: int = 255
    root: str = ""  # Actual root overrides model root_units; preserves trailing separator.
    prefix: str = ""
    suffix: str = ""
    already_projected: bool = False

    def validate(self):
        for key in ("relative_limit", "root_units", "full_visible_limit", "segment_limit"):
            value = getattr(self, key)
            if not isinstance(value, int) or isinstance(value, bool) or value < 0:
                raise AuditError("Policy %s must be a nonnegative integer" % key)
        for key in ("root", "prefix", "suffix"):
            if not isinstance(getattr(self, key), str):
                raise AuditError("Policy %s must be a string" % key)
        if not isinstance(self.already_projected, bool):
            raise AuditError("Policy already_projected must be boolean")
        if self.prefix:
            validate_path(self.prefix[:-1] if self.prefix.endswith("/") else self.prefix)
        if "\0" in self.suffix or "\\" in self.prefix or "\\" in self.suffix:
            raise AuditError("Projection uses slash separators and cannot contain NUL")
        if "\0" in self.root:
            raise AuditError("Root cannot contain NUL")
        utf16_units(self.root)
        utf16_units(self.suffix)
        return self

    def root_cost(self):
        if self.root:
            return utf16_units(self.root), 0 if self.root.endswith(("/", "\\")) else 1
        return self.root_units, 1 if self.root_units else 0

    def project(self, entry):
        path = entry["effective_path"]
        if self.already_projected or entry.get("already_projected", False):
            return path
        projected = ((self.prefix.rstrip("/") + "/") if self.prefix else "") + path + self.suffix
        return validate_path(projected, entry["type"] == "directory")


def metrics(path, directory=False):
    segments = path.split("/")
    return {"relative_utf16": utf16_units(path), "utf8_bytes": len(path.encode("utf-8")),
            "max_segment_utf16": max(map(utf16_units, segments)), "segment_count": len(segments),
            "directory_depth": len(segments) if directory else len(segments) - 1}


def coverage_status(manifest, entries):
    errors, warnings = [], []
    if type(manifest.get("schema_version")) is not int or manifest.get("schema_version") != 1:
        errors.append("schema_version must be 1")
    complete = manifest.get("completeness")
    if not isinstance(complete, dict):
        complete = {}
        errors.append("Missing completeness object")
    if complete.get("complete") is not True:
        errors.append("Inventory completeness is not explicitly true")
    if complete.get("truncated") is not False:
        errors.append("Inventory truncated must be explicitly false")
    if complete.get("uncovered"):
        errors.append("Inventory declares uncovered paths/trees")
    if not entries:
        errors.append("Empty inventory: no full-tree conclusions or passing gate")
    expected = complete.get("expected_entries")
    if expected is not None and (not isinstance(expected, int) or isinstance(expected, bool) or expected != len(entries)):
        errors.append("expected_entries does not match actual entry count")
    gitlinks = [e["path"] for e in entries if e["type"] == "gitlink"]
    unexpanded = [e["path"] for e in entries if e["type"] == "gitlink" and not e.get("gitlink_expanded", False)]
    # A global flag does not prove individual submodule enumeration. Expansion
    # requires each gitlink's explicit flag plus its own coverage manifest.
    if unexpanded:
        errors.append("Unexpanded gitlinks: " + ", ".join(repr(p) for p in unexpanded))
    if gitlinks:
        warnings.append("gitlink_expanded is a caller attestation; verify child commit inventories separately")
    if any("\\" in e["effective_path"] for e in entries):
        warnings.append("Literal backslash in a Git/ZIP name is a Windows separator incompatibility; metrics preserve it literally")
    warnings.append("Length compliance does not validate reserved names, case collisions, trailing dots/spaces, or tool compatibility")
    return {"complete": not errors, "declared": complete, "errors": errors,
            "warnings": warnings, "unexpanded_gitlinks": unexpanded}


def baseline_entries(baseline, policy):
    if baseline is None:
        return {}
    if not isinstance(baseline, dict):
        raise AuditError("Baseline must be a JSON object")
    if type(baseline.get("schema_version")) is not int or baseline.get("schema_version") != 1 or baseline.get("policy") != asdict(policy):
        raise AuditError("Baseline schema/policy differs; refusing silent budget/projection expansion")
    values = baseline.get("exceptions")
    if not isinstance(values, list):
        raise AuditError("Baseline exceptions must be a list")
    indexed = {}
    known_rules = {"relative_utf16", "full_visible_utf16", "segment_utf16"}
    for exc in values:
        if not isinstance(exc, dict):
            raise AuditError("Each baseline exception must be an object")
        path = exc.get("path")
        validate_path(path, isinstance(path, str) and path.endswith("/"))
        if path in indexed:
            raise AuditError("Duplicate baseline path: " + repr(path))
        for key in ("category", "reason"):
            if not isinstance(exc.get(key), str) or not exc[key].strip() or "REVIEW_REQUIRED" in exc[key]:
                raise AuditError("Baseline needs a reviewed exact-path category and reason")
        rules = exc.get("rules")
        if not isinstance(rules, list) or not rules or not set(rules) <= known_rules or len(set(rules)) != len(rules):
            raise AuditError("Baseline rules must enumerate known, unique violated rules")
        indexed[path] = dict(exc)
    return indexed


def validate_baseline_revision(baseline, reference):
    """Only deletions permitted. New/expanded exceptions require a separate review."""
    if baseline.get("policy") != reference.get("policy"):
        raise AuditError("Baseline policy changed versus trusted reference")
    if {k: v for k, v in baseline.items() if k != "exceptions"} != {
            k: v for k, v in reference.items() if k != "exceptions"}:
        raise AuditError("Baseline metadata changed versus trusted reference")
    old = {e["path"]: e for e in reference.get("exceptions", [])}
    for entry in baseline.get("exceptions", []):
        if entry["path"] not in old:
            raise AuditError("Baseline addition versus trusted reference: " + repr(entry["path"]))
        if entry != old[entry["path"]]:
            raise AuditError("Baseline exception modified/expanded versus trusted reference: " + repr(entry["path"]))


def impact_matrix(rows, exception_paths):
    matrix = []
    for relative_limit in (180, 200):
        for root_units in (40, 60, 80):
            rel = [r for r in rows if r["projected_relative_utf16"] > relative_limit]
            full = [r for r in rows if root_units + 1 + r["projected_relative_utf16"] > 240]
            impacted = {r["path"] for r in rel + full}
            matrix.append({"relative_limit": relative_limit, "root_units": root_units,
                           "separator_units": 1, "full_visible_limit": 240,
                           "effective_relative_limit": min(relative_limit, 240 - root_units - 1),
                           "relative_exceeded": len(rel), "full_exceeded": len(full),
                           "union_exceeded": len(impacted),
                           "historical_exact_paths": len(impacted & exception_paths),
                           "new_paths": len(impacted - exception_paths),
                           "minimum_visible_headroom": min((240 - root_units - 1 - r["projected_relative_utf16"] for r in rows), default=None)})
    return matrix


def audit(manifest, policy=None, baseline=None, baseline_reference=None):
    started = time.perf_counter()
    policy = (policy or Policy()).validate()
    if not isinstance(manifest, dict) or not isinstance(manifest.get("entries"), list):
        raise AuditError("Manifest needs an entries array")
    entries = [normalize_entry(e) for e in manifest["entries"]]
    names = [e["path"] for e in entries]
    if len(names) != len(set(names)):
        raise AuditError("Duplicate raw paths in manifest")
    # Also reject ZIP directory a/ plus a or duplicate effective names.
    effective = [e["effective_path"] for e in entries]
    if len(effective) != len(set(effective)):
        raise AuditError("Duplicate effective paths in manifest")
    coverage = coverage_status(manifest, entries)
    exceptions = baseline_entries(baseline, policy)
    if baseline_reference is not None:
        if baseline is None:
            raise AuditError("Baseline reference requires a baseline candidate")
        baseline_entries(baseline_reference, policy)
        validate_baseline_revision(baseline, baseline_reference)
    root_length, separator = policy.root_cost()
    rows, active, new = [], [], []
    for entry in entries:
        original = metrics(entry["effective_path"], entry["type"] == "directory")
        projected_path = policy.project(entry)
        projected = metrics(projected_path, entry["type"] == "directory")
        full = root_length + separator + projected["relative_utf16"]
        violations = []
        for rule, observed, limit in (("relative_utf16", projected["relative_utf16"], policy.relative_limit),
                                      ("full_visible_utf16", full, policy.full_visible_limit),
                                      ("segment_utf16", projected["max_segment_utf16"], policy.segment_limit)):
            if observed > limit:
                violations.append({"rule": rule, "observed": observed, "limit": limit, "over_by": observed - limit})
        exc = exceptions.get(entry["path"])
        grandfathered = bool(violations and exc and {v["rule"] for v in violations} <= set(exc["rules"]))
        status = "historical_exception" if grandfathered else "new_violation" if violations else "within_budget"
        row = {"path": entry["path"], "type": entry["type"], "mode": entry["mode"], "sha": entry["sha"],
               "category": entry["category"], **original, "projected_path": projected_path,
               "projected_relative_utf16": projected["relative_utf16"],
               "projected_max_segment_utf16": projected["max_segment_utf16"],
               "full_visible_utf16": full, "visible_headroom": policy.full_visible_limit - full,
               "status": status, "violations": violations}
        rows.append(row)
        if grandfathered:
            active.append(entry["path"])
        elif violations:
            new.append(entry["path"])
    present = {e["path"] for e in entries}
    stale = [{"path": p, "reason": "removed_or_renamed" if p not in present else "now_within_budget_or_rule_changed"}
             for p in exceptions if p not in active]
    counts = Counter(e["type"] for e in entries)
    dirs = defaultdict(lambda: {"entries": 0, "new_violations": 0, "historical_exceptions": 0,
                                "max_relative_utf16": 0, "max_full_visible_utf16": 0})
    for row in rows:
        key = row["path"].split("/", 1)[0] if "/" in row["path"] else "(root)"
        item = dirs[key]
        item["entries"] += 1
        item["new_violations"] += row["status"] == "new_violation"
        item["historical_exceptions"] += row["status"] == "historical_exception"
        item["max_relative_utf16"] = max(item["max_relative_utf16"], row["relative_utf16"])
        item["max_full_visible_utf16"] = max(item["max_full_visible_utf16"], row["full_visible_utf16"])
    canonical = json.dumps(manifest["entries"], ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    gate = "incomplete" if not coverage["complete"] else "fail" if new or stale else "pass"
    return {"schema_version": 1, "source": manifest.get("source", {}),
            "input_sha256": manifest.get("input_sha256"), "entries_sha256": hashlib.sha256(canonical).hexdigest(),
            "policy": asdict(policy), "root_utf16": root_length, "root_separator_utf16": separator,
            "statistics_scope": "complete_inventory" if coverage["complete"] else "observed_entries_only",
            "counting": {"windows": "Original Unicode UTF-16 code units; no normalization",
                         "full_visible": "root + at most one join separator + projected relative path; excludes final NUL",
                         "directory_depth": "ancestor directories for files; includes self for directory entries",
                         "zip_directory_terminator": "Original path retained; final slash excluded from extracted path metrics"},
            "coverage": coverage, "gate": gate,
            "summary": {"entries": len(rows), "types": dict(counts), "new_violations": len(new),
                        "historical_exceptions": len(active), "stale_exceptions": len(stale),
                        "max_relative_utf16": max((r["relative_utf16"] for r in rows), default=None),
                        "max_projected_relative_utf16": max((r["projected_relative_utf16"] for r in rows), default=None),
                        "max_segment_utf16": max((r["max_segment_utf16"] for r in rows), default=None),
                        "max_utf8_bytes": max((r["utf8_bytes"] for r in rows), default=None),
                        "max_directory_depth": max((r["directory_depth"] for r in rows), default=None)},
            "baseline": {"used": baseline is not None, "reference_checked": baseline_reference is not None,
                         "active_exact_paths": active, "stale_requires_removal": stale,
                         "trust_requirement": "Read baseline from trusted target revision; never trust PR-added exceptions without review"},
            "impact_matrix": impact_matrix(rows, set(exceptions)),
            "by_top_directory": dict(sorted(dirs.items())),
            "longest_30": sorted(rows, key=lambda r: (-r["relative_utf16"], r["path"]))[:30],
            "violations": [r for r in rows if r["violations"]], "entries": rows,
            "performance": {"scan_seconds": time.perf_counter() - started,
                            "scope": "normalization, metrics, baseline, summaries; excludes input fetch/parse and output serialization"}}


CSV_FIELDS = ["path", "type", "mode", "sha", "category", "relative_utf16", "max_segment_utf16",
              "utf8_bytes", "directory_depth", "segment_count", "projected_path", "projected_relative_utf16",
              "projected_max_segment_utf16", "full_visible_utf16", "visible_headroom", "status", "violation_rules"]


def write_csv(report, path):
    with open(path, "w", encoding="utf-8", newline="") as output:
        writer = csv.DictWriter(output, fieldnames=CSV_FIELDS)
        writer.writeheader()
        for row in report["entries"]:
            csvrow = {k: row.get(k) for k in CSV_FIELDS}
            csvrow["violation_rules"] = ";".join(v["rule"] for v in row["violations"])
            writer.writerow(csvrow)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input")
    parser.add_argument("--format", choices=("manifest", "git-ls-tree-nul", "archive-list", "zip"), default="manifest")
    parser.add_argument("--metadata", help="Source/completeness JSON for raw Git/archive lists")
    parser.add_argument("--relative-limit", type=int, default=200)
    parser.add_argument("--root-units", type=int, default=60, help="Root model length excluding its join separator")
    parser.add_argument("--root", default="", help="Actual root; overrides --root-units")
    parser.add_argument("--full-visible-limit", type=int, default=240)
    parser.add_argument("--segment-limit", type=int, default=255)
    parser.add_argument("--prefix", default="")
    parser.add_argument("--suffix", default="")
    parser.add_argument("--already-projected", action="store_true")
    parser.add_argument("--baseline", help="Reviewed exact-path baseline, sourced from a trusted revision")
    parser.add_argument("--baseline-reference", help="Trusted baseline to reject additions/expansion in candidate baseline")
    parser.add_argument("--json", dest="json_output", help="JSON output path, or - for stdout")
    parser.add_argument("--csv", help="All-entry UTF-8 CSV output path")
    args = parser.parse_args(argv)
    try:
        metadata = read_json(args.metadata) if args.metadata else None
        manifest = load_manifest(args.input, args.format, metadata)
        policy = Policy(relative_limit=args.relative_limit, root_units=args.root_units,
                        full_visible_limit=args.full_visible_limit, segment_limit=args.segment_limit,
                        root=args.root, prefix=args.prefix, suffix=args.suffix, already_projected=args.already_projected)
        report = audit(manifest, policy, read_json(args.baseline) if args.baseline else None,
                       read_json(args.baseline_reference) if args.baseline_reference else None)
        if args.json_output:
            payload = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
            if args.json_output == "-":
                sys.stdout.write(payload)
            else:
                Path(args.json_output).write_text(payload, encoding="utf-8")
        if args.csv:
            write_csv(report, args.csv)
        summary = report["summary"]
        stream = sys.stderr if args.json_output == "-" else sys.stdout
        print("gate=%s entries=%s new=%s historical=%s stale=%s scan=%.6fs" % (
              report["gate"], summary["entries"], summary["new_violations"], summary["historical_exceptions"],
              summary["stale_exceptions"], report["performance"]["scan_seconds"]), file=stream)
        for error in report["coverage"]["errors"]:
            print("INCOMPLETE: " + error, file=stream)
        for row in report["violations"][:20]:
            print("%s utf16=%d full=%d %s" % (json.dumps(row["path"], ensure_ascii=False),
                  row["projected_relative_utf16"], row["full_visible_utf16"], row["status"]), file=stream)
        return 2 if report["gate"] == "incomplete" else 1 if report["gate"] == "fail" else 0
    except (AuditError, OSError, TypeError, KeyError) as exc:
        print("ERROR: " + str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
