# Tooltip Regression — 历史 Web vs AS2 像素 diff harness

本目录保留迁移期 `TooltipGroundTruthDump` 的像素差校准工具：把旧 AS2 几何真值喂进 Playwright + Chromium，在真实 `launcher/web/css/panels.css` 中复刻 tooltip DOM，并比较 `offsetHeight/offsetWidth`。它只回答“Web 与旧 Flash 几何差多少”，不是当前文本容量、密集命中或检视状态的权威门。

当前验证入口分工：

- `scripts/run-tooltip-corpus-audit.ps1` + `tools/parse-tooltip-corpus.js`：事务化采集正式 AS2 composer 的完整输入语料；
- `launcher/perf/tooltip-audit/runner.js`：全语料、真实 CSS/JS、三视口/两密度/四后缀的排版与 hit-test；
- `launcher/perf/tooltip-interaction/runner.js`：真实鼠标、滚轮和键盘的三 profile 状态机；
- 本目录 runner：只有确实需要回看旧 Flash 像素偏差时才运行。

## 真值文件（dev-only，不进 git）

`tooltip-truth.json` ≈ 1.5MB，是 AS2 端 dump 的 860 物品 × 9 mouseY 采样产物，
属于"web 跟 AS2 对齐"迁移期的中间产物——长期权威翻转到 web 后会退役。
所以放在 perf/ 目录、不进 runtime 包、`.gitignore` 排除。

`tooltip-truth.json` 不在仓库时，本历史 runner 不具备可复验输入，应跳过并运行上方现役门；不要为日常验证手工改写 `scripts/TestLoader.as`。若未来必须重采精确 AS2 几何真值，应先增加与 `run-tooltip-corpus-audit.ps1` 同级的 scratch transaction、随机 runId 与异步闭包校验，再使用新鲜真值，不能恢复下方已退役的手工切入口流程。

## 一次跑通

```bash
cd launcher/perf
node tooltip-regression/runner.js                  # 全量 860 物品，baseline CSS
node tooltip-regression/runner.js --limit 30       # 快速冒烟
node tooltip-regression/runner.js --lh 1.25        # 临时 line-height override
node tooltip-regression/runner.js --sweep-lh 1.0,1.15,1.25,1.4   # 多候选对比
```

报告落到 `tooltip-regression/reports/<timestamp>/`：
- `report.md`：分位统计 + 直方图 + worst-case top10（单次）
- `sweep.md`：line-height 候选对比表（sweep 模式）
- `raw.json` / `sweep.json`：机读

## diff 字段语义

| 字段 | 含义 | 正值=web 大于 AS2 |
|------|------|------|
| `introBgH_diff` | introPanel.offsetHeight − AS2 introBgH | |
| `mainBgH_diff` | descPanel.offsetHeight − AS2 mainBgH（自然态） | |
| `introTH_diff` | .flash-tt-intro.offsetHeight − AS2 Flash TextField textHeight | 字号/行高纯偏差 |
| `introW_diff` | introPanel.offsetWidth − AS2 introW | icon 占位等 |
| `mainW_diff` | descPanel.offsetWidth − AS2 mainW | desc shrink-to-fit 缺失 |

## 已落地的调优

**2026-05-16 — line-height 1.6 → 1.25**：
通过 `--sweep-lh 1.0,1.1,1.15,1.2,1.25,1.3,1.4,1.5` 跑全量 860 物品，
`introTH_diff p50` 单调收敛到 lh=1.25 时为 0（mean=-0.12），改前 +42。
落到 `panels.css` 的 `--tt-intro-line-height` / `--tt-desc-line-height`。

**2026-05-16 — Port AS2 estimateMainWidth 到 tooltip.js**：
desc 在 web 端原本 max-width=650 永远横铺，`mainW_diff p50=+381`。
通过 `--sweep-ppu 5,5.5,6,6.5,7,7.5,8,9` 跑全量得最优均衡点：AS2 默认 ppu=6.0 让
`mainW_diff p50=+9`、`mainBgH_diff p50=+42`（box-model 12 + 字号渲染差累计）。
port `htmlScoresBoth` + `estimateMainWidth` 到 `tooltip.js`，在 `showAtMouse` 时给 desc
写 `style.width = estimateMainWidth(scores)`。

最终全量 diff（vs 改前）：

| metric | 改前 p50 | 改后 p50 | 备注 |
|--------|----------|----------|------|
| `introTH_diff` | +42 | 0 | line-height 1.25 完美对齐 |
| `introBgH_diff` | +44 | +2 | 96% 改善 |
| `mainW_diff` | +381 | +9 | 98% 改善 |
| `mainBgH_diff` | -78 | +42 | desc 不再横铺；剩余偏差 = padding/font 系统差 |
| `introW_diff` | +79 | +79 | 未动（icon flex 占位） |

**2026-05-16 — XFL 资产真值复刻 + introBg 锁宽 BASE_NUM=200**：
读 `flashswf/UI/注释框/LIBRARY/sprite/Symbol 274.xml` 发现 AS2 端 introBg/mainBg 实际是
垂直金属渐变 (#999→#333) + alpha 0.8、无 border、无 shadow、文字默认色 #FFFFFF、
icon overlay 混合。读 `TooltipComposer.renderItemIcon` R2 注释发现 `measuredIntroW = BASE_NUM`
强制锁死宽度，不走 estimateWidth。web 端原本 `max-width:300 + align-items:stretch` 导致
icon container 在过宽 panel 内居中 → 用户实测发现 icon 左右各 ~40px 空洞。
修复：`width: 200px` 锁死 + panel padding 24→4 对齐 AS2 端无 padding + Flash TextField gutter。

| metric | 锁宽前 p50 | 锁宽后 p50 | 备注 |
|--------|-----------|-----------|------|
| `introBgH_diff` | +4 | **-3** | -border + 锁宽 + padding 全套 |
| `mainBgH_diff` | +44 | **-2** | padding 24→8 后系统偏差消失 |
| `introW_diff` | +78 | **+58** | dump bug 显形，见下 |

## 已知未修偏差

- **`introW_diff` p50=+58** —— 是 **dump 自身的字段计算 bug**，不是 web 端宽。
  旧 dump 用 `estimateWidth(introText, MIN_W=150, INTRO_MAX_W=300)` 算出来的范围
  [150, 300] 漂移；但 AS2 runtime 实际走 `TooltipComposer.renderItemIcon` 的
  `measuredIntroW = BASE_NUM = 200` 锁宽分支，跟 estimateWidth 没关系。
  已在 `TooltipGroundTruthDump.as:182` 修复：`var introW:Number = TooltipConstants.BASE_NUM;`。
  **下次重采 truth.json 后该 diff 应收敛到 ~0**（web 200 vs dump 200）。

## 真值重采状态

旧手工重采步骤已退役。原行协议仍可在 `scripts/类定义/org/flashNight/gesh/tooltip/test/TooltipGroundTruthDump.as` 顶部查阅，但在事务化 runner 落地前不得把手工切换 TestLoader 得到的文件当正式证据。
