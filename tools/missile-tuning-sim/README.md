# Missile Tuning Sim

Offline tuning harness for `MissileMovement.as`.

Purpose:
- mirror the current AS2 missile physics and proportional-navigation steering
- compare presets from `data/items/missileConfigs.xml`
- batch-scan parameter grids without reopening Flash CS6 for each tweak

The simulator focuses on the missile movement stack, not the whole game loop. By default it assumes a designated target, which matches the common "shooter already has an attack target" path in the current AS2 search callback.

`compare` keeps each preset's random stream stable by config name, so subset/order changes do not silently change the sampled result.
`scan` reuses the same random seed across all candidates so ranking is driven by parameters, not by different random rolls.

## What It Mirrors

- `InitMissileCallbacks.as`
- `TrackTargetCallbacks.as`
- `PreLaunchMoveCallbacks.as`
- `MissileMovement.as`

Included behaviors:
- prelaunch arc and shake
- PN guidance and angle correction
- thrust, turn-force clamp, drag, induced drag
- 150-frame missile lifetime

## Quick Start

```bash
cd tools/missile-tuning-sim
python run_sim.py audit --verbose
python run_sim.py compare --configs interceptor cruise pressureSlow --velocity 20 --use-prelaunch
python run_sim.py scan --base-config pressureSlow --objective pressure --use-prelaunch
python run_sim.py scan --base-config cruise --objective loiter --use-prelaunch --grid rotationSpeed=0.5,0.7 preLaunchFrames.min=16,22
```

## Commands

`list-scenarios`
- prints the built-in target motion cases

`audit`
- shows which presets are partial relative to `default`
- helps catch XML presets that rely on missing fields

`compare`
- runs one or more presets against built-in scenarios
- writes `summary.json`, `compare.csv`, and per-scenario SVG trajectories

`scan`
- grid-searches parameters around a base preset
- writes ranked `scan.json` and `scan.csv`
- supports dotted nested overrides such as `preLaunchFrames.min=18`

## Useful Flags

`--raw-config`
- disables default-preset merging
- useful when you want to inspect the XML as written instead of a normalized config

`--undesignated-target`
- forces the simulator to respect `searchRange`
- default mode keeps the target predesignated

`--use-prelaunch`
- includes the prelaunch arc in the simulation

`--grid rotationSpeed=1.2,1.6,2.0 acceleration=2.5:4.5:1.0`
- custom grid for `scan`

`--set preLaunchPeakHeight.max=120`
- overrides nested base-config fields before a scan

## Output

All generated files go under `tools/missile-tuning-sim/results/` unless `--out-dir` is provided.

Key metrics:
- `hit_rate`
- `avg_min_distance`
- `avg_pressure_frames`
- `avg_first_pressure_frame`
- `avg_max_pressure_streak`

The default `pressure` scan objective rewards sustained close pressure, not just raw earliest-hit time.

`loiter` rewards long pressure streaks, stable re-entry timing, and low terminal distance for slower cruise-style harassment missiles.
