# Adaptive Frame Rate Control in Resource-Constrained Rendering Environments: A Control-Theoretic Approach

> **Intended use**: In-game intelligence item (academic-style technical note; not for submission)
> **Revision**: 2026-02-07 r2 (proof rigor: Prop. 1 sign-reversal sub-cases, explicit derivative bounds, sensitivity assumption; figure renumbering; reference updates; Definition 1 operationalizability note; Abstract compressed)

---

## Abstract

We present a closed-loop performance scheduler for a legacy Flash/AS2 renderer under three constraints: a four-level discrete actuator with non-uniform gains (including a near-deadzone step), and an unmodeled, time-varying black-box plant. We show that PID control with frame-count delta time (30–120 frames) degenerates to a biased proportional threshold generator—integral clamping saturates in one step, the derivative attenuates to moderate damping—so that **switching dynamics are governed by the quantizer's confirmation-based hysteresis, not by fine PID tuning**. This is the paper's central finding: in coarse-actuator systems, the dominant design lever for low-oscillation scheduling is the confirmation mechanism, not the continuous controller.

Low-oscillation safety is supported by a four-link evidence chain: constructive boundedness, a linear surrogate diagnostic excluding high-frequency self-excited limit cycles ($k_0 < 1$ regime only, Machine B; Assumption S1, Section 6.3), structural dwell-time frequency bounds from the confirmation FSM (Lemma 2), and empirical attribution from battle logs. On a low-end machine the system maintains a 26 FPS target (mean 26.86 FPS, stutter rate reduced from 93% to <9%), with 25 level switches at 13.6 ± 7.5 s/switch ($f_{\text{sw}}=0.072$ Hz) and no self-excited chattering. A separate-session comparison yields an indicative 50–62% mean FPS improvement across two hardware configurations (Section 7.2).

**Keywords**: adaptive frame rate control; quantized feedback control; hysteresis quantizer; dwell time; PID degeneration; sensitivity function; adaptive sampling; resource-constrained rendering

---

## 1. Introduction

### 1.1 Problem Context

Real-time interactive applications face a fundamental tension between visual fidelity and computational performance. When rendering load exceeds hardware capacity, the application must reduce its quality settings to maintain acceptable frame rates. This problem—dynamic performance scheduling—is ubiquitous in gaming, simulation, and real-time visualization.

Most deployed solutions use threshold-based heuristics: if frame rate drops below a lower bound, reduce quality; if it rises above an upper bound, restore quality. While simple and robust, these open-loop or quasi-open-loop approaches lack formal stability guarantees, cannot adapt their sampling rates to system dynamics, and offer no principled mechanism for handling the asymmetry between degradation (which must be fast for user safety) and restoration (which should be cautious to avoid ping-pong oscillation).

More sophisticated approaches in modern rendering engines, such as Unreal Engine's Dynamic Resolution Scaling [1], employ proportional control over continuously adjustable parameters (e.g., render resolution from 50% to 100%). However, these methods rely on the existence of a continuous actuator. When the actuator is inherently discrete—as when the primary quality parameter is an enumerated preset with no intermediate states—continuous control theory does not directly apply, and the system enters the domain of quantized feedback control [2, 3].

From a control perspective, the Flash rendering pipeline and virtual machine form a **nonlinear, time-varying black-box plant**. The controlled output is the achieved frame rate $y$ (FPS); exogenous gameplay load (enemy spawns, particles, UI) acts as an unmeasured disturbance; and the only available control input is a small set of discrete quality presets. These properties make the problem closer to hybrid, disturbance-driven regulation than to classical linear setpoint tracking, and motivate (i) explicit anti-oscillation switching logic and (ii) *multi-evidence* assurance rather than a single closed-form stability proof.

### 1.2 The Quantized Control Challenge

Quantized feedback control has been studied extensively in communication-constrained control [2, 4] and networked control systems [5]. The central challenge is the **quantization limit cycle**: when the continuous controller output oscillates near a quantization boundary, the discrete actuator switches back and forth indefinitely, producing a self-excited oscillation that degrades performance and accelerates mechanical wear (or, in software systems, visual flicker).

The standard remedy is **hysteresis**—introducing asymmetric switching thresholds that create a dead zone around each quantization boundary. The theoretical framework for analyzing such systems was established by Tsypkin [6] for relay systems and extended to quantized control by Elia and Mitter [2] and Delchamps [3]. However, these analyses typically assume uniform quantizer step sizes and time-invariant plant dynamics—assumptions violated in our application.

### 1.3 Specific Challenges in This Work

The system presented here—a performance scheduler for a production Flash-based game—confronts three specific challenges that distinguish it from standard quantized control problems:

**C1. Non-uniform actuator gains (with deadzones).** The four discrete quality levels produce frame rate improvements of approximately +0.5, +3.3, and −0.6 FPS per level step on the representative low-end machine (the last is within measurement noise and thus effectively ≈0). The L1→L2 transition, which activates a global rendering quality reduction, contributes ≈87% of the total load-shedding capacity (3.3/3.8). The remaining transitions produce negligible or zero measurable effect (an actuator deadzone / saturation-like behavior). This extreme non-uniformity means that a single PID gain cannot be optimal across all operating regions.

**C2. Unmodeled plant dynamics.** The rendering engine (Adobe Flash Player, ActionScript Virtual Machine 1 (AVM1)) cannot be modeled from first principles. Its frame rate depends on scene complexity, number of active entities, script execution time, garbage collection pauses, and operating system scheduling—none of which are observable or controllable by the application. The plant must be treated as a black box with uncertain dynamics.

**C3. Platform constraints.** The target platform is single-threaded with no hardware floating-point acceleration. The control loop must execute within a per-frame budget of less than 30 μs and introduce zero memory allocation (to avoid triggering garbage collection, itself a source of frame rate jitter).

### 1.4 Contributions

This paper makes the following contributions:

1. **PID degeneration under frame-count delta time** (Section 5). We show that when a PID controller with integral clamping is driven with $\Delta T$ measured in frame counts (30–120), the integral term saturates within one sampling step for any practically relevant error and becomes a constant directional bias, while the derivative term is scaled by $1/N$ and acts as moderate damping. The effective control law becomes a biased proportional threshold generator; after quantization, fine PID precision has little influence on switching behavior.

2. **Direction-memory confirmation as a finite-state switching mechanism with dwell time** (Sections 2.5 and 6.4). We formalize the confirmation-based hysteresis quantizer as a finite-state machine (state = current level, pending direction, confirmation counter), and relate its asymmetric $n$-step rules to dwell-time constraints in switched systems [12, 13].

3. **Multi-evidence low-oscillation assurance** (Section 6). Under an unmodeled, time-varying plant, we replace a single "stability" claim with a four-link evidence chain (constructive boundedness, conservative surrogate margins with sensitivity analysis, dwell-time frequency bounds, and empirical attribution), yielding an actionable assurance argument against self-excited limit cycles. We term this framework *multi-evidence low-oscillation safety* and provide a formal definition (Definition 1) with quantitative acceptance criteria.

4. **Reproducible experimental validation** (Section 7). We present open-loop identification data (4 levels × 2 directions, 117 samples) and closed-loop battle logs (195 samples, 25 level switches, 345.5 seconds) on two hardware configurations. For Machine B, all figures and reported metrics are derived directly from the bundled CSV logs, with scalar aggregation computed by `./tools/generate_paper_figures.py` and event-count conventions specified in Appendix C.

### 1.5 Related Work

**Dynamic quality adjustment in games.** Dynamic resolution scaling (DRS) is the most widely deployed adaptive performance technique in modern rendering engines. Unreal Engine's DRS [1] and Unity's Adaptive Performance SDK [15] adjust render resolution proportionally to maintain target frame time, relying on continuous actuators that permit classical proportional control. Temporal upscaling techniques (AMD FSR, NVIDIA DLSS) further enable fine-grained, near-continuous quality adjustment. These approaches do not address the discrete actuator setting considered here, where the primary quality parameter is an enumerated preset with no intermediate states. Console-era "performance vs. quality" mode selection represents the extreme case of discrete quality control, but is typically manual rather than automated.

**Quantized and switched feedback control.** The theoretical foundations for control with quantized inputs were established by Delchamps [3] and extended by Elia and Mitter [2] and Brockett and Liberzon [4], primarily in the context of communication-constrained networked control. These works focus on minimum data rates for stabilization under uniform quantization. Our problem involves non-uniform actuator gains, a finite four-level actuator, and a black-box plant—making the relay and hysteresis control literature [6] more directly relevant, particularly Tsypkin's describing-function framework for limit-cycle analysis. Switched systems with dwell-time constraints [12, 13] provide the theoretical underpinning for our confirmation-based switching analysis.

**Dynamic voltage and frequency scaling (DVFS).** Discrete actuator levels with non-uniform performance/power trade-offs also arise in embedded power management, where DVFS controllers select among enumerated CPU frequency/voltage states [16, 17]. PID-based DVFS governors (e.g., the Linux `ondemand` governor) face similar quantization limit-cycle issues and use hysteresis dead-bands to suppress chattering. Our multi-sample confirmation mechanism can be viewed as a generalization of this hysteresis dead-band approach, adding direction memory and asymmetric dwell-time enforcement.

**Adaptive bitrate streaming (ABR).** Discrete quality-level selection under uncertain throughput arises in HTTP adaptive streaming, where the client selects among enumerated video bitrates. Yin et al. [18] apply a PID-like control law to this problem; buffer-based algorithms (e.g., BBA [19]) use threshold hysteresis to suppress bitrate oscillation. Our direction-memory confirmation mechanism generalizes the fixed-threshold hysteresis used in ABR by adding asymmetric dwell-time enforcement and direction tracking, which are unnecessary in ABR (where the "actuator" gain is approximately uniform across bitrate levels) but critical when actuator gains are non-uniform.

**Event-triggered and self-triggered control.** Our adaptive sampling period (Section 2.2), where the sampling interval is a function of the current performance level, relates to the event-triggered control framework [7, 8]. Unlike classical event-triggered systems where sampling is triggered by a state-dependent threshold condition, our sampling is state-dependent but periodic within each mode, creating a hybrid between time-triggered and state-triggered paradigms.

### 1.6 Scope, Definitions, and Organization

#### 1.6.1 Scope and Assumptions

This document analyzes a performance controller embedded in a legacy Flash/AS2 real-time application. The emphasis is on (i) a defensible modeling posture for a black-box plant, (ii) a control design that is implementable under strict runtime constraints, and (iii) a quantitatively checkable *low-oscillation* property rather than an optimality claim.

The analysis adopts the following assumptions and conventions:

- **A1 (Frame-rate cap).** The renderer enforces an upper bound $f_r=30$ FPS. The control objective is regulation to a setpoint $r=26$ FPS below this cap (noise margin).
- **A2 (Discrete actuator).** The control input is a discrete performance level $u\in\{0,1,2,3\}$. We use $L_i$ as a synonym for $u=i$ when describing step tests and actuator presets.
- **A3 (Dominant monotonicity in expectation).** The actuator is designed to be monotone (higher $u$ reduces load). Empirically, the dominant boundary $L1\leftrightarrow L2$ has positive gain. Some boundaries may be ineffective or slightly non-monotone within measurement noise; this motivates confirmation-based switching.
- **A4 (Measurement sanity).** Interval-average FPS is computed from a monotone wall-clock timer (`getTimer()`), so each sampling window satisfies $\Delta t_k>0$; measured FPS may exceed 30 slightly due to timestamp quantization and rounding, but remains bounded.
- **A5 (Evaluation scope).** Reported results are based on offline analysis of battle logs from a fixed scenario and two machines. Generalizability is discussed as a threat-to-validity issue (Section 8.3) rather than assumed.

#### 1.6.2 Operational Definitions (Metrics and Events)

To make the empirical claims in Sections 6–7 mechanically checkable, we define all metrics in terms of the logged event stream produced by `PerformanceLogger` (`./PerformanceLogger.as`) (Appendix C).

- **Sample.** One *sample* corresponds to one control evaluation at the end of an interval window and is logged as `EVT_SAMPLE` with fields (time, level, measured FPS, Kalman estimate, PID output).
- **Switch event.** A *switch* is a realized level change logged as `EVT_LEVEL_CHANGED`. The switch count is the number of such events.
- **Skip-level event.** A *skip-level* event is a switch with $|\Delta u|>1$.
- **Mean switching frequency.** Over a test duration $T$ (seconds), $f_{\text{sw}} = N_{\text{sw}}/T$, where $N_{\text{sw}}$ is the number of switch events.
- **Reversal (ping-pong) event.** In this work, a *reversal* (ping-pong) is defined as a *fast round-trip away from a primary operating level*. Let the set of primary levels be $\mathcal{U}_{\text{prim}}\triangleq\{0,2\}$ (L0 = ideal, L2 = combat default). Consider a switch at time $t_i$ that leaves a primary level $u^-_i\in\mathcal{U}_{\text{prim}}$. A reversal event is counted if the level returns to $u^-_i$ within $T_{\text{rev}}$ seconds (possibly via intermediate levels); the event interval is the elapsed time between the departure switch and the first return. This convention (i) avoids double-counting symmetric two-level oscillations by anchoring at primary levels (L1 and L3 are transitional), and (ii) focuses the metric on user-relevant modes. In this work, we use $T_{\text{rev}}=10$ s. This value is chosen as approximately $3\,T_{s,\max} = 3 \times 4 = 12$ s, rounded down: a reversal must therefore span at least 2–3 full sampling periods at the slowest rate ($T_{s,\max}=4$ s at level 3), ensuring that only multi-sample oscillation cycles—rather than single transient adjustments—are counted. The resulting events are listed in Table 6.
- **Stutter rate.** The stutter rate is the fraction of `EVT_SAMPLE` observations with measured FPS $<20$ (a perceptual threshold used as a coarse proxy for visible stutter). This is *sample-weighted* rather than time-weighted; time-weighted residence is reported separately in Section 7.3.

Unless otherwise stated, scalar statistics (mean, percentiles, standard deviation) in Section 7 for Machine B are computed from the bundled CSV logs using the reproduction script (Appendix C). Standard deviations use the population convention (`ddof=0`) to match `derived_metrics.json`.

#### 1.6.3 Document Organization

Section 2 describes the system architecture. Section 3 presents plant identification results. Section 4 describes the feedforward interface. Section 5 analyzes PID degeneration. Section 6 presents multi-evidence low-oscillation assurance (including a formal safety definition, sensitivity analysis, and dwell-time frequency bounds). Section 7 reports experimental validation. Section 8 discusses generalizability and limitations, and Section 9 concludes.

---

## 2. System Architecture

### 2.1 Control Loop Topology

The performance scheduler implements a sampled-data feedback control system with the following signal flow:

```
      r = 26 FPS (setpoint)
              |
              v
      e_k = r - y_hat_k
              |
              v
  [PID] -> u*_k -> [Quantizer + confirmer] -> u_k -> [Actuator] -> Plant -> y(t)
    ^                                                                  |
    |                                                                  v
    +------------- y_hat_k <- [Kalman] <- y_k <- [Interval sampler] <---+
```

**Fig. 1.** Feedback control topology (text rendering; see implementation artifact for source). The control loop consists of six functional modules: an adaptive interval-averaging sampler (sensor), an adaptive Kalman filter (state estimator), a PID controller (control law), an asymmetric hysteresis quantizer (switching logic), a multi-parameter actuator (effector), and a performance logger (observer, not shown). The setpoint r = 26 FPS is set 4 FPS below the hardware frame rate cap of 30 FPS to provide a noise margin that prevents the controller from operating near the saturation boundary.

> **Terminology convention.** Throughout this paper, the performance level $u \in \{0,1,2,3\}$ increases with computational load reduction: $u=0$ denotes maximum visual quality (no load shedding) and $u=3$ denotes minimum quality (maximum load shedding). We use **"downgrade"** to mean $u$ increases (quality decreases, load decreases) and **"upgrade"** to mean $u$ decreases (quality increases, load increases). This convention aligns with the actuator's monotonic load-shedding semantics: higher levels always reduce rendering load.

**Control objective (problem statement).** Let $y(t)$ be the achieved frame rate and let $r=26$ FPS be the setpoint. At each sampling instant $k$, the controller selects a discrete level $u_k\in\{0,1,2,3\}$ to regulate $y$ toward $r$ while limiting switching. The design requirements are:

1. **Regulation:** keep the interval-average FPS close to $r$ under unknown, time-varying gameplay load.
2. **Low oscillation:** avoid self-excited level oscillation and limit switching frequency (formalized in Definition 1).
3. **Asymmetry:** respond quickly to FPS collapse (downgrade) and restore cautiously (upgrade) to prevent ping-pong.
4. **Runtime constraints:** per-frame overhead $\ll 30\,\mu$s and no runtime allocation.

**Implementation mapping (artifact).** Module-to-code correspondence (paths are relative to this `paper.md`):

| Role | Class / component | File |
|------|-------------------|------|
| Scheduler (feedback + feedforward) | `PerformanceScheduler` | `./PerformanceScheduler.as` |
| Interval-average sensor | `IntervalSampler` | `./IntervalSampler.as` |
| State estimator | `AdaptiveKalmanStage` + `SimpleKalmanFilter1D` | `./AdaptiveKalmanStage.as`, `../Controller/SimpleKalmanFilter1D.as` |
| Control law | `PIDController` | `../Controller/PIDController.as` |
| Quantizer + confirmer | `HysteresisQuantizer` | `./HysteresisQuantizer.as` |
| Actuator (load shedding) | `PerformanceActuator` | `./PerformanceActuator.as` |
| Logging / observability | `PerformanceLogger` | `./PerformanceLogger.as` |

The controller executes once per sampling window (not once per frame), with the sampling window length adapting to the current performance level. Between sampling points, only a single decrement operation (frame counter) is performed, consuming 2.66 μs on the target platform.

### 2.2 Adaptive Interval-Averaging Sampler

The sampler serves a dual role: measurement (computing the average FPS over the sampling window) and anti-aliasing pre-filter (attenuating high-frequency frame rate fluctuations before they enter the control loop).

**Unit convention.** Throughout this paper, elapsed times ($\Delta t_k$, $T_s$) are in **seconds** unless otherwise noted. The implementation records timestamps in milliseconds; conversion to seconds occurs at the measurement interface.

**Measurement model.** The interval-average FPS is computed as:

$$\bar{y}_k = \frac{N_k}{\Delta t_k}$$

where $N_k = f_r \cdot (1 + u_k)$ is the number of frames in the sampling window, $f_r = 30$ is the nominal frame rate, $u_k \in \{0,1,2,3\}$ is the current performance level, and $\Delta t_k$ is the elapsed wall-clock time in seconds.

**Adaptive sampling period.** The sampling window length adapts to the performance level:

| Level $u$ | Window (frames) | Approx. period |
|-----------|-----------------|----------------|
| 0         | 30              | ~1 s           |
| 1         | 60              | ~2 s           |
| 2         | 90              | ~3 s           |
| 3         | 120             | ~4 s           |

This adaptation implements **time-scale separation**: at higher performance levels (where the plant time constant τ is expected to be larger due to accumulated entity counts and deferred garbage collection), the sampling period automatically increases to match, preventing over-sampling of transient dynamics. By design, the sampling period satisfies $T_s \propto (1 + u)$. The underlying assumption—that $\tau_{\text{plant}}$ also scales approximately as $(1 + u)$—is an engineering heuristic motivated by the observation that higher-level scenes carry more deferred load, not a formally identified relationship. Section 3.4 establishes only a bound $\tau \in [0.5, 5]$ s; verifying proportionality would require per-level step-response data with higher SNR than is currently available.

**Interpretation as implicit gain scheduling.** Because $T_s$ is a function of the discrete level $u$, the loop update rate and effective closed-loop bandwidth decrease automatically at higher load. This can be viewed as an implicit gain-scheduling mechanism: as the plant becomes “slower” (larger effective $\tau$), the controller samples less frequently, improving phase robustness and noise rejection. Importantly, the same frame-count window length $N_k$ is later reused as the PID delta time $\Delta T_k$ (Section 2.4), coupling sampling and control in a consistent time-scale.

**Anti-aliasing property.** The N-sample interval average is equivalent to a moving-average (boxcar) low-pass filter whose frequency response is $H(f) = \operatorname{sinc}(f T) \triangleq \sin(\pi f T)/(\pi f T)$ where $T = N/f_r$ is the window duration. The $-3$ dB cutoff (half-power point) is at:

$$f_{-3\text{dB}} \approx \frac{0.4429 \, f_r}{N}$$

where $0.4429$ is the numerical solution of $|\operatorname{sinc}(x)| = 1/\sqrt{2}$ (half-power point). At level 0 ($N=30$): $f_{-3\text{dB}} \approx 0.44$ Hz (attenuates fluctuations with period $\lesssim 2.3$ s). At level 3 ($N=120$): $f_{-3\text{dB}} \approx 0.11$ Hz (attenuates fluctuations with period $\lesssim 9$ s). The first null of the sinc response is at $f_r/N$; between the $-3$ dB point and the null, attenuation increases monotonically. This pre-filtering constitutes the first of three cascaded low-pass stages in the system and is the primary defense against high-frequency frame rate noise caused by transient events (explosions, particle bursts).

**Remark (frame-event sampling).** The controller is *frame-event sampled*: the sampling window triggers after $N$ rendered frames, not after a fixed wall-clock interval. The nominal periods ~1–4 s in the table above assume FPS near the cap ($f_r = 30$). When FPS collapses (e.g., 15 FPS at level 2), the same 90-frame window takes ~6 s in wall-clock time, automatically extending the sampling interval. This is stability-friendly: the effective bandwidth decreases precisely when the system is under stress, providing additional phase margin and noise rejection beyond what the nominal $T_s$ suggests. The resulting positive feedback (high level → slow sampling → delayed response) is bounded because $u \in \{0,1,2,3\}$, precluding divergence. This state-dependent sampling scheme is related to event-triggered control [7, 8].

### 2.3 Adaptive Kalman Filter (State Estimator)

A one-dimensional Kalman filter with adaptive process noise provides the state estimate $\hat{y}_k$. The filter observation $\tilde{y}_k$ is the interval-average FPS $\bar{y}_k$ from the sampler (Section 2.2); we use distinct notation to emphasize the measurement-noise interpretation.

**State model:** $x_{k+1} = x_k + w_k$, $w_k \sim \mathcal{N}(0, Q_k)$

**Observation model:** $\tilde{y}_k = x_k + v_k$, $v_k \sim \mathcal{N}(0, R)$

The process noise covariance adapts to the sampling interval:

$$Q_k = \text{clamp}(Q_0 \cdot \Delta t_k, \; Q_{\min}, \; Q_{\max})$$

with $Q_0 = 0.1$, $Q_{\min} = 0.01$, $Q_{\max} = 2.0$, and $R = 1.0$. The rationale is that longer sampling intervals allow more time for the plant state to change (due to entity spawning, AI state changes, etc.), so the filter should trust the measurement more ($Q \uparrow \Rightarrow K \uparrow$). This lightweight covariance-adaptation heuristic is in the spirit of classical adaptive filtering approaches [14].

For the random-walk model ($x_{k+1}=x_k+w_k$ with $H=1$) used in the implementation, the steady-state *prior* covariance $P^-_\infty$ and the corresponding Kalman gain are obtained by solving the algebraic Riccati equation:

$$P^-_\infty = \frac{Q + \sqrt{Q^2 + 4QR}}{2}, \qquad K_\infty = \frac{P^-_\infty}{P^-_\infty + R}$$

With $R=1.0$ and $Q = Q_0\Delta t$ (before clamping), the steady-state gain over the nominal 1–4 s operating range is:

| $\Delta t$ (s) | $Q$ | $K_\infty$ |
|----------------|-----|------------|
| 1 | 0.10 | 0.270156212 |
| 2 | 0.20 | 0.358257569 |
| 3 | 0.30 | 0.417890835 |
| 4 | 0.40 | 0.463324958 |

Thus $K_\infty$ varies from 0.27 to 0.46 across operating levels: the estimator provides moderate smoothing (never becoming a near-pass-through filter), while still trusting measurements more as the sampling interval grows. This filter is the second low-pass stage in the cascade.

**Design note.** The constant-state model ($x_{k+1} = x_k$) introduces inherent lag when the true FPS is changing rapidly. This lag was identified as the root cause of a premature restoration event (Oscillation #4 in Section 7.4) and motivated the addition of a trend gate (Section 2.6).

### 2.4 PID Controller (Control Law)

The discrete PID controller computes:

$$u^*_k = K_p \cdot e_k + K_i \cdot I_k + K_d \cdot D_k$$

where:
- $e_k = r - \hat{y}_k$ (error, with setpoint $r = 26$ FPS)
- $I_k = \text{clamp}(I_{k-1} + e_k \cdot \Delta T_k, \; -M, \; +M)$ (integral with anti-windup clamping, $M = 3$)
- $D_k = (1-\alpha) D_{k-1} + \alpha \cdot (e_k - e_{k-1}) / \Delta T_k$ (filtered derivative, $\alpha = 0.2$)
- $\Delta T_k = f_r \cdot (1 + u_k) \in \{30, 60, 90, 120\}$ (in frame counts, not seconds)

**Parameters** (loaded from XML configuration):

| Parameter | Symbol | Value |
|-----------|--------|-------|
| Proportional gain | $K_p$ | 0.25 |
| Integral gain | $K_i$ | 0.5 |
| Derivative gain | $K_d$ | −30 |
| Integral limit | $M$ | 3 |
| Derivative filter | $\alpha$ | 0.2 |

**Derivative filter time constant.** The filtered derivative is a first-order IIR low-pass applied to the raw difference quotient (Section 5.2b). Its time constant in samples is $\tau_d = -1/\ln(1-\alpha) = -1/\ln(0.8) \approx 4.48$ samples. Across operating levels, this corresponds to $4.48 \times T_s \in [4.5, 18]$ s in wall-clock time (level 0 through level 3). In the frequency domain, the filter's $-3$ dB cutoff is $f_d = 1/(2\pi\tau_d T_s) \in [0.009, 0.035]$ Hz—well below the dwell-time oscillation bound of 0.2 Hz (Section 6.4), confirming that the derivative stage attenuates rather than amplifies potential chattering frequencies.

**Critical design choice (time-scale normalization).** The variable $\Delta T_k$ is passed to the PID in **frame counts** (30–120), not in seconds (~1–4). This can be interpreted as normalizing the controller to the frame index: the controller integrates and differentiates per-frame rather than per-second, which (i) makes its effective action less sensitive to the instantaneous wall-clock sampling period and (ii) forces an analyzable degeneration in the presence of integral clamping (Proposition 1). The full analysis is deferred to Section 5.

### 2.5 Asymmetric Hysteresis Quantizer

The quantizer maps the continuous PID output $u^*$ to a discrete level $u \in \{u_{\min}, \ldots, 3\}$ through:

Conceptually, this module acts as an **asymmetric, direction-memory Schmitt trigger / debouncer** around the round() boundaries: downgrades (quality ↓) are confirmed quickly, while upgrades (quality ↑) require stronger evidence to avoid ping-pong.

**Step 1. Quantization:**

$$u_{\text{cand}} = \text{clamp}(\text{round}(u^*), \; u_{\min}, \; 3)$$

**Step 2. Direction-aware confirmation:**

If $u_{\text{cand}} \neq u_{\text{current}}$, the quantizer determines the direction $d = \text{sign}(u_{\text{cand}} - u_{\text{current}})$:
- $d = +1$: downgrade (level increases, quality decreases)
- $d = -1$: upgrade (level decreases, quality increases)

The confirmation counter increments if the direction matches the pending direction, or resets to 1 if the direction reverses. Switching occurs when the counter reaches the direction-dependent threshold:

| Direction | Threshold | Rationale |
|-----------|-----------|-----------|
| Downgrade ($d=+1$) | $n_{\text{down}} = 2$ | Fast response to protect frame rate |
| Upgrade ($d=-1$) | $n_{\text{up}} = 3$ | Cautious restoration to prevent ping-pong |

**Direction memory vs. candidate memory.** The confirmation counter tracks only the *direction* of the pending change, not the specific candidate level. This means that if the candidate level changes (e.g., from 2 to 3) while maintaining the same direction (downgrade), the confirmation count continues to accumulate. This is critical for handling **performance cliffs**: when FPS drops rapidly, the PID output may increase from 2 to 3 across consecutive samples, and direction memory allows the system to switch directly to level 3 without resetting the confirmation counter.

**Equivalence reset.** When $u_{\text{cand}} = u_{\text{current}}$, the confirmation counter resets to zero, preventing residual confirmation state from triggering unintended switches during subsequent perturbations.

#### 2.5.1 Finite-State Formalization (Direction-Memory Confirmer)

Although implemented as a few lines of code, the confirmation mechanism is best understood as a finite-state machine (FSM) whose internal state is

$$s_k \triangleq \big(u_k,\; p_k,\; c_k\big),$$

where $u_k\in\{0,1,2,3\}$ is the current performance level, $p_k\in\{-1,0,1\}$ is the pending direction ($1$ downgrade, $-1$ upgrade, $0$ idle), and $c_k\in\mathbb{N}_0$ is the consecutive confirmation counter.

At each sampling instant $k$, the continuous controller output $u_k^*$ is mapped to a candidate level

$$u_{\text{cand},k} \triangleq \operatorname{sat}_{[u_{\min},\,3]}\!\left(\operatorname{round}(u_k^*)\right).$$

Define the direction symbol

$$
d_k \triangleq 
\begin{cases}
1, & u_{\text{cand},k} > u_k \quad\text{(downgrade)}\\
-1, & u_{\text{cand},k} < u_k \quad\text{(upgrade)}\\
0, & u_{\text{cand},k} = u_k.
\end{cases}
$$

Let the direction-dependent threshold be

$$
n(d) \triangleq
\begin{cases}
n_{\text{down}}, & d=1\\
n_{\text{up}}, & d=-1.
\end{cases}
$$

The FSM update is:

1. If $d_k=0$, reset confirmation $(p_{k+1},c_{k+1})\leftarrow(0,0)$ and hold $u_{k+1}\leftarrow u_k$.
2. If $d_k\neq 0$, update the pending direction and counter:
   - if $c_k>0$ and $p_k=d_k$: $(p',c')\leftarrow(d_k,\,c_k+1)$;
   - else (first detection or direction flip): $(p',c')\leftarrow(d_k,\,1)$.
3. If $c'\ge n(d_k)$, execute the switch $u_{k+1}\leftarrow u_{\text{cand},k}$ and reset $(p_{k+1},c_{k+1})\leftarrow(0,0)$; otherwise hold $u_{k+1}\leftarrow u_k$ and keep $(p_{k+1},c_{k+1})\leftarrow(p',c')$.

This FSM is intentionally **direction-memory only**: the counter is keyed to $d_k$, not to the identity of $u_{\text{cand},k}$. Consequently, during a performance cliff the candidate may drift (e.g., 1→2→3) while $d_k=1$ remains constant, and the confirmation still accumulates toward a decisive downgrade.

#### 2.5.2 Dwell-Time Interpretation

The output $u_k$ is a discrete switching signal. The confirmation FSM enforces a **minimum dwell time in samples**: after any switch event, the internal state is reset and at least $n(d)$ consecutive samples with the same direction are required for the next switch. Because $n_{\text{down}}\neq n_{\text{up}}$, the dwell-time constraint is asymmetric: downgrades may occur after 2 confirmations, while upgrades require 3.

In wall-clock time, each sample corresponds to the adaptive sampling period $T_s(u_k)=N_k/f_r$ (Section 2.2). Under the nominal design $N_k = 30(1+u_k)$ at $f_r=30$ Hz, $T_s\in\{1,2,3,4\}$ s. Therefore the confirmer implies approximate dwell-time bounds of

- downgrade: $\approx 2T_s \in [2,8]$ s,
- upgrade: $\approx 3T_s \in [3,12]$ s,

which can be interpreted as a practical dwell-time constraint for a switched/hybrid system [12, 13]. Section 6.4 connects this FSM to the assurance argument for low-chatter switching.

### 2.6 Trend Gate

The trend gate addresses a known failure mode of the constant-state Kalman model: when FPS is declining rapidly, the Kalman estimate lags behind the true value and may remain above the setpoint, causing the PID to incorrectly signal "sufficient frame rate" and approve an upgrade.

The gate computes the normalized trend rate:

$$\rho_k = \frac{\hat{y}_k - \hat{y}_{k-1}}{\Delta t_k} \quad \text{(FPS/sec)}$$

When $\rho_k < -\theta$ (with threshold $\theta = 0.2$ FPS/s), and the hysteresis quantizer has a pending upgrade confirmation, the confirmation counter is cleared. This suppresses upgrade decisions during declining FPS without affecting downgrade decisions.

Normalization by $\Delta t_k$ (in seconds) ensures that the threshold sensitivity is independent of the adaptive sampling period.

### 2.7 Actuator (Multi-Parameter Load Shedding)

The actuator maps discrete levels to concrete parameter adjustments:

| Parameter | L0 (ideal) | L1 (buffer) | L2 (combat) | L3 (fallback) |
|-----------|-----------|-------------|-------------|---------------|
| Render quality | Preset | MEDIUM | **LOW** | LOW |
| Max effects | 20 | 12 | 10 | 0 |
| Shell limit | 25 | 12 | 12 | 10 |
| Area coeff. | 300K | 450K | 600K | 3M |
| Death effects | On | On | Off | Off |
| UI animations | On | On | Off | Off |

**Monotonicity (design intent).** All parameters are designed to change monotonically with level: higher levels always reduce computational load, satisfying the sign convention required for negative feedback. Empirical validation (Section 3.3) confirms this monotonicity at the dominant L1↔L2 boundary ($\Delta\text{FPS}_{12} = +3.3$), but reveals that the L2→L3 transition produces a statistically insignificant negative gain ($\Delta\text{FPS}_{23} = -0.6$, within $1\sigma$ of zero) on low-end hardware. This localized non-monotonicity does not compromise closed-loop behavior because the dominant control authority is concentrated at the L1↔L2 boundary (where >87% of load shedding occurs), while switching is confirmation-based and L3 is used primarily as a safety mode rather than a high-leverage control region (Section 7.3).

### 2.8 Emergency Bypass

A hard-coded panic threshold ($\text{FPS}_{\text{panic}} = 5$) triggers immediate single-step downgrade when the raw (pre-Kalman) interval-average FPS falls below this value. This bypasses the Kalman filter, PID, and hysteresis, providing a last-resort safety net for near-freeze conditions. The threshold is set conservatively to avoid interfering with the normal control loop during typical low-FPS conditions (10–20 FPS range).

**Anti-chattering property of the bypass.** After executing a downgrade, the emergency bypass resets the Kalman estimate, the PID internal state, and the hysteresis confirmation state, and clears any active hold window. This prevents two potential instabilities: (1) a stale Kalman estimate triggering an immediate upgrade reversal, and (2) residual confirmation counts carrying across the boundary. After a bypass event, the next control action requires a full sampling window ($T_s \geq 1$ s) plus $n_{\text{down}} = 2$ confirmations to trigger a further downgrade, providing a natural dwell time. Chattering at exactly $\text{FPS}_{\text{panic}} = 5$ is implausible in practice because (a) the bypass fires at most once per sampling window (not per frame), (b) a single-step downgrade from any level $u < 3$ reduces load, and (c) the threshold is set far below the normal operating range (the minimum observed FPS in closed-loop testing was 14.9).

**Limitation: near-zero adjacent-level gain.** On hardware where adjacent-level gains are near zero (e.g., $\Delta\text{FPS}_{01} \approx 0$ on Machine B), the single-step bypass may be ineffective: a panic event at L0 triggers a downgrade to L1, which provides negligible FPS improvement. Recovery then requires an additional sampling window plus confirmation to reach the effective L2 boundary. A multi-step fallback (bypassing directly to L2 when the L0→L1 gain is known to be negligible) would reduce recovery latency; this is not implemented in the current version.

---

## 3. Plant Identification

### 3.1 Experimental Protocol

System identification was performed using open-loop step response testing. Open-loop segments are realized by combining:
1. A `forceLevel(L)` call, which applies the actuator at level $L$, clears PID and confirmation state, clears any hold window, and resets the sampling interval to match $L$.
2. A quantizer lock ($u_{\min}=u_{\max}=L$), which prevents the feedback path from overriding the forced level by clamping the candidate back to $L$.

The Kalman estimator is intentionally not reset between segments; it continues to track the measured FPS and provides a denoised trace for logging. Because the quantizer is locked, PID/Kalman outputs do not affect the applied level during identification and are recorded only for analysis.

The test protocol traverses all four levels in both directions:

$$L_0 \xrightarrow{\text{step}} L_1 \xrightarrow{\text{step}} L_2 \xrightarrow{\text{step}} L_3 \xrightarrow{\text{step}} L_2 \xrightarrow{\text{step}} L_1 \xrightarrow{\text{step}} L_0$$

Each segment runs for 30–60 seconds to allow steady-state convergence. The full test produces 7 segments with 117 samples over 355.7 seconds.

All data is recorded by the ring-buffer performance logger at each sampling point, capturing: timestamp, level, raw FPS, Kalman estimate, PID output, and PID component decomposition (P, I, D terms).

### 3.2 Steady-State Gain Identification

The steady-state FPS for each level is obtained by averaging the interval-average FPS over the stable portion of each segment. Forward and reverse measurements are cross-validated:

| Level | Forward $\bar{K}_L$ | Reverse $\bar{K}_L$ | Cross-mean $\hat{K}_L$ | $\Delta$ |
|-------|---------------------|---------------------|------------------------|----------|
| L0    | 17.2                | 15.4                | 16.3                   | 1.8      |
| L1    | 16.9                | 16.6                | 16.8                   | 0.3      |
| L2    | 20.2                | 20.1                | 20.1                   | 0.1      |
| L3    | 19.5                | —$^\ddagger$        | 19.5$^\ddagger$        | —        |

The L0 forward/reverse discrepancy (1.8 FPS) is attributed to load drift during the 6-minute test (enemy entities accumulate over time in the combat scenario). L1 and L2 show excellent forward/reverse consistency (Δ ≤ 0.3), indicating stable load during the middle portion of the test.

**Table 1.** Steady-state FPS per level, low-end machine configuration. Test scenario: wave-based combat level with periodic enemy spawning. $^\ddagger$L3 has only a forward measurement (the step protocol terminates at L3 before reversing); $\hat{K}_3 = 19.5$ is therefore a single-direction estimate, not a cross-validated mean.

### 3.3 Actuator Gain Non-Uniformity

The inter-level gain (FPS improvement per level step) reveals severe non-uniformity:

$$\Delta\text{FPS}_{01} = \hat{K}_1 - \hat{K}_0 = 16.8 - 16.3 = +0.5 \; \text{FPS}$$
$$\Delta\text{FPS}_{12} = \hat{K}_2 - \hat{K}_1 = 20.1 - 16.8 = +3.3 \; \text{FPS}$$
$$\Delta\text{FPS}_{23} = \hat{K}_3 - \hat{K}_2 = 19.5 - 20.1 = -0.6 \; \text{FPS} \quad (|\Delta| < 1\sigma_{\text{meas},L2} \approx 1.23; \text{ not statistically significant})$$

The L1→L2 transition—which activates `_quality = LOW` in the rendering engine—contributes $3.3 / 3.8 = 87\%$ of the total load-shedding capacity. The remaining transitions produce effects within the measurement noise ($\sigma \approx 1.5$–$2.0$ FPS).

Cross-machine comparison with a second test configuration confirms the pattern with different magnitudes:

| Gain | Machine A | Machine B (low-end) |
|------|-----------|---------------------|
| $\Delta\text{FPS}_{01}$ | +1.7 | +0.5 |
| $\Delta\text{FPS}_{12}$ | +6.1 | +3.3 |
| $\Delta\text{FPS}_{23}$ | +3.0 | −0.6 |
| **Total $\sum$** | **+10.8** | **+3.2** |
| **Effective range** $\max_L \hat{K}_L - \min_L \hat{K}_L$ | +10.8 | **+3.8**$^\dagger$ |

$^\dagger$On Machine B, the maximum FPS is achieved at L2 ($\hat{K}_2 = 20.1$), not L3. The effective range (L0→L2) is 3.8 FPS, while the algebraic sum including the slightly negative L2→L3 increment is 3.2 FPS. In the analysis below we therefore use the effective range $\max_L \hat{K}_L - \min_L \hat{K}_L$; closed-loop switching is dominated by the L1↔L2 boundary and confirmation-based logic (Section 7.3), so the sign of the small L2→L3 increment does not materially affect observed behavior.

The negative value $\Delta\text{FPS}_{23} = -0.6$ on Machine B deserves comment. Three explanations are consistent with the data: (1) **measurement noise**: the steady-state standard deviation at L2 and L3 is 1.2 and 0.5 FPS respectively, so $-0.6$ lies within $1\sigma$ of zero and may be a statistical artifact; (2) **rendering pipeline path change**: disabling all visual effects at L3 may cause the renderer to traverse a different code path (e.g., skipping the effects compositor entirely), which could introduce a small overhead from branch misprediction or cache effects; (3) **load drift**: the L3 measurement segment occurs later in the test than L2, and entity accumulation increases baseline load over time (cf. the 1.8 FPS L0 forward/reverse discrepancy). Regardless of cause, the practical consequence is that the L2→L3 transition is an **ineffective actuator step** on this hardware: it costs a quality reduction but provides no measurable FPS benefit.

On the low-end machine, the four-level system therefore degenerates to an effective two-level system: {L0 ≈ L1} and {L2 ≈ L3}. The controller's response to this degeneracy is analyzed in Section 7.3 (emergent skip-level behavior).

**Table 2.** Inter-level actuator gains across two hardware configurations.

### 3.4 Plant Time Constant

The plant time constant $\tau_L$ characterizes how quickly FPS responds to a level change. For a first-order model $x_{k+1} = a_L x_k + (1-a_L) K_L$, the time constant is $\tau_L = -T_s / \ln(a_L)$.

Precise extraction of $\tau_L$ is not possible from the current data because:
1. For L0→L1 and L2→L3 transitions, $\Delta\text{FPS} \approx 0$, so the transient is indistinguishable from noise ($\text{SNR} < 0.3$).
2. For the L1→L2 transition ($\Delta\text{FPS} = 3.3$, $\sigma \approx 1.5$, $\text{SNR} \approx 2.2$), the first post-step sample (at $\Delta t \approx 4.7$ s) already shows FPS near the new steady state, implying $\tau_L < T_s \approx 4.7$ s.

We therefore establish a bound:

$$\tau_L \in [0.5, 5.0] \; \text{s}$$

The lower bound (0.5 s) corresponds to the fastest plausible plant response (immediate parameter application + one rendering frame). The upper bound (5.0 s) is established by the observation that the first post-step sample is already at steady state.

**This bound is sufficient for the conservative surrogate-margin checks** in Section 6, which compute Nyquist/gain margins parametrically over plausible $\tau_L$ (and even beyond this range, for conservatism).

### 3.5 Noise Characterization

**Measurement noise.** The variance of the interval-average FPS during steady-state segments:

| Level | Samples | $\hat{\sigma}^2_{\text{meas}}$ | $\hat{\sigma}_{\text{meas}}$ |
|-------|---------|-------------------------------|------------------------------|
| L0    | 15 (tail) | 3.27                        | 1.81                         |
| L1    | 10 (mid) | 1.64                         | 1.28                         |
| L2    | 8 (mid)  | 1.51                         | 1.23                         |
| L3    | 7 (all)  | 0.24                         | 0.49                         |

The monotonic decrease in measurement noise with level is expected: higher levels use longer sampling windows ($N = 30(1+u)$ frames), and the interval-average variance scales as $\sigma^2_{\text{meas}} \propto 1/N$. This confirms the anti-aliasing role of the adaptive sampler.

**Table 3.** Measurement noise characteristics per level, estimated from open-loop steady-state segments.

**Non-Gaussian noise structure.** The Kalman filter assumes Gaussian process and measurement noise ($w_k, v_k$). In practice, two sources of non-Gaussianity are present: (1) **garbage-collection (GC) pauses** produce heavy-tailed, positively skewed outliers in the interval-average FPS (a single 50 ms GC pause in a 1 s window reduces the measured FPS by ≈1.5); (2) **gameplay-correlated load** (wave spawns, boss phases) introduces colored, non-stationary disturbances that violate the white-noise assumption. The adaptive $Q$ scaling (Section 2.3) partially compensates for the latter by widening the process noise covariance during longer windows, but does not address the non-Gaussian tail structure. In the current design, robustness to these violations comes from the downstream hysteresis quantizer, which filters out isolated outliers through multi-sample confirmation. A more principled approach would replace the Kalman filter with a robust estimator (e.g., Huber-based or median-based), but this is not pursued given the platform's computational constraints.

**Non-minimum-phase transients.** The `_quality` parameter switch (L1↔L2 boundary) triggers an internal rendering pipeline reconfiguration that may produce a transient FPS dip before the steady-state improvement materializes—a non-minimum-phase response. This effect was observed qualitatively during development (a 1–2 frame stutter immediately after a quality change) but is not resolvable in the current data because the sampling window (1–4 s) averages over the transient. The surrogate model in Section 6 does not model an initial inverse-response transient (i.e., it assumes no right-half-plane zeros); if such a transient is significant, it would increase the effective delay $\theta$ and reduce phase margin. The conservative choice of $\theta = 2$ s (half of the maximum 4 s window) provides some buffer for this effect.

---

## 4. Feedforward Control Interface

In addition to the closed-loop feedback path, the scheduler provides a feedforward channel (`setPerformanceLevel`) that allows external systems (e.g., level scripts, menu controls) to directly set the performance level with a hold window. This dual-channel architecture separates two concerns: the feedback loop handles *runtime adaptation* to unknown load, while the feedforward channel handles *anticipated transitions* (scene changes, user preferences) where the desired level is known a priori.

The feedforward procedure executes the following steps:

1. Immediately applies the requested level via the actuator.
2. Resets PID and hysteresis states to prevent the feedback loop from immediately overriding the forced level.
3. Sets a hold timer ($\Delta t_{\text{hold}}$, default 5 s) during which the Kalman filter and PID continue to observe, but the quantizer and actuator outputs are suppressed.

At the end of the hold window, the Kalman estimate has converged to the actual FPS under the new level, so the feedback loop resumes from a consistent state rather than from a stale estimate.

This **measurement/hold decoupling** (designated Method B in the implementation) resolves a prior bug where hold windows distorted FPS measurement by creating a mismatch between the frame count numerator and elapsed time denominator in the interval-average computation. The earlier implementation (`setProtectionWindow`) extended `_framesLeft` to span the hold period, which caused `measure()` to compute FPS as $N_{\text{normal}} / \Delta t_{\text{hold}}$—systematically underestimating FPS by a factor of $(1+u)/(\text{holdSec} \cdot f_r)$ when the hold exceeded one sampling period. Method B avoids this by using normal-length sampling windows throughout the hold period and suppressing only the output (quantizer and actuator).

---

## 5. PID Degeneration in Quantized Control Systems

This section presents the central theoretical contribution: a formal characterization of how PID control degenerates when connected to a quantized actuator through an interval-averaging sampler, and—more importantly—why this degeneration implies that **low-oscillation behavior in such systems is structurally determined by the quantizer's confirmation mechanism, not by the precision of PID tuning**. The degeneration result itself (integral saturation, derivative attenuation) is not surprising in isolation; its significance lies in the consequence for the quantized closed-loop system: after rounding, only the quantization interval matters, rendering fine PID parameter sensitivity irrelevant to the switching dynamics.

### 5.1 Proposition: PID Degeneration Under Frame-Count Delta Time

**Proposition 1 (PID degeneration).** *Consider a discrete PID controller with proportional gain $K_p$, integral gain $K_i$, derivative gain $K_d$, derivative filter coefficient $\alpha \in (0,1)$, and anti-windup integral clamping at $\pm M$. Let the delta time be $\Delta T_k = N_k$ in frame counts, where $N_k = f_r(1+u_k) \geq N_{\min}$ for some nominal frame rate $f_r$. Let the error signal be $e_k = r - \hat{y}_k$. Then:*

*(a) (Integral saturation) For any error $|e_k| > M / N_{\min}$, the integral term saturates to $\pm M$ in exactly one sampling step after a PID reset. Two sub-cases govern the subsequent behavior: (i) if the error sign is consistent ($\text{sign}(e_k) = \text{sign}(e_{k-1})$), the integral remains clamped at the same bound; (ii) if the error sign reverses with $|e_k| > M / N_k$, the integral re-saturates to the opposite bound within one step (since $|e_k \cdot N_k| > M$ drives the accumulated value past both zero and the opposite clamp). In either case, $|I_k| = M$ whenever $|e_k| > M / N_k$. At near-zero error ($|e_k| \leq M / N_k \leq 0.1$ FPS), the integral increment $|e_k \cdot N_k| \leq M$ may not reach the clamp boundary, and the integral temporarily leaves saturation before re-saturating on the next sufficiently large error. In the saturated regime, the integral contribution is the constant $\pm K_i M$, independent of the error magnitude.*

*(b) (Derivative attenuation) For a fixed performance level (i.e., $N_k = N$ constant within the current operating mode), the effective first-sample derivative gain is $|K_{d,\text{eff}}| = |K_d| \cdot \alpha / N$. For any sustained error ramp with constant step $\delta = e_k - e_{k-1}$, the steady-state derivative contribution is $K_d \cdot \delta / N$. When a level switch changes $N_k$, the derivative magnitude adjusts instantaneously to the new $N_k$, but the qualitative behavior is unchanged. Since the filter's DC gain is unity, the global bound (valid for all $k$) is $|K_d D_k| \leq |K_d| \cdot |\Delta e_{\max}| / N_{\min}$. The first-sample impulse peak after an error jump $\Delta e$ from a quiescent state is the tighter $|K_d| \cdot \alpha \cdot |\Delta e| / N$; this is the practically relevant bound because error differences in this system are impulsive rather than sustained.*

*(c) (Effective control law) In the saturated regime (i.e., when $|e_k| > M/N_k$—equivalently $|e_k \cdot N_k| > M$, covering both the sign-consistent and sign-reversal sub-cases of part (a)—which holds for $>97\%$ of operating samples; see Corollary C1), the PID output takes the form:*

$$u^*_k = K_p \cdot e_k + \text{sign}(e_k) \cdot K_i M + D_{\text{damp},k}$$

*where $|D_{\text{damp},k}| \leq |K_d| \cdot |\Delta e_{\max}| / N_{\min}$ globally (DC gain bound). For impulsive error jumps, the first-sample peak is $|K_d| \cdot \alpha \cdot |\Delta e| / N \leq 0.2|\Delta e|$ at the most sensitive level (deployed parameters, level 0). After rounding and clamping to $\{u_{\min}, \ldots, u_{\max}\}$, the switching decision depends only on which quantization interval $u^*_k$ falls into, not on its precise value within that interval.*

**Corollary 1 (Numerical instantiation).** *With the deployed parameters $K_p = 0.25$, $K_i = 0.5$, $K_d = -30$, $M = 3$, $\alpha = 0.2$, $f_r = 30$, $N_k \in \{30, 60, 90, 120\}$:*

- *Integral saturation threshold: $M/N_k \in [3/120, 3/30] = [0.025, 0.1]$ FPS (depending on level); in particular, $M/N_{\min} = 0.1$ guarantees one-step saturation for any $|e|>0.1$ after reset.*
- *Saturated integral contribution: $K_i M = 0.5 \times 3 = \pm 1.5$.*
- *Effective first-sample derivative gain: $|K_{d,\text{eff}}| = 6/N_k \in [0.05, 0.20]$.*

### 5.2 Proof

**(a) Integral saturation.** After a PID reset, $I_0 = 0$. At the first sampling step:

$$I_1 = \text{clamp}(I_0 + e_1 \cdot N, \; -M, \; +M)$$

For $|e_1| > M/N_{\min}$:

$$|e_1 \cdot N| \geq |e_1| \cdot N_{\min} > M$$

Therefore $|I_1| = M$ (one-step saturation). For subsequent steps, we distinguish two sub-cases:

*Sub-case (i): sign-consistent error.* If $\text{sign}(e_k) = \text{sign}(I_{k-1})$ and $|e_k| > M/N_k$, then $I_{k-1} + e_k N_k$ has the same sign as $I_{k-1}$ with $|I_{k-1} + e_k N_k| \geq M + |e_k| N_k > M$, so $I_k$ remains clamped at $\text{sign}(I_{k-1}) \cdot M$.

*Sub-case (ii): sign reversal.* If $\text{sign}(e_k) = -\text{sign}(I_{k-1})$ and $|e_k| > M/N_k$, then $I_{k-1} = \pm M$ and the update computes $I_{k-1} + e_k N_k$, which has sign equal to $\text{sign}(e_k)$ whenever $|e_k N_k| > M$ (since $|e_k N_k| > M = |I_{k-1}|$ ensures the new term dominates). The clamp then yields $I_k = \text{sign}(e_k) \cdot M$. Thus the integral re-saturates to the opposite bound within one step, with no intermediate unsaturated sample.

In both sub-cases, $|I_k| = M$ whenever $|e_k| > M/N_k$. At near-zero error ($|e_k| \leq M/N_k = 0.1$ FPS at level 0, or $\leq 0.025$ FPS at level 3), the integral increment $|e_k \cdot N_k| \leq M$ may not reach the clamp boundary, and the integral temporarily leaves saturation. Empirically, this occurs in 5/195 = 2.6% of samples (Section 5.3, corollary C1), all at error zero-crossings or post-reset transients. The integral is therefore clamped at $\pm M$ for all samples satisfying $|e_k| > M/N_k$, which covers >97% of operating conditions.

**(b) Derivative attenuation.** The filtered derivative update is:

$$D_k = (1-\alpha) D_{k-1} + \alpha \cdot \frac{e_k - e_{k-1}}{N_k}$$

This is a first-order IIR low-pass filter applied to the raw difference $(e_k-e_{k-1})/N_k$. Consider first the case where the performance level is fixed ($N_k = N$ constant). The filter's steady-state gain (DC gain) is unity: $\alpha / (1-(1-\alpha)) = 1$. Therefore, under a sustained error ramp where $e_k - e_{k-1} = \delta$ is approximately constant:

$$D_\infty = \frac{\delta}{N}$$

The derivative contribution to the PID output is $K_d \cdot D_\infty = K_d\,\delta/N$. For a single-step error jump $\Delta e$ (impulse in the difference signal), the peak response occurs at the first sample: $D_1 = \alpha \cdot \Delta e / N$, then decays geometrically as $(1-\alpha)^{k-1}$. The effective first-sample derivative gain is:

$$|K_{d,\text{eff}}| = |K_d| \cdot \frac{\alpha}{N}$$

When a level switch changes $N_k$ from $N_{\text{old}}$ to $N_{\text{new}}$, the filter state $D_{k-1}$ carries over, and the next update uses the new $N_k$. Since $N_k \in \{30, 60, 90, 120\}$ is a finite set, the derivative magnitude at any sample is bounded by:

$$|D_k| \leq \frac{\alpha \cdot |\Delta e_{\max}|}{N_{\min}} + (1-\alpha)|D_{k-1}|$$

Iterating this recurrence to steady state (assuming the worst-case input $|\Delta e_{\max}|/N_{\min}$ is sustained), the geometric series converges to the global (DC gain) bound:

$$|D_k| \leq \frac{|\Delta e_{\max}|}{N_{\min}}, \qquad |K_d D_k| \leq \frac{|K_d| \cdot |\Delta e_{\max}|}{N_{\min}}$$

For a single error jump $\Delta e$ from a quiescent state ($D_{k-1} = 0$), the first-sample impulse peak is $|D_1| = \alpha \cdot |\Delta e| / N$, with $|K_d D_1| = |K_d| \cdot \alpha \cdot |\Delta e| / N$. Since error differences in this system are impulsive (transient jumps, not sustained), this first-sample bound is the practically relevant constraint and is used in the corollary checks (Section 5.3, C2).

**(c) Degeneration to biased proportional controller.** Combining (a) and (b), in the saturated regime:

$$u^*_k = \underbrace{K_p \cdot e_k}_{\text{proportional}} + \underbrace{(\pm K_i M)}_{\text{directional bias}} + \underbrace{D_{\text{damp},k}}_{|D_{\text{damp},k}| \leq |K_d||\Delta e_{\max}|/N_{\min}}$$

The $\text{round}(\cdot) + \text{clamp}$ operation maps this continuous value to one of $u_{\max}-u_{\min}+1$ integers with quantization step size 1. The bias term $\pm K_i M$ shifts the operating point, ensuring that even small errors in the bias direction cross a quantization boundary. This eliminates the **steady-state error dead zone** that would otherwise exist in a purely proportional quantized controller (where errors smaller than $0.5/K_p$ would not cross the quantization boundary). The derivative damping term is bounded globally by $|K_d| \cdot |\Delta e_{\max}| / N_{\min}$ (DC gain bound); for impulsive error jumps, the first-sample peak is $|K_d| \cdot \alpha \cdot |\Delta e| / N_{\min} = 0.2|\Delta e|$ (at the most sensitive operating level). After rounding, the derivative's effect is limited to advancing or delaying a boundary crossing by at most one quantization step. ∎

**Remark (Numerical instantiation).** With the deployed parameters (Corollary 1): the integral contribution is the constant $K_i M = 0.5 \times 3 = \pm 1.5$. For $N = 30$ (level 0), $K_d D_\infty = -\delta$ (same order as the proportional term); for $N = 120$ (level 3), $K_d D_\infty = -0.25\delta$ (significantly attenuated). The bias of $\pm 1.5$ ensures that even small positive errors produce $u^* \geq 1.5$, which rounds to 2. The proportional dead zone is $0.5/K_p = 2$ FPS; the integral bias eliminates it entirely.

### 5.3 Testable Corollaries (Battle-Log Checks)

Proposition 1 yields **checkable predictions** on recorded PID components. Using the 195-sample closed-loop battle log (Machine B), we verify (all scalars in this subsection are emitted by the reproducibility script to `./figures/derived_metrics.json`):

- **C1 (integral clamping dominates).** Prediction: the integral contribution to the control output should satisfy $|I_k|\approx |K_iM|=1.5$ except near $e_k\approx 0$ or immediately after resets. Observation: $|I_k|\ge 1.49$ in 190/195 = 97.4% of samples. Across the same run, $e_k$ changes sign 33 times, yet only five samples leave saturation; these coincide with near-zero error (zero-crossings) and the post-hold PID reset (timestamps listed in Section 7.5).

- **C2 (derivative is moderate damping).** Prediction: the derivative contribution scales as $\mathcal{O}(1/N)$ (Proposition 1b) and should remain $\mathcal{O}(1)$ in controller output units. Observation: $|K_d D_k|\in[0.002, 1.276]$ while $|P_k|\in[0.006, 1.940]$ over the same 195-sample run. The analytic peak bound $|K_{d,\text{eff}}| \cdot |\Delta e_{\max}| = 0.20 \times 7.36 = 1.47$ (at level 0 with the largest observed error jump) is consistent with the observed maximum of 1.276, confirming that the derivative never dominates the PID output.

- **C3 (switching is quantizer-dominated).** Prediction: once $u_k^*$ is rounded and passed through confirmation, fine variations of $u_k^*$ within a quantization bin should not trigger switches; switching is shaped primarily by the hysteresis/confirmation FSM (Section 2.5). Observation: the instantaneous candidate $\operatorname{sat}(\operatorname{round}(u_k^*))$ differs from the current level in 69/195 = 35.4% of samples, yet only 25 switch events occur, with a minimum separation of two samples (Lemma 2). This mismatch-to-switch gap quantifies chattering suppression due to confirmation. Conversely, Table 4 illustrates the reverse: in the saturated regime, the integral bias $\pm K_i M = \pm 1.5$ drives $u^*$ decisively into the adjacent quantization bin (e.g., the "typical" row at 99405 ms: $u^* = 1.50$, which rounds to 2, crossing the L1→L2 boundary). Because the bias magnitude (1.5) equals the bin width, even small positive errors produce candidates in the next bin—confirming that the quantizer, not PID fine-tuning, is the switching bottleneck.

Representative samples from the battle log illustrate the degenerated mapping $u^* \approx 0.25e \pm 1.5 + D$ and the subsequent quantized candidate (before confirmation):

| Time (ms) | $u$ | FPS | $e=r-\hat{y}$ | $P_k$ | $I_k$ | $D_k$ | $u^*_k$ | cand | Note |
|-----------|-----|-----|---------------|-------|-------|-------|---------|------|------|
| 81073 | 2 | 24.6 | +0.02 | +0.01 | −0.40 | −0.05 | −0.44 | 0 | post-reset |
| 99405 | 1 | 24.2 | +2.69 | +0.67 | +1.50 | −0.68 | +1.50 | 1 | typical |
| 116193 | 1 | 14.9 | +7.36 | +1.84 | +1.50 | −0.72 | +2.62 | 3 | FPS cliff |
| 300402 | 2 | 23.6 | −0.16 | −0.04 | −1.50 | −0.07 | −1.61 | 0 | typical |
| 256508 | 0 | 32.3 | −3.74 | −0.93 | −1.50 | +0.35 | −2.08 | 0 | typical |

**Table 4.** Testable-corollary snapshots from the closed-loop battle log (Machine B). Here $P_k$, $I_k$, and $D_k$ are the logged contributions to $u^*_k$ (so $u^*_k=P_k+I_k+D_k$), and cand is $\operatorname{sat}(\operatorname{round}(u^*_k))$ before confirmation. The first row (81073 ms) is sampled immediately after a PID reset, hence $I_k = -0.40 \neq \pm 1.5$; this is one of the five unsaturated samples identified in C1.

### 5.4 Implications

**Implication 1: Fine PID tuning is not the low-oscillation bottleneck.** Since the PID output is quantized to four levels and filtered by confirmation-based hysteresis, the precise values of $K_p$, $K_i$, and $K_d$ affect mainly the location of quantization boundaries in error space, not the switching dynamics. Low-chatter behavior is determined primarily by the hysteresis/confirmation mechanism (dwell time), not by PID parameter accuracy.

**Implication 2: The "PID" is a biased threshold generator.** The system would produce identical switching behavior if the PID were replaced by a lookup table mapping FPS ranges to candidate levels, with the integral bias serving as a fixed offset. The PID structure is retained for its engineering convenience (single-formula implementation, compatibility with standard tuning infrastructure) rather than for its dynamical properties.

**Implication 3: Anti-windup mode is irrelevant.** The integral uses simple clamping (the crudest anti-windup method). More sophisticated methods (back-calculation, conditional integration) would produce identical behavior because the integral is *intended* to saturate—it functions as a directional bias, not as an accumulator.

---

## 6. Multi-Evidence Low-Oscillation Safety

Because the plant is unmodeled, nonlinear, time-varying, sampled, and hybrid (the sampling period depends on the discrete level), a single global stability proof would be both fragile and out of scope. We first define the safety property we aim to establish, then organize the analysis as a multi-link evidence chain.

**Definition 1 (Low-oscillation safety).** *The switching signal $u_k$ is said to satisfy $(\bar{f}_{\text{sw}}, \bar{n}_{\text{rev}}, T_{\text{rev}})$-low-oscillation safety over a test duration $T$ if:*

1. *The mean switching frequency satisfies $f_{\text{sw}} = |\{k : u_k \neq u_{k-1}\}| / T \leq \bar{f}_{\text{sw}}$;*
2. *The number of reversal (ping-pong) events—defined as fast round-trips away from a primary level within $T_{\text{rev}}$ seconds (Section 1.6.2)—satisfies $n_{\text{rev}} \leq \bar{n}_{\text{rev}}$.*

*Both conditions are mechanically computable from the event log. We additionally apply a **causal-attribution audit protocol** (Section 7.4) to check whether observed reversals are disturbance-driven rather than self-excited. This audit requires human inspection of each reversal event against known disturbance timing (e.g., wave spawns) and is therefore empirical and not part of the formal definition. A fully automatable alternative would require that all reversals coincide with a measured FPS change exceeding a threshold $\Delta_{\text{dist}}$ within the preceding sampling window, but calibrating $\Delta_{\text{dist}}$ requires per-scenario tuning and is left for future work.*

*Operationalization.* In this implementation, switching occurs only at sampling instants and is logged explicitly as `EVT_LEVEL_CHANGED`. Therefore $|\{k:u_k\ne u_{k-1}\}|$ is equal to the number of switch events $N_{\text{sw}}$ in the log, and $f_{\text{sw}}=N_{\text{sw}}/T$. Reversal counting follows the primary-level round-trip definition in Section 1.6.2 with $\mathcal{U}_{\text{prim}}=\{0,2\}$ and $T_{\text{rev}}=10$ s.

*In this work, we target $\bar{f}_{\text{sw}} = 0.1$ Hz (one switch per 10 s), set $T_{\text{rev}} = 10$ s (Section 1.6.2), and set $\bar{n}_{\text{rev}}=6$. The reversal budget $\bar{n}_{\text{rev}}=6$ corresponds to ≈1 reversal/min over the test duration $T\approx 345$ s, or approximately 17% of the $\lfloor T/T_{\text{rev}}\rfloor \approx 34$ available non-overlapping reversal windows. This threshold is motivated by adaptive bitrate streaming research, where quality-switching rates above 1–2 per minute are consistently associated with significant user annoyance [18, 19]; since performance-level switching in our system has analogous perceptual impact (visual quality changes), adopting the same order-of-magnitude rate cap is a conservative choice. The causal-attribution audit protocol is evaluated via event-level attribution in the battle logs (Section 7.4).*

The analysis is organized as a **four-link evidence chain** supporting low-oscillation safety:

- **E1 Constructive boundedness**: show all internal signals are bounded by design (BIBO sanity baseline).
- **E2 Conservative surrogate margins**: compute linear margins on a worst-case first-order delay surrogate.
- **E3 Describing-function diagnostics**: use relay/hysteresis describing functions as a heuristic limit-cycle check.
- **E4 Empirical attribution**: use battle logs to attribute observed “ping-pong” to external disturbances, not self-excitation.

### 6.1 Constructive Boundedness (Global Boundedness by Construction)

**Proposition 2 (internal-state boundedness).** *Every signal in the closed loop is bounded for all time, independent of the plant model.*

*Proof.* We verify boundedness signal-by-signal:
- **Switching signal:** $u_k \in \{0, 1, 2, 3\}$, bounded by the finite actuator set.
- **Plant output:** The rendered frame rate is bounded above by the hardware cap $f_r$; the interval-average FPS may slightly exceed $f_r$ due to timestamp granularity, but remains bounded.
- **State estimate:** The Kalman update $\hat{y}_k = (1-K_\infty)\hat{y}_{k-1} + K_\infty \tilde{y}_k$ is a convex combination ($K_\infty \in (0,1)$), so $\hat{y}_k$ remains in the convex hull of past observations—bounded whenever the plant output is bounded.
- **PID state:** The integral is hard-clamped to $[-M, +M]$; the derivative filter is a contraction mapping with bounded input; hence $u^*_k$ is a finite linear combination of bounded terms.
- **Error:** $e_k = r - \hat{y}_k$ is bounded as a difference of bounded signals.

Since all internal signals are bounded by construction—without invoking any plant model—the loop satisfies global state boundedness. ∎

Boundedness alone does not preclude **limit cycles**—bounded periodic oscillations that persist indefinitely. The remainder of this section addresses the limit-cycle question through three complementary lenses (E2–E4).

### 6.2 Conservative Surrogate Margins: Linear Decomposition

We decompose the loop into a linear part $L(z)$ and a nonlinear part $\mathcal{N}$:

$$L(z) = H_{\text{Kalman}}(z) \cdot H_{\text{PID}}(z) \cdot G_{\text{plant}}(z)$$

**Kalman filter transfer function** (at steady state):

$$H_{\text{Kalman}}(z) = \frac{K_\infty \, z}{z - (1 - K_\infty)}$$

*Derivation.* From the steady-state Kalman update $\hat{y}_k = (1-K_\infty)\hat{y}_{k-1} + K_\infty y_k$, taking the $z$-transform:

$$\hat{Y}(z) = (1-K_\infty)\,z^{-1}\hat{Y}(z) + K_\infty\,Y(z)$$

$$\hat{Y}(z)\bigl[1 - (1-K_\infty)z^{-1}\bigr] = K_\infty\,Y(z)$$

$$H_{\text{Kalman}}(z) = \frac{\hat{Y}(z)}{Y(z)} = \frac{K_\infty}{1 - (1-K_\infty)z^{-1}} = \frac{K_\infty\,z}{z - (1-K_\infty)}$$

The $z$ in the numerator reflects that the measurement $y_k$ enters at the same time index as the output $\hat{y}_k$ (causal, zero-delay).

DC gain: $H_{\text{Kalman}}(1) = \frac{K_\infty \cdot 1}{1-(1-K_\infty)} = 1$ (unity DC gain, as expected for a consistent estimator).

**PID transfer function** (small-signal, with saturated integral):

Since the integral is saturated and contributes a constant bias (not a dynamic element), the small-signal PID transfer function around any operating point is:

$$H_{\text{PID}}(z) = K_p + K_d \cdot \frac{\alpha (1 - z^{-1})}{N(1 - (1-\alpha)z^{-1})}$$

DC gain: $H_{\text{PID}}(1) = K_p = 0.25$.

**Plant transfer function** (first-order model):

$$G_{\text{plant}}(z) = \frac{\Delta\text{FPS}_L \cdot (1 - a_L)}{z - a_L}, \quad a_L = e^{-T_s/\tau_L}$$

DC gain: $G_{\text{plant}}(1) = \Delta\text{FPS}_L$.

**Open-loop DC gain:**

$$|L(1)| = 1 \times K_p \times \Delta\text{FPS}_L = 0.25 \times \Delta\text{FPS}_L$$

| Boundary | $\Delta\text{FPS}_L$ | $\|L(1)\|$ |
|----------|---------------------|------------|
| L0 ↔ L1 | 0.5                 | 0.125      |
| L1 ↔ L2 | 3.3                 | **0.825**  |
| L2 ↔ L3 | 0.0                 | 0.000      |

The maximum open-loop DC gain is 0.825, occurring at the L1↔L2 boundary.

### 6.3 Nyquist Margin and Sensitivity of a First-Order Delay Surrogate (E2)

**Why a continuous-time surrogate.** Section 6.2 derives $z$-domain transfer functions, and one might expect a discrete Nyquist plot of $L(e^{j\omega T_s})$. We use a continuous-time surrogate instead because: (1) the sampling period $T_s$ is state-dependent ($T_s = (1+u)/f_r$), so the discrete loop transfer function is not time-invariant and a single $z$-domain Nyquist does not capture this multi-rate behavior; (2) the surrogate is deliberately *simpler* than the true system, capturing only the DC gain and a lumped delay. The true loop includes additional low-pass filtering from the Kalman estimator ($K_\infty \in [0.27, 0.46]$) and the adaptive sampler, both of which attenuate high-frequency components beyond what the first-order lag predicts. The surrogate therefore *overestimates* the loop gain at frequencies where limit cycles would occur; all margins reported here are lower bounds on the true linear margins.

**Surrogate model.** We approximate the plant as a first-order lag with time constant $\tau$ and include a lumped sensor delay $\theta$ to represent interval averaging:

$$L(j\omega) = k_0\frac{e^{-j\omega\theta}}{1 + j\omega\tau}, \qquad k_0 = K_p\Delta\text{FPS}_{\max}$$

For the low-end machine, $\Delta\text{FPS}_{\max} = 3.3$ at the L1↔L2 boundary, hence $k_0 = 0.25\times 3.3 = 0.825$. We take $\theta = 2$ s as a conservative upper bound (half of the 4 s window at level 3) and sweep $\tau \in \{0.5, 2, 5, 10\}$ s. This continuous-time visualization is interpreted via the classical Nyquist criterion [10, 11].

![Fig. 2. Nyquist plot of the surrogate loop transfer function.](./figures/fig_nyquist.png)

**Fig. 2.** Nyquist plot of the surrogate model $L(j\omega)$ for $k_0=0.825$ and $\theta=2$ s. For all tested $\tau$, the locus remains far from −1 and does not encircle it, indicating comfortable linear margin at the worst-case DC gain boundary.

**Assumption S1 (Surrogate-model premises for margin computation).** *The following margins are valid under two premises: (a) the loop is approximated by the LTI surrogate $L(j\omega) = k_0 e^{-j\omega\theta}/(1+j\omega\tau)$; (b) $k_0 < 1$. Under (a), $|L(j\omega)| = k_0/\sqrt{1+\omega^2\tau^2}$ is strictly monotone-decreasing. Combined with (b), this implies $|L(j\omega)| < 1$ for all $\omega \geq 0$: the Nyquist locus lies entirely within the open unit disk, and the closest approach to $-1$ occurs at the unique phase crossover $\omega_{-\pi}$. Gain margin and $M_s$ then follow from $|L(j\omega_{-\pi})|$. When (b) is violated ($k_0 > 1$, as on Machine A), these margin arguments do not apply; see the scope limitation below.*

**Gain margins.** Under Assumption S1, $|L(j\omega)| \leq k_0 < 1$ for all $\omega$. There is therefore **no gain crossover frequency** in the surrogate model. The gain margin (reciprocal of $|L|$ at the phase crossover $\angle L = -\pi$) is:

| $\tau$ (s) | $\omega_{-\pi}$ (rad/s) | $|L(j\omega_{-\pi})|$ | GM (dB) | $M_s$ upper bound |
|-------------|--------------------------|----------------------|---------|-------------------|
| 0.5 | 1.23 | 0.703 | 3.1 | 3.37 (10.5 dB) |
| 2 | 0.96 | 0.381 | 8.4 | 1.62 (4.2 dB) |
| 5 | 0.83 | 0.193 | 14.3 | 1.24 (1.9 dB) |
| 10 | 0.78 | 0.105 | 19.6 | 1.12 (1.0 dB) |

Even in the worst case ($\tau = 0.5$ s), the gain margin of 3.1 dB means the loop gain could increase by a factor of 1.42 before the linear surrogate loses stability—a comfortable margin given that $k_0$ is bounded by identified actuator gains.

**Sensitivity function analysis.** The sensitivity function $S(j\omega) = 1/(1+L(j\omega))$ quantifies closed-loop disturbance rejection. Its peak $M_s = \max_\omega |S(j\omega)|$ is the reciprocal of the minimum distance from $L(j\omega)$ to the critical point $-1$. The surrogate magnitude is $|L(j\omega)| = k_0 / \sqrt{1+\omega^2\tau^2}$ (the delay $e^{-j\omega\theta}$ contributes only phase, not magnitude). Under Assumption S1, $k_0/\sqrt{1+\omega^2\tau^2} \leq k_0 = 0.825 < 1$ for all $\omega \geq 0$, so the Nyquist locus lies entirely within the open unit disk. The closest approach to $-1$ occurs at the phase crossover (Assumption S1), where $L(j\omega_{-\pi}) = -|L(j\omega_{-\pi})|$ and the distance is $d_{\min} = 1 - |L(j\omega_{-\pi})|$. Therefore:

$$M_s \leq \frac{1}{1 - |L(j\omega_{-\pi})|}$$

The $M_s$ upper bounds are tabulated above. For $\tau \geq 2$ s (the plausible plant time-constant range from Section 3.4), $M_s \leq 1.62$, which is well within the standard robustness requirement $M_s < 2.0$ (6 dB) [10]. Even the extreme case $\tau = 0.5$ s yields $M_s \leq 3.37$—moderate disturbance amplification at a single frequency, but bounded.

At DC, the sensitivity is $|S(0)| = 1/(1+k_0) = 1/1.825 \approx 0.548$ (−5.2 dB), meaning that slow load disturbances are attenuated by approximately 45%. This attenuation is the mechanism by which the controller maintains mean FPS near the setpoint despite load variation.

![Fig. 3. Sensitivity Bode plot of the surrogate model.](./figures/fig_sensitivity_bode.png)

**Fig. 3.** Sensitivity magnitude $|S(j\omega)|$ for the surrogate model across $\tau \in \{0.5, 2, 5, 10\}$ s. For $\tau \geq 2$ s, the peak remains below the 6 dB ($M_s = 2.0$) robustness limit. All curves converge to $-5.2$ dB at DC (45% disturbance attenuation) and to 0 dB at high frequencies, visualizing the waterbed trade-off discussed below.

**Remark (waterbed effect).** Low-frequency disturbance rejection ($|S| < 1$) must be compensated by $|S| > 1$ at some higher frequency (Bode's integral constraint). The $M_s$ bound above quantifies the worst-case amplification at that frequency. The favorable $M_s$ values for $\tau \geq 2$ s indicate that the waterbed effect is mild: the loop attenuates low-frequency load variations without significantly amplifying high-frequency noise—a consequence of the cascaded low-pass filtering (sampler + Kalman + derivative filter).

**Scope limitation: hardware dependence of $k_0$.** The margins above are computed for Machine B ($\Delta\text{FPS}_{12} = 3.3$, $k_0 = 0.825 < 1$). On Machine A, $\Delta\text{FPS}_{12} = 6.1$, yielding $k_0 = K_p \times 6.1 = 1.525 > 1$. In this regime, the surrogate loop gain exceeds unity at DC and the gain crossover frequency is nonzero, so the linear gain margin argument above does not apply. For Machine A, the anti-chattering guarantee falls back to the dwell-time frequency bound (Section 6.4, Lemma 2) and empirical attribution (Section 7.4), which are plant-gain-independent. The $1/n$ confirmation heuristic (Section 6.4) reduces the effective gain to $k_{0,\text{down}} \approx 0.76$ and $k_{0,\text{up}} \approx 0.51$, both below unity, but this is a heuristic rather than a formal margin. A tighter analysis for $k_0 > 1$ would require switched-system Lyapunov methods [12] and is deferred to future work. Note that the empirical attribution data (Section 7.4) covers only Machine B; for Machine A, the assurance rests entirely on the structural dwell-time bound (E2c, Lemma 2) and the aggregate statistics in Table 7.

**Surrogate-model fidelity note.** The first-order lag surrogate captures only the DC gain and a lumped delay; it does not model the Kalman filter's frequency-dependent phase lag (which increases with frequency and depends on $K_\infty$). The true loop therefore has more phase loss at frequencies near the dwell-time bound (0.2 Hz) than the surrogate predicts. Since additional phase loss *reduces* the gain at the phase crossover, this omission is conservative for the gain margin but not for the phase margin. The margins in the table above should be interpreted as order-of-magnitude estimates of linear robustness, not as precise certificates.

### 6.4 Dwell Time from FSM Confirmation (Switched-System View, E2/E4)

The implemented quantizer is not a static relay: it is the finite-state confirmer defined in Section 2.5.1. A level change is executed only after $n$ consecutive samples confirm the same direction ($n_{\text{down}}=2$, $n_{\text{up}}=3$), after which the internal state is reset. This directly suppresses high-frequency boundary crossings, analogous to dwell-time constraints in switched systems [12, 13].

**Lemma 2 (minimum dwell time in samples).** Let $\{k_i\}$ be the sample indices at which the discrete level changes ($u_{k_i}\neq u_{k_i-1}$). If the switch at $k_{i+1}$ has direction $d\in\{1,-1\}$, then

$$k_{i+1}-k_i \ge n(d), \quad\text{hence}\quad k_{i+1}-k_i \ge \min(n_{\text{down}}, n_{\text{up}})=2.$$

*Proof.* Immediately after a switch, the confirmer resets $(p,c)\leftarrow(0,0)$. On each subsequent sample, the counter can increase by at most one. Therefore reaching $c\ge n(d)$ requires at least $n(d)$ samples. (Note: a direction reversal during the confirmation phase resets the counter to 1, not 0—see Section 2.5.1, rule 2b. This reset itself consumes the current sample, so the minimum number of *additional* samples needed to reach $n(d)$ is still $n(d)-1$, preserving the bound $k_{i+1}-k_i \ge n(d)$.) ∎

Because the sampling period itself depends on $u$ (Section 2.2), this sample-domain dwell time translates into a variable wall-clock dwell time (Section 2.5.2). In the closed-loop battle logs, the observed mean switch interval is 13.6 ± 7.5 s, and the minimum observed separation between switch events is two samples (consistent with $n_{\text{down}}=2$), indicating that empirical dwell times are typically far above the minimum constraint.

**Frequency upper bound from dwell time (rigorous).** Lemma 2 guarantees that any switch through the confirmer requires at least $n$ consecutive samples with the same direction. A complete oscillation cycle (downgrade + upgrade) requires at least $n_{\text{down}} + n_{\text{up}} = 5$ samples. Combined with the adaptive sampling period $T_s \in [1, 4]$ s, the maximum self-excited oscillation frequency is:

$$f_{\text{osc}} \leq \frac{1}{(n_{\text{down}} + n_{\text{up}}) \cdot T_{s,\min}} = \frac{1}{5 \times 1} = 0.2 \; \text{Hz}$$

At this frequency, the surrogate loop gain is heavily attenuated. For the worst-case plant ($\tau = 0.5$ s, $\theta = 2$ s):

$$|L(j \cdot 2\pi \cdot 0.2)| = \frac{0.825}{\sqrt{1 + (2\pi \cdot 0.2 \cdot 0.5)^2}} = \frac{0.825}{\sqrt{1 + 0.395}} \approx 0.699$$

This is well below unity, confirming that even at the maximum possible oscillation frequency, the loop gain is insufficient to sustain a limit cycle in the linear surrogate. For the more realistic $\tau = 2$ s:

$$|L(j \cdot 2\pi \cdot 0.2)| \approx \frac{0.825}{\sqrt{1 + (2\pi \cdot 0.2 \cdot 2)^2}} \approx 0.296$$

The dwell-time constraint therefore acts as a structural guarantee: it restricts oscillations to frequencies where the loop gain is heavily attenuated, independent of describing-function assumptions.

**Effective-gain heuristic for the describing-function analysis (auxiliary).** To further incorporate confirmation into the describing-function framework of Section 6.5, we additionally introduce an engineering heuristic: approximate the effect of $n$-step confirmation as a $1/n$ reduction of the effective nonlinearity gain. The motivation is that the confirmer delays each switch by at least $n$ samples, implying $T \geq 2n T_s$ for a complete switching cycle, or equivalently $f \leq f_s/(2n)$. Scaling the effective relay gain by $1/n$ captures this effect approximately.

**This approximation is a heuristic, not a derived bound; its error magnitude is unknown.** The classical describing function assumes a memoryless nonlinearity, whereas the confirmer has internal state (direction, counter). The $1/n$ scaling captures the intuition that multi-sample confirmation reduces effective throughput, but the actual gain reduction depends on the input amplitude and frequency in a way that the $1/n$ factor does not model. The scaling should be interpreted as an engineering rule of thumb that provides a useful diagnostic, not as a formal stability certificate. The formal anti-chattering guarantee comes from the dwell-time frequency bound above and Lemma 2, not from this heuristic.

Under this approximation, the effective DC loop gain becomes:

$$k_{0,\text{down}} \approx \frac{K_p \Delta\text{FPS}_{\max}}{n_{\text{down}}}, \qquad k_{0,\text{up}} \approx \frac{K_p \Delta\text{FPS}_{\max}}{n_{\text{up}}}$$

For Machine A (higher actuator range), $\Delta\text{FPS}_{12}=6.1$ yields $K_p\Delta\text{FPS}=1.525$ at the L1↔L2 boundary, but confirmation reduces the effective gain to $\approx 0.76$ in the downgrade direction and $\approx 0.51$ in the upgrade direction.

### 6.5 Describing-Function Diagnosis (Auxiliary Heuristic, E3†)

> **Note on evidence weight.** This subsection provides an auxiliary diagnostic, not a formal stability certificate. The confirmation FSM has internal state (direction, counter), violating the memoryless assumption required by the classical describing function [9]. The formal anti-chattering guarantees in this paper rest on the dwell-time frequency bound (Section 6.4) and empirical attribution (Section 7.4), not on this analysis. We include it because the describing function provides useful visual intuition for *why* confirmation suppresses limit cycles in the relay approximation [6, 11].

To make the quantization limit-cycle mechanism explicit, we apply a describing-function check to the surrogate model.

Approximating the quantizer as a relay with hysteresis half-width $\Delta$ and output amplitude $M=1$ (one level step), the describing function is:

$$N(A) = \frac{4M}{\pi A}\left[\sqrt{1 - \left(\frac{\Delta}{A}\right)^2} - j\frac{\Delta}{A}\right], \quad A > \Delta$$

and the limit-cycle condition is $L(j\omega) = -1/N(A)$.

Using $k_0=0.825$, $\tau=3$ s, $\theta=2$ s, $M=1$, and $\Delta=0.5$ (static rounding dead zone—the half-width of the `round()` quantization bin; this is distinct from the dynamic equivalent hysteresis width introduced by confirmation, which depends on the error trajectory and is not captured by the static $\Delta$), the naive static-relay model admits an intersection at:

- $A \approx 0.564$ (level units), $\omega \approx 0.524$ rad/s ($f \approx 0.0834$ Hz)
- $L(j\omega) \approx -0.205 - 0.393j$, $-1/N(A) \approx -0.205 - 0.393j$

This suggests that **hysteresis alone** does not rule out a self-excited oscillation in the naive surrogate. However, when we incorporate $n$-step confirmation using the effective-gain approximation ($k_0\to k_0/n$), the intersection disappears in both switching directions:

- **Downgrade** ($n_{\text{down}}=2$, $k_0 \to 0.4125$): minimum locus distance $d_{\min}=0.109$ (Fig. 4b).
- **Upgrade** ($n_{\text{up}}=3$, $k_0 \to 0.275$): minimum locus distance $d_{\min}=0.200$ (Fig. 4c).

The upgrade direction is more conservative by design ($n_{\text{up}} > n_{\text{down}}$), and the larger clearance confirms that cautious restoration also provides a wider stability margin in the describing-function sense.

![Fig. 4. Describing-function intersection check (naive vs. confirmation).](./figures/fig_describing_function_intersection.png)

**Fig. 4.** Describing-function intersection check for the surrogate model. (a) Naive static relay model shows an intersection at $(A, \omega) = (0.564, 0.524\;\text{rad/s})$ (green marker). (b) Accounting for $n_{\text{down}}=2$ confirmation ($k_0 \times 0.5 = 0.4125$) removes the intersection; minimum distance $d_{\min} = 0.109$. (c) Accounting for $n_{\text{up}}=3$ confirmation ($k_0 \times 1/3 = 0.275$) provides even larger clearance; $d_{\min} = 0.200$.

### 6.6 Evidence Chain Summary

**Verification against Definition 1.** The closed-loop battle log (345.5 s, 25 switches) yields $f_{\text{sw}} = 25/345.5 = 0.072$ Hz $< \bar{f}_{\text{sw}} = 0.1$ Hz ✓. Under $T_{\text{rev}}=10$ s and $\mathcal{U}_{\text{prim}}=\{0,2\}$ (Section 1.6.2), the reversal count is $n_{\text{rev}}=5 \leq \bar{n}_{\text{rev}}=6$ (Table 6) ✓. The causal-attribution audit (Section 7.4) additionally finds all reversals attributable to external disturbances ✓.

| Link | Claim | Method | Result |
|------|-------|--------|--------|
| E1 | Internal boundedness | Constructive signal bounding (Proposition 2) | All signals bounded by construction, independent of plant model |
| E2a | Conservative linear margin | Nyquist on first-order delay surrogate (Fig. 2) | No gain crossover ($k_0 = 0.825 < 1$); GM 3.1–19.6 dB over $\tau\in[0.5,10]$ s. **Machine B only** (Assumption S1); Machine A ($k_0>1$) relies on E2c + E4 |
| E2b | Bounded sensitivity (disturbance rejection) | Sensitivity function $S(j\omega) = 1/(1+L)$ | $M_s \leq 1.62$ for $\tau \geq 2$ s; DC attenuation −5.2 dB. **Machine B only** (Assumption S1) |
| E2c | Dwell-time frequency bound | Lemma 2 + sampling period | Max oscillation frequency $f_{\text{osc}} \leq 0.2$ Hz; $|L(j2\pi \cdot 0.2)| \leq 0.70$ (insufficient for limit cycle) |
| E2/E4 | Minimum dwell time prevents chattering | FSM confirmer + log statistics | Min separation ≥2 samples; mean 13.6 ± 7.5 s/switch |
| E3† | *Auxiliary*: no plausible relay limit cycle under confirmation | Describing-function intersection (Fig. 4) with $1/n$ heuristic | Naive relay intersects; heuristic model clears with $d_{\min}=0.109$ (down), $0.200$ (up) |
| E4 | Residual ping-pong is disturbance-driven | Empirical event classification (Section 7.4) | All reversals attributable to external wave timing and estimator lag |
| E4+ | Estimator-lag upgrade suppressed | Trend gate (Section 2.6) | Declining Kalman estimate clears upgrade confirmation |

†E3 is an auxiliary diagnostic (Section 6.5); formal anti-chattering guarantees rest on E2c and E4.

---

## 7. Experimental Validation

### 7.1 Test Protocol

Closed-loop testing was conducted on the wave-based combat scenario "Fallen City Defense" (stage file: `data/stages/基地车库/堕落城保卫战.xml`), which produces cyclic load variations via periodic enemy spawning. The scenario was chosen because it stresses the controller with alternating high-load (active combat) and low-load (wave intermission) phases.

**Configuration:**
- Frame rate cap: 30 FPS. Setpoint: 26 FPS.
- PID parameters: $K_p = 0.25$, $K_i = 0.5$, $K_d = -30$, $M = 3$, $\alpha = 0.2$.
- Hysteresis: downgrade threshold = 2, upgrade threshold = 3.
- Initial condition: manual preset to L2 with 10-second hold window.
- Duration: 345.5 seconds (195 samples, 25 level switches, 5 scene transitions).

**Reproducibility.** All figures (Figs. 2–6) and Machine B scalar aggregates reported in Sections 5–7 (e.g., Table 5, switch-interval statistics, Kalman gains, and describing-function diagnostics) are derived from the two bundled CSV logs in `./log/` by running `./tools/generate_paper_figures.py`, which regenerates the figure PNGs and `./figures/derived_metrics.json`. Event-count metrics (skip-level and reversal events) follow the explicit `EVT_LEVEL_CHANGED` scan conventions in Appendix C. (Machine A results in Section 7.6 are aggregated values from an earlier run and are not fully reproducible from the bundled logs.)

### 7.2 Overall Performance

To provide an open-loop baseline at maximum quality, we use the first steady segment `OL:0>0` from the system identification log (30 samples spanning 51.3 s). Closed-loop results use the full battle log (195 samples, 345.5 s).

![Fig. 5. Closed-loop FPS time series and performance level.](./figures/fig_fps_timeseries.png)

**Fig. 5.** Closed-loop time series (Machine B). Blue: measured interval-average FPS. Orange: Kalman estimate. Dashed: target (26 FPS). Gray: discrete performance level $u$ (0 = best, 3 = lowest). Vertical markers indicate level changes. The estimator may report FPS slightly above the 30 FPS cap due to timestamp granularity and interval-averaging error; the rendered frame rate remains capped.

**Table 5.** Overall FPS comparison between an open-loop L0 baseline segment and closed-loop operation (Machine B).

| Metric | Open-loop baseline (L0 locked, `OL:0>0`) | Closed-loop (adaptive) |
|--------|-----------------------------------------|------------|
| Samples | 30 | 195 |
| Mean FPS | 17.16 | 26.86 |
| Std. dev. (`ddof=0`) | 2.40 | 4.15 |
| Median FPS | 17.20 | 28.90 |
| P5 FPS (5th percentile) | 13.31 | 18.29 |
| Min FPS | 11.2 | 14.9 |
| Max FPS | 22.6 | 32.3 |
| FPS < 20 (stutter rate) | 93.3% (28/30) | 8.7% (17/195) |
| **FPS improvement (mean)** | — | **+50–62%** (estimated; separate-session baseline) |
| **P5 FPS improvement** | — | **+37.4%** |

The controller maintains the mean FPS within 1 FPS of the 26 FPS setpoint, with the median above the setpoint (indicating the system spends more than half its time in a comfortable operating region). The tail-latency improvement is also substantial: the 5th-percentile FPS rises from 13.3 to 18.3 (+37.4%), and the fraction of samples below 20 FPS (a perceptible stutter threshold) drops from 93% to under 9%. The P5 improvement is a more conservative metric than the mean improvement because it characterizes worst-case rather than average behavior.

**Same-session regulation metrics (baseline-independent).** The following metrics are computed entirely within the closed-loop session and do not depend on the open-loop baseline: median FPS = 28.90 (above the 26 FPS setpoint); stutter rate (FPS $< 20$) = 8.7% sample-weighted; time-weighted stutter residence = 12.2% (computed by attributing inter-sample durations to the later sample's level, per Section 7.3); and the system spends 44.1% of wall-clock time at L0 (maximum quality). These figures provide evidence of effective regulation independent of any cross-session comparison.

**Methodological caveat.** The open-loop baseline and closed-loop test are from separate recording sessions (the system identification run and the battle test, respectively), not from simultaneous or alternating trials. Both sessions use the same combat scenario ("Fallen City Defense") on the same machine (Machine B), but differences in exact game state (enemy entity counts, spawn timing, and load drift—see the 1.8 FPS forward/reverse discrepancy in Section 3.2) may affect the baseline FPS. The reported improvement should therefore be interpreted as an approximate range estimate (50–62% across two machines). The cross-machine comparison (Section 7.6), which yields a consistent range, provides additional confidence in the magnitude of improvement but does not eliminate the baseline confound. A more rigorous evaluation would interleave open-loop and closed-loop segments within a single test session; this is left for future work.

### 7.3 Level Residence and Switching Behavior

**Level residence distribution:**

| Level | Sample % | Time % | Mean FPS | Design intent |
|-------|----------|--------|----------|---------------|
| L0 | 68.2% | 44.1% | 27.2 | Ideal (highest quality) |
| L1 | 14.9% | 20.4% | 25.7 | Buffer |
| L2 | 13.3% | 26.0% | 26.9 | Combat default |
| L3 | 3.6% | 9.5% | 26.1 | Fallback |

Time % is computed by summing inter-sample durations and attributing each duration to the **later** sample's level (a conservative convention for hybrid systems with switching and adaptive sampling [12]). Under this definition, the system spends 44.1% of its time at L0 (maximum quality) while maintaining target frame rate. L3 (emergency fallback) is used only 9.5% of the time, confirming that it serves as a safety net rather than a primary operating mode.

**Switching statistics:**
- Total switches: 25 (15 downgrades, 10 upgrades).
- Mean switching interval: 13.6 ± 7.5 s/switch.
- Downgrade response: 2 sampling periods (2–8 s depending on level).
- Upgrade response: 3 sampling periods (3–12 s depending on level).

**Emergent skip-level behavior.** Ten multi-level transitions ($|\Delta u|>1$) were observed:
- L0→L2 (2 events): PID output exceeds 1.5, rounding directly to level 2, bypassing the ineffective L1.
- L1→L3 (1 event): During severe FPS collapse (14.9 FPS), direction memory allows confirmation to accumulate across changing candidates (2→3).
- L2→L0 (5 events): During wave intermission, FPS recovers toward 30, the PID output falls below the 0.5 rounding threshold (after clamp), and 3 consecutive upgrade confirmations execute a direct 2-step restoration.
- L3→L0 (2 events): Same mechanism as above, yielding a direct 3-step restoration.

This skip-level behavior is an **emergent property** of the continuous PID + discrete quantizer interaction. The system was not explicitly designed to skip levels, but the combination of (a) the biased proportional control law producing large $|u^*|$ during severe deviations and (b) the direction-memory hysteresis allowing cross-level confirmation naturally produces this behavior. On the low-end machine, where $\Delta\text{FPS}_{01} \approx 0$ renders L1 ineffective, the controller automatically bypasses it—a form of implicit actuator gain adaptation.

### 7.4 Oscillation Analysis

Five ping-pong oscillation events (fast return to a primary level within $T_{\text{rev}}=10$ s; Section 1.6.2) were identified:

| # | Levels | Interval | Cause |
|---|--------|----------|-------|
| 1 | L0↔L1 | 8.2 s | Wave intermission FPS recovery |
| 2 | L0↔L1 | 8.4 s | Same (consecutive cycle) |
| 3 | L0↔L1 | 8.7 s | Same (forms 26.5 s sustained oscillation with #2) |
| 4 | L2→L0→L2 | 3.3 s | Kalman lag → premature restoration |
| 5 | L2→L0→L1→L2 | 8.3 s | Stepped re-degradation after wave start |

**Table 6.** Reversal (ping-pong) events ($n_{\text{rev}} = 5$ within $T_{\text{rev}} = 10$ s; $\mathcal{U}_{\text{prim}}=\{0,2\}$). All events are attributable to external periodic disturbances (enemy wave timing) rather than controller self-excitation (causal-attribution audit protocol; see Definition 1).

**Quantitative attribution evidence.** To support the causal attribution claim, we examine the measured FPS change in the sampling window immediately preceding each departure switch. For all five reversals, the pre-departure FPS change exceeds 3 FPS—at least $2\times$ the steady-state noise $\sigma \approx 1.5$ FPS (Table 3)—indicating an external load disturbance rather than noise-driven drift. Oscillation #4 (L2→L0→L2, 3.3 s) exhibits the largest pre-departure FPS drop (23.6→16.8, $\Delta = -6.8$ FPS, $>4\sigma$), consistent with the wave-spawn disturbance identified in the data analysis report. This magnitude test provides a quantitative (though not fully automated) basis for the causal-attribution audit protocol (Definition 1).

**Audit procedure.** The following three-step protocol was applied to each reversal event in Table 6:

1. **Window extraction.** For each reversal with departure time $t_{\text{leave}}$ and return time $t_{\text{return}}$, extract the log window $[t_{\text{leave}} - T_s,\; t_{\text{return}} + T_s]$, where $T_s$ is the sampling period at the departure level ($T_s \in \{1,2,3,4\}$ s).
2. **Disturbance proxy check.** Within the window, identify observable proxies for exogenous load changes: (a) measured FPS change $|\Delta\text{FPS}| > 2\sigma_{\text{meas}}$ (Table 3) in the sample preceding departure; (b) known scenario event timing (wave spawn at fixed intervals in the "Fallen City Defense" stage). If either proxy is present, classify as *exogenous*.
3. **Residual classification.** Events not matching any proxy are classified as *potential self-excitation* and listed separately for manual review.

All five events in Table 6 satisfy criterion 2(a) ($|\Delta\text{FPS}| > 3$ FPS $> 2\sigma$) and four of five coincide with known wave-spawn timing (criterion 2(b)). No events fall into the residual category. This protocol is scenario-specific; extending it to other scenarios would require calibrating the proxy thresholds and event timing, which is noted as future work.

**Reversal-counting verification.** Each event satisfies the primary-level departure criterion (Section 1.6.2): events #1–3 depart from $L0 \in \mathcal{U}_{\text{prim}}$ (L0→L1→L0 round-trips); event #4 departs from $L2 \in \mathcal{U}_{\text{prim}}$ (L2→L0→L2); event #5 departs from $L2 \in \mathcal{U}_{\text{prim}}$ (L2→L0→L1→L2, returning via intermediate levels). All return intervals are below $T_{\text{rev}}=10$ s. The count $n_{\text{rev}}=5 \leq \bar{n}_{\text{rev}}=6$ satisfies condition (2) of Definition 1.

**Oscillations #1–3** involve L0↔L1 transitions where $\Delta\text{FPS}_{01} \approx 0$. These oscillations produce **no perceptible visual change** for the player, as both levels have nearly identical rendering output on the test hardware.

**Oscillation #4** is the most informative: at $t = 300402$ ms, the system is at L2 with FPS = 23.6 (declining). The Kalman estimate is 26.16 (lagging behind the declining true FPS), so the PID computes a negative output that triggers upgrade confirmation. Three consecutive samples confirm upgrade → switch to L0. Within 3.3 s, FPS collapses to 16.8 → 19.4, and the system rapidly re-degrades to L2.

This event motivated the **trend gate** (Section 2.6), which detects declining Kalman estimates and suppresses upgrade confirmation. The trend gate was validated in the subsequent test iteration.

### 7.5 PID Component Analysis

Direct measurement of PID components confirms the degeneration theorem:

![Fig. 6. PID component decomposition and output.](./figures/fig_pid_components.png)

**Fig. 6.** PID component decomposition for the closed-loop run (Machine B). The integral term remains clamped at approximately ±1.5 for nearly the entire run, while the derivative term provides moderate damping during transients. This visualization matches the analytic degeneration result in Section 5.

**Integral saturation:** 190/195 = 97.4% of samples have $|I_k| \geq 1.49$ (within 1% of the theoretical maximum $|K_i \cdot M| = 1.5$). The 5 unsaturated samples occur at exact zero-crossings:

| Time (ms) | $I_k$ | Context |
|-----------|--------|---------|
| 81073 | −0.40 | Post-reset recovery (PID just cleared) |
| 157369 | −0.56 | L1 stable, error ≈ 0 |
| 203938 | −0.02 | L0 stable, error ≈ 0 |
| 268840 | +0.40 | Error zero-crossing |
| 329325 | +0.25 | Error zero-crossing |

**Derivative damping:** During FPS decline ($de/dt > 0$): $D \in [-1.28, -0.54]$, partially canceling $P$ (mean cancellation: 45% of P-term). During FPS recovery ($de/dt < 0$): $D \in [+0.03, +0.74]$, partially canceling $P$ (mean cancellation: 25% of P-term). At steady state: $D \approx 0$.

The asymmetric damping behavior (stronger damping during decline than recovery) is a consequence of the nonlinear derivative filter: rapid FPS changes produce larger error differences, and the low-pass filter ($\alpha = 0.2$) responds more strongly to large transients.

### 7.6 Cross-Machine Comparison

Machine A results are taken from an earlier test run on a second hardware configuration; only aggregated metrics are reported here. The CSV logs bundled with this paper correspond to Machine B (low-end).

| Metric | Machine A | Machine B (low-end) |
|--------|-----------|---------------------|
| Test duration | 275.7 s | 345.5 s |
| Open-loop FPS (L0) | ~16 | ~17 |
| Closed-loop mean FPS | 26.1 | 26.9 |
| Closed-loop P5 FPS | — | 18.3 |
| FPS improvement | +62% | +56% |
| Switching events | 26 | 25 |
| Mean switch interval | 10.6 s | 13.7 s |
| Ping-pong events | 6 | 5 |
| Effective actuator range$^\dagger$ | +10.8 FPS | +3.8 FPS |
| Integral saturation rate | 96.2% | 97.4% |
| Skip-level events ($|\Delta u|>1$) | 0 | 10 |

**Table 7.** Cross-machine comparison. $^\dagger$Effective actuator range is $\max_L \hat{K}_L - \min_L \hat{K}_L$ (see Table 2 footnote). The controller achieves comparable frame rate improvement (56–62%) despite a 3× difference in effective actuator range. Machine B's lower range is partially compensated by emergent skip-level behavior (10 events vs. 0 on Machine A).

The consistency of integral saturation rates (96–97%) across machines with different timing characteristics validates the degeneration theorem's generality.

---

## 8. Discussion

### 8.1 Positioning Relative to Existing Approaches

As discussed in Section 1.5 (Related Work), the majority of deployed dynamic quality systems in modern engines use continuous actuators (DRS, temporal upscaling) that permit classical proportional control. The simplest discrete approaches—threshold heuristics equivalent to relay controllers with dead zones—lack filtering, adaptation, and formal anti-oscillation guarantees. This work occupies a middle ground: a full closed-loop system with state estimation, control law, nonlinear quantization, and asymmetric hysteresis, justified by the specific combination of discrete actuator, non-uniform gains, and unmodeled plant dynamics. The closest analogy in other domains is DVFS power management (Section 1.5), which faces similar discrete-actuator quantization limit-cycle challenges, though typically with better-characterized plants.

### 8.2 Generalizability

The analysis framework extends to any system with:
- A discrete actuator with $n$ levels and non-uniform gains.
- An unmodeled or partially modeled plant.
- A requirement for asymmetric response (fast degradation, cautious restoration).

Candidate applications include:
- **Server QoS management**: discrete service tiers (e.g., video resolution levels) with non-uniform bandwidth savings.
- **Embedded power management**: discrete CPU frequency/voltage states (DVFS) with non-linear power-performance curves.
- **Network congestion control**: discrete rate levels with heterogeneous link capacities.

The key insight—that PID precision is often irrelevant after coarse quantization and low-oscillation behavior is determined primarily by the hysteresis/confirmation mechanism—applies universally to these domains.

### 8.3 Limitations

1. **Plant identification depth.** The time constant $\tau_L$ could not be precisely extracted due to insufficient signal-to-noise ratio. While the conservative surrogate-margin checks in Section 6 accommodate this via parametric bounds, a precise $\tau_L$ would enable tighter performance guarantees and optimal sampling period selection.

2. **Single-scenario validation.** Closed-loop testing was conducted on one combat scenario. Different scenarios (boss fights, exploration, cutscenes) may have different load dynamics. The open-loop data covers only one scenario on one machine pair.

3. **Two-machine sample.** Cross-machine comparison uses only two hardware configurations. A broader hardware survey would strengthen the generalizability claims, particularly regarding the actuator gain non-uniformity pattern.

4. **Surrogate-model limitations in assurance analysis.** The Nyquist and describing-function analyses use a first-order continuous-time surrogate model with lumped delay, whereas the real system is sampled, multi-rate, and time-varying (the sampling period depends on the performance level). The margins reported (Section 6.3) apply to the surrogate and serve as conservative lower bounds (Section 6.3, "Why a continuous-time surrogate"), not exact characterizations of the true hybrid system. A rigorous proof would require switched-system Lyapunov methods [12], which are deferred to future work.

5. **Describing-function heuristic.** The $1/n$ effective-gain reduction used in Section 6.4 to model the effect of $n$-step confirmation on the describing function is an engineering heuristic, not a derived bound. The classical describing function assumes a memoryless nonlinearity, whereas the confirmation FSM has internal state (direction, counter). This link (E3†) in the evidence chain is marked as auxiliary accordingly; the formal anti-chattering guarantee comes from the dwell-time frequency bound (Section 6.4) and Lemma 2, not from the describing-function diagnostic.

6. **Noise and plant model simplifications.** The Kalman filter assumes Gaussian, white process and measurement noise, whereas the actual noise includes heavy-tailed GC outliers and colored gameplay-correlated disturbances (Section 3.5). The surrogate plant model is a minimum-phase first-order lag, but the `_quality` parameter switch may introduce non-minimum-phase transients (Section 3.5). These model–reality gaps are partially mitigated by the downstream hysteresis quantizer and the conservative delay parameter $\theta$, but are not formally bounded.

7. **Missing ablation baselines.** The paper does not report ablation experiments isolating the contribution of individual components (e.g., Kalman filter alone, PID without hysteresis, fixed vs. adaptive sampling). Without these baselines, the claim that "low-oscillation behavior is dominated by hysteresis and confirmation" (Section 5.4) rests on the analytical degeneration argument and battle-log corollaries, not on comparative experimental evidence. A systematic ablation study—disabling components one at a time and measuring switching frequency and FPS variance—would strengthen this central claim.

8. **Baseline methodology.** The open-loop baseline and closed-loop test are from separate recording sessions (Section 7.2). A more rigorous evaluation would interleave open-loop and closed-loop segments within a single test session, eliminating load-drift confounds. The P5 FPS improvement (+37.4%) provides a more conservative estimate than the mean improvement (50–62%).

9. **No formal optimality.** The current controller parameters are tuned heuristically. The MDP formulation outlined in the implementation roadmap could provide provably optimal switching thresholds, but this requires the scene parameter table from comprehensive system identification.

---

## 9. Conclusion

We have presented the analysis and deployment of a quantized feedback controller for real-time performance scheduling, demonstrating three findings of general applicability:

1. **PID degeneration is analyzable and harmless in quantized systems.** When the integral term saturates to become a directional bias and the derivative is attenuated to moderate damping, the resulting control law is a biased proportional controller. This degeneration does not impair performance because post-quantization, only the quantization interval matters, not the precise PID output value.

2. **Low-oscillation behavior is dominated by hysteresis and confirmation, not by PID fine tuning.** Multi-sample confirmation gives the nonlinearity memory and enforces dwell time (Section 2.5.1, Lemma 2), structurally limiting the maximum oscillation frequency to $\leq 0.2$ Hz (Section 6.4). The multi-evidence assurance chain in Section 6 combines surrogate margins with sensitivity analysis ($M_s \leq 1.62$ for plausible plant time constants), dwell-time frequency bounds, and battle-log attribution to establish low-oscillation safety (Definition 1) under a black-box plant.

3. **Non-uniform actuator gains are handled through emergent adaptation.** When the PID output naturally exceeds the quantization range of ineffective levels, the controller automatically bypasses them. This skip-level behavior requires no explicit gain scheduling—it arises from the interaction between continuous PID output and discrete quantization.

The system has been deployed in a game environment, achieving an estimated 50–62% mean frame rate improvement (37% at the 5th percentile) across two hardware configurations with 2.66 μs per-frame overhead (Section 7.2 caveat: the baseline is from a separate session, so these figures are approximate range estimates). The closed-loop system satisfies the low-oscillation safety criteria of Definition 1 ($f_{\text{sw}} = 0.072$ Hz, all reversals disturbance-driven).

These results point to a broader design principle: in coarse-actuator systems where quantization dominates, **confirmation-based hysteresis is the primary design lever for low-oscillation performance scheduling**, while fine PID tuning is of secondary importance. Future work should address four gaps: (i) interleaved open/closed-loop baseline protocols to eliminate load-drift confounds (Section 8.3, limitation 8); (ii) switched-system Lyapunov analysis to replace the conservative surrogate margins with formal hybrid stability certificates (limitation 4); (iii) ablation experiments to isolate individual component contributions (limitation 7); and (iv) MDP-based optimal switching threshold computation using comprehensive scene-parameterized system identification (limitation 9).

---

## References

[1] Epic Games, "Dynamic Resolution," Unreal Engine Documentation, n.d. [Online; accessed 2026-01].

[2] N. Elia and S. K. Mitter, "Stabilization of linear systems with limited information," *IEEE Trans. Automatic Control*, vol. 46, no. 9, pp. 1384–1400, 2001.

[3] D. F. Delchamps, "Stabilizing a linear system with quantized state feedback," *IEEE Trans. Automatic Control*, vol. 35, no. 8, pp. 916–924, 1990.

[4] R. W. Brockett and D. Liberzon, "Quantized feedback stabilization of linear systems," *IEEE Trans. Automatic Control*, vol. 45, no. 7, pp. 1279–1289, 2000.

[5] G. N. Nair, F. Fagnani, S. Zampieri, and R. J. Evans, "Feedback control under data rate constraints: An overview," *Proc. IEEE*, vol. 95, no. 1, pp. 108–137, 2007.

[6] Ya. Z. Tsypkin, *Relay Control Systems*, Cambridge University Press, 1984.

[7] P. Tabuada, "Event-triggered real-time scheduling of stabilizing control tasks," *IEEE Trans. Automatic Control*, vol. 52, no. 9, pp. 1680–1685, 2007.

[8] W. P. M. H. Heemels, K. H. Johansson, and P. Tabuada, "An introduction to event-triggered and self-triggered control," in *Proc. 51st IEEE CDC*, 2012, pp. 3270–3285.

[9] H. K. Khalil, *Nonlinear Systems*, 3rd ed., Prentice Hall, 2002, Ch. 7 (Circle and Popov criteria).

[10] K. J. Åström and R. M. Murray, *Feedback Systems: An Introduction for Scientists and Engineers*, Princeton University Press, 2008.

[11] G. F. Franklin, J. D. Powell, and A. Emami-Naeini, *Feedback Control of Dynamic Systems*, 8th ed., Pearson, 2019.

[12] D. Liberzon, *Switching in Systems and Control*, Birkhäuser, 2003.

[13] J. P. Hespanha and A. S. Morse, "Stability of switched systems with average dwell-time," in *Proc. 38th IEEE CDC*, 1999, pp. 2655–2660.

[14] R. K. Mehra, "On the identification of variances and adaptive Kalman filtering," *IEEE Trans. Automatic Control*, vol. 15, no. 2, pp. 175–184, 1970.

[15] Unity Technologies, "Adaptive Performance," Unity Documentation, n.d. [Online; accessed 2026-01].

[16] V. Pallipadi and A. Starikovskiy, "The ondemand governor: Past, present, and future," in *Proc. Linux Symposium*, vol. 2, 2006, pp. 223–238.

[17] K. Flautner, S. Reinhardt, and T. Mudge, "Automatic performance setting for dynamic voltage scaling," *Wireless Networks*, vol. 8, no. 5, pp. 507–520, 2002.

[18] X. Yin, A. Jindal, V. Sekar, and B. Sinopoli, "A control-theoretic approach for dynamic adaptive video streaming over HTTP," in *Proc. ACM SIGCOMM*, 2015, pp. 325–338.

[19] T.-Y. Huang, R. Johari, N. McKeown, M. Trunnell, and M. Watson, "A buffer-based approach to rate adaptation: Evidence from a large video streaming service," in *Proc. ACM SIGCOMM*, 2014, pp. 187–198.

---

## Appendix A: Notation Summary

| Symbol | Meaning |
|--------|---------|
| $r$ | Frame rate setpoint (26 FPS) |
| $y_k$, $\bar{y}_k$ | Measured interval-average FPS at sample $k$ |
| $\tilde{y}_k$ | Kalman observation ($\equiv \bar{y}_k$; distinct notation emphasizes noise model) |
| $\hat{y}_k$ | Kalman-filtered FPS estimate |
| $e_k$ | Error signal: $r - \hat{y}_k$ |
| $u^*_k$ | Continuous PID output |
| $u_k$ | Discrete performance level $\in \{0,1,2,3\}$ |
| $f_r$ | Nominal frame rate (30 Hz) |
| $N_k$ | Sampling window length (frames): $f_r(1+u_k)$ |
| $T_s$ | Sampling period (seconds): $N_k / f_r$ |
| $\Delta T_k$ | PID delta time (frame counts): $N_k$ |
| $K_L$ | Steady-state FPS at level $L$ |
| $\Delta\text{FPS}_L$ | Actuator gain at boundary $L$: $K_{L+1} - K_L$ (equivalent to $\Delta\text{FPS}_{L,L+1}$) |
| $\tau_L$ | Plant time constant at level $L$ |
| $a_L$ | Plant pole: $e^{-T_s/\tau_L}$ |
| $K_p, K_i, K_d$ | PID gains (0.25, 0.5, −30) |
| $M$ | Integral clamp limit (3) |
| $\alpha$ | Derivative filter coefficient (0.2) |
| $n_{\text{down}}, n_{\text{up}}$ | Hysteresis confirmation thresholds (2, 3) |
| $K_\infty$ | Steady-state Kalman gain |
| $Q, R$ | Kalman process/measurement noise covariances |
| $k_0$ | Worst-case open-loop DC gain: $K_p \cdot \Delta\text{FPS}_{\max}$ |
| $\theta$ | Lumped sensor delay in surrogate model |
| $S(j\omega)$ | Sensitivity function: $1/(1+L(j\omega))$ |
| $M_s$ | Sensitivity peak: $\max_\omega |S(j\omega)|$ |
| $f_{\text{sw}}$ | Mean switching frequency (Hz) |
| $\bar{f}_{\text{sw}}$ | Prescribed switching frequency bound (Definition 1) |
| $\bar{n}_{\text{rev}}$ | Prescribed reversal-count bound (Definition 1) |
| $T_{\text{rev}}$ | Reversal time horizon (seconds) |
| $\mathcal{U}_{\text{prim}}$ | Primary levels used for reversal counting ($\{0,2\}$) |
| $n_{\text{rev}}$ | Number of reversal events within $T_{\text{rev}}$ |
| $\Delta\text{FPS}_{ij}$ | Inter-level actuator gain: $\hat{K}_j - \hat{K}_i$ |

## Appendix B: Implementation Metrics

| Metric | Value |
|--------|-------|
| Source code | 7 classes, 1,735 lines (ActionScript 2) |
| Unit tests | 6 test modules (`./test/`), 27 test functions, 172 assertion checks (`out += line(...)` calls) |
| Hot path (per frame, no sample) | 2.66 μs |
| Hot path (sampling point) | 26.8 μs |
| Memory allocation at runtime | 0 (pre-allocated ring buffers; string allocation in `PerformanceLogger` and `FPSVisualization` excluded—disable these modules in production for zero-allocation guarantee) |
| Configuration | XML-loaded PID parameters ($K_p = 0.25$ at runtime; source comments note an earlier value of 0.2) |
| Logging overhead (when enabled) | 1 ring-buffer write per sample (~0.5 μs) |

## Appendix C: Reproducibility and Artifact Checklist

This appendix specifies the concrete artifacts needed to reproduce the figures and scalar metrics reported for **Machine B**.

### C.1 Artifact Locations

All paths below are relative to this `paper.md` (i.e., the `PerformanceOptimizer/` directory).

- **Raw logs (CSV):**
  - `./log/fs_开环阶跃响应.csv` (open-loop identification)
  - `./log/fs_堕落城保卫战测试.csv` (closed-loop battle test)
- **Reproduction script:** `./tools/generate_paper_figures.py`
- **Generated outputs (PNG + JSON):**
  - `./figures/fig_nyquist.png` (Fig. 2)
  - `./figures/fig_sensitivity_bode.png` (Fig. 3)
  - `./figures/fig_describing_function_intersection.png` (Fig. 4)
  - `./figures/fig_fps_timeseries.png` (Fig. 5)
  - `./figures/fig_pid_components.png` (Fig. 6)
  - `./figures/derived_metrics.json`

### C.2 How to Reproduce

The script is self-contained with respect to data dependencies and only requires a Python environment with `numpy` and `matplotlib` installed.

From this directory:

```bash
python ./tools/generate_paper_figures.py
```

The script overwrites the figure PNGs and regenerates `./figures/derived_metrics.json`.

### C.3 Log Schema and Metric Conventions

**CSV schema.** Each row has the columns:

`timeMs, evt, a, b, c, d, s`

where `evt` is an event type and the payload fields follow the logger schema in `PerformanceLogger` (`./PerformanceLogger.as`):

- `evt=1 (EVT_SAMPLE)`: `a=level`, `b=actualFPS`, `c=denoisedFPS`, `d=pidOutput`, `s=tag`
- `evt=2 (EVT_LEVEL_CHANGED)`: `a=oldLevel`, `b=newLevel`, `c=actualFPS`, `s=quality`
- `evt=3 (EVT_MANUAL_SET)`: `a=level`, `b=holdSec`
- `evt=4 (EVT_SCENE_CHANGED)`: `a=level`, `b=actualFPS`, `c=targetFPS`, `s=quality`
- `evt=5 (EVT_PID_DETAIL)`: `a=pTerm`, `b=iTerm`, `c=dTerm`, `d=pidOutput`

**Durations.** The closed-loop test duration $T$ in Section 7 is computed as $(t_{\max}-t_{\min})/1000$ over `EVT_SAMPLE` timestamps. Switch-interval statistics are computed from `EVT_LEVEL_CHANGED` timestamps.

**Statistics.** Unless otherwise stated, the script uses `numpy` conventions:

- Standard deviation uses the population definition (`ddof=0`).
- Percentiles (P5, P1, etc.) use `numpy.percentile` (linear interpolation for non-integer ranks).

**Time-weighted residence (Section 7.3).** Time by level is computed by summing inter-sample durations and attributing each duration to the *later* sample’s level. This convention is conservative with respect to post-switch load attribution in a hybrid (switched) system.

**Skip-level counting.** Skip-level events in Section 7 are computed by scanning `EVT_LEVEL_CHANGED` and counting rows with $|\Delta u|=|u_{\text{new}}-u_{\text{old}}|>1$.

**Reversal counting.** Reversal events (Table 6, Definition 1) are computed by scanning `EVT_LEVEL_CHANGED` for *departure* switches whose `oldLevel` lies in $\mathcal{U}_{\text{prim}}=\{0,2\}$. For each departure at time $t_i$, find the first subsequent switch that returns to the same level; if the elapsed time is $\leq T_{\text{rev}}=10$ s, count one reversal event with interval $(t_{\text{return}}-t_i)/1000$ seconds (possibly via intermediate levels). Each departure contributes at most one reversal (the earliest return), avoiding double-counting.
