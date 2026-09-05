# 游戏设计参考

---

## 1. 数值平衡

- **核心公式最高权威**：`0.说明文件与教程/武器-技能数值-价格-合成表填写的参考公式（修改后请勿上传git）.xlsx`
- **武器 balance 落盘与复现契约**：`tools/cf7-balance-tool/docs/agent-balance-record-design.md`
- **武器平衡业务判据与条款 ID**：`tools/cf7-balance-tool/docs/weapon-balance-rulebook.md`
- **材料统计**：`0.说明文件与教程/材料的单位、关卡统计.xlsx`
- **机制属性记录**：`0.说明文件与教程/武器装备与敌人的机制属性伤害类型魔抗的实装记录.txt`
- **标签与属性**：`0.说明文件与教程/Label与魔法种类与装备属性加成的类型汇总.txt`
- **数据文件**：`data/items/`、`data/units/`
- **武器散射度口径**：`data/items/weapon-diffusion-guidelines.md`

## 2. 机制体系

- **战斗机制**：伤害类型与魔抗体系、Buff/Debuff 计算、子弹与攻击判定（详见 [game-systems.md](game-systems.md)）
- **套装系统**：[套装系统设计与剑圣一期验收](../docs/套装系统-设计与剑圣一期验收-2026-07-14.md)（抗性表项声明 + 定制行为双路由；抗性字段存在会开启对应定向特攻破击，剑圣五件套为第一阶段验收产物）
- **钛合金61式套装玩法**：[钛合金61式装甲套装玩法设计 ADR](../docs/钛合金61式装甲套装-玩法设计-ADR-2026-07-27.md)（五件防具门控；MP驱动护盾/维生/双枪补弹；P90发射发电；M134/P90/血剑机制亲和；高级夜视与应急自动注射边界）
- **武器异质化讨论备忘**：[冲锋枪错位竞争与双枪插件设计备忘](../docs/冲锋枪错位竞争与双枪插件-设计备忘-2026-07-13.md)（换弹负担、冲击曲线、`hitBehavior`、破韧增伤 MetaBuff、普通手枪行为型补弱；两波均已施工，运行态标定待做）
- **盗贼黑市盲盒鉴定**：[玩法规格与审计基线](../docs/盗贼黑市盲盒鉴定-玩法规格与审计基线-2026-08-19.md)（六货包三组二选一、交易点/K 点流动价值闭环、解密 0–10 级信息权限、page draft/page object 双阶段、纸娃娃污泥配对、独立小游戏视觉硬门与跨栈验收；影子版已将 492/492 非颈部防具接入现役 `EquipmentInspector` 局部 fit/draw 取景，只渲染装备占用的多组件肢体，并以切组封存层阻断未覆泥原图闪现；污泥已按“休眠军用纳米机器人”设定升级为静态团簇、蜂群接缝与冷金属微粒材质；当前仍为 `AUDIT_REVISED / SHADOW_MINIGAME_V1 / OBJECT_SURFACE_V2 / BROWSER_VISUAL_REVIEW_PENDING / PRODUCTION_NOT_IMPLEMENTED`）；项目内首版入口与边界见[黑市全目录影子版](../launcher/web/modules/minigames/blackmarket/README.md)，One-shot 产出回收和真实游戏接入见[交接文档](../docs/盗贼黑市盲盒鉴定-产出回收与游戏接入交接-2026-08-19.md)
- **军阀战棋关卡化与大地图**：[vNext ADR](../docs/军阀战棋关卡化-N阵营编制与大地图演进-ADR-2026-08-31.md) 冻结 Warlord SubStage、N 战略阵营/二方交战、CommandElement/编制/TaskGroup、指挥所/VictoryGroup、规则与表现分离，以及“零英文、零战棋基础”的玩家语义。
  - Demo 1 的单 Warlord GameStage、动态九节点地图、Organization sidecar、2～4 人临时编队、五阵型和目标节点近 `180` / 中 `360` / 远 `650` 已贯通；维护者已确认编组、Formation、距离功能和主体玩法有效。距离与攻宽、阵型正交，设计目标仍是让突击兵/弹药兵在狙击兵之外获得实战位置。
  - Slice 4 已有 N 阵营机器实现：固定对称关系、阵营 block turn、三个 VictoryGroup、指挥所失败/投降清理，以及玩家主角与三名 Boss 共四名指挥官。映射固定为吴豫 / Itinerant / 111、袁望 / Surveyor / 113、阎凝儿 / Gazer / 112；吴豫与阎凝儿结盟，袁望政治独立但在本局与其余三方全部 hostile。同盟过境与玩家/AI 命令共用同一 validator。
  - Slice 6 的 `demo2-thick-x-80` 采用四角基地、中央高价值产地的 80 节点“厚 ×”：四方各 14 节点本土纵深，经 16 个争夺臂节点进入中央 8 节点工业环。候选同时具备中文检索/告警、六节点虚拟导航、三级 LOD、路线/实例批处理和有预算的局部 AI 枚举；战区工具默认收起并从节点导航栏展开，`Esc` 收起后回焦；底部 8 张普通兵牌可从 `120px` 折为 `32px`，向沙盘返还 `88px`。Host exact catalog 固化四方关系并逐一复验 80 节点的三档交战距离。Demo 1/2 的独立 GameStage XML 目前只由测试菜单白名单选关页暴露，默认生产目录保持不变，正式入口属于 Slice 7。
  - Slice 5 产品桥已完成 exact inner lease、每战 fresh world、world/dispatcher/camera/污染 teardown，以及真实玩家主角的隔离生成、攻守控制、阵亡转镜头和状态恢复机器闭环。初始、r2、r3 三个候选均因真人阻断固定为 `FAILED / SUPERSEDED / NOT_DEPLOYED`；当前 r4 已修复 canonical digest、AI 未开战收束、存档权威纸娃娃、player-avatar 专用棋子与 receipt、exact terminal/close/fresh resume，并把过渡世界清理从外层启动前移到已提交的 Action battle handoff。r4 已从精确 Core 路径启动，准确状态为 `SLICE_4_MACHINE_VERIFIED / SLICE_5_PRODUCT_BRIDGE_MACHINE_VERIFIED / SLICE_6_REPAIR_MACHINE_VERIFIED / READY_FOR_HUMAN_SLICE_6_ACCEPTANCE / candidate_executed / NOT_DEPLOYED`；Demo 2 连续 WebView2/AS2 多战、玩家存档无漂移、目标设备性能和 Slice 6 真人玩法仍待验收，正式 runtime 与 deployment 未改变。
- **好感度系统**：`0.说明文件与教程/好感度系统思路方案.xlsx`

## 3. 世界观与叙事

- **对话数据**：`data/dialogues/`
- **支线规划**：`0.说明文件与教程/支线规划表.xlsx`
- **Wings 桌宠 / Agent 一期方向**：[CF7 Agent Runtime 与 Wings Network 一期范围冻结 ADR](../docs/CF7-Agent-Runtime与Wings-Network一期-范围冻结-ADR-2026-07-30.md)（F7 C1 source freeze `dd84230a1d262c6478591cae2d11051b7a8aa7b1` 与其 `candidate_built / NOT_DEPLOYED` 凭据超时结论保留为历史证据。F8 implementation source `53caabc90941826ddacf626f536b0f473adbf049` 的 isolated candidate 先经纯 Agent Runtime MCP 达到 `e2e_verified / NOT_DEPLOYED`；release source `6f3d50a52413c747b05b74be88d6ee46650f4597` 随后取得本地 X509 + GitHub OIDC/Sigstore 双故障域共识、完成 v2 promotion，并由无 candidate id 的正式入口复验同一单屏 Launcher、玩家 HUD 与经授权打开的帮助 Web 面板纵切，达到 `standard_entry_verified`。production structured opener 的关闭 allow-list 另含地图、任务、队伍和点唱机，但本轮没有把其余四个面板写成人工目视通过。Flash 游戏画面本身只暴露可见性与窗口元数据，不向 Agent 提供像素、激活或原生输入；运行未使用 Codex Computer Use、browser/Chrome、legacy privileged HTTP 或 `input.*`。该结论不表示 Agent 可以代打、控制战斗、读取 Flash 画面、跨物理双屏操作，也不表示 Hair/Wings 完整产品或维护者人工目视签收已经完成。Wings 仍是复用项目中立底座的受限叙事客户端，自由文本永远零执行；桌宠口吻/视觉与最终 Boss 机制尚未冻结，既有剧情真相仍以 worldbuilding 权威路由为准）

## 4. 关卡与环境

- `data/stages/`、`data/environment/`、`0.说明文件与教程/无限过图背景配置教程.pdf`

## 5. 新内容添加

- `0.说明文件与教程/添加新物品和单位的详细基础教程宝宝可用.docx`
- `0.说明文件与教程/1.改动说明（含作弊码）.txt`

---

游戏设计决策和平衡调整应在此文档中记录理由。归档流程见 [self-optimization.md](self-optimization.md)。

