"""Validate explicit overload metadata and optionally compare ordinary weapon stats to a Git baseline."""
import argparse
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
FIELDS = ("capacity", "power", "split", "diffusion", "velocity", "interval", "reloadType", "bullet", "clipname")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    rows, errors, ordinary_changes = [], [], []
    for path in sorted((ROOT / "data/items").glob("武器*.xml")):
        data = ET.parse(path).getroot()
        previous = {}
        if args.base:
            old = subprocess.run(["git", "show", args.base + ":" + path.relative_to(ROOT).as_posix()],
                                 cwd=ROOT, check=True, capture_output=True).stdout
            previous = {x.findtext("name"): x for x in ET.fromstring(old).findall("item")}
        for item in data.findall("item"):
            name, weapon = item.findtext("name"), item.find("data")
            if weapon is None:
                continue
            config = weapon.find("overload")
            shotgun = item.get("weapontype") == "霰弹枪"
            if shotgun and config is None:
                errors.append(name + ": missing explicit shotgun classification")
            if config is not None:
                values = {"chamber": 0, "ghost": 0, "reward": 0}
                for child in config:
                    if child.tag not in values or child.text not in ("0", "1", "2") or (child.tag == "reward" and child.text == "2"):
                        errors.append(name + ": invalid overload field " + child.tag)
                    else:
                        values[child.tag] = int(child.text)
                if values["ghost"] and not values["chamber"]:
                    errors.append(name + ": carrier quota without chamber classification")
                rows.append(dict(name=name, shotgun=shotgun, capacity=int(weapon.findtext("capacity")), **values))
            if args.base and name in previous:
                old_item = previous[name]
                for profile in item:
                    if profile.tag != "data" and not profile.tag.startswith("data_"):
                        continue
                    old_profile = old_item.find(profile.tag)
                    if old_profile is None:
                        continue
                    for field in FIELDS:
                        old_value, new_value = old_profile.findtext(field), profile.findtext(field)
                        if old_value != new_value:
                            change = dict(name=name, profile=profile.tag, field=field, before=old_value, after=new_value)
                            ordinary_changes.append(change)
                            if change != dict(name="TTI Benelli M4", profile="data", field="capacity", before="8", after="7"):
                                errors.append("unexpected ordinary stat change: " + json.dumps(change, ensure_ascii=False))
    by_name = {x["name"]: x for x in rows}
    if by_name.get("TTI Benelli M4", {}).get("capacity") != 7:
        errors.append("TTI ordinary capacity must be seven")
    gm6 = by_name.get("GM6_LYNX", {})
    if (gm6.get("chamber"), gm6.get("ghost"), gm6.get("reward")) != (1, 0, 1):
        errors.append("GM6 must have independent chamber and reward sources")
    for name in ("双管白火铳", "白火铳", "Six12-Matryoshka", "Jackhammer", "AA12"):
        row = by_name.get(name, {})
        if (row.get("chamber"), row.get("ghost")) != (0, 0):
            errors.append(name + ": native eligibility must not be inferred from reload type")
    mods = ET.parse(ROOT / "data/items/equipment_mods/中等材料_枪械专用.xml").getroot()
    inner = next(x for x in mods.findall("mod") if x.findtext("name") == "枪械内构强化套件")
    if inner.findtext("stats/merge/overload/ghostLimit") != "2":
        errors.append("inner kit must merge a limit of two")
    if inner.find("stats/merge/overload/ghost") is not None:
        errors.append("inner kit must not grant structural eligibility")
    report = dict(ok=not errors, annotated=len(rows), shotguns=sum(r["shotgun"] for r in rows),
                  chamberEligible=sum(r["chamber"] > 0 for r in rows), ghostEligible=sum(r["ghost"] > 0 for r in rows),
                  ordinaryChanges=ordinary_changes, errors=errors, weapons=rows)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k != "weapons"}, ensure_ascii=False))
    raise SystemExit(0 if report["ok"] else 1)


if __name__ == "__main__":
    main()
