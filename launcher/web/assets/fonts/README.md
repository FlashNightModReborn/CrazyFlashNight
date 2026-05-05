# 情报 H5 Webfont 资源

本目录下的字体被 `launcher/web/css/panels.css` 顶部的 `@font-face` 引用，用于情报系统多 skin 表达力。文件**缺失也不会破坏渲染**——CSS 已配置 `font-display: swap` 与系统字体回退链。

字体清单的权威源是 [`font-pack-manifest.json`](font-pack-manifest.json)（FontPackTask 按需下载到 `%LOCALAPPDATA%/CF7FlashNight/fonts/`，cfn-fonts.local 虚拟主机优先映射该目录）。本 README 是人类可读说明，新增/修改字体时**两处都要改**。

## 字体矩阵

| 文件名 | 字体 | 角色 | 大小 | License | Group |
|---|---|---|---|---|---|
| `jetbrains-mono.woff2` | JetBrains Mono Regular | terminal skin / mask=mojibake 字形 / `--intel-font-mono` | 92 KB | Apache 2.0 | `essential`（shipped） |
| `lxgw-wenkai-screen.ttf` | 霞鹜文楷 Screen v1.522 | dossier 朱印 / field-notes 批注 / diary 全文 / mask=garble & symbol 罕用 CJK / `--intel-font-body` | 24.5 MB | SIL OFL 1.1 | `expressive` |
| `maoken-yingbi-kaishu.ttf` | 猫啃硬笔楷书 v0.20 | 中文 note 主选 / diary 全文 / 私人手记 / `--intel-font-note` 主选 | 6.1 MB | SIL OFL 1.1 | `expressive-handwriting` |
| `klee-one-regular.ttf` | Klee One Regular | 日文场景备用——简中字符覆盖不全（per-char fallback 漏字），已从 `--intel-font-note` 链移除 | 8.3 MB | SIL OFL 1.1 | `expressive-handwriting` |
| `ma-shan-zheng-regular.ttf` | Ma Shan Zheng Regular | 标题手写 / 戏剧性大字 / `--intel-font-title` 主选 | 5.6 MB | SIL OFL 1.1 | `expressive-handwriting` |
| `zhi-mang-xing-regular.ttf` | Zhi Mang Xing Regular | 标题随性手写 / `--intel-font-title` fallback | 3.9 MB | SIL OFL 1.1 | `expressive-handwriting` |
| `liu-jian-mao-cao-regular.ttf` | Liu Jian Mao Cao Regular | 失控短句 / outburst 戏剧草书 / `--intel-font-outburst` | 4.7 MB | SIL OFL 1.1 | `expressive-handwriting` |
| `jason-handwriting-7.ttf` | 清松手写体 7 号 飘逸 | 哀痛情绪 / outburst lament tone / 临终遗言 / `--intel-font-emotional` | 8.8 MB | SIL OFL 1.1 | `expressive-handwriting` |
| `jason-handwriting-1.ttf` | 清松手写体 1 号 圆体 | NPC 笔迹差异化 / handwritten voice="neat" / Shop Girl 类商务文员 / `--intel-font-character-neat` | 8.5 MB | SIL OFL 1.1 | `expressive-handwriting` |
| `jason-handwriting-8.ttf` | 清松手写体 8 号 Casual | NPC 笔迹差异化 / handwritten voice="rough" / 老周/盗贼/雇佣兵 / `--intel-font-character-rough` | 7.7 MB | SIL OFL 1.1 | `expressive-handwriting` |
| `jason-handwriting-2.ttf` | 清松手写体 2 号 不规则 | NPC 笔迹差异化 / handwritten voice="plain" / 浑浑噩噩小市民 / `--intel-font-character-plain` | 5.1 MB | SIL OFL 1.1 | `expressive-handwriting` |
| `jason-handwriting-9.ttf` | 清松手写体 9 号 | NPC 笔迹差异化 / handwritten voice="weary" / 流民/逃难者疲惫笔迹 / `--intel-font-character-weary` | 8.0 MB | SIL OFL 1.1 | `expressive-handwriting` |
| `source-han-serif-cn-regular.otf` | Source Han Serif CN Regular（思源宋体） | dossier / 官方资料集 / 中立编纂 / `--intel-font-archive` | 11.1 MB | SIL OFL 1.1 | `expressive-archive` |

**Group 总量**：essential 92 KB（shipped）+ expressive 24.5 MB + expressive-handwriting 53.6 MB（猫啃 6.1 + 清松1 8.5 + 清松7 8.8 + 清松8 7.7 + 4 旧字 22.5）+ expressive-archive 11.1 MB ≈ **89 MB 全矩阵**

## CSS 角色绑定

`panels.css` 顶部声明了一组字体角色变量，使用方在 .intel-* 选择器里 `font-family: var(--intel-font-X)` 引用即可。变量内置完整 fallback 链，未安装时自动落回系统字体（STKaiti / SimSun / Consolas）。

```css
--intel-font-body:     'LXGW WenKai Screen', 'LXGW WenKai', 'STKaiti', '楷体', 'KaiTi', serif;
--intel-font-title:    'Ma Shan Zheng', 'Zhi Mang Xing', 'STKaiti', '楷体', 'KaiTi', serif;
--intel-font-note:     'MaokenYingBiKaiShuJ', 'LXGW WenKai Screen', 'STKaiti', '楷体', 'KaiTi', serif;
--intel-font-outburst: 'Liu Jian Mao Cao', 'Ma Shan Zheng', 'STKaiti', '楷体', 'KaiTi', serif;
--intel-font-emotional:'JasonHandwriting7', 'MaokenYingBiKaiShuJ', 'LXGW WenKai Screen', 'STKaiti', '楷体', serif;
--intel-font-archive:  'Source Han Serif CN', 'Source Han Serif SC', 'Noto Serif CJK SC', 'SimSun', '宋体', serif;
--intel-font-character-neat:  'JasonHandwriting1', 'MaokenYingBiKaiShuJ', 'LXGW WenKai Screen', 'STKaiti', '楷体', serif;
--intel-font-character-rough: 'JasonHandwriting8', 'MaokenYingBiKaiShuJ', 'LXGW WenKai Screen', 'STKaiti', '楷体', serif;
--intel-font-character-plain: 'JasonHandwriting2', 'MaokenYingBiKaiShuJ', 'LXGW WenKai Screen', 'STKaiti', '楷体', serif;
--intel-font-character-weary: 'JasonHandwriting9', 'MaokenYingBiKaiShuJ', 'LXGW WenKai Screen', 'STKaiti', '楷体', serif;
--intel-font-mono:     'JetBrains Mono', Consolas, 'Courier New', monospace;
```

绑定到具体 skin / block 的工作（"字体角色绑定"）单列任务，本次只完成**矩阵储备**：manifest 注册 + @font-face 声明 + 变量声明。

### 三档差异化人设手写体（2026-05-05 落地）

JSON 顶层 `writerVoice` 字段让一篇 diary/field-notes 整篇走特定 NPC 字迹（不再是 PC 默认）：

| writerVoice | 字体 | 人设 | 实例 |
|---|---|---|---|
| (未指定) | 猫啃硬笔楷书 | PC 默认 / 训练有素硬笔楷书 | （未来通用 PC 视角篇） |
| `plain` | 清松2 不规则 | 浑浑噩噩小市民 / 朴拙未受训 | `商业区感染日记` |
| `neat` | 清松1 圆体 | 文职首领 / Shop Girl / 商务文员 | `符线溯源笔记` |
| `rough` | 清松8 Casual | 佣兵 / 老周 / 盗贼 | `贫民窟探查笔记` |
| `weary` | 清松9 | 流民 / 逃难者 / 疲惫涣散 | `环线流民日记` |

`note tone` 是 `writerVoice` 的显式例外：

| tone | 字体 | 语义 |
|---|---|---|
| (未指定) | 跟随写作者的笔 | 个人批注 |
| `archive` | 思源宋体 | 制度铅字 — 组织文档批注（声明/备注/评估/理由） |
| `stagecraft` | LXGW italic 小字 | 舞台说明 — `（纸张参差不齐沾着灰烬）`这种观察者代笔旁注 |

## 玩家入口

1. **Welcome 页字体扩展条**（100% 经过的入口）：检测 missing groups → "立即安装" 进度条 + 取消按钮 → 6h × 抑制
2. **情报面板内 banner**（兜底冗余）：跳过 welcome 直接 deeplink 进游戏的极端路径

两入口共享 `cfn_font_pack_banner_suppressed_until` localStorage key。

## 创作期 vs 打包阶段

**创作期**：所有字体走全字符 ttf/otf，FontPackTask 按需下载到 AppData。理由：
- mask=garble 字符池含罕用 CJK（蹇鼯驎黧 等），子集化到 GB2312 会裁掉
- 创作期会随时引入新字，重复跑子集化太脆弱
- 用户网络一次下完终身受益

**打包阶段（发行版优化）**：按实际用字裁剪到 woff2，体积可压到 ~1.5 MB / 字体：
```
node tools/collect-h5-charset.js > release.charset.txt
pyftsubset launcher/web/assets/fonts/lxgw-wenkai-screen.ttf \
    --unicodes-file=release.charset.txt \
    --flavor=woff2 \
    --output-file=launcher/web/assets/fonts/lxgw-wenkai-screen.woff2
```

`tools/collect-h5-charset.js` 待后续编写——遍历 data/intelligence_h5/*.json + components.js 的 MASK_POOLS 收集所有出现过的 codepoint。

## 字体 fallback 链（缺失时仍可用）

- 楷体路径：`'LXGW WenKai Screen' → 'LXGW WenKai' → 'STKaiti' → '楷体' → 'KaiTi' → 'serif'`
- 等宽路径：`'JetBrains Mono' → Consolas → 'Courier New' → monospace'`
- 衬线路径：`'Source Han Serif CN' → 'Noto Serif CJK SC' → 'SimSun' → '宋体' → 'serif'`
- 标题手写：`'Ma Shan Zheng' → 'Zhi Mang Xing' → 'STKaiti' → ...`
- 批注手写：`'Klee One' → 'LXGW WenKai Screen' → 'STKaiti' → ...`
- 戏剧草书：`'Liu Jian Mao Cao' → 'Ma Shan Zheng' → 'STKaiti' → ...`

## 何时该考虑把字体打包进发行版

- 字体文件总和 < 6MB ≈ 一首 mp3 大小，可接受 → 当前 essential 92 KB 已 shipped
- 玩家无网络时打开游戏，系统字体回退视觉退化明显但不破图
- 若装机率覆盖率成问题，再考虑随发行版打包 expressive base（LXGW Screen 子集化版）

## 添加新字体

1. 下载字体到本地，`sha256sum` 计算 SHA256（小写）+ 记录 byte 大小
2. `font-pack-manifest.json` 加 group/file 条目（urls 多镜像优先）
3. `panels.css` 加 `@font-face`（src 走 `https://cfn-fonts.local/<name>`）
4. 必要时新增 `--intel-font-<role>` 变量并补 fallback 链
5. 更新本 README 表格 + fallback 链段落
