#!/usr/bin/env python3
"""Regression gate for feature-profile geometry feasibility."""

from __future__ import annotations

import json
from pathlib import Path

import prepare_campaign
import prepare_pilot


ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "tools" / "portrait-pilot" / "fixtures"


def load(version: str) -> dict[str, object]:
    with (FIXTURES / f"campaign-feature-inference.{version}.json").open("r", encoding="utf-8") as stream:
        value = json.load(stream)
    if not isinstance(value, dict):
        raise AssertionError(f"{version} profile 顶层不是对象")
    return value


def main() -> None:
    rejected = None
    try:
        prepare_campaign.validate_campaign_feature_profile(load("v8"))
    except prepare_pilot.PilotError as error:
        rejected = str(error)
    if rejected is None or "可实现上限 0.800000" not in rejected:
        raise AssertionError("v8 不可实现几何合同没有被精确拒绝")
    prepare_campaign.validate_campaign_feature_profile(load("v9"))
    prepare_campaign.validate_campaign_feature_profile(load("v10"))
    prepare_campaign.validate_campaign_feature_profile(load("v11"))
    prepare_campaign.validate_campaign_feature_profile(load("v12"))
    prepare_campaign.validate_campaign_feature_profile(load("v13"))
    print(
        json.dumps(
            {"status": "feature_profile_feasibility_verified", "rejected": "v8", "accepted": ["v9", "v10", "v11", "v12", "v13"]},
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
