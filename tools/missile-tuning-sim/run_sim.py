from __future__ import annotations

import argparse
import copy
import csv
import json
import math
import os
import zlib
from datetime import datetime
from typing import Any, Dict, Iterable, List

from config_io import build_bundles, default_xml_path, validate_effective_config
from render import write_compare_svg
from scan import DEFAULT_SCAN_GRID, aggregate_results, apply_overrides, print_scan_table, run_grid_scan
from scenario_lib import get_scenario_by_name, get_scenarios, list_scenarios
from simulator import SimulationOptions, simulate_batch


def _results_root() -> str:
    return os.path.join(os.path.dirname(__file__), "results")


def _timestamp() -> str:
    return datetime.now().strftime("%Y%m%d_%H%M%S")


def _resolve_out_dir(subcommand: str, explicit: str | None) -> str:
    if explicit:
        out_dir = explicit
    else:
        out_dir = os.path.join(_results_root(), subcommand + "_" + _timestamp())
    os.makedirs(out_dir, exist_ok=True)
    return out_dir


def _config_seed(base_seed: int, config_name: str) -> int:
    # Keep each preset's random stream stable across compare runs even if the
    # caller changes config order or compares a subset of presets.
    return base_seed + zlib.crc32(config_name.encode("utf-8"))


def _parse_scalar(raw: str) -> Any:
    value = raw.strip()
    lower = value.lower()
    if lower == "true":
        return True
    if lower == "false":
        return False

    try:
        if any(ch in value for ch in ".eE"):
            parsed = float(value)
            return int(parsed) if parsed.is_integer() else parsed
        return int(value)
    except ValueError:
        try:
            parsed = float(value)
            return int(parsed) if parsed.is_integer() else parsed
        except ValueError:
            return value


def _expand_range(spec: str) -> List[Any]:
    parts = [part.strip() for part in spec.split(":")]
    if len(parts) != 3:
        raise ValueError("Range specs must look like start:stop:step")
    start = float(parts[0])
    stop = float(parts[1])
    step = float(parts[2])
    if step <= 0:
        raise ValueError("Range step must be > 0")

    values: List[Any] = []
    current = start
    epsilon = step / 1000.0
    while current <= stop + epsilon:
        rounded = round(current, 10)
        values.append(int(rounded) if float(rounded).is_integer() else rounded)
        current += step
    return values


def _parse_assignments(assignments: Iterable[str]) -> Dict[str, Any]:
    parsed: Dict[str, Any] = {}
    for assignment in assignments:
        if "=" not in assignment:
            raise ValueError("Assignments must look like key=value")
        key, raw_value = assignment.split("=", 1)
        parsed[key.strip()] = _parse_scalar(raw_value)
    return parsed


def _parse_grid_assignments(assignments: Iterable[str]) -> Dict[str, List[Any]]:
    grid: Dict[str, List[Any]] = {}
    for assignment in assignments:
        if "=" not in assignment:
            raise ValueError("Grid assignments must look like key=v1,v2 or key=start:stop:step")
        key, raw_value = assignment.split("=", 1)
        raw_value = raw_value.strip()
        if ":" in raw_value and "," not in raw_value:
            values = _expand_range(raw_value)
        else:
            values = [_parse_scalar(part) for part in raw_value.split(",") if part.strip() != ""]
        if not values:
            raise ValueError("Grid assignment has no values: " + assignment)
        grid[key.strip()] = values
    return grid


def _json_safe(value: Any) -> Any:
    if isinstance(value, float):
        if math.isnan(value) or math.isinf(value):
            return None
        return value
    if isinstance(value, dict):
        return {key: _json_safe(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_json_safe(item) for item in value]
    return value


def _write_json(path: str, payload: Dict[str, Any]) -> None:
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(_json_safe(payload), handle, indent=2, ensure_ascii=False)


def _serializable_args(args: argparse.Namespace) -> Dict[str, Any]:
    payload = dict(vars(args))
    payload.pop("func", None)
    return payload


def _fmt(value: Any, digits: int = 2) -> str:
    if value is None:
        return ""
    if isinstance(value, float):
        if math.isnan(value) or math.isinf(value):
            return ""
        return ("{0:." + str(digits) + "f}").format(value)
    return str(value)


def _scenario_list(args: argparse.Namespace):
    if args.scenario:
        return [get_scenario_by_name(args.scenario)]
    return get_scenarios(args.scenario_set)


def _sim_options(args: argparse.Namespace, capture_trace: bool = True) -> SimulationOptions:
    return SimulationOptions(
        velocity=args.velocity,
        rotation=args.rotation,
        use_prelaunch=args.use_prelaunch,
        max_frames=args.max_frames,
        hit_radius=args.hit_radius,
        pressure_radius=args.pressure_radius,
        designated_target=args.designated_target,
        capture_trace=capture_trace,
    )


def cmd_list_scenarios(_: argparse.Namespace) -> None:
    print("Available scenarios:")
    for scenario in list_scenarios():
        print("  {name:<16} {description}".format(name=scenario.name, description=scenario.description))


def cmd_audit(args: argparse.Namespace) -> None:
    merged_bundles = build_bundles(args.xml_path, merge_default=True)
    raw_bundles = build_bundles(args.xml_path, merge_default=False)
    out_dir = _resolve_out_dir("audit", args.out_dir)

    rows: List[Dict[str, Any]] = []
    print("\nPreset completeness audit:")
    for name in sorted(merged_bundles.keys()):
        merged = merged_bundles[name]
        raw = raw_bundles[name]
        required_missing = validate_effective_config(raw.effective, args.use_prelaunch, args.designated_target)
        row = {
            "name": name,
            "missing_default_fields": merged.missing_fields,
            "required_missing_without_merge": required_missing,
        }
        rows.append(row)
        print(
            "  {name:<16} raw_missing={raw_missing:<2} required_missing={required_missing_count:<2}".format(
                name=name,
                raw_missing=len(merged.missing_fields),
                required_missing_count=len(required_missing),
            )
        )
        if args.verbose and merged.missing_fields:
            print("    defaults: " + ", ".join(merged.missing_fields))
        if args.verbose and required_missing:
            print("    raw required: " + ", ".join(required_missing))

    _write_json(
        os.path.join(out_dir, "audit.json"),
        {
            "xml_path": args.xml_path,
            "use_prelaunch": args.use_prelaunch,
            "designated_target": args.designated_target,
            "rows": rows,
        },
    )
    with open(os.path.join(out_dir, "audit.csv"), "w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["name", "missing_default_fields", "required_missing_without_merge"])
        for row in rows:
            writer.writerow(
                [
                    row["name"],
                    ";".join(row["missing_default_fields"]),
                    ";".join(row["required_missing_without_merge"]),
                ]
            )
    print("\nAudit saved to: " + out_dir)


def cmd_compare(args: argparse.Namespace) -> None:
    bundles = build_bundles(args.xml_path, merge_default=not args.raw_config)
    scenarios = _scenario_list(args)
    options = _sim_options(args, capture_trace=True)
    out_dir = _resolve_out_dir("compare", args.out_dir)

    config_names = args.configs or sorted(bundles.keys())
    summary: Dict[str, Any] = {"configs": {}, "scenarios": [scenario.name for scenario in scenarios]}
    results_by_config: Dict[str, List[Any]] = {}

    print("\nPreset comparison:")
    for name in config_names:
        if name not in bundles:
            raise ValueError("Unknown config: " + name)
        bundle = bundles[name]
        required_missing = validate_effective_config(bundle.effective, args.use_prelaunch, args.designated_target)
        if required_missing:
            raise ValueError(
                "Config {0} is incomplete for this run mode. Missing: {1}".format(
                    name,
                    ", ".join(required_missing),
                )
            )

        warnings: List[str] = []
        if bundle.missing_fields and not args.raw_config:
            warnings.append("merged default fields: " + ", ".join(bundle.missing_fields))
        elif bundle.missing_fields and args.raw_config:
            warnings.append("raw preset is partial: " + ", ".join(bundle.missing_fields))

        results = simulate_batch(
            config_name=name,
            config=bundle.effective,
            scenarios=scenarios,
            options=options,
            seed=_config_seed(args.seed, name),
            warnings=warnings,
        )
        aggregate = aggregate_results(results)
        results_by_config[name] = results
        summary["configs"][name] = {
            "warnings": warnings,
            "missing_default_fields": bundle.missing_fields,
            "effective_config": bundle.effective,
            "aggregate": aggregate,
            "scenarios": [result.summary_dict() for result in results],
        }
        print(
            "  {name:<16} hit={hit:5.1%} pressure={pressure:6.2f} streak={streak:6.2f} "
            "min={min_dist:6.2f} terminal={terminal:6.2f}".format(
                name=name,
                hit=aggregate["hit_rate"],
                pressure=aggregate["avg_pressure_frames"],
                streak=aggregate["avg_max_pressure_streak"],
                min_dist=aggregate["avg_min_distance"],
                terminal=aggregate["avg_terminal_distance"],
            )
        )
        if warnings:
            print("    " + " | ".join(warnings))

    with open(os.path.join(out_dir, "compare.csv"), "w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            [
                "config",
                "hit_rate",
                "avg_hit_frame",
                "avg_min_distance",
                "avg_terminal_distance",
                "avg_pressure_frames",
                "avg_first_pressure_frame",
                "avg_max_pressure_streak",
                "avg_lock_frame",
                "warnings",
            ]
        )
        for name in config_names:
            aggregate = summary["configs"][name]["aggregate"]
            writer.writerow(
                [
                    name,
                    _fmt(aggregate["hit_rate"], 4),
                    _fmt(aggregate["avg_hit_frame"]),
                    _fmt(aggregate["avg_min_distance"]),
                    _fmt(aggregate["avg_terminal_distance"]),
                    _fmt(aggregate["avg_pressure_frames"]),
                    _fmt(aggregate["avg_first_pressure_frame"]),
                    _fmt(aggregate["avg_max_pressure_streak"]),
                    _fmt(aggregate["avg_lock_frame"]),
                    " | ".join(summary["configs"][name]["warnings"]),
                ]
            )

    if not args.no_svg:
        svg_dir = os.path.join(out_dir, "svg")
        for scenario in scenarios:
            scenario_results = []
            for name in config_names:
                scenario_results.extend(
                    result
                    for result in results_by_config[name]
                    if result.scenario_name == scenario.name
                )
            write_compare_svg(svg_dir, scenario.name, scenario_results)

    _write_json(
        os.path.join(out_dir, "summary.json"),
        {
            "xml_path": args.xml_path,
            "merge_default": not args.raw_config,
            "options": _serializable_args(args),
            "summary": summary,
        },
    )
    print("\nComparison saved to: " + out_dir)


def cmd_scan(args: argparse.Namespace) -> None:
    bundles = build_bundles(args.xml_path, merge_default=not args.raw_config)
    if args.base_config not in bundles:
        raise ValueError("Unknown base config: " + args.base_config)

    base_config = copy.deepcopy(bundles[args.base_config].effective)
    apply_overrides(base_config, _parse_assignments(args.set_values))
    required_missing = validate_effective_config(base_config, args.use_prelaunch, args.designated_target)
    if required_missing:
        raise ValueError(
            "Base config is incomplete for this run mode. Missing: " + ", ".join(required_missing)
        )

    param_grid = _parse_grid_assignments(args.grid) if args.grid else copy.deepcopy(DEFAULT_SCAN_GRID)
    scenarios = _scenario_list(args)
    options = _sim_options(args, capture_trace=False)
    out_dir = _resolve_out_dir("scan", args.out_dir)

    rows = run_grid_scan(
        base_config=base_config,
        param_grid=param_grid,
        scenarios=scenarios,
        options=options,
        objective=args.objective,
        seed=args.seed,
    )
    print_scan_table(rows, args.top_n)

    with open(os.path.join(out_dir, "scan.csv"), "w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            [
                "rank",
                "score",
                "params",
                "hit_rate",
                "avg_hit_frame",
                "avg_min_distance",
                "avg_terminal_distance",
                "avg_pressure_frames",
                "avg_first_pressure_frame",
                "avg_max_pressure_streak",
            ]
        )
        for row in rows:
            aggregate = row["aggregate"]
            writer.writerow(
                [
                    row["rank"],
                    _fmt(row["score"], 4),
                    json.dumps(row["params"], ensure_ascii=False),
                    _fmt(aggregate["hit_rate"], 4),
                    _fmt(aggregate["avg_hit_frame"]),
                    _fmt(aggregate["avg_min_distance"]),
                    _fmt(aggregate["avg_terminal_distance"]),
                    _fmt(aggregate["avg_pressure_frames"]),
                    _fmt(aggregate["avg_first_pressure_frame"]),
                    _fmt(aggregate["avg_max_pressure_streak"]),
                ]
            )

    best_config = copy.deepcopy(base_config)
    if rows:
        apply_overrides(best_config, rows[0]["params"])
    _write_json(
        os.path.join(out_dir, "scan.json"),
        {
            "xml_path": args.xml_path,
            "base_config": args.base_config,
            "objective": args.objective,
            "param_grid": param_grid,
            "options": _serializable_args(args),
            "best_config": best_config,
            "rows": rows,
        },
    )
    print("\nScan saved to: " + out_dir)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Offline missile tuning simulator")
    parser.add_argument("--xml-path", default=default_xml_path(), help="Path to missileConfigs.xml")

    subparsers = parser.add_subparsers(dest="command", required=True)

    list_parser = subparsers.add_parser("list-scenarios", help="Show built-in target scenarios")
    list_parser.set_defaults(func=cmd_list_scenarios)

    audit_parser = subparsers.add_parser("audit", help="Audit preset completeness against the default preset")
    audit_parser.add_argument("--out-dir", default=None, help="Optional output directory")
    audit_parser.add_argument("--use-prelaunch", action="store_true", help="Audit prelaunch-required fields as well")
    audit_parser.add_argument("--undesignated-target", dest="designated_target", action="store_false")
    audit_parser.add_argument("--verbose", action="store_true", help="Print missing field names")
    audit_parser.set_defaults(designated_target=True, func=cmd_audit)

    compare_parser = subparsers.add_parser("compare", help="Compare one or more presets across built-in scenarios")
    compare_parser.add_argument("--configs", nargs="*", default=None, help="Preset names to compare")
    compare_parser.add_argument("--scenario-set", default="standard", choices=["standard", "pressure", "all"])
    compare_parser.add_argument("--scenario", default=None, help="Run a single scenario by name")
    compare_parser.add_argument("--velocity", type=float, default=20.0)
    compare_parser.add_argument("--rotation", type=float, default=0.0)
    compare_parser.add_argument("--max-frames", type=int, default=150)
    compare_parser.add_argument("--hit-radius", type=float, default=10.0)
    compare_parser.add_argument("--pressure-radius", type=float, default=60.0)
    compare_parser.add_argument("--seed", type=int, default=1337)
    compare_parser.add_argument("--use-prelaunch", action="store_true")
    compare_parser.add_argument("--undesignated-target", dest="designated_target", action="store_false")
    compare_parser.add_argument("--raw-config", action="store_true", help="Do not merge missing fields from default")
    compare_parser.add_argument("--no-svg", action="store_true", help="Skip trajectory SVG output")
    compare_parser.add_argument("--out-dir", default=None, help="Optional output directory")
    compare_parser.set_defaults(designated_target=True, func=cmd_compare)

    scan_parser = subparsers.add_parser("scan", help="Grid-scan movement parameters around a base preset")
    scan_parser.add_argument("--base-config", default="default", help="Preset used as the scan baseline")
    scan_parser.add_argument("--grid", nargs="*", default=[], help="Grid spec, e.g. rotationSpeed=1.0,1.4,1.8")
    scan_parser.add_argument("--set", dest="set_values", nargs="*", default=[], help="One-off base overrides, e.g. acceleration=3.5 or preLaunchFrames.min=18")
    scan_parser.add_argument("--objective", default="pressure", choices=["pressure", "balanced", "hit", "loiter"])
    scan_parser.add_argument("--top-n", type=int, default=10)
    scan_parser.add_argument("--scenario-set", default="pressure", choices=["standard", "pressure", "all"])
    scan_parser.add_argument("--scenario", default=None, help="Run a single scenario by name")
    scan_parser.add_argument("--velocity", type=float, default=20.0)
    scan_parser.add_argument("--rotation", type=float, default=0.0)
    scan_parser.add_argument("--max-frames", type=int, default=150)
    scan_parser.add_argument("--hit-radius", type=float, default=10.0)
    scan_parser.add_argument("--pressure-radius", type=float, default=60.0)
    scan_parser.add_argument("--seed", type=int, default=1337)
    scan_parser.add_argument("--use-prelaunch", action="store_true")
    scan_parser.add_argument("--undesignated-target", dest="designated_target", action="store_false")
    scan_parser.add_argument("--raw-config", action="store_true", help="Do not merge missing fields from default")
    scan_parser.add_argument("--out-dir", default=None, help="Optional output directory")
    scan_parser.set_defaults(designated_target=True, func=cmd_scan)

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
