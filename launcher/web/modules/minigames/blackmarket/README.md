# 黑市鉴定全目录影子版

**状态**：`SHADOW_MINIGAME_V1 / OBJECT_SURFACE_V2 / BROWSER_VISUAL_REVIEW_PENDING / NOT_PRODUCTION_STATEFUL / NOT_DEPLOYED`

本模块是盗贼黑市盲盒鉴定的首个项目内测试渠道。它用现役物品 XML 与图标 manifest 生成全目录样本，让 UI、污泥算法、左右偏差和经济不变量可以在真实数据跨度上持续迭代；它不是正式黑市业务域，也不读取或写入真实库存、交易点、K 点与主存档。

## 边界

| 能力 | 首版实现 | 生产结论 |
| --- | --- | --- |
| 物品目录 | 覆盖 `data/items/list.xml` 的全部条目；Lab 可搜索并把任一机械可渲染物品定点放入货舱 | 仅机械盘点；所有候选仍为 `productionEligibility=review` |
| 资产 | 材料/消耗品优先使用现役 `f2` 透明掉落物帧；无 `f2` 时，影子版把单帧 `f1` 的全部可见像素统一去色。五类非颈部防具复用 `EquipmentInspector` 的 fit/draw 局部裁剪；武器复用同一解析器的完整单件/双刀/刀鞘商品图。解析不到完整装备素材时才回退图标代理，并在旋转缩放后、污泥生成前做只改 RGB 的轻度保边锐化 | 492/492 件非颈部防具至少有一个可导出性别分支；其中 476 件双性别可用，2 件仅男、14 件仅女。同组防具先选择双方共有的 authored 分支，无共同分支则整组封存；锐化代理不改变 Alpha/SDF/覆盖预算，也不授予生产视觉资格 |
| 三组二选一 | 每页 3 组、6 件唯一物品、组内同 subclass | 只证明纯生成核心，不是 AS2 page object |
| 购买/回售 | 会话内 TP/K 影子余额与幂等 call receipt | `productionWrites=false`；退出即丢弃 |
| 物品排布 | 从有效物品 Alpha 自动计算包围盒与 PCA 主轴；横向长物品只在 `0 / +90 / -90°` 中选最佳适配方向，避免任意角旋转造成插值模糊 | 锚点、旋转角、置信度与低置信 fallback 均自动派生；不维护全目录人工标注表 |
| 放大检视 | 卡片与检视窗共享固定 `512×768` 覆泥母版；选中货舱后可点“放大检视”或按 `V`，独立横向视口会按旋转后的物品包围盒、污泥外扩半径自动缩放并移到视线中心，也可拖拽、滚轮/按钮缩放、全貌/聚焦、90° 整体旋转及切换同舱 A/B | 检视壳只消费已覆泥安全画布，不调用会读取真实标题/原图的 `EquipmentInspector.open()`；切侧、旋转和重开都会重算聚焦，旋转作用于物品和污泥整体，A/B 切换不改变购买选择，打开/关闭不写领域状态 |
| 污泥 | `object-sdf-nanobot-sludge.v2`：保留精确 SDF、自动锚点、测地扩散和局部包络；材质改为休眠军用纳米机器人团簇，以 fBm 宏观泥团、Worley 蜂群接缝、SDF 贴附层、静态结节和稀疏冷金属微粒共同着色，单元尺度按画布短轴归一化 | 宏观看似湿污泥，近看才出现机械结构；休眠态不做持续动画。材质不能改变 Alpha 覆盖预算，当前 `97% / 84% / 54% / 18%` 仍只是 Lab 调参值 |
| 切组封存 | 新组六件先显示不含物品身份的封存层，原始解码图始终不可见；只有旋转、SDF 与污泥全部完成后才原子揭示画布，失败继续封存 | 消除原图闪现，也避免未旋转原图与已旋转污泥叠加形成视觉错位；仍需真实 WebView2 逐帧目视复验 |
| 身份 | 购买前公开快照/DOM 不含名称和 XML 路径 | 全目录仍在开发态 Web 内存，不能当生产保密边界 |
| 存档 | 无 localStorage、无文件写入 | AS2 page draft/page object、flush、reconcile 均未实现 |

外部参考包 `black-market-appraisal-demo-v1.zip`（source commit `6fac4334fc66841afe50ae32ce70526ad8e03dd6`）没有整体导入：外部 `dist`、Fixture Host 和 localStorage 存档均不进入现役运行闭包。首版只回收了三舱视觉方向、交易生命周期意图和测试目标，并按项目原生 Panel/Host bridge 重新实现。

## 结构

- `core/index.js`：确定性生成、脱敏投影、影子交易状态机；暴露互不混合的 `product` 与 `lab` 两个 port，只有 Lab 能搜索身份和定点采样。
- `visual/equipment-preview.js`：把私有货物身份交给现役 `EquipmentInspector.resolveProductSource/buildStateForSource`；防具复用槽位级 fit/draw 裁剪，武器复用完整/复合商品图，再通过 `MercPortraits.renderStateDataUrl()` 生成透明快照；同组防具协商一个共有性别分支，并带并发去重与小型 LRU。
- `visual/inspection-focus.js`：只消费覆泥母版的 `objectBounds`、外扩半径与当前正交旋转，纯计算检视相机的 fit zoom、自动聚焦 zoom 和偏移；不读取物品身份，也不重跑污泥。
- `visual/item-surface.js`：Alpha/背景分割、精确 SDF、骨架锚点、正交旋转、代理 RGB 保边锐化、实际覆盖预算与休眠纳米机器人污泥的纯算法和浏览器 renderer；固定母版尺寸进入 cache key。
- `visual/item-surface-worker.js`：只处理当前可见六件表面的 `OffscreenCanvas` worker；不支持时单件回退主线程，结果按资产、尺寸、种子、覆盖率和诊断模式缓存。
- `blackmarket-panel.js`：项目原生 `Panels.register("blackmarket")` UI；复用项目 `1024×576` Flash 逻辑画布和 `PanelScale`，并拥有覆泥母版缓存、共享 `WorkbenchInspectionViewport` 身份安全检视壳与 `minigame_session` 遥测。
- `blackmarket.css`：三舱工业黑市固定设计面；不按物理 viewport 重排，仅保留 reduced-motion 能力适配。
- `dev/qa-suite.js`：全目录、经济、随机侧偏、身份、事务、自动旋转/锚点、Alpha/SDF、异形覆盖预算、材质确定性及休眠纳米结构纯逻辑门。
- `dev/harness.html`：真实生成目录下的浏览器交互/布局夹具。
- `../../../data/black-market-shadow-catalog.v1.json`：由仓库数据派生的版本化影子目录，不是 authored eligibility 真源。
- `../../../../../tools/derive-black-market-shadow-catalog.js`：目录生成器；输入或输出漂移时 `--check` 失败，并把材料/消耗品明确分类为透明掉落帧或隐藏态统一去色的单帧回退。

## 入口

Launcher 内从“其他 → 测试 → 黑市鉴定测试”打开；Host 只发送：

```json
{"mode":"dev","source":"runtime","shadowOnly":true,"seed":"runtime-<seed>","debug":true}
```

面板会拒绝非 `dev + shadowOnly` 的 initData。当前没有普通游戏命令、NPC opener 或 `panel-contracts.v2.json` 登记。

浏览器夹具：

```text
launcher/web/modules/minigames/blackmarket/dev/harness.html?qa=1
```

## 验证

```powershell
chcp.com 65001 | Out-Null
node tools/derive-black-market-shadow-catalog.js --check
node tools/test-blackmarket-equipment-preview.js
node launcher/tools/run-minigame-qa.js --game blackmarket
node launcher/tools/validate-minigame-final-state.js
```

浏览器夹具额外覆盖三舱挂载、购买前身份、影子购买→揭晓→回售、Lab 全目录定点采样、布局边界、六件表面生成、黄金骑士牙狼胸甲局部纸娃娃、剧毒蛇矛完整武器源、`512×768` 同源放大检视/整体旋转/自动聚焦、低清装备代理锐化、切组首帧封存，以及把宿主改为 `768×432` 后仍保持 `1024×576` 逻辑画布和三舱结构。Lab 的“Alpha / SDF / 锚点 / 覆盖率叠层”会直接显示旋转、有效像素、目标/实测覆盖、自动锚点置信度、SDF 内径、耗时、backend 与视觉来源。

纯逻辑门当前为 19 项，浏览器夹具为 11 个场景；新增门锁定休眠静态材质、蜂群接缝、结节、冷金属微粒、代理锐化不改变 Alpha、武器私有 dressup 端口不进入公开快照、自动聚焦计算和固定 Flash 设计面。装备/检视专项为 30/30，防具覆盖仍为 492/492 非颈部防具、16 件性别限定资产和 968 个可聚焦性别分支，并增加完整武器、锐化回退、旋转后聚焦及无 viewport reflow 静态门。浏览器不可用时必须把 harness 已编写与实际浏览器未执行分开报告；Node 门不代替真实 WebView2 像素观感。

## 下一阶段

在污泥、配对和收益分布完成玩家调教前继续留在本渠道。进入正式接入必须新建 AS2 权威 page draft/page object 与存档、Host 脱敏 adapter、`black-market.v1` panel contract、堕落城入口和真实失败恢复；不能把本模块的影子余额、完整 Web 目录、锐化图标代理或未经 authored eligibility 审核的 dressup 预览直接翻转为生产实现。
