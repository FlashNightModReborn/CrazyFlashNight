"""Export calibration inputs from one completed emissive asset TestLoader run.

The producer's fresh Compiler 0/0 and source identity remain the focused runner's
responsibility. This validates the trace block, never infers gameplay acceptance.
"""
import argparse
import json
import re
from pathlib import Path


def export(text):
    starts = list(re.finditer(r"^FocusedTestRunId equipment-emissive-assets Start: ([0-9a-f]+)$", text, re.M))
    ends = list(re.finditer(r"^FocusedTestRunId equipment-emissive-assets Complete: ([0-9a-f]+)$", text, re.M))
    if len(starts) != 1 or len(ends) != 1 or starts[0][1] != ends[0][1] or starts[0].end() >= ends[0].start():
        raise ValueError("expected one ordered, matching asset suite run")
    body = text[starts[0].end():ends[0].start()]
    if len(re.findall(r"^EquipmentEmissiveAssetTest Tests Failed: 0$", body, re.M)) != 1 or re.search(r"^EquipmentEmissiveAssetTest FAIL:", body, re.M):
        raise ValueError("asset suite did not finish without assertion failures")
    rows = re.findall(r"^EquipmentEmissiveAssetTest LightingWire (blue-[a-z]+): (.+)$", body, re.M)
    if len(rows) != 3 or {name for name, wire in rows} != {"blue-set", "blue-same", "blue-blood"}:
        raise ValueError("expected one snapshot for each calibration case")
    return dict(rows)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    result = export(args.trace.read_text(encoding="utf-8-sig"))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print("Exported three validated AS2 calibration snapshots.")
