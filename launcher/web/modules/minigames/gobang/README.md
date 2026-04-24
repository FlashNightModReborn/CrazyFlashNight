# Gobang · 铁枪会虚渊接入台

This directory is the active runtime source for the Gobang minigame, skinned as
the 铁枪会 intrusion interface for the 尸解仙 virtual-abyss (虚渊) isolation grid.

- Runtime root: `launcher/web/modules/minigames/gobang/`
- Shared shell + host bridge live in `launcher/web/modules/minigames/shared/`
- AI move evaluation is delegated to Launcher `GomokuTask` / Rapfi through the panel bridge.
- The Web core remains the authority for move legality and final game state.

## Narrative mapping

- **Black (role=1) = 铁枪会 anchor**: industrial silver-blue stone with amber core indicator, octagonal "weapon chassis" silhouette; represents an intrusion anchor deployed on a node of the 虚渊 isolation grid.
- **White (role=-1) = 尸解仙 defense meme**: deep violet orb with purple mist halo; represents the latent protective meme left behind by the 尸解仙 that re-forms the network topology to keep intruders out.
- **Board = 虚渊 isolation grid**: breathing θ-field, corner anchor reticles, star-point nodes glow cyan.
- **Last-move reticle**: orange-red crosshair with cross-ticks, echoing the 铁枪 weapon sight.
- **Win highlight**: emerald energy halo, echoing the green power-core on the 铁枪 emblem.
- **铁枪会 emblem**: diamond frame + central crosshair + crossed barrels + electric-blue arcs (inline SVG in header).

Thematic vocabulary (see `docs/worldbuilding/07-祛魅补丁与支线储备.md`):

| UI 位 | 原称 | 主题称 |
|-------|------|--------|
| 规则 | casual / renju | 协议 · 侦查 / 绞杀 |
| 难度 | fast / normal / hard / master | 烈度 · 速击 / 标准 / 深渗 / 铁枪 |
| 执棋 | 黑 / 白 | 阵营 · 铁枪 / 尸解仙 |
| 新局 | — | 启动遗线 |
| 悔棋 | — | 信号回溯 |
| 重试 AI | — | 重载引擎 |
| 导出 | — | 作战日志 |
| 引擎区块 | — | 黑铁剑引擎 · Rapfi |
| 坐标 | A1 | CH-A · 001 |

## Module layout

- Deterministic gameplay core and rules in `core/index.js`
- Browser panel shell + thematic skin in `gobang-panel.js`
- Runtime-specific visuals in `gobang.css`
- Standalone browser harness in `dev/harness.html`
- Pure logic QA suite in `dev/qa-suite.js`

## Rulesets

- `casual` (侦查)：no forbidden moves; five or more in a row wins.
- `renju` (绞杀)：black overline, double-three, and double-four are forbidden; white five or more wins.

## QA

```powershell
node launcher/tools/run-minigame-qa.js --game gobang
```
