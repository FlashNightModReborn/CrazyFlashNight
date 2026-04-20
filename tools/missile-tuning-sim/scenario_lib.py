from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Dict, List, Tuple


@dataclass(frozen=True)
class Scenario:
    name: str
    description: str
    target_start: Tuple[float, float]
    kind: str
    params: Dict[str, object] = field(default_factory=dict)


def _orbit_start(center_x: float, center_y: float, radius: float, phase: float) -> Tuple[float, float]:
    return (
        center_x + radius * math.cos(phase),
        center_y + radius * math.sin(phase),
    )


STANDARD_SCENARIOS: List[Scenario] = [
    Scenario(
        name="straight_retreat",
        description="Target keeps opening distance on a clean line.",
        target_start=(110.0, 0.0),
        kind="straight",
        params={"vx": 1.2, "vy": 0.0},
    ),
    Scenario(
        name="lateral_cross",
        description="Target drifts forward while cutting across the line of fire.",
        target_start=(90.0, 45.0),
        kind="straight",
        params={"vx": 0.8, "vy": -1.4},
    ),
    Scenario(
        name="wide_zigzag",
        description="Target retreats with repeated side-switching.",
        target_start=(120.0, 0.0),
        kind="zigzag",
        params={"forward_speed": 1.0, "lateral_speed": 1.8, "switch_interval": 10},
    ),
    Scenario(
        name="panic_jink",
        description="Target retreats, then throws short panic dashes when the missile gets close.",
        target_start=(100.0, 10.0),
        kind="panic_jink",
        params={
            "base_vx": 1.0,
            "base_vy": 0.0,
            "lateral_speed": 2.8,
            "trigger_distance": 65.0,
            "dash_frames": 6,
            "cooldown_frames": 10,
        },
    ),
    Scenario(
        name="orbiting_kite",
        description="Target keeps a small circular kite while drifting away.",
        target_start=_orbit_start(86.0, 0.0, 28.0, 1.0),
        kind="orbit_drift",
        params={
            "center_x": 86.0,
            "center_y": 0.0,
            "radius": 28.0,
            "phase": 1.0,
            "angular_speed": 0.09,
            "drift_vx": 0.55,
            "drift_vy": 0.0,
        },
    ),
    Scenario(
        name="cutback_escape",
        description="Target retreats, hard-cuts across, then accelerates out again.",
        target_start=(115.0, -20.0),
        kind="cutback",
        params={
            "phases": [
                {"start": 0, "vx": 1.1, "vy": 0.1},
                {"start": 22, "vx": 0.3, "vy": -2.2},
                {"start": 38, "vx": 1.3, "vy": 0.5},
            ]
        },
    ),
]


PRESSURE_SCENARIOS: List[Scenario] = [
    scenario
    for scenario in STANDARD_SCENARIOS
    if scenario.name in ("wide_zigzag", "panic_jink", "orbiting_kite", "cutback_escape")
]


SCENARIO_SETS = {
    "standard": STANDARD_SCENARIOS,
    "pressure": PRESSURE_SCENARIOS,
    "all": STANDARD_SCENARIOS,
}


def get_scenarios(set_name: str = "standard") -> List[Scenario]:
    if set_name not in SCENARIO_SETS:
        raise ValueError("Unknown scenario set: " + set_name)
    return list(SCENARIO_SETS[set_name])


def get_scenario_by_name(name: str) -> Scenario:
    for scenario in STANDARD_SCENARIOS:
        if scenario.name == name:
            return scenario
    raise ValueError("Unknown scenario: " + name)


def list_scenarios() -> List[Scenario]:
    return list(STANDARD_SCENARIOS)

