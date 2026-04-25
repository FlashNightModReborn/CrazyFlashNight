# CF7:ME Web overlay 性能测试 harness

量化测量 launcher/web overlay 各项 CSS/JS 特性对 iGPU 合成成本的实际影响。
WebView2 ≡ Chromium，Playwright headless 跑出的相对排名能直接外推到真机。

## 一次跑通

```bash
cd launcher/perf
npm install                # 装 playwright + 下载浏览器
node harness.js --mode all
```

输出落在 `reports/<timestamp>/`：

- `meta.json`：本次跑的参数与 scenario/ablation 清单
- `partial.json`：**每个 ablation 完成后立即写入**，崩溃可恢复（见下）
- `summary.json` / `summary.md` / `visual-diff.html`：run 结束时统一写
- `screenshots/` / `videos/`：截图与 webm 视频

## 中断恢复

死机或 Ctrl+C 中断后，已完成 ablation 的数据存在 `partial.json` 里。运行：

```bash
node recover.js                        # 自动找最新含 partial.json 的目录
node recover.js reports/2026-04-25T...  # 或指定具体目录
```

会从 partial.json 重新生成 summary.json / summary.md / visual-diff.html。

如果连 partial.json 都没（旧 run 在增量持久化补丁前），可用日志抢救：

```bash
python launcher/perf/tools/salvage-from-log.py /path/to/run.log reports/<dir>
node recover.js reports/<dir>
```

## 目录结构

```
launcher/perf/
├── harness.js          # CLI 入口
├── lib/
│   ├── server.js       # 静态文件 server（替代 overlay.local 虚拟主机）
│   ├── runner.js       # 单次试验执行（场景 setup + ablation 注入 + 量测）
│   ├── metrics.js      # CDP Performance.getMetrics + 页内 rAF 帧时间
│   └── report.js       # JSON / Markdown / HTML 报表生成
├── scenarios/          # 测试场景：定义"测什么状态"
│   ├── idle.js         # 非 panel 态 HUD
│   ├── panel-map.js    # map 面板打开
│   └── panel-lockbox.js
├── ablations/          # 实验变量：定义"改什么"
│   ├── baseline.js     # 不改（必须存在，作参照）
│   ├── backdrop-filter-off.js
│   ├── mix-blend-off.js
│   ├── filter-off.js
│   ├── box-shadow-off.js
│   ├── animations-off.js
│   ├── will-change-off.js
│   ├── perf-low-effects.js
│   └── nuclear.js      # 全关，上界对照
└── reports/            # gitignore，每次跑生成新 timestamp 子目录
```

## 加新场景

`scenarios/<name>.js`：

```js
module.exports = {
    name: 'panel-gobang',
    description: '五子棋面板：棋盘呼吸 + sweep 光束',
    async setup(page) {
        // page 是 Playwright Page，可以 evaluate / mouse 操作
        await page.evaluate(() => Panels.open && Panels.open('gobang'));
    },
};
```

## 加新 ablation

`ablations/<name>.js`，三种粒度按需选用：

```js
module.exports = {
    name: 'mapStageScan-only',
    description: '只停 map-stage-scanline 动画',

    // 一级：CSS stylesheet 注入。最快、最广，但 `*` 选择器会引入 cascade 副作用
    css: `.map-stage-scanline { animation: none !important; }`,

    // 二级：靶向 inline style。先 getComputedStyle 找出实际使用该属性的元素，
    // 只对它们注入 inline。避开 cascade 副作用，且能输出归因清单。
    targetedJs: `(() => {
        document.querySelectorAll('*').forEach(el => {
            if (getComputedStyle(el).backdropFilter !== 'none') el.style.backdropFilter = 'none';
        });
    })();`,

    // 三级：任意 JS（如激活降级类）
    // js: `document.documentElement.classList.add('perf-low-effects');`,
};
```

**两级体系**：先用 `css` 全局注入做雷达扫描，发现异常信号后用 `targetedJs` 精确归因。
当前已有的 `*-targeted` 系列（`backdrop-filter-targeted` / `mix-blend-targeted` / `filter-targeted` /
`will-change-targeted`）就是这个模式。新增的文件被 harness.js 自动发现，无需注册。

## 常用命令

```bash
node harness.js --mode all                              # 全跑（5 重复 + 2000ms warmup + dry-run，全套保护）
node harness.js --mode all --quick                      # 快速版（1 重复，仅冒烟，慎据此决策）
node harness.js --mode all --scenario panel-map         # 只跑某场景
node harness.js --mode all --ablation mix-blend-targeted   # 只对比某 ablation
node harness.js --mode all --repeats 10 --sample 5000   # 高置信测量（重决策前）
node harness.js --no-videos                             # 跳过视频生成（更快）
node harness.js --mode watch --scenario idle            # 浏览器可见 + 调试
```

## 方法论保护（默认开启）

依 Kimi peer review 建议（[docs/web-overlay-perf-harness-methodology-review-2026-04-25.md](../../docs/web-overlay-perf-harness-methodology-review-2026-04-25.md)）：

1. **5 次重复取中位数**（`--repeats 5`）。单次采样 CV 通常 5-15%，单点测不到 -15% 真实收益与噪声的差。
2. **Dry-run 预热**（`--no-dry-run` 关闭）。每个 ablation 先跑一次丢弃，预热 V8 JIT / 字体 / 图片解码。
3. **2000ms warmup + 600ms settle**（`--warmup` / `--settle` 调整）。让 layer tree、合成器稳定。
4. **Ablation 顺序随机化**：每个场景内 ablation 序列在 baseline 之外随机，抵消串行污染。
5. **CV 标注**：报告里每个 ablation 标注变异系数；标 ✓✓ 表示 |Δ| > 2×CV 强信号，✓ 表示 > CV 弱信号，无标 = 噪声。

## 度量含义与可信度

**主指标 `cpuPerSec`**（每秒主线程 CPU 时间，单位秒/秒）：
- `> 1.0` 表示主线程超过 100% 占用（多核被 chromium 内部线程池消耗）
- 越低越省。**这个数字 headless / 真机都可信**
- 来源：CDP `Performance.getMetrics` 的 `TaskDuration` 累计差量除以采样窗口

**辅助指标**：
- `script/s`：`ScriptDuration / sample`，纯 JS 执行时间
- `recalc/s` `recalcDur/s`：style recalc 频率与累计时间
- `layouts/s` `layoutDur/s`：layout 频率与累计时间
- `longTasks`：> 50ms 的 main-thread task 数（卡顿指标）
- `rafFps` / `rafMeanMs`：rAF 间隔（**仅作参考，见下文限制**）

## 关键限制：headless 测不到 GPU 成本

**这是一条硬约束**：headless Chromium 在没有挂载显示器/合成目标时，compositor 不产生帧。
所以 backdrop-filter / mix-blend-mode / filter:blur 等 **GPU 端成本在 headless 下全部为 0**。

实测案例（本仓库 4 月 25 日基线）：
- `panel-lockbox` 场景：mix-blend-off 让主线程 cpu/s -26%，box-shadow-off -21%，backdrop-filter-off -15%（CPU 端可测）
- `panel-map` 场景：所有 GPU-only ablation 的 cpu/s 改动 < 2%（说明该场景 CPU 不是瓶颈，GPU 才是）

**结论**：panel-map / 全屏毛玻璃这类 GPU 主导场景，**必须用真 WebView2 模式**（见下文）才能拿到信号。

## 真 WebView2 模式（GPU 端 ground-truth）

启动器加 `webView2AdditionalArgs = "--remote-debugging-port=9222"` 到 `config.toml`，重启游戏到 Ready，然后：

```bash
# 你手动打开要测的 panel（map / lockbox / etc.）后运行：
node harness-webview2.js --scenario panel-map --sample 5000
```

会 attach 到游戏中真实的 WebView2 实例，跑全部 ablation，结果落在 `reports-webview2/<timestamp>/`。

每次 ablation 切换会临时注入/移除 `<style id="__cf7_ablation_style">`，离开恢复原状，不会污染游戏运行态。

## 其他已知限制

1. **headless GPU 与真 iGPU 不等价**：即使 headless 能产出帧，硬件路径也与 WebView2 不一致；与玩家机器（不同 GPU）有更大差异。**相对排名可信，绝对百分比要打折**
2. **DWM 合成不可测**：launcher 的 layered window + Flash 底层 alpha blend 既 headless 也 connectOverCDP 都看不到。这一项配合 launcher 内 Ctrl+G 探针单独测（见 `WebOverlayForm.ToggleCompositionProbe`）
3. **Bridge 依赖**：headless 没有 `window.chrome.webview`。模块代码已 guard，但依赖 C# 推送数据的 panel 可能呈现空状态。场景里可手工注入 mock
4. **Ablation 不可线性叠加**：单独测 A 省 20% + 单独测 B 省 15% **不等于** A+B 省 35%。要做组合，新增 ablation 同时关 A+B
