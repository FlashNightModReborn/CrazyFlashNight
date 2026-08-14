# 音频资源与 BGM 系统使用说明

**文档角色**：`sounds/` 音频目录、格式能力、发现规则与点歌器资源状态的 canonical 说明。精确 wire、generation、qualification 与发布 Gate 见 [Audio Platform v2 ADR](../docs/原生音频平台-v2-格式能力桥接契约与可观测性-ADR-2026-08-09.md)。

> **状态边界**：下文的 Audio Platform v2 能力描述的是当前目标与源码候选实现，不代表 Launcher 二进制已部署、H2 已通过、真实端点已有非零信号，也不代表人类已经听到或接受音频。

## Audio Platform v2 格式能力

| 音频内容 | 当前解码路径 | 常用发现扩展名 |
|----------|--------------|----------------|
| RIFF/WAVE PCM 或 IEEE Float | built-in | `.wav` |
| MPEG Audio Layer III | built-in | `.mp3` |
| 原生 FLAC | built-in | `.flac` |
| Ogg Vorbis | libvorbis | `.ogg` |
| Ogg Opus | libopus | `.opus` |
| AAC-LC / HE-AAC（ISO BMFF） | Media Foundation | `.m4a`、`.mp4` |
| AAC-LC / HE-AAC（ADTS） | Media Foundation | `.aac`、`.adts` |

`.wav`、`.mp3`、`.flac`、`.ogg`、`.m4a`、`.mp4`、`.aac`、`.adts`、`.opus` 只是目录发现提示，不是格式支持证明。WMA 不在当前能力合同内，不承诺因 Windows 安装了系统 codec 就能播放。

候选曲目按以下顺序 fail-closed 判定：

1. 从文件头 content sniff 出真实 container/codec/decoder，不盲信扩展名。
2. 将检测结果与当前 native capability digest 绑定；能力未知或不匹配时不标记可播。
3. 对稳定输入执行有时间、输入字节数与解码帧数上限的 runtime compatibility probe。
4. 将结果投影为 `available`、`probing` 或 `unavailable`，并附结构化 `reason`。

bounded probe 不是 decode-to-EOF、真实设备输出或人类听感证明。扩展名与内容不一致时，只有 content sniff、capability 和 probe 都成立才可成为 `available`。本轮已将 11 个“内容为 AAC/ISO BMFF、原名却是 `.wav`”的 BGM 规范为 `.m4a`，并同步其 `bgm_list.xml` URL；这项规范化本身不构成可听或发布证据。

## 文件发现与目录边界

### BGM

- 手动曲目由 `sounds/bgm_list.xml` 注册；XML 记录即使指向缺失文件也会保留为 `unavailable / missing`，不会伪装成可播放。
- 自动发现只扫描 `sounds/` 下一级“专辑目录”中的直接文件，例如 `sounds/TFR/track.mp3`；不递归发现更深层文件，并跳过 `sounds/export/`。
- 仓库顶层 `music/` 不属于当前 BGM 自动发现根。需要运行时使用的曲目应放入 `sounds/<专辑>/` 并随包交付，或在 XML 中使用可解析的 `sounds/...` 路径注册。
- `sounds/` 与 `bgm_list.xml` 由 watcher 监听，变更经约 0.5 秒 debounce 后重新扫描和 probe；热更新不会放宽上述目录与格式规则。

### SFX

- SFX preload 按固定顺序扫描 `sounds/export/武器/`、`sounds/export/特效/`、`sounds/export/人物/` 的直接文件。
- 文件名（含扩展名）就是 `linkageId`，AS2、XML 与装备脚本可能直接引用它。不得为“统一格式”批量改名；单项改名必须同时迁移全部引用并重新生成资产 inventory。

## 添加自定义音乐

1. 在 `sounds/` 目录下创建一级文件夹，文件夹名即“专辑名”。
2. 将符合上表内容与扩展提示的音乐文件直接放入该文件夹，不要再嵌套子目录。
3. 运行时会在 debounce 和 bounded probe 完成后更新目录；只有 `available` 曲目可以播放。

示例：

```
sounds/
  我的歌单/
    好听的歌.mp3
    另一首歌.wav
```

目录会识别为专辑“我的歌单”；曲目是否可选仍由 content sniff、capability 与 probe 结果决定。

## 点歌器资源状态

| `availability` | 界面语义 |
|----------------|----------|
| `available` | 可点击，并允许向音频桥转发；`reason` 可说明扩展名不匹配或信号未知等兼容状态。 |
| `probing` | 暂时禁用并显示原因，例如输入仍在变化或 bounded probe 超时；不得当作“先试着播放”。 |
| `unavailable` | 禁用并显示原因；`missing`、`unsupported_container`、`unsupported_codec`、`malformed`、`truncated`、I/O 或 ABI/capability 错误都属于该状态。 |

旧 catalog 若缺少 `availability`，点歌器消费端必须按 `unavailable` 处理；DOM 状态或伪造点击不能绕过发送前的 catalog 二次校验。

## 点歌器操作

点歌器位于游戏右上角工具栏下方，点击"点歌"按钮展开。

### 界面布局

- **标题栏**：显示当前曲目名（超长名会自动滚动）和播放时间
- **波形图**：实时音频可视化
- **进度条**：可拖拽跳转到指定位置
- **专辑下拉**：筛选显示某个专辑的曲目，或选择"全部"
- **曲目列表**：点击曲目名即可播放，当前曲目高亮

### 控制按钮

| 按钮 | 说明 |
|------|------|
| ‖ | 暂停/继续当前播放 |
| ■ | 停止点歌器，恢复场景默认 BGM |
| ? | 打开帮助（即本文档） |

设置面板内嵌在展开界面左栏（音量/开关/播放模式/磷光主题），随面板直接可见。

### 键盘操作

| 按键 | 说明 |
|------|------|
| Tab / Shift+Tab | 在控件之间移动焦点 |
| ↑ / ↓ | 曲目列表中移动选择 |
| ← / → | 进度条快退/快进 5 秒；音量滑条减/加 5 |
| Home / End | 进度或音量跳到两端 |
| Enter / Space | 播放选中曲目、切换设置、触发按钮 |
| Esc | 逐层关闭：帮助弹窗 → 专辑下拉 → 面板 |

## 设置选项

### 音量

| 滑条 | 说明 |
|------|------|
| 全局 | 控制所有声音的主音量（0-100） |
| 音乐 | 控制 BGM 音量（0-100），不影响音效 |

### 开关

| 设置 | 说明 |
|------|------|
| 覆盖关卡BGM | 启用后，进入战斗关卡时点歌器不会被关卡音乐打断 |
| 真随机 | 启用后，专辑随机播放不保证前后两首不重复；关闭时保证相邻两首不同 |

### 播放模式

| 模式 | 说明 |
|------|------|
| 单曲循环 | 当前曲目无限循环（默认） |
| 专辑循环 | 播完当前曲后，自动从同专辑随机选下一首继续播放 |
| 播完回默认 | 播完一首后，恢复场景默认 BGM |

所有设置（含音量）会随存档保存，下次加载自动恢复。

## BGM 优先级

默认优先级（从高到低）：
1. **关卡 BGM**：战斗关卡中由关卡脚本指定的音乐
2. **点歌器**：玩家手动选择的曲目
3. **场景 BGM**：和平地图/基地的背景音乐

启用"覆盖关卡BGM"后，点歌器优先级提升到最高。

## 高级：bgm_list.xml

`sounds/bgm_list.xml` 是手动注册的曲目列表，支持更精细的控制：

```xml
<music>
    <title>曲目标题</title>
    <url>sounds/文件夹/文件名.mp3</url>
    <album>专辑名</album>          <!-- 可选，不填则从路径推导 -->
    <fadeDuration>20</fadeDuration> <!-- 可选，淡出帧数（30fps），默认 20 -->
    <baseVolume>100</baseVolume>    <!-- 可选，基础音量，默认 100 -->
    <weight>100</weight>            <!-- 可选，专辑内随机权重，默认 100 -->
</music>
```

未在 XML 中注册、但位于自动发现边界内的文件会使用默认参数。XML 中的配置优先级高于自动发现；注册不等于可播放，物理文件缺失或 probe 不成立时仍按上述状态 fail-closed。

## 场景专辑配置

在 `data/environment/scene_environment.xml` 中，场景 BGM 支持两种写法：

```xml
<!-- 单曲模式（传统） -->
<BGM>Dialtone</BGM>

<!-- 专辑模式（新增）：从专辑中加权随机选取 -->
<BGM album="TFR"/>

<!-- 专辑模式 + 回退默认曲 -->
<BGM album="TFR" default="Dialtone"/>
```
