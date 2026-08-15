# PanelTooltip interaction harness

This harness loads the production `panels.css` and `tooltip.js` in Chromium. It uses
Playwright's physical mouse, wheel, and keyboard APIs to verify the three tooltip host
profiles and dense-grid ownership transitions.

Run from the repository root:

```powershell
node launcher/perf/tooltip-interaction/runner.js
```

Coverage includes the default 1-second inspection threshold, delayed basic-to-rich
content, horizontal/vertical/diagonal tile sweeps at two speeds, immediate owner
preemption, fast in-owner motion resetting the dwell, wheel boundary ownership,
keyboard access, pinned inspector dismissal, scope disposal, and the inspection status
remaining a tinted in-flow strip above the annotation instead of covering it, plus an
inspect-entry expansion and persistent outline on the triggering tile. It also checks
the computed 6px pending/inspect dense scrollbar, the interactive 7px pinned scrollbar,
and suppression of native arrow buttons and the 15px system gutter. The
fixture uses production DOM/CSS; it does not mock `PanelTooltip`.
