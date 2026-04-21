from __future__ import annotations

import copy
import itertools
from typing import Dict, Iterable, List, Tuple

from simulator import SimulationOptions, SimulationResult, simulate_batch
from scenario_lib import Scenario


DEFAULT_SCAN_GRID = {
    "rotationSpeed": [1.0, 1.4, 1.8],
    "acceleration": [2.5, 3.5, 4.5],
    "dragCoefficient": [0.0035, 0.005, 0.0065],
    "navigationRatio": [4.0, 4.8, 5.6],
    "angleCorrection": [0.16, 0.22, 0.28],
}


def _set_nested_value(target: Dict[str, object], path: str, value: object) -> None:
    parts = [part.strip() for part in path.split(".") if part.strip()]
    if not parts:
        raise ValueError("Override path cannot be empty")

    cursor: Dict[str, object] = target
    for part in parts[:-1]:
        next_value = cursor.get(part)
        if not isinstance(next_value, dict):
            next_value = {}
            cursor[part] = next_value
        cursor = next_value
    cursor[parts[-1]] = value


def apply_overrides(target: Dict[str, object], overrides: Dict[str, object]) -> Dict[str, object]:
    for path, value in overrides.items():
        _set_nested_value(target, path, value)
    return target


def aggregate_results(results: Iterable[SimulationResult]) -> Dict[str, float]:
    rows = list(results)
    total = len(rows)
    if total == 0:
        return {}

    hits = [row for row in rows if row.hit]
    pressured = [row for row in rows if row.first_pressure_frame is not None]
    locked = [row for row in rows if row.lock_frame is not None]

    return {
        "n_scenarios": float(total),
        "hit_rate": sum(1 for row in rows if row.hit) / total,
        "pressure_entry_rate": len(pressured) / total,
        "avg_hit_frame": (
            sum(row.hit_frame for row in hits if row.hit_frame is not None) / len(hits)
            if hits
            else float("inf")
        ),
        "avg_min_distance": sum(row.min_distance for row in rows) / total,
        "avg_terminal_distance": sum(row.terminal_distance for row in rows) / total,
        "avg_pressure_frames": sum(row.pressure_frames for row in rows) / total,
        "avg_first_pressure_frame": (
            sum(row.first_pressure_frame for row in pressured if row.first_pressure_frame is not None) / len(pressured)
            if pressured
            else float("inf")
        ),
        "avg_max_pressure_streak": sum(row.max_pressure_streak for row in rows) / total,
        "avg_lock_frame": (
            sum(row.lock_frame for row in locked if row.lock_frame is not None) / len(locked)
            if locked
            else float("inf")
        ),
    }


def score_aggregate(aggregate: Dict[str, float], objective: str) -> float:
    hit_rate = aggregate.get("hit_rate", 0.0)
    pressure_entry_rate = aggregate.get("pressure_entry_rate", 0.0)
    avg_hit_frame = aggregate.get("avg_hit_frame", float("inf"))
    avg_min_distance = aggregate.get("avg_min_distance", float("inf"))
    avg_terminal_distance = aggregate.get("avg_terminal_distance", float("inf"))
    avg_pressure_frames = aggregate.get("avg_pressure_frames", 0.0)
    avg_first_pressure_frame = aggregate.get("avg_first_pressure_frame", float("inf"))
    avg_max_pressure_streak = aggregate.get("avg_max_pressure_streak", 0.0)

    if objective == "hit":
        return (
            hit_rate * 8.0
            + pressure_entry_rate * 1.5
            - avg_hit_frame / 35.0
            - avg_min_distance / 45.0
            - avg_terminal_distance / 80.0
        )

    if objective == "balanced":
        return (
            hit_rate * 6.0
            + pressure_entry_rate * 2.0
            + avg_pressure_frames / 18.0
            + avg_max_pressure_streak / 15.0
            - avg_hit_frame / 55.0
            - avg_first_pressure_frame / 70.0
            - avg_terminal_distance / 90.0
        )

    if objective == "loiter":
        entry_timing = abs(avg_first_pressure_frame - 24.0)
        return (
            hit_rate * 2.5
            + pressure_entry_rate * 4.0
            + avg_pressure_frames / 8.5
            + avg_max_pressure_streak / 8.0
            - entry_timing / 16.0
            - avg_min_distance / 65.0
            - avg_terminal_distance / 70.0
        )

    return (
        hit_rate * 4.0
        + pressure_entry_rate * 3.0
        + avg_pressure_frames / 14.0
        + avg_max_pressure_streak / 12.0
        - avg_first_pressure_frame / 50.0
        - avg_terminal_distance / 85.0
    )


def run_grid_scan(
    base_config: Dict[str, object],
    param_grid: Dict[str, List[object]],
    scenarios: Iterable[Scenario],
    options: SimulationOptions,
    objective: str = "pressure",
    seed: int = 0,
) -> List[Dict[str, object]]:
    param_names = list(param_grid.keys())
    param_values = [param_grid[name] for name in param_names]
    combos = list(itertools.product(*param_values))
    rows: List[Dict[str, object]] = []

    for index, combo in enumerate(combos):
        overrides = dict(zip(param_names, combo))
        candidate = copy.deepcopy(base_config)
        apply_overrides(candidate, overrides)

        run_options = copy.deepcopy(options)
        run_options.capture_trace = False
        results = simulate_batch(
            config_name="scan_" + str(index + 1),
            config=candidate,
            scenarios=scenarios,
            options=run_options,
            seed=seed,
        )
        aggregate = aggregate_results(results)
        rows.append(
            {
                "rank": 0,
                "score": score_aggregate(aggregate, objective),
                "params": overrides,
                "aggregate": aggregate,
                "results": [result.summary_dict() for result in results],
            }
        )

    rows.sort(key=lambda row: row["score"], reverse=True)
    for rank, row in enumerate(rows, start=1):
        row["rank"] = rank
    return rows


def print_scan_table(rows: List[Dict[str, object]], top_n: int = 10) -> None:
    print("\nTop scan candidates:")
    for row in rows[:top_n]:
        aggregate = row["aggregate"]
        print(
            "  #{rank:<2} score={score:7.3f} hit={hit:5.1%} pressure={pressure:6.2f} "
            "streak={streak:6.2f} min={min_dist:6.2f} params={params}".format(
                rank=row["rank"],
                score=row["score"],
                hit=aggregate["hit_rate"],
                pressure=aggregate["avg_pressure_frames"],
                streak=aggregate["avg_max_pressure_streak"],
                min_dist=aggregate["avg_min_distance"],
                params=row["params"],
            )
        )
