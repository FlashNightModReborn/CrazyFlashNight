"""
Generate figures + derived numeric results for `paper.md`.

This script is intentionally self-contained (no pandas/scipy dependency).

Run (from repo root or anywhere):
  python scripts/类定义/org/flashNight/neur/PerformanceOptimizer/tools/generate_paper_figures.py
"""

from __future__ import annotations

import csv
import json
import math
from collections import Counter
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

import numpy as np

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt


EVT_SAMPLE = 1
EVT_LEVEL_CHANGED = 2
EVT_MANUAL_SET = 3
EVT_SCENE_CHANGED = 4
EVT_PID_DETAIL = 5


@dataclass(frozen=True)
class EventRow:
    time_ms: int
    evt: int
    a: Optional[float]
    b: Optional[float]
    c: Optional[float]
    d: Optional[float]
    s: str


def _to_float(v: str) -> Optional[float]:
    if v is None or v == "":
        return None
    return float(v)


def read_events(csv_path: Path) -> List[EventRow]:
    with csv_path.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        rows: List[EventRow] = []
        for r in reader:
            rows.append(
                EventRow(
                    time_ms=int(r["timeMs"]),
                    evt=int(r["evt"]),
                    a=_to_float(r.get("a", "")),
                    b=_to_float(r.get("b", "")),
                    c=_to_float(r.get("c", "")),
                    d=_to_float(r.get("d", "")),
                    s=r.get("s", ""),
                )
            )
        return rows


def is_open_loop(csv_path: Path) -> bool:
    with csv_path.open("r", encoding="utf-8-sig") as f:
        head = f.read(2048)
    return "OL:" in head


def find_log_csvs(log_dir: Path) -> Tuple[Path, Path]:
    csv_files = sorted(log_dir.glob("fs_*.csv"))
    if len(csv_files) < 2:
        raise SystemExit(f"Expected >=2 log csv files in {log_dir}, found {len(csv_files)}.")

    open_loop: Optional[Path] = None
    closed_loop: Optional[Path] = None
    for p in csv_files:
        if is_open_loop(p):
            open_loop = p
        else:
            closed_loop = p

    if open_loop is None or closed_loop is None:
        raise SystemExit(
            f"Failed to classify open/closed loop csv in {log_dir}. Files: {[p.name for p in csv_files]}"
        )
    return open_loop, closed_loop


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def save_png(
    fig: plt.Figure,
    path: Path,
    *,
    tight_layout_rect: Optional[Tuple[float, float, float, float]] = None,
) -> None:
    if tight_layout_rect is None:
        fig.tight_layout()
    else:
        fig.tight_layout(rect=tight_layout_rect)
    fig.savefig(path, dpi=240, bbox_inches="tight")
    plt.close(fig)


def plot_fps_timeseries(
    samples: List[EventRow],
    level_changes: List[EventRow],
    target_fps: float,
    out_path: Path,
) -> None:
    t0 = samples[0].time_ms
    t = np.array([(r.time_ms - t0) / 1000.0 for r in samples])
    level = np.array([int(r.a or 0) for r in samples], dtype=int)
    actual = np.array([float(r.b or 0.0) for r in samples])
    denoised = np.array([float(r.c or 0.0) for r in samples])

    fig, ax = plt.subplots(figsize=(8.4, 3.6))
    ax.plot(t, actual, label="Measured FPS (interval-average)", linewidth=1.4, color="#1f77b4")
    ax.plot(t, denoised, label="Kalman estimate", linewidth=1.4, color="#ff7f0e")
    ax.axhline(target_fps, linestyle="--", linewidth=1.0, color="#222222", label=f"Target = {target_fps:g} FPS")

    for ev in level_changes:
        ax.axvline((ev.time_ms - t0) / 1000.0, color="#bbbbbb", linewidth=0.8, alpha=0.35)

    ax.set_xlabel("Time (s)")
    ax.set_ylabel("FPS")
    ax.set_xlim(t.min(), t.max())
    ax.set_ylim(0, max(31.0, float(np.nanmax(actual)) + 1.0))
    ax.grid(True, which="both", linewidth=0.6, alpha=0.35)

    ax2 = ax.twinx()
    ax2.step(t, level, where="post", color="#666666", linewidth=1.0, alpha=0.55, label="Performance level u")
    ax2.set_ylabel("Performance level u (0=best, 3=lowest)")
    ax2.set_ylim(-0.2, 3.2)

    h1, l1 = ax.get_legend_handles_labels()
    h2, l2 = ax2.get_legend_handles_labels()
    ax.legend(h1 + h2, l1 + l2, loc="upper right", fontsize=9, framealpha=0.95)

    save_png(fig, out_path)


def plot_pid_components(samples: List[EventRow], pid_detail_by_time: Dict[int, EventRow], out_path: Path) -> None:
    t0 = samples[0].time_ms
    t: List[float] = []
    p_term: List[float] = []
    i_term: List[float] = []
    d_term: List[float] = []
    pid_out: List[float] = []

    for s in samples:
        pid = pid_detail_by_time.get(s.time_ms)
        if pid is None:
            continue
        t.append((s.time_ms - t0) / 1000.0)
        p_term.append(float(pid.a or 0.0))
        i_term.append(float(pid.b or 0.0))
        d_term.append(float(pid.c or 0.0))
        pid_out.append(float(pid.d or 0.0))

    t_arr = np.array(t)
    fig, ax = plt.subplots(figsize=(8.4, 3.6))
    ax.plot(t_arr, p_term, label="P-term", linewidth=1.2)
    ax.plot(t_arr, i_term, label="I-term (clamped)", linewidth=1.2)
    ax.plot(t_arr, d_term, label="D-term (filtered)", linewidth=1.2)
    ax.plot(t_arr, pid_out, label="PID output u*", linewidth=1.6, color="#222222")

    ax.set_xlabel("Time (s)")
    ax.set_ylabel("Contribution (level units)")
    ax.grid(True, which="both", linewidth=0.6, alpha=0.35)
    ax.legend(loc="upper right", fontsize=9, framealpha=0.95)

    save_png(fig, out_path)


def plot_nyquist(
    kp: float,
    delta_fps: float,
    tau_list: Iterable[float],
    sensor_delay_s: float,
    out_path: Path,
) -> None:
    k0 = kp * delta_fps
    w = np.logspace(-3, 1.0, 2000)  # rad/s

    fig, ax = plt.subplots(figsize=(5.4, 5.4))
    for tau in tau_list:
        jw = 1j * w
        l = k0 * np.exp(-jw * sensor_delay_s) / (1 + jw * tau)
        ax.plot(l.real, l.imag, linewidth=1.2, label=f"$\\tau$={tau:g}s")

    ax.scatter([-1.0], [0.0], color="#d62728", s=40, marker="x", label="-1")
    ax.axhline(0, color="#999999", linewidth=0.8)
    ax.axvline(0, color="#999999", linewidth=0.8)
    ax.set_title(f"Nyquist plot of $L(j\\omega)$ (Kp·ΔFPS={k0:.3f}, delay={sensor_delay_s:g}s)")
    ax.set_xlabel("Re")
    ax.set_ylabel("Im")
    ax.grid(True, which="both", linewidth=0.6, alpha=0.35)
    ax.set_aspect("equal", "box")
    ax.legend(loc="best", fontsize=9, framealpha=0.95)

    save_png(fig, out_path)


def plot_sensitivity_bode(
    kp: float,
    delta_fps: float,
    tau_list: Iterable[float],
    sensor_delay_s: float,
    out_path: Path,
) -> None:
    """Plot |S(jω)| Bode magnitude for the first-order delay surrogate."""
    k0 = kp * delta_fps
    w = np.logspace(-3, 1.0, 2000)  # rad/s

    fig, ax = plt.subplots(figsize=(7.0, 4.2))
    for tau in tau_list:
        jw = 1j * w
        l = k0 * np.exp(-jw * sensor_delay_s) / (1 + jw * tau)
        s = 1.0 / (1.0 + l)
        s_db = 20.0 * np.log10(np.abs(s))
        ax.semilogx(w, s_db, linewidth=1.2, label=f"$\\tau$={tau:g} s")

    # Reference lines
    ax.axhline(0, color="#999999", linewidth=0.8, linestyle="--", label="0 dB ($|S|=1$)")
    ax.axhline(6.02, color="#d62728", linewidth=0.8, linestyle=":", label="6 dB ($M_s=2.0$ limit)")
    s_dc_db = 20.0 * math.log10(1.0 / (1.0 + k0))
    ax.axhline(s_dc_db, color="#2ca02c", linewidth=0.8, linestyle=":", alpha=0.6,
               label=f"DC: {s_dc_db:.1f} dB")

    ax.set_title(f"Sensitivity $|S(j\\omega)|$ (Kp·ΔFPS={k0:.3f}, delay={sensor_delay_s:g} s)")
    ax.set_xlabel("Frequency $\\omega$ (rad/s)")
    ax.set_ylabel("$|S(j\\omega)|$ (dB)")
    ax.set_ylim(-12, 12)
    ax.grid(True, which="both", linewidth=0.6, alpha=0.35)
    ax.legend(loc="best", fontsize=8, framealpha=0.95)

    save_png(fig, out_path)


def plot_describing_function_intersection(
    kp: float,
    delta_fps: float,
    tau_s: float,
    sensor_delay_s: float,
    relay_m: float,
    hyst_delta: float,
    out_path: Path,
) -> Dict[str, Any]:
    """
    Plot Nyquist of the linear part L(jw) together with the -1/N(A) locus
    for a relay-with-hysteresis describing function (Tsypkin-style).

    Returns a small numeric summary (grid min distance).
    """
    def l_of_w(k0: float, w: np.ndarray) -> np.ndarray:
        jw = 1j * w
        return k0 * np.exp(-jw * sensor_delay_s) / (1 + jw * tau_s)

    def inv_n_of_a(a: np.ndarray) -> np.ndarray:
        ratio = hyst_delta / a
        n = (4.0 * relay_m) / (math.pi * a) * (np.sqrt(1.0 - ratio**2) - 1j * ratio)
        return -1.0 / n

    def min_distance_details(k0: float) -> Dict[str, Any]:
        # Coarse search on a reasonably dense grid
        w = np.logspace(-3, 1.0, 20000)  # rad/s
        a = np.linspace(hyst_delta + 1e-5, 8.0, 20000)  # input amplitude A
        l = l_of_w(k0, w)
        inv = inv_n_of_a(a)

        inv_sub = inv[::4]
        d = np.abs(l[:, None] - inv_sub[None, :])
        i, j = np.unravel_index(np.argmin(d), d.shape)
        w0 = float(w[i])
        a0 = float(a[::4][j])

        # Local refinement around the coarse minimizer
        w2 = np.linspace(max(1e-6, w0 - 0.03), w0 + 0.03, 6001)
        a2 = np.linspace(max(hyst_delta + 1e-6, a0 - 0.03), a0 + 0.03, 6001)
        l2 = l_of_w(k0, w2)
        inv2 = inv_n_of_a(a2)
        d2 = np.abs(l2[:, None] - inv2[None, :])
        i2, j2 = np.unravel_index(np.argmin(d2), d2.shape)
        w_best = float(w2[i2])
        a_best = float(a2[j2])
        l_best = l_of_w(k0, np.array([w_best]))[0]
        inv_best = inv_n_of_a(np.array([a_best]))[0]
        dist_best = float(abs(l_best - inv_best))

        return {
            "k0": float(k0),
            "min_distance": dist_best,
            "w_rad_per_s": w_best,
            "freq_hz": w_best / (2.0 * math.pi),
            "A": a_best,
            "L_at_min": {"re": float(l_best.real), "im": float(l_best.imag)},
            "minus_invN_at_min": {"re": float(inv_best.real), "im": float(inv_best.imag)},
        }

    k0 = kp * delta_fps
    details_naive = min_distance_details(k0)
    details_down = min_distance_details(k0 * 0.5)  # n_down=2
    details_up = min_distance_details(k0 / 3.0)  # n_up=3

    # Plot three panels: naive, effective downgrade (n=2), effective upgrade (n=3)
    w_plot = np.logspace(-3, 1.0, 2500)
    # Keep A-range moderate so the locus stays within a readable window.
    # (As A→∞, -1/N(A) marches to -∞ on the real axis, which is uninformative here.)
    a_plot = np.linspace(hyst_delta + 1e-4, 2.5, 2500)
    inv_plot = inv_n_of_a(a_plot)

    fig, axes = plt.subplots(1, 3, figsize=(15.6, 5.4))
    panels = [
        (axes[0], k0, f"(a) Naive (no confirmation)\n$k_0={k0:.3f}$"),
        (axes[1], k0 * 0.5, f"(b) $n_{{\\mathrm{{down}}}}=2$ (eff. gain $\\times 0.5$)\n$k_0={k0*0.5:.4f}$"),
        (axes[2], k0 / 3.0, f"(c) $n_{{\\mathrm{{up}}}}=3$ (eff. gain $\\times 1/3$)\n$k_0={k0/3.0:.4f}$"),
    ]
    for ax, k0_panel, title in panels:
        l_plot = l_of_w(k0_panel, w_plot)
        ax.plot(l_plot.real, l_plot.imag, linewidth=1.25, label="$L(j\\omega)$")
        ax.plot(inv_plot.real, inv_plot.imag, linewidth=1.1, label="$-1/N(A)$ (relay+hysteresis)")
        ax.scatter([-1.0], [0.0], color="#d62728", s=40, marker="x", label="-1")
        ax.axhline(0, color="#999999", linewidth=0.8)
        ax.axvline(0, color="#999999", linewidth=0.8)
        ax.set_title(title, fontsize=10)
        ax.set_xlabel("Re")
        ax.set_ylabel("Im")
        ax.grid(True, which="both", linewidth=0.6, alpha=0.35)
        ax.set_xlim(-2.2, 1.0)
        ax.set_ylim(-0.95, 0.95)
        ax.set_aspect("equal", "box")

    # Mark the (grid-refined) naive intersection point for clarity.
    axes[0].scatter(
        [details_naive["L_at_min"]["re"]],
        [details_naive["L_at_min"]["im"]],
        color="#2ca02c",
        s=36,
        marker="o",
        label="intersection (grid)",
        zorder=5,
    )

    # Annotate min-distance on panels (b) and (c)
    for ax_idx, details, label in [
        (1, details_down, "$d_{\\min}$"),
        (2, details_up, "$d_{\\min}$"),
    ]:
        ax = axes[ax_idx]
        lp = details["L_at_min"]
        ip = details["minus_invN_at_min"]
        mid_re = (lp["re"] + ip["re"]) / 2
        mid_im = (lp["im"] + ip["im"]) / 2
        ax.annotate(
            f'{label}={details["min_distance"]:.3f}',
            xy=(mid_re, mid_im),
            xytext=(mid_re - 0.6, mid_im + 0.35),
            fontsize=8,
            arrowprops=dict(arrowstyle="->", color="#555555", lw=0.8),
            color="#555555",
        )

    axes[0].legend(loc="best", fontsize=8, framealpha=0.95)
    axes[1].legend(loc="best", fontsize=8, framealpha=0.95)
    axes[2].legend(loc="best", fontsize=8, framealpha=0.95)
    fig.suptitle(
        "Describing-function intersection check\n"
        f"($\\tau$={tau_s:g}s, delay={sensor_delay_s:g}s, M={relay_m:g}, $\\Delta$={hyst_delta:g})",
        fontsize=12,
    )

    save_png(fig, out_path, tight_layout_rect=(0.0, 0.0, 1.0, 0.88))
    return {
        "model": {
            "tau_s": tau_s,
            "sensor_delay_s": sensor_delay_s,
            "relay_m": relay_m,
            "hyst_delta": hyst_delta,
            "k0": k0,
        },
        "naive": details_naive,
        "effective_downgrade_n2": details_down,
        "effective_upgrade_n3": details_up,
    }


def kalman_k_inf(q: float, r: float) -> float:
    # Random walk 1D Kalman steady-state gain (A=1, H=1).
    # Let S = P^- = P + Q. Solve S^2 - Q S - Q R = 0 -> S = (Q + sqrt(Q^2 + 4QR))/2.
    s = (q + math.sqrt(q * q + 4.0 * q * r)) / 2.0
    return s / (s + r)


def _basic_stats(values: List[float]) -> Dict[str, Any]:
    arr = np.array(values, dtype=float)
    return {
        "n": int(arr.size),
        "mean": float(np.mean(arr)) if arr.size else None,
        "median": float(np.median(arr)) if arr.size else None,
        "p5": float(np.percentile(arr, 5)) if arr.size else None,
        "p1": float(np.percentile(arr, 1)) if arr.size else None,
        "min": float(np.min(arr)) if arr.size else None,
        "max": float(np.max(arr)) if arr.size else None,
        "std": float(np.std(arr)) if arr.size else None,
        "below_20_count": int(np.sum(arr < 20.0)) if arr.size else None,
        "below_20_rate": float(np.mean(arr < 20.0)) if arr.size else None,
    }


def derive_metrics_from_closed_loop(events: List[EventRow]) -> Dict[str, Any]:
    samples = [e for e in events if e.evt == EVT_SAMPLE]
    changes = [e for e in events if e.evt == EVT_LEVEL_CHANGED]
    scenes = [e for e in events if e.evt == EVT_SCENE_CHANGED]
    manual = [e for e in events if e.evt == EVT_MANUAL_SET]
    pid_by_time: Dict[int, EventRow] = {e.time_ms: e for e in events if e.evt == EVT_PID_DETAIL}

    samples.sort(key=lambda r: r.time_ms)
    changes.sort(key=lambda r: r.time_ms)

    metrics: Dict[str, Any] = {
        "samples": len(samples),
        "level_changes": len(changes),
        "scene_changes": len(scenes),
        "manual_set": len(manual),
    }
    if samples:
        t0 = samples[0].time_ms
        t1 = samples[-1].time_ms
        metrics["duration_s"] = (t1 - t0) / 1000.0
        actual = [float(s.b or 0.0) for s in samples]
        metrics["fps"] = _basic_stats(actual)

    if len(changes) >= 2:
        intervals = [(changes[i].time_ms - changes[i - 1].time_ms) / 1000.0 for i in range(1, len(changes))]
        mean_i = sum(intervals) / len(intervals)
        std_i = math.sqrt(sum((x - mean_i) ** 2 for x in intervals) / len(intervals))
        metrics["switch_interval_mean_s"] = float(mean_i)
        metrics["switch_interval_std_s"] = float(std_i)

    if samples:
        # Sample distribution by level
        levels = [int(s.a or 0) for s in samples]
        level_counts = Counter(levels)
        n = len(levels)
        metrics["samples_by_level"] = {
            str(level): {"n": int(level_counts.get(level, 0)), "pct": float(level_counts.get(level, 0) / n * 100.0)}
            for level in sorted(set(level_counts.keys()) | {0, 1, 2, 3})
        }

        # Mean FPS by level (useful for residence table)
        fps_by_level: Dict[int, List[float]] = defaultdict(list)
        for s in samples:
            level = int(s.a or 0)
            fps_by_level[level].append(float(s.b or 0.0))
        metrics["mean_fps_by_level"] = {str(level): float(np.mean(v)) for level, v in sorted(fps_by_level.items())}

        # dt stats by level (based on consecutive sample deltas; attribute dt to the *later* sample's level)
        prev_t: Optional[int] = None
        dt_by_level: Dict[int, List[float]] = defaultdict(list)
        for s in samples:
            if prev_t is not None:
                level = int(s.a or 0)
                dt_by_level[level].append((s.time_ms - prev_t) / 1000.0)
            prev_t = s.time_ms

        metrics["dt_by_level"] = {
            str(level): {
                "n": len(arr),
                "mean_s": float(sum(arr) / len(arr)) if arr else None,
                "min_s": float(min(arr)) if arr else None,
                "max_s": float(max(arr)) if arr else None,
            }
            for level, arr in sorted(dt_by_level.items())
        }

        time_by_level = {level: float(sum(arr)) for level, arr in dt_by_level.items()}
        total_time = float(sum(time_by_level.values())) if time_by_level else 0.0
        metrics["time_by_level"] = {
            str(level): {
                "time_s": float(time_by_level.get(level, 0.0)),
                "pct": float(time_by_level.get(level, 0.0) / total_time * 100.0) if total_time > 0 else None,
            }
            for level in sorted(set(time_by_level.keys()) | {0, 1, 2, 3})
        }

        # --- PID / quantizer diagnostics used in the paper text ---
        target_fps = 26.0  # match paper constant

        # Error sign changes (zero-crossing proxy), based on Kalman estimate.
        errors = [target_fps - float(s.c or 0.0) for s in samples]
        sign_changes = 0
        for e0, e1 in zip(errors, errors[1:]):
            if e0 == 0.0 or e1 == 0.0:
                continue
            if (e0 > 0.0) != (e1 > 0.0):
                sign_changes += 1
        metrics["error_sign_changes"] = int(sign_changes)

        # Align PID detail rows with samples (same timestamp by design).
        aligned_pid: List[EventRow] = []
        for s in samples:
            pid = pid_by_time.get(s.time_ms)
            if pid is not None:
                aligned_pid.append(pid)

        if aligned_pid:
            # Logged PID contributions: a=P, b=I, c=D, d=u*
            p_terms = [float(p.a or 0.0) for p in aligned_pid]
            i_terms = [float(p.b or 0.0) for p in aligned_pid]
            d_terms = [float(p.c or 0.0) for p in aligned_pid]
            u_stars = [float(p.d or 0.0) for p in aligned_pid]

            # Integral saturation (Ki*M = 1.5 in this controller); use paper threshold 1.49.
            sat_threshold = 1.49
            sat_mask = [abs(i) >= sat_threshold for i in i_terms]
            unsat_times = [aligned_pid[i].time_ms for i, sat in enumerate(sat_mask) if not sat]

            metrics["pid_terms"] = {
                "aligned": int(len(aligned_pid)),
                "abs_P_min": float(min(abs(x) for x in p_terms)),
                "abs_P_max": float(max(abs(x) for x in p_terms)),
                "abs_D_min": float(min(abs(x) for x in d_terms)),
                "abs_D_max": float(max(abs(x) for x in d_terms)),
                "integral_saturation": {
                    "threshold_abs": float(sat_threshold),
                    "count": int(sum(1 for x in sat_mask if x)),
                    "rate": float(sum(1 for x in sat_mask if x) / len(sat_mask)),
                    "unsat_times_ms": [int(t) for t in unsat_times],
                },
            }

            # Candidate mismatch: cand = clamp(int(u*+0.5), 0, 3), compare to current level.
            mismatches = 0
            for s in samples:
                pid = pid_by_time.get(s.time_ms)
                if pid is None:
                    continue
                u_star = float(pid.d or 0.0)
                cand = int(u_star + 0.5)  # matches (u*+0.5)>>0 for mn>=0
                if cand < 0:
                    cand = 0
                elif cand > 3:
                    cand = 3
                if int(s.a or 0) != cand:
                    mismatches += 1
            metrics["candidate_mismatch"] = {
                "count": int(mismatches),
                "rate": float(mismatches / len(samples)) if samples else None,
            }

        # Switch gaps in samples (in addition to wall-clock switch intervals).
        switch_idxs = [i for i in range(1, len(levels)) if levels[i] != levels[i - 1]]
        gaps = [b - a for a, b in zip(switch_idxs, switch_idxs[1:])]
        gaps_sorted = sorted(gaps)
        metrics["switch_gap_samples"] = {
            "switches": int(len(switch_idxs)),
            "gaps": int(len(gaps)),
            "min": int(min(gaps_sorted)) if gaps_sorted else None,
            "median": int(gaps_sorted[len(gaps_sorted) // 2]) if gaps_sorted else None,
            "max": int(max(gaps_sorted)) if gaps_sorted else None,
        }

    return metrics


def derive_metrics_from_open_loop(events: List[EventRow]) -> Dict[str, Any]:
    samples = [e for e in events if e.evt == EVT_SAMPLE]
    samples.sort(key=lambda r: r.time_ms)

    fps_by_segment: Dict[str, List[float]] = defaultdict(list)
    dt_by_segment: Dict[str, List[float]] = defaultdict(list)

    prev_time_ms: Optional[int] = None
    prev_seg: Optional[str] = None
    for s in samples:
        seg = (s.s or "").strip()
        if seg:
            fps_by_segment[seg].append(float(s.b or 0.0))
        if prev_time_ms is not None and prev_seg is not None and seg == prev_seg and seg:
            dt_by_segment[seg].append((s.time_ms - prev_time_ms) / 1000.0)
        prev_time_ms = s.time_ms
        prev_seg = seg

    segments: Dict[str, Any] = {}
    for seg in sorted(fps_by_segment.keys()):
        fps = fps_by_segment[seg]
        stats = _basic_stats(fps)
        dts = dt_by_segment.get(seg, [])
        if dts:
            stats["dt_mean_s"] = float(sum(dts) / len(dts))
            stats["dt_min_s"] = float(min(dts))
            stats["dt_max_s"] = float(max(dts))
        else:
            stats["dt_mean_s"] = None
            stats["dt_min_s"] = None
            stats["dt_max_s"] = None
        segments[seg] = stats

    baseline_seg = "OL:0>0"
    return {
        "segments": segments,
        "baseline_segment": baseline_seg,
        "baseline_L0": segments.get(baseline_seg),
    }


def main() -> None:
    base_dir = Path(__file__).resolve().parents[1]
    log_dir = base_dir / "log"
    fig_dir = base_dir / "figures"

    ensure_dir(fig_dir)

    open_loop_csv, closed_loop_csv = find_log_csvs(log_dir)
    events_ol = read_events(open_loop_csv)
    events_cl = read_events(closed_loop_csv)

    samples_cl = [e for e in events_cl if e.evt == EVT_SAMPLE]
    if not samples_cl:
        raise SystemExit(f"No EVT_SAMPLE rows found in {closed_loop_csv}.")

    pid_detail_by_time = {e.time_ms: e for e in events_cl if e.evt == EVT_PID_DETAIL}
    level_changes = [e for e in events_cl if e.evt == EVT_LEVEL_CHANGED]

    # Paper constants (match implementation)
    target_fps = 26.0
    kp = 0.25
    delta_fps_max = 3.3

    # --- Figures ---
    plot_fps_timeseries(
        samples=samples_cl,
        level_changes=level_changes,
        target_fps=target_fps,
        out_path=fig_dir / "fig_fps_timeseries.png",
    )
    plot_pid_components(
        samples=samples_cl,
        pid_detail_by_time=pid_detail_by_time,
        out_path=fig_dir / "fig_pid_components.png",
    )

    # Nyquist: include a conservative sensor/measurement delay surrogate.
    # Interval-average measurement effectively centers the measurement at ~T/2; worst case at level 3 is ~2s.
    plot_nyquist(
        kp=kp,
        delta_fps=delta_fps_max,
        tau_list=[0.5, 2.0, 5.0, 10.0],
        sensor_delay_s=2.0,
        out_path=fig_dir / "fig_nyquist.png",
    )

    # Sensitivity Bode: |S(jw)| for the same surrogate, visualising disturbance rejection.
    plot_sensitivity_bode(
        kp=kp,
        delta_fps=delta_fps_max,
        tau_list=[0.5, 2.0, 5.0, 10.0],
        sensor_delay_s=2.0,
        out_path=fig_dir / "fig_sensitivity_bode.png",
    )

    df_summary = plot_describing_function_intersection(
        kp=kp,
        delta_fps=delta_fps_max,
        tau_s=3.0,
        sensor_delay_s=2.0,
        relay_m=1.0,
        hyst_delta=0.5,
        out_path=fig_dir / "fig_describing_function_intersection.png",
    )

    # --- Numeric derivations ---
    metrics: Dict[str, Any] = {
        "source_files": {
            "open_loop_csv": str(open_loop_csv.relative_to(base_dir)),
            "closed_loop_csv": str(closed_loop_csv.relative_to(base_dir)),
        },
        "open_loop_metrics": derive_metrics_from_open_loop(events_ol),
        "closed_loop_metrics": derive_metrics_from_closed_loop(events_cl),
        "kalman_gain": {
            "baseQ": 0.1,
            "R": 1.0,
            "dt_1s_K_inf": kalman_k_inf(0.1, 1.0),
            "dt_2s_K_inf": kalman_k_inf(0.2, 1.0),
            "dt_3s_K_inf": kalman_k_inf(0.3, 1.0),
            "dt_4s_K_inf": kalman_k_inf(0.4, 1.0),
        },
        "describing_function_intersection": df_summary,
    }

    (fig_dir / "derived_metrics.json").write_text(json.dumps(metrics, indent=2), encoding="utf-8")
    print(f"Wrote figures to: {fig_dir}")
    print(f"Wrote metrics to: {fig_dir / 'derived_metrics.json'}")


if __name__ == "__main__":
    main()
