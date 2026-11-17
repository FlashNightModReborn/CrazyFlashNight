# 统合61式候选修改说明

版本：`R01`（v4 硬边冷锻规范·全套 24 件完整候选返包）

## 修改范围

本轮完成了 `assets/unified/` 下**全部 24 个可编辑工作 SVG** 的统一重塑与契约校验（无未改动遗留分件），同时保持 `baseline/`、`references/`、`data/`、`source_snapshot/` 及 `MANIFEST.json` 全部只读基准字节零改动：

1. **跨性别共享闭合件（4 件）**
   - `assets/unified/closed/head.svg`：重塑克虏伯深炭钢盔顶、冷锻钛钨眉檐与九面体防毒面具、双联锐角红目镜及 `radialGradient` 光学红晕。
   - `assets/unified/closed/glove_left.svg`：补齐原本仅有 17 条稀疏路径的左手甲结构，重塑四阶硬边冷锻手背主甲、拇指护板、指节装甲段及统合绯红远端指套。
   - `assets/unified/closed/glove_right.svg`：统一长护臂延伸甲板、深色嵌入式腕表模块、冷锻手背甲与绯红指套，同步服务持械远伸姿态与 `24×24` `hands` 图标裁切。
   - `assets/unified/closed/boots.svg`：清除原稿底部的泥点碎块（`[52..54]`）与杂乱军绿偏色，重塑冷锻脚背/鞋头重甲（Sabaton）、深炭踝部液压模块与绯红鞋跟稳定块。
2. **男款专用闭合件（8 件）**
   - `assets/unified/closed/male_torso.svg`、`male_upper_arm.svg`、`male_forearm_left.svg`、`male_forearm_right.svg`、`male_pelvis.svg`、`male_thigh_left.svg`、`male_thigh_right.svg`、`male_calf.svg`。
3. **女款专用闭合件（8 件）**
   - `assets/unified/closed/female_torso.svg`、`female_upper_arm.svg`、`female_forearm_left.svg`、`female_forearm_right.svg`、`female_pelvis.svg`、`female_thigh_left.svg`、`female_thigh_right.svg`、`female_calf.svg`。
4. **男女胸甲开门与开火状态件（4 件）**
   - `assets/unified/open/male_torso_open.svg`、`assets/unified/open/female_torso_open.svg`：保持胸甲主体与闭合态字节级同源对齐，上下装甲舱门向两侧滑开，露出内部深色膛线导轨与电热预充能线圈微光。
   - `assets/unified/fire/male_torso_fire.svg`、`assets/unified/fire/female_torso_fire.svg`：在开门态基础上点亮背包状态灯，并在膛内叠加 5 层高能电热等离子喷流与 `radialGradient` 炮口光晕，严格保留末尾逻辑接口 `<g transform="matrix(1 -0.6 0.25 0.95 47 -19)" data-name="炮口位置" />` 且未在 `(47,-19)` 绘制任何可见准星残影。

## 统一的画风规则

1. **零软渐变硬边冷锻色阶（对标钛合金 61 套工艺）**：彻底摒弃金属主甲上的线性软渐变，全部采用硬边多阶色块切分，彻底消除混色发灰与塑料感。
2. **双主色体块拉开深浅反差**：
   - **克虏伯深炭底盘（`#080A0E` / `#161C24` / `#222A34` / `#3A4450`）**：用于头盔穹顶、背部反应堆背包、三段腹甲、上臂液压连杆、前臂内嵌仪表槽、侧胯挂甲、大腿侧包、小腿正锁扣座及踝部关节，压稳重装底盘剪影。
   - **冷锻钛钨受光主甲（`#3A4450` 暗折面 → `#7E8D9B`/`#8897A6` 锻钢中调 → `#CFDCE6` 宽倒角 → `#F8FBFE` 内缩刀锋高光）**：用于钢盔眉裙、呼吸面具、护颈领圈、斜向胸甲、肩甲下裙边、上下臂护圈、手背主甲、腰带扣与三段 V 字裆甲、正侧大腿主甲、护膝/胫骨脊及重装靴头。所有 `#F8FBFE` 纯白高光均相对 `#05070A` 外轮廓向内退让 `1.5–2.5` 局部单位，避免边缘泛白发粉。
3. **统合绯红指挥色与原版肩徽严守**：
   - 男女上臂 `male_upper_arm.svg` 与 `female_upper_arm.svg` 均 **100% 原路径完整保留统合五层肩徽（巴别塔 + 地球经纬线 + 双交叉轨道环）**，并将其色值统一提亮为高反差象牙冷白 `#F5EFE2`，衬于硬边冷漆绯红（`#380806` → `#6E140E` → `#8F1D15` → `#B8281E` → `#D63A2D` + `#FFADA0` 刀锋反光）多面体肩甲之上。
   - 统合绯红点缀同步贯穿头盔战术条、胸炮警示带、远端指套、内胯饰条、大腿上冠切角、护膝/脚踝战术标与鞋跟稳定块；光学目镜、胸炮状态灯、上臂/前臂指示灯采用显式 `userSpaceOnUse` 的 `radialGradient` 绯红光晕。
4. **复用件对称性与现役矩阵严守**：
   - 移除肩甲与胸甲上的单向微字序列号（`061-01`），胸甲仅保留高对比战术钢印 `61`；`upper_arm`、`calf`、`boots` 采用兼顾前后双实例复用与整机水平翻转（`--mirror`）的平衡受光结构。
   - 四个下臂（`male/female_forearm_left/right`）完整保留 `constraints.json` 规定的现役烘焙拉伸矩阵，局部注册原点 `(0,0)` 与全部 24 个文件的 `viewBox/width/height` 原样保持。

## 小尺寸变化

1. **`96px` / `128px` / `160px` 画布高度实测**：
   - 原稿在 `96px` 与 `128px` 下全身装甲明度集中在 `24%–42%` 灰蓝区间，头胸腹胯与四肢糊成一团灰影，双目暗淡无神。
   - 新版 v4 依靠“深黑关节沟槽 + 克虏伯深炭底盘 + 冷锻亮银倒角/内缩高光刀锋 + 绯红肩甲/指套/战术标”四重明度锚点，在 `96px` 下即可一眼分辨钢盔眉檐、双红目镜、绯红统合肩甲（含白色巴别塔徽记轮廓）、斜向亮银胸甲、V 字裆甲及大腿/胫骨/靴头节律，彻底消除了小尺寸糊片现象。
   - 合并并清理了 `<0.35` 线宽的杂乱碎裂细线、底部泥点及无法在小尺寸成形的微缩编号框，保留机械液压杆、前臂仪表盘和反应堆脊线的大体块转折。
2. **`24×24` 装备栏双帧图标（Frame 1 带底影 / Frame 2 无底影）实测**：
   - `head`、`chest`、`legs`、`hands`、`boots` 五个槽位在 `24×24` 原生像素尺寸下均具备极清晰的轮廓与冷银/绯红高对比焦点，尤其 `legs`（V 字冷锻裆甲+绯红内衬）、`hands`（冷锻手背+绯红五指端）与 `boots`（冷锻靴头+绯红底边）较原稿辨识度大幅跃升。

## 拼接和状态检查

已运行 `preview.py --verify`、`preview.py --refresh-viewer`、`preview.py --review --png` 及附加单状态渲染命令，完整生成并目视核查了 `rendered/` 下的全部 SVG 与 1:1 原尺寸 PNG：

- **男女 11 组战斗站姿与持械关键帧（共 22 组 SVG + PNG）**：`rendered/unified_{male,female}_{idle,rifle,pistol,pistol2,dual_pistols,melee,grenade,weapon_key_1,weapon_key_2,weapon_key_3,weapon_key_4}_closed.{svg,png}`。
- **男女胸甲闭合/开门/开火三态对照与单图（共 8 组 SVG + PNG）**：`rendered/torso_{male,female}_{open,fire}.{svg,png}` 及单帧 `rendered/{male,female}_{open,fire}.{svg,png}`。
- **小尺寸与多尺寸前后对照（共 11 组 SVG + PNG）**：`rendered/compare_{male,female}_{96,128,160,320}.{svg,png}` 及单帧 `rendered/size{96,128,160}.{svg,png}`。
- **浅色底、暗色底与水平翻转方向检查（共 8 组 SVG + PNG）**：`rendered/{male,female}_{light,dark,mirrored}.{svg,png}` 及 `rendered/mirrored_light.{svg,png}`、`rendered/dark.{svg,png}`。
- **五部位双帧 `24×24` 图标（共 10 组 SVG + PNG）**：`rendered/icon_{head,chest,legs,hands,boots}_f{1,2}.{svg,png}`。

## 尚存问题

1. **Windows 原生 XFL 回装与 CS6 编译待核对**：本返包为离线静态候选矢量资产（已通过全部 24 件 SVG 语法与坐标契约校验，不含任何未授权标签或样式表），但离线 SVG/PNG 预览不代表 Flash CS6 原生编译签收。回装时请对照 `source_snapshot/unified-native` 定向合入改动，切勿使用初次导入脚本覆盖四个下臂的现役实例矩阵、`炮口位置` 逻辑节点及图标双帧阴影层。
2. **游戏内连续动作与持械遮挡实机验证**：`glove_right.svg` 含远伸持械长护臂结构，静态关键帧（`rifle`、`pistol`、`dual_pistols`、`weapon_key_1..4`）已核查无断层，但仍需在 Windows 端编译进游戏后结合真实枪火特效、胸炮弹道生成点 `(47,-19)` 与连续帧动画做最终上屏验收。
