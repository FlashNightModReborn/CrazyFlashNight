from __future__ import annotations

import math
import random
from dataclasses import asdict, dataclass, field
from typing import Dict, Iterable, List, Optional

from scenario_lib import Scenario


def _to_float(value: object, default: float = 0.0) -> float:
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        return default
    if math.isnan(parsed):
        return default
    return parsed


def _wrap_degrees(angle: float) -> float:
    while angle > 180.0:
        angle -= 360.0
    while angle < -180.0:
        angle += 360.0
    return angle


@dataclass
class SimulationOptions:
    velocity: float = 20.0
    rotation: float = 0.0
    use_prelaunch: bool = False
    max_frames: int = 150
    hit_radius: float = 10.0
    pressure_radius: float = 60.0
    designated_target: bool = True
    capture_trace: bool = True


@dataclass
class FrameSample:
    frame: int
    missile_x: float
    missile_y: float
    target_x: float
    target_y: float
    state_name: str
    distance: float


@dataclass
class SimulationResult:
    config_name: str
    scenario_name: str
    description: str
    hit: bool
    hit_frame: Optional[int]
    expired: bool
    frames_simulated: int
    min_distance: float
    terminal_distance: float
    pressure_frames: int
    first_pressure_frame: Optional[int]
    max_pressure_streak: int
    lock_frame: Optional[int]
    use_prelaunch: bool
    designated_target: bool
    warnings: List[str] = field(default_factory=list)
    trace: List[FrameSample] = field(default_factory=list)

    def summary_dict(self) -> Dict[str, object]:
        payload = asdict(self)
        payload.pop("trace", None)
        return payload


@dataclass
class TargetState:
    x: float
    y: float
    vx: float = 0.0
    vy: float = 0.0
    context: Dict[str, float] = field(default_factory=dict)


@dataclass
class MissileState:
    x: float
    y: float
    vx: float = 0.0
    vy: float = 0.0
    speed: float = 0.0
    acceleration: float = 0.5
    max_speed: float = 10.0
    rotation_angle: float = 0.0
    rotation_speed: float = 5.0
    drag_coefficient: float = 0.001
    desired_angular_velocity: float = 0.0
    state_name: str = "Initialize"
    frame: int = 0
    has_target: bool = False
    previous_los_angle: Optional[float] = None
    lock_rotation: bool = False
    pre_initialized: bool = False
    pre_frame: int = 0
    pre_total: int = 0
    launch_x: float = 0.0
    launch_y: float = 0.0
    peak_height: float = 0.0
    horiz_amp: float = 0.0
    horiz_cycles: float = 0.0
    launch_cos: float = 1.0
    launch_sin: float = 0.0


def _pick_linear_range(rng: random.Random, node: Dict[str, object]) -> float:
    low = _to_float(node.get("min"))
    high = _to_float(node.get("max"))
    if high <= low:
        return low
    return low + rng.random() * (high - low)


def _pick_int_range(rng: random.Random, node: Dict[str, object]) -> int:
    low = int(_to_float(node.get("min")))
    high = int(_to_float(node.get("max"), low))
    if high <= low:
        return low
    return low + rng.randrange(high - low + 1)


def _initialize_missile(missile: MissileState, config: Dict[str, object], options: SimulationOptions) -> None:
    initial_speed_ratio = _to_float(config.get("initialSpeedRatio"))
    rotation_speed = _to_float(config.get("rotationSpeed"))
    acceleration = _to_float(config.get("acceleration"))

    missile.speed = max(0.0, options.velocity * initial_speed_ratio)
    missile.rotation_angle = options.rotation
    missile.rotation_speed = rotation_speed
    missile.max_speed = max(0.0, options.velocity)
    missile.acceleration = acceleration
    missile.previous_los_angle = None
    radians = math.radians(options.rotation)
    missile.vx = missile.speed * math.cos(radians)
    missile.vy = missile.speed * math.sin(radians)
    missile.desired_angular_velocity = 0.0


def _search_for_target(
    missile: MissileState,
    target: TargetState,
    config: Dict[str, object],
    options: SimulationOptions,
) -> bool:
    if options.designated_target:
        missile.has_target = True
        return True

    search_range = _to_float(config.get("searchRange"))
    distance = math.hypot(target.x - missile.x, target.y - missile.y)
    found = distance <= search_range
    missile.has_target = found
    return found


def _track_target(missile: MissileState, target: TargetState, config: Dict[str, object]) -> None:
    dx = target.x - missile.x
    dy = target.y - missile.y
    current_los_angle = math.degrees(math.atan2(dy, dx))

    if missile.previous_los_angle is None:
        missile.previous_los_angle = current_los_angle
        missile.desired_angular_velocity = 0.0
        missile.has_target = True
        return

    los_angular_velocity = current_los_angle - missile.previous_los_angle
    if los_angular_velocity > 180.0:
        los_angular_velocity -= 360.0
    elif los_angular_velocity < -180.0:
        los_angular_velocity += 360.0

    required_angular_velocity = _to_float(config.get("navigationRatio")) * los_angular_velocity
    current_angle = missile.rotation_angle
    angle_diff = _wrap_degrees(current_los_angle - current_angle)
    corrected_angular_velocity = angle_diff * _to_float(config.get("angleCorrection"))
    final_angular_velocity = (required_angular_velocity + corrected_angular_velocity) / 2.0
    missile.desired_angular_velocity = math.radians(final_angular_velocity)
    missile.previous_los_angle = current_los_angle
    missile.has_target = True


def _prelaunch_move(
    missile: MissileState,
    config: Dict[str, object],
    options: SimulationOptions,
    rng: random.Random,
) -> None:
    if not missile.pre_initialized:
        missile.pre_initialized = True
        missile.pre_frame = 0
        missile.rotation_angle = options.rotation
        missile.pre_total = _pick_int_range(rng, config["preLaunchFrames"])
        missile.launch_x = missile.x
        missile.launch_y = missile.y
        radians = math.radians(options.rotation)
        missile.launch_cos = math.cos(radians)
        missile.launch_sin = math.sin(radians)
        missile.peak_height = _pick_linear_range(rng, config["preLaunchPeakHeight"])
        horiz_amp_node = config.get("preLaunchHorizAmp")
        cycles_node = config.get("preLaunchCycles")
        missile.horiz_amp = _pick_linear_range(rng, horiz_amp_node) if isinstance(horiz_amp_node, dict) else 5.0
        missile.horiz_cycles = _pick_linear_range(rng, cycles_node) if isinstance(cycles_node, dict) else 2.0

    missile.pre_frame += 1
    t = missile.pre_frame / float(max(1, missile.pre_total))
    if t < 0.4:
        t1 = t / 0.4
        y = -missile.peak_height * (1.0 - math.pow(1.0 - t1, 3))
    else:
        t2 = (t - 0.4) / 0.6
        y = -missile.peak_height * (1.0 - math.pow(t2, 3))

    decay = 1.0 - t
    sin_value = math.sin(2.0 * math.pi * missile.horiz_cycles * t)
    forward_offset = missile.horiz_amp * decay * sin_value
    x = missile.launch_cos * forward_offset
    forward_y = missile.launch_sin * forward_offset * 0.15

    shake = config["rotationShakeTime"]
    if _to_float(shake.get("start")) < t < _to_float(shake.get("end")):
        missile.rotation_angle = options.rotation + (rng.random() - 0.5) * _to_float(config.get("rotationShakeAmplitude"))
    else:
        missile.rotation_angle = options.rotation

    missile.x = missile.launch_x + x
    missile.y = missile.launch_y + y + forward_y
    missile.lock_rotation = True


def _run_state_machine(
    missile: MissileState,
    target: TargetState,
    config: Dict[str, object],
    options: SimulationOptions,
    rng: random.Random,
) -> None:
    for _ in range(10):
        state_name = missile.state_name

        if state_name == "PreLaunch":
            _prelaunch_move(missile, config, options, rng)
            if missile.pre_frame >= missile.pre_total:
                missile.state_name = "Initialize"
                continue
            break

        if state_name == "Initialize":
            _initialize_missile(missile, config, options)
            missile.state_name = "SearchTarget"
            continue

        if state_name == "SearchTarget":
            if _search_for_target(missile, target, config, options):
                missile.state_name = "TrackTarget"
                continue
            missile.state_name = "FreeFly"
            continue

        if state_name == "TrackTarget":
            _track_target(missile, target, config)
            if not missile.has_target:
                missile.state_name = "SearchTarget"
                continue
            break

        if state_name == "FreeFly":
            break

        raise ValueError("Unknown missile state: " + state_name)


def _apply_physics(missile: MissileState) -> None:
    vx = 0.0 if math.isnan(missile.vx) else missile.vx
    vy = 0.0 if math.isnan(missile.vy) else missile.vy
    desired = 0.0 if math.isnan(missile.desired_angular_velocity) else missile.desired_angular_velocity
    rotation_angle = 0.0 if math.isnan(missile.rotation_angle) else missile.rotation_angle
    acceleration = 0.0 if math.isnan(missile.acceleration) else missile.acceleration
    max_speed = 0.0 if math.isnan(missile.max_speed) or missile.max_speed < 0.0 else missile.max_speed
    rotation_speed = 5.0 if math.isnan(missile.rotation_speed) else missile.rotation_speed
    drag_coefficient = 0.001 if math.isnan(missile.drag_coefficient) else missile.drag_coefficient

    current_speed = math.hypot(vx, vy)
    if current_speed > 0.001:
        current_angle = math.atan2(vy, vx)
    else:
        current_angle = math.radians(rotation_angle)
    max_turn_rate_rad = math.radians(rotation_speed)
    normal_accel = max_turn_rate_rad * current_speed
    turn_force = desired * current_speed
    turn_force = max(-normal_accel, min(normal_accel, turn_force))

    normal_dir_x = -math.sin(current_angle)
    normal_dir_y = math.cos(current_angle)

    thrust_x = 0.0
    thrust_y = 0.0
    if current_speed < max_speed:
        forward_dir_x = math.cos(current_angle)
        forward_dir_y = math.sin(current_angle)
        thrust_x = forward_dir_x * acceleration
        thrust_y = forward_dir_y * acceleration

    speed_squared = current_speed * current_speed
    drag_x = -vx * drag_coefficient * speed_squared
    drag_y = -vy * drag_coefficient * speed_squared
    turn_angle = abs(desired)
    induced_drag_factor = 1.0 + math.sin(turn_angle) * 2.0
    drag_x *= induced_drag_factor
    drag_y *= induced_drag_factor

    vx += thrust_x + normal_dir_x * turn_force + drag_x
    vy += thrust_y + normal_dir_y * turn_force + drag_y

    new_speed = math.hypot(vx, vy)
    if math.isnan(new_speed) or new_speed <= 0.0:
        vx = 0.0
        vy = 0.0
        new_speed = 0.0
    elif new_speed > max_speed > 0.0:
        scale = max_speed / new_speed
        vx *= scale
        vy *= scale
        new_speed = max_speed

    missile.vx = vx
    missile.vy = vy
    missile.speed = new_speed

    if missile.lock_rotation:
        missile.lock_rotation = False
    else:
        missile.x += vx
        missile.y += vy
        if new_speed > 0.001:
            rotation_angle = math.degrees(math.atan2(vy, vx))
        if math.isnan(rotation_angle):
            rotation_angle = 0.0

    missile.rotation_angle = rotation_angle


def _init_target(scenario: Scenario) -> TargetState:
    return TargetState(x=scenario.target_start[0], y=scenario.target_start[1])


def _step_target(scenario: Scenario, frame_index: int, target: TargetState, missile: MissileState) -> None:
    params = scenario.params
    kind = scenario.kind

    if kind == "straight":
        target.vx = _to_float(params.get("vx"))
        target.vy = _to_float(params.get("vy"))
        target.x += target.vx
        target.y += target.vy
        return

    if kind == "zigzag":
        interval = max(1, int(_to_float(params.get("switch_interval"), 10)))
        direction = 1.0 if ((frame_index // interval) % 2 == 0) else -1.0
        target.vx = _to_float(params.get("forward_speed"))
        target.vy = direction * _to_float(params.get("lateral_speed"))
        target.x += target.vx
        target.y += target.vy
        return

    if kind == "panic_jink":
        base_vx = _to_float(params.get("base_vx"))
        base_vy = _to_float(params.get("base_vy"))
        lateral_speed = _to_float(params.get("lateral_speed"))
        trigger_distance = _to_float(params.get("trigger_distance"))
        dash_frames = max(1, int(_to_float(params.get("dash_frames"), 6)))
        cooldown_frames = max(0, int(_to_float(params.get("cooldown_frames"), 10)))
        dash_remaining = int(target.context.get("dash_remaining", 0.0))
        cooldown = int(target.context.get("cooldown", 0.0))
        dash_sign = float(target.context.get("dash_sign", 1.0))
        distance = math.hypot(target.x - missile.x, target.y - missile.y)

        if dash_remaining > 0:
            target.vx = base_vx
            target.vy = base_vy + dash_sign * lateral_speed
            dash_remaining -= 1
            if dash_remaining == 0:
                cooldown = cooldown_frames
        else:
            if cooldown > 0:
                cooldown -= 1
            if distance <= trigger_distance and cooldown == 0:
                dash_sign = -dash_sign
                dash_remaining = dash_frames - 1
                target.vx = base_vx
                target.vy = base_vy + dash_sign * lateral_speed
                if dash_remaining == 0:
                    cooldown = cooldown_frames
            else:
                target.vx = base_vx
                target.vy = base_vy

        target.context["dash_remaining"] = float(dash_remaining)
        target.context["cooldown"] = float(cooldown)
        target.context["dash_sign"] = dash_sign
        target.x += target.vx
        target.y += target.vy
        return

    if kind == "orbit_drift":
        center_x = float(target.context.get("center_x", _to_float(params.get("center_x"))))
        center_y = float(target.context.get("center_y", _to_float(params.get("center_y"))))
        phase = float(target.context.get("phase", _to_float(params.get("phase"))))
        center_x += _to_float(params.get("drift_vx"))
        center_y += _to_float(params.get("drift_vy"))
        phase += _to_float(params.get("angular_speed"))
        new_x = center_x + _to_float(params.get("radius")) * math.cos(phase)
        new_y = center_y + _to_float(params.get("radius")) * math.sin(phase)
        target.vx = new_x - target.x
        target.vy = new_y - target.y
        target.x = new_x
        target.y = new_y
        target.context["center_x"] = center_x
        target.context["center_y"] = center_y
        target.context["phase"] = phase
        return

    if kind == "cutback":
        vx = 0.0
        vy = 0.0
        for phase in params.get("phases", []):
            if frame_index >= int(phase.get("start", 0)):
                vx = _to_float(phase.get("vx"))
                vy = _to_float(phase.get("vy"))
        target.vx = vx
        target.vy = vy
        target.x += vx
        target.y += vy
        return

    raise ValueError("Unknown target behavior: " + kind)


def simulate_scenario(
    config_name: str,
    config: Dict[str, object],
    scenario: Scenario,
    options: SimulationOptions,
    seed: int = 0,
    warnings: Optional[Iterable[str]] = None,
) -> SimulationResult:
    rng = random.Random(seed)
    target = _init_target(scenario)
    missile = MissileState(
        x=0.0,
        y=0.0,
        rotation_angle=options.rotation,
        rotation_speed=_to_float(config.get("rotationSpeed"), 5.0),
        drag_coefficient=_to_float(config.get("dragCoefficient"), 0.001),
        state_name="PreLaunch" if options.use_prelaunch else "Initialize",
    )

    trace: List[FrameSample] = []
    lock_frame: Optional[int] = None
    hit = False
    hit_frame: Optional[int] = None
    expired = False
    min_distance = float("inf")
    pressure_frames = 0
    first_pressure_frame: Optional[int] = None
    max_pressure_streak = 0
    current_pressure_streak = 0
    terminal_distance = float("inf")

    for frame_index in range(options.max_frames):
        _step_target(scenario, frame_index, target, missile)
        _run_state_machine(missile, target, config, options, rng)

        missile.frame += 1
        _apply_physics(missile)

        distance = math.hypot(target.x - missile.x, target.y - missile.y)
        min_distance = min(min_distance, distance)
        terminal_distance = distance

        if missile.has_target and lock_frame is None:
            lock_frame = missile.frame

        if distance <= options.pressure_radius:
            pressure_frames += 1
            current_pressure_streak += 1
            if first_pressure_frame is None:
                first_pressure_frame = missile.frame
            if current_pressure_streak > max_pressure_streak:
                max_pressure_streak = current_pressure_streak
        else:
            current_pressure_streak = 0

        if options.capture_trace:
            trace.append(
                FrameSample(
                    frame=missile.frame,
                    missile_x=missile.x,
                    missile_y=missile.y,
                    target_x=target.x,
                    target_y=target.y,
                    state_name=missile.state_name,
                    distance=distance,
                )
            )

        if distance <= options.hit_radius:
            hit = True
            hit_frame = missile.frame
            break

        if missile.frame >= options.max_frames:
            expired = True
            break

    return SimulationResult(
        config_name=config_name,
        scenario_name=scenario.name,
        description=scenario.description,
        hit=hit,
        hit_frame=hit_frame,
        expired=expired,
        frames_simulated=missile.frame,
        min_distance=min_distance,
        terminal_distance=terminal_distance,
        pressure_frames=pressure_frames,
        first_pressure_frame=first_pressure_frame,
        max_pressure_streak=max_pressure_streak,
        lock_frame=lock_frame,
        use_prelaunch=options.use_prelaunch,
        designated_target=options.designated_target,
        warnings=list(warnings or []),
        trace=trace,
    )


def simulate_batch(
    config_name: str,
    config: Dict[str, object],
    scenarios: Iterable[Scenario],
    options: SimulationOptions,
    seed: int = 0,
    warnings: Optional[Iterable[str]] = None,
) -> List[SimulationResult]:
    results: List[SimulationResult] = []
    for index, scenario in enumerate(scenarios):
        results.append(
            simulate_scenario(
                config_name=config_name,
                config=config,
                scenario=scenario,
                options=options,
                seed=seed + index * 1009,
                warnings=warnings,
            )
        )
    return results
