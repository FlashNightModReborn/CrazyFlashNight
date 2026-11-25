#!/usr/bin/env python3
"""Evaluate a camera write inventory against the exact source policy."""

import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path

from camera_write_scan import TOOL_VERSION, external_output, sha256, tokens, write_json


POLICY = Path(__file__).with_name("camera_write_policy.json")
FINGERPRINT_FIELDS = (
    "sourcePath", "symbolName", "linkageIdentifier", "frameOrClipEvent",
    "target", "property", "operator",
)
COVERAGE_FIELDS = ("parseFailures", "dynamicReview", "unsupportedSourceContainers")


def fingerprint(row):
    identity = [row[key] for key in FINGERPRINT_FIELDS]
    identity.append(" ".join(t[0] for t in tokens(row["writeExpression"])))
    return hashlib.sha256(json.dumps(identity, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()


def policy_index(policy):
    rules = {}
    for ledger in ("allow", "removedLiveLegacy", "repositoryLegacyDebt"):
        for rule in policy[ledger]:
            key = rule["fingerprint"]
            if key in rules or key != fingerprint(rule) or type(rule["maxCount"]) is not int or rule["maxCount"] < 1:
                raise ValueError(f"invalid or duplicate policy fingerprint: {key}")
            rules[key] = (ledger, rule)
    return rules


def evaluate(rows, policy, mode, coverage, *, require_complete_coverage=False):
    rules = policy_index(policy)
    closure = set(policy["liveClosureFiles"])
    observed = defaultdict(list)
    for row in rows:
        observed[fingerprint(row)].append(row)

    violations, live_entries, repo_entries = [], [], []
    authority_preserved = live_removed = 0
    for key in sorted(rules.keys() | observed.keys()):
        ledger, rule = rules.get(key, ("unreviewed", {}))
        matches = observed.get(key, [])
        count = len(matches)
        maximum = rule.get("maxCount", 0)
        entry = dict(rule or matches[0], fingerprint=key, count=count,
                     lines=[row.get("line", "unknown") for row in matches])
        if ledger == "removedLiveLegacy":
            live_entries.append(entry)
            live_removed += max(0, maximum - count)
        elif ledger == "repositoryLegacyDebt":
            repo_entries.append(entry)
        elif rule.get("category") == "camera_authority":
            authority_preserved += min(count, maximum)

        if not count:
            continue
        if ledger == "removedLiveLegacy":
            reason = "removed_live_writer_reappeared"
        elif entry["sourcePath"].split("::", 1)[0] in closure and ledger != "allow":
            reason = "unauthorized_live_closure_writer"
        elif ledger == "repositoryLegacyDebt" and (mode == "clean" or count > maximum):
            reason = "repository_legacy_remaining" if mode == "clean" else "repository_legacy_count_increased"
        elif count > maximum:
            reason = "unreviewed_global_transform_writer" if not maximum else "allowed_writer_count_increased"
        else:
            continue
        violations.append(dict(entry, reason=reason))

    scope = coverage["scope"]
    if scope != "full":
        violations.append(dict(reason="full_repository_inventory_required", scope=scope))
    if coverage["toolVersion"] != TOOL_VERSION or coverage["writeExpressions"] != len(rows):
        violations.append(dict(reason="source_inventory_metadata_mismatch"))
    for item in coverage["parseFailures"]:
        path = item["sourcePath"]
        if path == "HEAD":
            violations.append(dict(reason="unstable_source_head"))
        elif path in closure:
            violations.append(dict(reason="live_closure_source_unreadable", sourcePath=path))

    unresolved_counts = {key: len(coverage[key]) for key in COVERAGE_FIELDS}
    unresolved = sum(unresolved_counts.values())
    strict_passed = scope == "full" and unresolved == 0
    writer_passed = not violations
    return dict(
        mode=mode, head=coverage["head"], scope=scope,
        toolVersion=TOOL_VERSION, policyVersion=policy["policyVersion"],
        boundedWriterGatePassed=writer_passed,
        strictCoveragePassed=strict_passed,
        gatePassed=writer_passed and (strict_passed or not require_complete_coverage),
        liveLegacyRemaining=sum(entry["count"] for entry in live_entries),
        liveLegacyRemoved=live_removed,
        repositoryLegacyRemaining=sum(entry["count"] for entry in repo_entries),
        authorityPreserved=authority_preserved,
        coverageUnresolved=unresolved, coverageCounts=unresolved_counts,
        removedLiveLegacy=live_entries, repositoryLegacyDebt=repo_entries,
        liveClosureFiles=policy["liveClosureFiles"], violations=violations,
        coverage=coverage,
        qualification="Bounded source gate. The six SWF paths are verified by verify_published_swfs.py.",
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory", type=Path, required=True)
    parser.add_argument("--policy", type=Path, default=POLICY)
    parser.add_argument("--coverage", type=Path)
    parser.add_argument("--mode", choices=("new", "live-clean", "clean"), default="new")
    parser.add_argument("--require-complete-coverage", action="store_true")
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    coverage_path = args.coverage or args.inventory.with_name("source-scan-coverage.json")
    coverage = json.loads(coverage_path.read_text(encoding="utf-8-sig"))
    if coverage["inventorySha256"] != sha256(args.inventory):
        parser.error("inventory SHA-256 differs from the coverage receipt")
    rows = json.loads(args.inventory.read_text(encoding="utf-8-sig"))
    policy = json.loads(args.policy.read_text(encoding="utf-8-sig"))
    report = evaluate(rows, policy, args.mode, coverage,
                      require_complete_coverage=args.require_complete_coverage)
    report_path = external_output(Path(__file__).resolve().parents[2], args.report)
    write_json(report_path, report)
    summary = ("mode", "boundedWriterGatePassed", "strictCoveragePassed", "gatePassed",
               "liveLegacyRemaining", "liveLegacyRemoved", "repositoryLegacyRemaining",
               "authorityPreserved", "coverageUnresolved", "coverageCounts", "toolVersion",
               "policyVersion")
    print(json.dumps({key: report[key] for key in summary}, ensure_ascii=False))
    if not report["boundedWriterGatePassed"]:
        return 2
    return 0 if report["gatePassed"] else 3


if __name__ == "__main__":
    raise SystemExit(main())
