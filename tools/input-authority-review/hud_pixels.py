"""Verify that the visible modifier leaves the calibrated game HUD regions visible."""

import argparse
import json
from pathlib import Path

from evidence import identities_match, link, read_json, same_path


# Coordinates are in the game client at the captured 1600×900 layout.
REGIONS = {
    "healthWheel": ((14, 748, 122, 857), ("red", "cyan")),
    "powerBars": ((146, 815, 423, 878), ("cyan",)),
    "skillIcons": ((941, 834, 1041, 886), ("white",)),
    "skillRail": ((1170, 836, 1585, 890), ("white",)),
    "skillHeader": ((933, 804, 1156, 826), ("white",)),
}


def overlap(left, right):
    return left[0] < right[2] and right[0] < left[2] and left[1] < right[3] and right[1] < left[3]


def pixel_evidence(file, desktop):
    from PIL import Image

    if desktop.get("clientSize") != [1600, 900]:
        raise ValueError("The HUD component coordinates are calibrated for the 1600×900 game client.")
    windows = desktop["windows"]
    game = next(window for window in windows if window["hwnd"] == desktop["root"])
    game_rect = game["rect"]
    origin_x, origin_y = desktop["clientOrigin"]
    modifier = [window["rect"] for window in windows if window.get("title") == "CF7 Modifier"]
    results = {}
    with Image.open(file) as image:
        if image.size != (game_rect[2] - game_rect[0], game_rect[3] - game_rect[1]):
            raise ValueError("Screenshot dimensions do not match the captured game window.")
        for name, ((left, top, right, bottom), channels) in REGIONS.items():
            screen = (left + origin_x, top + origin_y, right + origin_x, bottom + origin_y)
            if not (game_rect[0] <= screen[0] < screen[2] <= game_rect[2] and game_rect[1] <= screen[1] < screen[3] <= game_rect[3]):
                raise ValueError(f"{name} is outside the observed game window.")
            if any(overlap(screen, bounds) for bounds in modifier):
                raise ValueError(f"{name} overlaps the separately visible Modifier window.")
            image_rect = (screen[0] - game_rect[0], screen[1] - game_rect[1], screen[2] - game_rect[0], screen[3] - game_rect[1])
            rgb = image.crop(image_rect).convert("RGB").tobytes()
            pixels = list(zip(rgb[::3], rgb[1::3], rgb[2::3]))
            counts = {
                "red": sum(red > 85 and red - green > 45 and red - blue > 32 for red, green, blue in pixels),
                "cyan": sum(min(green, blue) > 80 and min(green, blue) - red > 38 for red, green, blue in pixels),
                "white": sum(min(pixel) > 150 and max(pixel) - min(pixel) < 45 for pixel in pixels),
            }
            results[name] = {"screenRect": screen, "imageRect": image_rect, "pixels": len(pixels),
                             "counts": {channel: counts[channel] for channel in channels}}
    return {"screenshot": link(file), "modifierRects": modifier, "regions": results}


def read_hud_capture(run_root, expected=None):
    process_file = run_root / "process.json"
    desktop_file = run_root / "desktop.jsonl"
    cycles_file = run_root / "entry-cycles.json"
    process = read_json(process_file)
    observed = {"processPath": process.get("processPath"), "runtimeMode": process.get("runtimeMode"), "pid": process.get("pid"),
                **{key: process.get(key) for key in ("buildIdentity", "payloadClosure", "coreSha256")}}
    facts = {"status": "BLOCKED", "identityMatched": None, "observed": observed,
             "raw": link(desktop_file), "process": link(process_file), "cycles": link(cycles_file), "cases": {}}
    if expected:
        facts["identityMatched"] = (identities_match(process, expected) and same_path(process.get("processPath"), expected["processPath"]) and
                                    process.get("runtimeMode") == "isolated_candidate")
        if not facts["identityMatched"]:
            return facts
    with desktop_file.open(encoding="utf-8-sig") as source:
        desktop = {row["case"]: row for row in map(json.loads, source)}
    phases = ("before", "opened", "items-visible", "closed")
    for trial in read_json(cycles_file):
        cycle = f"entry-{trial['cycle']}"
        selected = phases + (("reopened",) if trial.get("held") else ())
        measurements = {}
        try:
            for phase in selected:
                label = f"{cycle}-{phase}"
                context = desktop[label]
                owner = context.get("desktop") or {}
                if (context.get("pid") != process.get("pid") or owner.get("threadReceivesInput") is not True or
                        any(owner.get(key) != "Default" for key in ("threadDesktop", "inputDesktop"))):
                    raise ValueError(f"{label}: process or Default desktop context is missing.")
                measurements[phase] = pixel_evidence(run_root / (label + ".png"), context)
        except (KeyError, OSError, ValueError, StopIteration) as error:
            facts["cases"][cycle] = {"status": "BLOCKED", "reason": str(error), "measurements": measurements}
            continue
        references = (measurements["before"]["regions"], measurements["closed"]["regions"])
        below = []
        without_reference = []
        for region, (_, channels) in REGIONS.items():
            for channel in channels:
                reference = min(r[region]["counts"][channel] / r[region]["pixels"] for r in references)
                if reference < 0.01:
                    without_reference.append({"region": region, "channel": channel, "ratio": reference})
                    continue
                for phase in selected:
                    if phase in ("before", "closed"):
                        continue
                    stats = measurements[phase]["regions"][region]
                    ratio = stats["counts"][channel] / stats["pixels"]
                    if ratio < 0.4 * reference:
                        below.append({"phase": phase, "region": region, "channel": channel,
                                      "ratio": ratio, "referenceRatio": reference, "requiredRatio": 0.4 * reference})
        facts["cases"][cycle] = {"status": "FAIL" if below else "BLOCKED" if without_reference else "PASS",
                                 "held": trial.get("held"), "belowReference": below, "invalidReference": without_reference,
                                 "measurements": measurements}
    outcomes = {row["status"] for row in facts["cases"].values()}
    held_cases = {row.get("held") for row in facts["cases"].values() if row["status"] == "PASS"}
    facts["status"] = "FAIL" if "FAIL" in outcomes else "PASS" if outcomes == {"PASS"} and held_cases == {False, True} else "BLOCKED"
    facts["regions"] = {name: {"clientBox": box, "channels": channels} for name, (box, channels) in REGIONS.items()}
    facts["comparedScreenshots"] = sum(len(case["measurements"]) for case in facts["cases"].values())
    return facts


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--run-root", type=Path, required=True)
    cli.add_argument("--output", type=Path, required=True)
    args = cli.parse_args()
    result = read_hud_capture(args.run_root.resolve())
    with args.output.open("x", encoding="utf-8", newline="\n") as out:
        json.dump(result, out, indent=2, ensure_ascii=False)
        out.write("\n")
    for cycle, data in result["cases"].items():
        print(cycle, data["status"], sorted({row["phase"] for row in data.get("belowReference", [])}))
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
