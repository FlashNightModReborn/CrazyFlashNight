# 统合61式打磨交接包

这个包供外部 AI 在没有游戏项目、Windows 或 Flash CS6 的环境中打磨统合61式套装。工作 SVG 从本次现役原生 XFL 导出，已包含下臂覆盖等后续修正；普通61与钛合金61作为完整分件与整机参考。目标是统一画风细节，并改善缩小后的结构辨识。

请先读 [AI_BRIEF.md](AI_BRIEF.md)，再开始修改。所有路径均相对解压后的包根目录。

## 立即查看

直接用现代浏览器打开 preview.html。它内嵌了初始分件、矩阵和参考图，不联网，不需要服务器或项目文件。

页面可以切换男女、姿势、朝向和胸甲三态，比较现役基准与工作稿，以及查看三套61、分件原点、五件图标和小尺寸 PNG。小尺寸区先按指定像素生成 PNG，再显示；勾选“2倍像素放大”可以检查像素混合。

修改 assets/unified 下的 SVG 并保存后，点击“载入工作文件夹”，选择整个包目录或 assets/unified 目录。也可选择多个修改后的 SVG。浏览器只读取文件，不会替你保存或改写磁盘。

浏览器若不支持文件夹选择，请使用“载入修改的 SVG”，或者运行下面的刷新命令。

## Python 入口

Python 3.9 或更新版本即可拼接 SVG 和更新网页；默认仅用标准库，没有 Windows 字体、项目目录、Node、网络或第三方 Python 依赖。

    python preview.py --verify-package
    python preview.py --verify
    python preview.py
    python preview.py --gender female --pose rifle --state open --height 160
    python preview.py --all
    python preview.py --review
    python preview.py --refresh-viewer

--verify-package 用于开始修改前核对原包。修改工作稿或刷新网页后，原包哈希发生变化是预期的；继续使用 --verify 检查工作稿。不要修改 MANIFEST.json 来“修复”这个差异。

--all 为男女各输出七种当前站姿和四个兵器关键帧，以及五件图标的两帧。所有结果写入 rendered，默认透明背景。查看可用的其他参数：

--review 一次生成完整返包评审图，另加胸甲三态的前后对照、男女多尺寸对照、明暗背景和反向检查。它把预览绑定到本轮24个 SVG 的实际字节；改稿后重新生成，避免返包混入旧预览。

    python preview.py --help

如果环境已有 CairoSVG 及其 Cairo 运行库，可以附加 --png，同时输出 PNG。requirements-optional.txt 记录本包制作时使用的版本。基础 SVG/HTML 功能不需要它。Linux、macOS 的 Cairo 运行库安装方式由该环境维护者决定，本包不会自动安装。

    python preview.py --review --png

无代码执行能力的聊天环境可直接查看 examples 中的 PNG、SVG 和参考板，但无法自行验证新的分件拼接。

## 包内内容

| 位置 | 内容与用途 |
|---|---|
| assets/unified | 唯一工作目录，20个闭合分件及男女胸甲开门、开火共24个 SVG |
| baseline/assets/unified | 与初始工作稿相同的只读现役基准，前后对照使用 |
| references/regular/svg | 普通61的20个矢量参考分件 |
| references/titanium/svg | 钛合金61的20个矢量参考分件 |
| references/native-png | 三套各20个现有 Web 导出像素分件，含原点和倍率映射 |
| references/native-icons | 现有物品图标像素及统合61当前原生图标 SVG |
| references/r38-archive | 早期作者 SVG 和姿态归档，只读；可参考语义分组，不能覆盖现役稿 |
| data | 装配、原点、复用关系、图标配方、颜色参考及来源哈希 |
| source_snapshot/unified-native | 本轮现役元件 XML 快照，供 Windows 接回核对，并非独立可编译 XFL 工程 |
| examples | 已生成的三套对照、男女多姿势、胸甲状态、小尺寸和图标示例 |
| return-notes | 返包修改说明模板 |

## 修改与返回

按 [STYLE_AND_READABILITY.md](STYLE_AND_READABILITY.md) 处理画风与小尺寸，按 [TECHNICAL_CONTRACT.md](TECHNICAL_CONTRACT.md) 保持接口，最后执行 [RETURN_GUIDE.md](RETURN_GUIDE.md) 中的检查和返包命令。

网页、CairoSVG 与 Flash 在抗锯齿和部分渐变采样上可能存在差别。本包的像素参考来自现有 Web 导出，未重新采集游戏画面。96、128、160等数值是评审画布高度，不是已测定的游戏角色高度。连续动作、实际游戏显示和最终 CS6 发布在 Windows 端完成。
