# Andy 工装裤 D 接入

维护者选定 D 漫画橄榄方向，作为 CF1《修理大学》Andy 的独立起始下装。
`Andy工装裤` 的所有运行属性及售价原样继承 `白色中山装裤子`；只改变装备身份、文案、图标和装扮链接。
新增防具进入 armor plan，并由现有同步器生成 audit 和 `<balance>`，保留原件的公式例外状态。

## 源与装配

- [交接归档](../../flashswf/arts/new/Codex素材源稿/Andy工装裤-D/README.md) 保留 D 的四个 SVG、原始 XFL 片段、原点和输入哈希。
- 唯一现役编辑源为 `flashswf/arts/new/Codex专用素材/LIBRARY/Codex/Andy工装裤/`。
- 臀部和两条大腿保留原始 Flash Edge 几何，仅按 D 改填充；小腿为原生二次曲线、填充和独立开放描边。没有栅格贴图或自动描边。
- 四个男模 linkage 为 `男变装-Codex-Andy工装裤{屁股,左大腿,右大腿,小腿}`，均保持局部 `(0,0)`。本次用于男角色 Andy，不新增跨性别别名。
- 图标第一帧沿用 24 像素遮罩、臀部细节和底影；第二帧为原空手站姿五个下身 holder 组成的完整裤子，供地面显式 `gotoAndStop(2)`。
- 通过既有 `Codex专用素材` 锚点及 things-new 共享库加载；不覆盖白裤或咖啡裤的原始元件。

## 操作与验证

```powershell
# 已选定交接稿的初次导入，后续原生编辑不要重跑覆盖。
python -X utf8 tools/andy-trousers-assets/build.py --import-approved

# 默认纯读：检查原几何、注册点、开放描边及与白裤逐字段相等的运行属性。
python -X utf8 tools/andy-trousers-assets/build.py
python -X utf8 scripts/tools/xfl/audit.py flashswf/arts/new/Codex专用素材
python -X utf8 tools/linkage_scanner/scan_linkage.py --xml-only
```

独立素材使用 CS6 发布 `Codex专用素材.xfl` 与 `things-new.fla`；新开局装备选择编译进 `asLoader`。
编译目标与恢复合同见 [CS6 编译](../../scripts/FlashCS6自动化编译.md)。
发布后优先通过现有物品素材工作台生成并应用本件候选；其内核调用 `bake-dressup-offline.py` 和 `bake-icons-offline.py`，从实际 SWF 烘焙四个皮肤及图标，不把归档 PNG 当成生产真源。
工作台只应用本件条目，保留其他装备既有的皮肤状态和骨架。底层 dressup CLI 会重建全量元数据；既有未烘焙来源不能因本件接入而被标记成可用。

```powershell
python -X utf8 tools/asset-workbench/cli.py bake --item Andy工装裤 --kind all
# 检查返回的 ready 候选，再使用其 jobId。
python -X utf8 tools/asset-workbench/cli.py apply --job <jobId>
```

`SaveManagerTest` 的书内 context 断言检查起始下装的新身份，保留白裤夹具及永久档案隔离验证。

站姿预览、编译与机器回归分别给出证据；动态关节、实际游戏观感和正式入口仍按真实验证范围报告。
本任务不自动授权 commit、push 或正式 runtime promotion。
