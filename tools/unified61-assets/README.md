# 统合61式资产与验证入口

本工具目录承接 Type61 R38 的初次导入、五件数据配表与定向验证。玩法规则见[设计与实现](../../docs/统合61式装甲套装-设计与实现-2026-10-25.md)，运行属性与配方仍由现役 XML/JSON、armor plan 维护。

## 来源与编辑边界

`source/` 是交接稿归档，包含20个闭合分件、男女躯干的开门/开火稿、作者姿态矩阵与输入哈希。`design.json` 保留本轮初值。首次导入之后直接维护现役XFL、物品XML和plan；不要用导入器覆盖后续原生编辑。

归档路径由 `.gitattributes` 禁用文本换行转换，跨 checkout 仍须逐字匹配 `source-manifest.json`；不得重算清单来接受 Git 改写的原稿。套装显示名遵循公共元数据合同，以“套装”结尾，`validate.py` 同时核对 design 与现役套装表。

唯一素材编辑源为 `flashswf/arts/new/Codex专用素材/LIBRARY/Codex/统合61式/`。新增资源使用独立 `Codex-统合61式` 链接，沿已有 Codex 素材库锚点加载，不改普通61或钛合金61原件。

`build.py` 保留SVG局部注册点，把弧线转为原生曲线，把对象包围盒渐变归一到用户坐标，并为孔口裁切创建原生mask层。5个图标均有物品栏与地面掉落两帧。胸炮模型三态由共享运行态按身体就位事件驱动，炮口位于作者舱门局部坐标。已有原生源时 `--install` 会拒绝覆盖。`native-manifest.json` 是首次66符号导入的历史记录，其 `compiled:false` 只描述导入器未调用编译器；当前符号数与编译身份由 `validate.py` 及本轮证据报告读取。

`revise_native.py` 在现役XFL内修正男女下臂的肘腕覆盖，保持注册点、横向宽度与动作骨架。图标首帧采用钛合金的24×24局部特写与径向底影，第二帧使用相同部件、矩阵与遮罩，只去掉底影。静态图标只引用闭合Graphic；胸甲和鞋的孔口遮罩提升到并列层，避免内外遮罩嵌套造成离线导出漏画。新增三个内部Graphic后本套共69符号、25个导出，`validate.py` 检查引用闭合、最大单层遮罩和两帧仅有底影差异。初版的五份完整部件总装保留为源稿转换记录，已不参与图标两帧。

## 初次导入

这些命令用于本轮已审阅输入的初次装配。`prepare_data.py` 只生成 `tmp/unified61-assets/` 候选；`install_data.py` 在发现已安装物品时拒绝再次追加。

```powershell
python -X utf8 tools/unified61-assets/prepare_data.py
python -X utf8 tools/unified61-assets/install_data.py
# 需要 lxml 与 fontTools；本机复用已有环境，不安装新依赖。
& tmp/cf6-py312/Scripts/python.exe -X utf8 tools/unified61-assets/build.py
& tmp/cf6-py312/Scripts/python.exe -X utf8 tools/unified61-assets/build.py --install
python -X utf8 tools/unified61-assets/register_assets.py
```

`register_assets.py` 只登记本套25个导出，并逐项证明原来源表记录未变。完整扫描仍由 `tools/linkage_scanner/scan_linkage.py` 提供；不因定向登记宣称全仓无冲突。

## Flash 与行为验证

遵循[CS6 编译协议](../../scripts/FlashCS6自动化编译.md)，与其他会话串行占用编译器。完整 asLoader 在本机可能需要约8分钟；超时、异常对话框和未完成SWF按该协议处理，1209字节的中间文件不能单独证明失败或成功。

```powershell
powershell -NoProfile -File scripts/run-unified61-tests.ps1 -TimeoutSeconds 360
powershell -NoProfile -File scripts/compile_test.ps1 -Target flashswf/arts/new/Codex专用素材/Codex专用素材.xfl -PublishOnly -VerifySwf flashswf/arts/new/Codex专用素材.swf -TimeoutSeconds 300
powershell -NoProfile -File scripts/compile_test.ps1 -Target publish -TimeoutSeconds 900 -QuitFlashAfterPublish
node tools/swf-function-sizes.js scripts/asLoader.swf --max 60000 --top 5
node tools/audit-as2-class-embedding.js
```

联合runner执行机制、资源与切枪入口、封闭插件策略套件；单独入口为 `run-unified61-set-tests.ps1`、`run-unified61-asset-tests.ps1` 和 `run-closed-mod-policy-tests.ps1`。测试不使用真实玩家存档。插件夹具由 `check_mod_policy.py` 从当前XML生成并在编译前校验，覆盖五件装甲、21件已有禁用规则的战术版武器与全部107种插件；验证菜单筛选、安装判定和真实等级计算一致。进入发布前须收束测试播放器和本轮拥有的编辑文档；退出请求不代替进程退出核对。

实际胸炮段数另用 `powershell -File scripts/run-vertical-chain-damage-probe.ps1 -TimeoutSeconds 600` 诊断。它连接真实五件套事件、工厂、碰撞队列与伤害处理器，区分一次发射、跨帧接触和每次有效段数；原调查的49项检查表示[缺陷复现闭合](../../docs/统合61胸炮-纵向穿刺联弹段数调查-2026-10-25.md)，不代表判定已修复。原机制套件的发射属性检查、资源像素检查及使用固定伤害边界的飞行套件，均不能代替这一完整伤害链验证。

后续水平一致性修复使用 `powershell -File scripts/run-vertical-pierce-coverage-tests.ps1 -TimeoutSeconds 600`：17个真实飞行场景、162项检查覆盖0°/180°微小角度边界、左右与MC/对象一致性、原非水平基线、散射5和宽目标超过24段。保留7/18及旧非水平几何，24仅为平衡参照。结果与现有Vepr12霰弹夹具阻断见[修复记录](../../docs/统合61胸炮-水平方向判定修复-2026-10-25.md)。

资源与联合runner在进入CS6前调用 `sync_probe.py --check`，逐字核对两份测试模板中的生产切枪函数；不一致时拒绝运行。生产入口修改后可用 `python -X utf8 tools/unified61-assets/sync_probe.py --write` 更新投影，再重新执行真实Flash测试，旧回执不自动延续。

## 数据与派生物

五件背景与效果文案统一维护在 `copy.json`。`sync_copy.py` 只同步现役物品和套装的 description 字段，保留其他 XML 字节；首次配表也读取同一来源。改文案后执行同步、只读检查和五件定向 armor balance 同步，不重新安装数据或重编 SWF。

```powershell
python -X utf8 tools/unified61-assets/sync_copy.py
python -X utf8 tools/unified61-assets/sync_copy.py --check
python -X utf8 tools/unified61-assets/validate.py
python -X utf8 tools/lifecycle-skill-metadata/validate.py
node tools/assemble-collapsed-frame.js --check
node tools/check-bom.js
node tools/validate-equip-fn-coverage.js
node tools/validate-doc-governance.js
```

在 `tools/cf7-balance-tool` 内执行：

```powershell
npm run armor-balance-sync -- --items '统合61式头部装甲,统合61式胸甲,统合61式腿甲,统合61式装甲鞋,统合61式手甲'
npm run armor-balance-check -- --items '统合61式头部装甲,统合61式胸甲,统合61式腿甲,统合61式装甲鞋,统合61式手甲'
npm run typecheck
npm test
npm run roundtrip-check
```

`--items` 是显式定向范围，仍核对plan中数值、价格、工作簿身份与派生账本；目录完整性只核所选物品，日志明确为SCOPED。无参数入口继续执行全目录覆盖门。目前既有3XF特勤五件缺plan登记，必须单独列出，不能由本套定向通过替代。

图标与装扮由[素材工作台](../asset-workbench/README.md)从本轮SWF生成。首次安装时，多件候选若共享同一初始清单，可用 `apply_web_batch.py --jobs-file <包含五件jobId的JSON>` 一次应用：它先验证全部原输入、输出与候选摘要，复用图片/配准点检查和全局互斥锁，仅合并本套5个图标、20个皮肤与5个物品投影；保留原件备份与逐文件事务记录，任何原有其他物品项发生变化都会拒绝。已有图像的修订通过工作台核心逐件执行 `bake` 后 `apply`，每件以上一件应用后的清单为输入；不要把已存在图片交给首次安装批处理，也不要伪造job已应用状态。

```powershell
python -X utf8 tools/unified61-assets/preview.py
python -X utf8 tools/unified61-assets/review_poses.py --label after --gender 男
python -X utf8 tools/unified61-assets/review_poses.py --label after --gender 女
python -X utf8 tools/unified61-assets/review_icons.py
```

初版预览使用实际SWF导出PNG和作者原生矩阵，输出男女六组装配。动作复核读取现役 `things0` 的短兵站立、短兵格斗、刀剑站立、长柄站立四个实际关键帧，尊重图层有效帧区间，不把过期分件跨分支残留；图标复核读取已应用WebP、钛合金参考和本轮保全原件。以上用于检查部件配准与静态取景，不是游戏截图或连续动作验收。
