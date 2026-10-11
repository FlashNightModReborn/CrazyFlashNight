# CF7 整架 v3 · 可重建 3D 试稿

## 交付与范围
- `bookshelf-v3.blend`：默认陈列态，已打包纹理，含棚拍相机与灯光。
- `bookshelf-v3.glb`：仅柜体与内容资产（PBR、内嵌纹理），不含棚拍灯光/背景；用于后续本地 Codex 接入。
- `overview.png` / `archives-open.png` / `collection-pulled.png`：实际 Blender 模型渲染；均为视觉样板，不是已运行的游戏界面。
- `build.py`、`make_labels.py`、`states.py`、`layout.json`、`semantic-nodes.json`、`modelstats.json`、`textures/` 与 QA 报告。
- 本次未修改 GitHub、游戏代码、用户电脑，也未实现 Web 交互、角色切换或真实档案读写。

## 默认陈列与真实容量
两层作品区 + 底部较矮档案柜。当前真实四本作品《尘都诡谈》《光明巴比伦》《守护之力》《风帆双子》与 CF1–6 一套合集（整套一个入口）。上层三本集中成组，两侧书挡收边；下层风帆双子与合集之间保留空间。没有假锁书或“敬请期待”。

当前 4 本普通书 + 4 个未绘制空位 = 保守 8 本普通书，另外容纳一套 CF1–6；不承诺 12 本。在 `layout.json` 给出了固定当前中心与四个预留中心，新增到 8 本不需移动或旋回当前作品。右侧较大留白是集中扩容区的明确取舍，不是遗漏资产。

柜体面板厚度 0.30，两层净高 6.80；最高完整书/套盒 6.55，顶部净余量 0.25。封皮、纸页、书脊为独立实体；高度厚度略有区别。原文字/配色保留，未知封面用素面材质，不编造官方封面。

## 档案语义（演示数据）
底部是 CF7 常驻角色档案，与各书阅读进度无关。
- 当前角色、角色档案 02、角色档案 03 是三个快捷入口，不是档案总容量。
- “全部档案”独立抽屉打开显示若干实体薄文件夹，示意目录；更多文件由后续 Web 列表面板承担，不用无限实体文件堆叠。
- 所有名字均为通用演示名，没有用户真实角色、等级、进度或存档数据。
- 后续交互必须先查看角色详情并确认，才切换当前角色。书架不实现创建、删除或覆盖。
- 文件夹均为抽屉后代，随抽屉父节点联动；固定滑轨不跟随。

## 重建
需要 Blender 4.3.2（本次验证版本）与 Python 3 + Pillow。已有全部 PNG 时直接：

    blender -b -t 10 --python build.py

生成/重建所有模型、GLB、元数据及三张 1600×900 渲染。`-- --preview` 为低采样布局预览；`-- --no-render` 只重建模型及元数据。输出会覆盖本目录 v3 文件，不碰 v2。

重新生成通用文字标签需运行 `python3 make_labels.py`；字体默认 `/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc` 与 Bold，其他平台需调整此路径。构建模型无需额外安装中文字体，使用已提供 PNG。

本云端 Blender 不含 OpenImageDenoise，渲染使用 160 samples，无去噪，细微颗粒属于渲染噪声。

## 层级、抽取与坐标
- 根：`CF7_BOOKSHELF_ROOT`
- 作品：`BOOK_dust` / `BOOK_babylon` / `BOOK_guardian` / `BOOK_sail-twins`，各有 `entryKey`。
- 合集：`COLLECTION_CF1_6`，`entryKey=crazy-flasher`；下含 `DISC_CF1`…`DISC_CF6`，子入口 `cf1`…`cf6`。
- 档案根：`ARCHIVE_BANK`；三个 `ARCHIVE_SHORTCUT_*` 与 `ARCHIVE_ALL_DRAWER` 分开，入口为 `archive:*`。

`states.py` 提供 `default`、`archives-open`、`collection-pulled`、`disc-pulled`、`book-pulled` 五种可逆参数状态。`reset()` 严格恢复记录的 restLocation；动作是参数，不是 glTF animation clips。模型未附动画剪辑，也没有浏览器中断/重复点击状态机。

Blender 源文件为 Z-up、正面为 -Y；GLB 为 glTF Y-up、正面为 +Z。GLB extras 的 `pullDirectionGltfParent=[0,0,1]` 与 `restTranslationGltf=[x,z,-y]` 用于接入，`pullAxis=-Y` 和 `restLocation` 仅指 Blender 作者坐标。各可动节点的 `pullMax` 为父坐标单位，拉出比例夹在 [0,1]。先恢复原位再施加偏移，避免累积漂移；子盒偏移叠加在合集父偏移上。不要把作者坐标数组直接当 glTF translation。

## 材质与视觉限制
资产是基础 PBR，未做灯光烘焙。离线棚拍灯光、环境阴影、AgX 色彩变换不在 GLB 内。直接放进旧 unlit renderer 不会自动等同这些预览；后续需要支持 PBR 并配置灯光/环境/阴影，或另做烘焙。此包不声称已完成该接入。

## 素材来源与诚实披露
11 张输入 PNG 由已连接 GitHub 对 `FlashNightModReborn/CrazyFlashNight` 的 `launcher/web/assets/bookshelf/shelf/textures/` 只读取得，并实际查看像素。它们是仓库现有素材，部分为程序排版候选，不统一宣称官方封面。

4 张原书脊保持；CF 各代原仓库图片置于薄盒侧面，另排 CF1…CF6 清晰窄脊并保留六色识别，避免把封面压扁。仓库 `disc-cf5.png` 画面实际写“闪客快打3 / 第5章”，保持输入图不改，以独立 CF5 盒脊和 `entryKey=cf5` 标明第五代；这是源素材异常，不是新的编号定义。

v2 Library 源包和预览的正式下载流程返回 HTTP 403，未能读取。因此这是依据认可的冷灰工业/蓝书/黑合集方向与仓库实际纹理新建的 v3，不声称复用或逐字复现不可读的 v2 blend。v2 的 Library 身份未修改。

## 后续性能优化候选（尚未进行游戏内性能验证）
最终 GLB 含 182 个 mesh、38 个导出材质、9,988 三角形、26 张内嵌 PNG，约 1.29 MB。`modelstats.json` 的 41 个材质是整个 Blender 场景总数，含离线背景等未导出材质。几何量不大，但 mesh/材质分散，不能据此宣称游戏运行帧率达标。

后续接入可优先评估静态柜体合批、重复薄盒/文件夹几何实例化、标签及封面纹理图集。保留作品、合集、单盒、档案快捷和全部档案的拾取/抽出语义根，不能为了合批把需要独立操作的对象合死。性能策略须结合实际 renderer、材质切换、目标硬件和1024×576界面评测，本包没有做这些优化或帧率验证。
