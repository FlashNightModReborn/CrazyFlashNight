# 统合61式返包要求

请交付一份完整候选压缩包，保留24个可编辑 SVG，以及可追踪的变化和对照。仅有整机效果图不能用于接回。

## 返包内容

1. assets/unified 下的全部24个 SVG。未修改的分件按原字节保留。
2. return-notes/CHANGELOG.md：修改了哪些分件、统一了哪些规则、小尺寸收益、尚存问题和对应预览。
3. rendered 下的男女多姿势图，至少包含七种当前站姿和四个额外兵器关键帧。
4. 闭合、开门、开火三态预览；对胸甲修改时必须完整检查。
5. 96、128、160画布高度的基准/候选对照，以及24×24图标对照。PNG 应保留原尺寸，不只提供截图或放大拼图。
6. 至少一张反向朝向、一张浅背景和一张暗背景检查图。
7. 工具自动生成的 return-manifest.json，绑定输入基准与候选文件哈希。

## 自检与生成

先运行：

    python preview.py --verify
    python preview.py --review
    python preview.py --refresh-viewer

有 CairoSVG 时，同时生成 PNG：

    python preview.py --review --png
    python preview.py --gender male --pose idle --state open --png --output rendered/male_open.svg
    python preview.py --gender male --pose idle --state fire --png --output rendered/male_fire.svg
    python preview.py --gender female --pose idle --state open --png --output rendered/female_open.svg
    python preview.py --gender female --pose idle --state fire --png --output rendered/female_fire.svg
    python preview.py --height 96 --png --output rendered/size96.svg
    python preview.py --height 128 --png --output rendered/size128.svg
    python preview.py --height 160 --png --output rendered/size160.svg
    python preview.py --mirror --background "#ded9c9" --png --output rendered/mirrored_light.svg
    python preview.py --background "#10161d" --png --output rendered/dark.svg

前后和小尺寸对照可从 preview.html 导出，并保存到 rendered。没有 CairoSVG 的环境可以先生成 SVG，再通过网页导出 PNG；如环境不能运行浏览器或 PNG 渲染，保留完整 SVG 对照，并在说明中准确写明未输出的 PNG，不能把示例图当成修改后的结果。

填写修改说明后生成新的版本文件名：

    python preview.py --return-zip type61-return-R01.zip

自动返包会核对24个 SVG、基准、参考和装配数据，收集工作稿、rendered 中的 SVG/PNG/JSON及 return-notes。缺少完整评审、改稿后预览过期、已生成的评审文件被替换时，会要求重新运行 --review。已经存在的返包文件不会覆盖，请使用新的版本号。

不要返回真实存档、游戏运行时、Windows 字体、虚拟环境、缓存、node_modules或整个项目。

## 判定范围

可以报告实际完成的矢量修改、静态重组、原点和文件检查、多尺寸渲染及查看结果。不要把这些结果写成 CS6 编译通过、连续动作通过或游戏已验收。Windows 接回时继续检查原生转换、真实持械动作、胸炮表现和最终上屏大小。
