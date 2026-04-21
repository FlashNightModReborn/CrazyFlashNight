from __future__ import annotations

import html
import os
from typing import Iterable, List, Tuple

from simulator import SimulationResult


PALETTE = [
    "#d62828",
    "#1d3557",
    "#2a9d8f",
    "#f4a261",
    "#6a4c93",
    "#264653",
]


def _safe_name(name: str) -> str:
    return "".join(ch if ch.isalnum() or ch in ("-", "_") else "_" for ch in name)


def _collect_bounds(results: Iterable[SimulationResult]) -> Tuple[float, float, float, float]:
    xs: List[float] = []
    ys: List[float] = []
    for result in results:
        for sample in result.trace:
            xs.extend((sample.missile_x, sample.target_x))
            ys.extend((sample.missile_y, sample.target_y))

    if not xs:
        return -10.0, 10.0, -10.0, 10.0

    min_x = min(xs)
    max_x = max(xs)
    min_y = min(ys)
    max_y = max(ys)
    pad_x = max(10.0, (max_x - min_x) * 0.12)
    pad_y = max(10.0, (max_y - min_y) * 0.12)
    return min_x - pad_x, max_x + pad_x, min_y - pad_y, max_y + pad_y


def _project(x: float, y: float, bounds: Tuple[float, float, float, float], width: int, height: int, pad: int) -> Tuple[float, float]:
    min_x, max_x, min_y, max_y = bounds
    usable_w = max(1.0, width - 2 * pad)
    usable_h = max(1.0, height - 2 * pad)
    x_ratio = 0.0 if max_x == min_x else (x - min_x) / (max_x - min_x)
    y_ratio = 0.0 if max_y == min_y else (y - min_y) / (max_y - min_y)
    px = pad + usable_w * x_ratio
    py = height - pad - usable_h * y_ratio
    return px, py


def _polyline(points: List[Tuple[float, float]], color: str, width: float, dash: str = "") -> str:
    data = " ".join("{:.2f},{:.2f}".format(x, y) for x, y in points)
    dash_attr = "" if dash == "" else ' stroke-dasharray="{}"'.format(dash)
    return '<polyline fill="none" stroke="{color}" stroke-width="{width}"{dash_attr} points="{data}" />'.format(
        color=color,
        width=width,
        dash_attr=dash_attr,
        data=data,
    )


def _circle(point: Tuple[float, float], radius: float, color: str, fill: str) -> str:
    return '<circle cx="{:.2f}" cy="{:.2f}" r="{:.2f}" stroke="{}" stroke-width="1.5" fill="{}" />'.format(
        point[0],
        point[1],
        radius,
        color,
        fill,
    )


def write_compare_svg(out_dir: str, scenario_name: str, results: List[SimulationResult]) -> str | None:
    if not results or not results[0].trace:
        return None

    os.makedirs(out_dir, exist_ok=True)
    width = 960
    height = 560
    pad = 56
    bounds = _collect_bounds(results)

    target_points = [
        _project(sample.target_x, sample.target_y, bounds, width, height, pad)
        for sample in results[0].trace
    ]
    content: List[str] = [
        '<rect x="0" y="0" width="{0}" height="{1}" fill="#f8f9fb" />'.format(width, height),
        '<rect x="{0}" y="{0}" width="{1}" height="{2}" fill="#ffffff" stroke="#d7dde8" stroke-width="1" />'.format(
            pad,
            width - 2 * pad,
            height - 2 * pad,
        ),
        _polyline(target_points, "#111111", 2.0, "8 5"),
    ]

    if target_points:
        content.append(_circle(target_points[0], 5.0, "#111111", "#ffffff"))
        content.append(_circle(target_points[-1], 4.0, "#111111", "#111111"))

    legend_y = 28
    content.append(
        '<text x="24" y="{0}" font-family="Consolas, monospace" font-size="18" fill="#111111">{1}</text>'.format(
            legend_y,
            html.escape("Scenario: " + scenario_name),
        )
    )
    legend_y += 24
    content.append(
        '<text x="24" y="{0}" font-family="Consolas, monospace" font-size="12" fill="#444444">{1}</text>'.format(
            legend_y,
            "black dashed = target path",
        )
    )

    for index, result in enumerate(results):
        color = PALETTE[index % len(PALETTE)]
        missile_points = [
            _project(sample.missile_x, sample.missile_y, bounds, width, height, pad)
            for sample in result.trace
        ]
        content.append(_polyline(missile_points, color, 2.6))
        if missile_points:
            content.append(_circle(missile_points[0], 4.0, color, "#ffffff"))
            content.append(_circle(missile_points[-1], 3.6, color, color))

        aggregate_text = "{name}  hit={hit}  min={min_dist:.1f}  pressure={pressure}  streak={streak}".format(
            name=result.config_name,
            hit="Y" if result.hit else "N",
            min_dist=result.min_distance,
            pressure=result.pressure_frames,
            streak=result.max_pressure_streak,
        )
        legend_y += 18
        content.append(
            '<text x="24" y="{0}" font-family="Consolas, monospace" font-size="12" fill="{1}">{2}</text>'.format(
                legend_y,
                color,
                html.escape(aggregate_text),
            )
        )

    out_path = os.path.join(out_dir, _safe_name(scenario_name) + ".svg")
    document = (
        '<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">'
        "{content}</svg>"
    ).format(width=width, height=height, content="".join(content))
    with open(out_path, "w", encoding="utf-8") as handle:
        handle.write(document)
    return out_path

