CF6 大刀机器人925：R2材质修订候选

本版从冻结R1独立建立，针对“机器人整体仍有塑料感”做材质响应调整。
- 金属：保留原造型，收窄局部反射带、压深背光及接触暗部，减细画上去的均匀白边。
- 紫臂：上臂图像保持R1原样，前臂只调整金属腕箍；紫色主体保留有机/涂层式柔和反光，不改成铬色。
- 大刀：仅微调钢面与刃口明暗，黑杆、缺口、5细槽、尖端孔、护手环孔位置与透明性不变。
- R1轮廓、原路径/椭圆几何、注册点、viewBox和时间轴保留。11个部件的alpha平面逐字节对比，防止材质调整扩大轮廓。

内容
10个主体件890–898、900与独立刀899，共11个纯矢量SVG。
916–923八个死亡复合碎片，40个原位图填充投射新atlas889。
7动作/分支共229帧静态重放；924死亡全部58帧；另有61个原始关键帧用于对照。
共用138个效果/辅助形状保留原数据，原隐藏helper仍按导出规则省略预览。

查看
previews/stand-original-r1-r2.png：原/R1/R2同尺度全身。
previews/stand-original-r1-r2-1x.png：原始局部坐标1×阅读尺度。
previews/material-comparison-892.png、890.png、898.png：底盘、尖足关节、壶身三联。
previews/mechanical-original-r1-r2.png、coating-weapon-original-r1-r2.png：分材质集中对照。
previews/*-original-r1-r2.png：抬刀、横扫、低姿、受击及零烟火死亡诊断。
previews/all-frames-*.png：所有动作逐帧联系表。

目录
parts/：原坐标新件；death-parts/：使用原clip路径与fill矩阵的八碎片。
shared/与reference/bitmaps/：未改共用效果及去重的原参考位图。
reference/：完整原形状/动作/控制清单，以及冷重建所需的冻结R1预览快照和几何目录。
source/：可编辑Bezier绘图、独立material_r2.py、图集投影、重建、对照和验证脚本。
qa/：覆盖、alpha、原几何/矩阵/裁切、刀孔、资源引用和每帧hash报告。

重建
需要Python 3、Pillow、NumPy、SciPy和Inkscape。独立解压source ZIP后运行：
python source/rebuild.py --workers 4
不依赖原工作目录、R1文件夹、原SWF、网络或Windows；R1对照快照已放在本源包内。
将重建11新件、8碎片、229候选帧、61原关键帧、原/R1/R2对照图及验证报告。

边界
本版仍为待用户标注的材质候选。结构/像素检查不能替代最终美术认可。
真实金属与紫臂保留各自克制的渐进反光，不宣称完全无渐变；原低分辨率贴图的表面噪点和部分细碎暗部有所简化。
全部是静态显示列表重放。嵌套动作按放置年龄推进，ActionScript goto/stop/随机分支未执行，不能视为游戏运行时测试。
未运行SWF/EXE/ActionScript，未修改R1，未提交生产工程，未操作Windows开发机。

每个交付文件为小于15,000,000字节的普通独立ZIP，不是分卷。source ZIP自身含全部冷重建输入，不依赖动作PNG或对照ZIP。各预览ZIP可独立打开，合并解压只为集中浏览。
