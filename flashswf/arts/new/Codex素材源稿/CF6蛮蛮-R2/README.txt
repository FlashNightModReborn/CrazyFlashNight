CF6 蛮蛮（root 692）材质精修候选 R2

状态：独立于冻结 R1 的静态候选，艺术仍待用户标注和验收。本包的结构验证不能代替美术判断。没有生产提交，没有修改或执行游戏、SWF、EXE、ActionScript，也未使用用户电脑。

先看
previews/stand-original-r1-r2.png：原 / R1 / R2 全身同尺度
previews/face-original-r1-r2.png：脸与钢盔
previews/torso-original-r1-r2.png：胸腹有机体积
previews/greave-metal-original-r1-r2.png、shoe-metal-original-r1-r2.png、axe-metal-original-r1-r2.png：金属对照
previews/upperarm-skin-original-r1-r2.png、forearm-skin-original-r1-r2.png：肩臂对照
previews/game-scale-original-r1-r2.png：正常游戏阅读尺度
previews/all-frames-*.png：7 序列全部 246 帧静态覆盖
previews/death-body-only-comparison.png：去除特效后的死亡身体 / 整头脱落诊断

R2 改动
皮肤改为低对比、宽的漫射体积与少量粗糙阴影碎线；胸肌不使用独立椭圆球面收口，阴影接入腋下和肋部，删去下缘薄亮圈。肩底环断开接入上臂。面部保留 R1 的内部锚点，增加眉眶、颧颊、唇口的粗线表现。
钢盔、腿甲、金属鞋盖、腰扣与斧刃增加受控渐变反射和细边高光，钢盔保中性灰；裤子保留哑光布料，不增加镀铬高光。斧刃主要血迹位置保留，加入少量表面磨痕。
仍是手绘矢量简化材质，不是原版渐变或纹理的逐像素复现。R1 在原独立目录及原 ZIP 中保持不变。

交付
- 11 身体件：632–640、643、646
- 642 完整纯矢量双刃长斧
- 646 保源 645 / 631 / 644 三层顺序、原路径和原矩阵
- 640 实际为长颈 / 斜方肌，来源旧清单“前臂B”不能用作造型语义
- 660–690 的 31 个原血迹 / 断面保持原文件字节
- 6 常规动作 158 帧 + 691 死亡 88 帧 = 7 序列 246 帧
- 完整参考、时间轴、源清单与全部重建脚本

帧文件与体积
previews/candidate/*.svg 保存全部 246 帧的完整放置和颜色变换。
为把独立 ZIP 控制在 15,000,000 字节以下，帧文件引用同包 previews/shared-shapes/ 中的共享纯矢量定义，以及 previews/shared-bitmaps/ 中不变的原特效图片。没有删帧或把身体矢量栅格化。请保持这三个目录的相对位置，直接用支持 SVG 外部 use 的查看器（例如 Inkscape）打开。独立身体/武器件 parts/*.svg 无需这些帧目录。另提供 previews/standalone/ 的 8 张完整内嵌关键帧 SVG，供不支持外部 use 的查看器直接打开。
共享前后全部 246 帧已逐帧渲染，RGBA 像素完全一致；该比较只验证文件组装等价，不评价艺术效果。
reference/ 中重复的内嵌 PNG 改为同目录原 PNG 引用以去重；原图像字节、原路径和原矩阵不变。source-checksums 为来源记录，asset-manifest.json 才是本包交付文件校验。

注册与范围
原 viewBox、width/height、boundsTwips、注册点、裁切路径、bitmap→shape 矩阵、动画矩阵、depth 和颜色变换均保留。透明轮廓沿用 R1 的 alpha 64 阈值、0.12 源像素简化精度矢量边界，不声称逐像素 alpha 相等。
静态嵌套时间轴按局部放置年龄推进；脚本 goto/stop、随机切帧、触发和碰撞没有运行或验证。全帧非空不是游戏运行通过证明。

独立重建
依赖：Python 3、Pillow、NumPy、Inkscape 命令行。
在解压目录运行：python source/rebuild.py
只读取本包文件，重建 12 件、246 帧、31 原效果、所有对照与结构报告，并去重共享矢量/图片，最后自动逐帧验证共享前后像素等价。无需原归档、R1 外部目录、Windows、开发机或网络。
若要重新验证共享后所有帧的像素等价，可运行：python source/verify_shared_frames.py
该过程只执行 Python / Inkscape 静态渲染，不执行游戏代码。

导入提示
parts/*.svg 的 viewBox 原点可为负数。导入保留本地原点和原矩阵；不要自动裁空、居中或改变注册点。原时间轴在 reference/timelines.json。导入游戏与运行时验证是另一个需授权的阶段。
