from __future__ import annotations

import copy
import os
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from typing import Any, Dict, List


PRELAUNCH_PATHS = [
    "preLaunchFrames.min",
    "preLaunchFrames.max",
    "preLaunchPeakHeight.min",
    "preLaunchPeakHeight.max",
    "rotationShakeTime.start",
    "rotationShakeTime.end",
]

TRACKING_PATHS = [
    "initialSpeedRatio",
    "rotationSpeed",
    "acceleration",
    "dragCoefficient",
    "navigationRatio",
    "angleCorrection",
]


@dataclass
class ConfigBundle:
    name: str
    raw: Dict[str, Any]
    effective: Dict[str, Any]
    missing_fields: List[str] = field(default_factory=list)


def repo_root() -> str:
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def default_xml_path() -> str:
    return os.path.join(repo_root(), "data", "items", "missileConfigs.xml")


def _coerce_text(text: str | None) -> Any:
    raw = (text or "").strip()
    if raw == "":
        return ""

    lower = raw.lower()
    if lower == "true":
        return True
    if lower == "false":
        return False

    try:
        if any(ch in raw for ch in ".eE"):
            value = float(raw)
            return int(value) if value.is_integer() else value
        return int(raw)
    except ValueError:
        try:
            value = float(raw)
            return int(value) if value.is_integer() else value
        except ValueError:
            return raw


def _parse_node(node: ET.Element) -> Any:
    if not list(node):
        return _coerce_text(node.text)

    parsed: Dict[str, Any] = {}
    for child in node:
        parsed[child.tag] = _parse_node(child)
    return parsed


def load_raw_configs(xml_path: str | None = None) -> Dict[str, Dict[str, Any]]:
    source = xml_path or default_xml_path()
    tree = ET.parse(source)
    root = tree.getroot()

    configs: Dict[str, Dict[str, Any]] = {}
    for config_node in root.findall("config"):
        name = config_node.attrib.get("name")
        if not name:
            continue
        configs[name] = _parse_node(config_node)
    return configs


def deep_merge(base: Dict[str, Any], override: Dict[str, Any]) -> Dict[str, Any]:
    merged = copy.deepcopy(base)
    for key, value in override.items():
        if (
            key in merged
            and isinstance(merged[key], dict)
            and isinstance(value, dict)
        ):
            merged[key] = deep_merge(merged[key], value)
        else:
            merged[key] = copy.deepcopy(value)
    return merged


def _collect_missing(default_value: Dict[str, Any], candidate: Dict[str, Any], prefix: str = "") -> List[str]:
    missing: List[str] = []
    for key, value in default_value.items():
        dotted = key if prefix == "" else prefix + "." + key
        if key not in candidate:
            missing.append(dotted)
            continue
        if isinstance(value, dict) and isinstance(candidate.get(key), dict):
            missing.extend(_collect_missing(value, candidate[key], dotted))
    return missing


def build_bundles(
    xml_path: str | None = None,
    merge_default: bool = True,
) -> Dict[str, ConfigBundle]:
    raw_configs = load_raw_configs(xml_path)
    if "default" not in raw_configs:
        raise ValueError("missileConfigs.xml is missing the default preset")

    default_raw = raw_configs["default"]
    bundles: Dict[str, ConfigBundle] = {}
    for name, raw in raw_configs.items():
        effective = deep_merge(default_raw, raw) if merge_default else copy.deepcopy(raw)
        missing_fields = [] if name == "default" else _collect_missing(default_raw, raw)
        bundles[name] = ConfigBundle(
            name=name,
            raw=copy.deepcopy(raw),
            effective=effective,
            missing_fields=missing_fields,
        )
    return bundles


def _has_path(config: Dict[str, Any], dotted_path: str) -> bool:
    current: Any = config
    for part in dotted_path.split("."):
        if not isinstance(current, dict) or part not in current:
            return False
        current = current[part]
    return True


def validate_effective_config(
    config: Dict[str, Any],
    use_prelaunch: bool,
    designated_target: bool,
) -> List[str]:
    required = list(TRACKING_PATHS)
    if not designated_target:
        required.append("searchRange")
    if use_prelaunch:
        required.extend(PRELAUNCH_PATHS)

    missing: List[str] = []
    for dotted_path in required:
        if not _has_path(config, dotted_path):
            missing.append(dotted_path)
    return missing

