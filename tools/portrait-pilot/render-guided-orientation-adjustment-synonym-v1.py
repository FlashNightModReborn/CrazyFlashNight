#!/usr/bin/env python3
"""Versioned lexical adapter for an explicit human ``反转`` instruction.

The frozen v1 renderer already implements and verifies the pixel operation.  This
adapter pins those bytes, extends only the explicit-orientation note vocabulary,
and makes the adapter itself the controller artifact recorded by the report.
"""

from __future__ import annotations

import hashlib
import importlib.util
import re
from pathlib import Path


BASE_SHA256 = "DD0AEBA26ABD12B37F66DA57A1B8713EB4933A2072040E8B577A763325A0F209"
BASE_NAME = "render-guided-orientation-adjustment.py"
ORIENTATION_NOTE = re.compile(r"方向反转|头朝右|头朝左|朝向|翻转|反转")


def load_pinned_base():
    controller_path = Path(__file__).resolve()
    base_path = controller_path.with_name(BASE_NAME)
    actual = hashlib.sha256(base_path.read_bytes()).hexdigest().upper()
    if actual != BASE_SHA256:
        raise RuntimeError(
            f"frozen guided-orientation controller digest mismatch: {actual} != {BASE_SHA256}"
        )
    spec = importlib.util.spec_from_file_location("cf7_guided_orientation_base_v1", base_path)
    if spec is None or spec.loader is None:
        raise RuntimeError("unable to load frozen guided-orientation controller")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.ORIENTATION_NOTE = ORIENTATION_NOTE
    module.__file__ = str(controller_path)
    return module


if __name__ == "__main__":
    raise SystemExit(load_pinned_base().main())
