# 普通战斗转场资源合同

HP/MP 权威仍在 actor，只有实际转场采样时创建 `PlayerResourceTransfer` 一次性内存快照。`PlayerSceneLifecycle` 拥有出生身份、场景 setup 与最终角色就绪的汇合，以及相机和 SceneReady/Start 的通知；首次出生或基地读档不创建资源继承对象。

完整属性尾部仍由 `PlayerStatRefreshCoordinator` 提供，场景通过 `setSpawnLifecycleHooks` 接入。它的装备、技能、成长与持久写职责不属于资源继承，也未在本次接线调整中删除。原 Bridge 的场景接线迁入场景 owner；这一步明确所有权并去掉资源数值冻结，不宣称已经消除了全部生命周期复杂度。

## 受理、清场和消费

门/nextStage 先冻结 run、context、slot、源 world/actor 普通对象身份及目标 substage；fade 返回 true 或 prepareDoor 成功后才登记意图，拒绝不替换旧 owner。药剂、治疗和淡出期间的正常资源变化不撤销意图。

普通无限过图的绿色箭头由 `flashswf/levels/wuxianguotu_1.swf` 内的门处理，其本地 `切换场景` 函数不是全局门函数。StageManager 在通关开放出口之前绑定该门，保留方向键、鼠标点击和双重命中检查，经实际 `nextStage` 受理后才停门动画。绑定持有源 world 普通对象身份，旧出口回调不能操作同名重建的世界；不得依赖早于子元件首帧的赋值，也不得让旧脚本直接淡出绕过意图登记。

SceneManager 在 Loot 收敛及 placement 预检后、第一次 release 前读取 HP/MP/旧最终最大值。整份校验失败保留旧世界并取消本次遮罩，不重试资源、不取旧数组。成功销毁后才提交；release/teardown 异常只撤销自己的票据，不能宣称已回滚清场。

拒绝原因区分转场身份和资源数值：缺失意图、run/world/actor/slot/substage 不匹配等记录具体字段并提示转场状态失效；仅资源样本非法提示生命或能量数据异常。身份检查不因 HP 溢出而放宽，有限的合法溢出仍按下述投影合同传递。

目标 attachMovie 的 initObject 带独立 actor identity。最终属性和外层状态跳转完成后，协调器在 derive/ready 之前调用资源 hook，先验证两项再同步写入、消费一次。普通对象身份隔离同名 MovieClip 重建。死亡、返回、换档、新生、新 run、关闭 run 撤销旧 generation。死亡仅保留同一世界、run、角色及已完成属性初始化的复活 owner。life authority 确认同一主角真实复活后，建立新的 gate 与 actor 普通对象身份，使用复活后的当前 HP/MP；不消费旧快照，也不重发 SceneReady/Start/刷怪。失败复活可保留原 owner，返回、换档或更换世界则撤销；旧 gate、意图及迟到清场均不能借复活复用。

相同或提高最大值保持 current 绝对值；降低普通资源最大值取 min(current,newMax)。原有 overflow 只服从有效的显式 cap；没有新 cap 合同则保留绝对值并诊断，不猜 1.5/2 倍，不延长击溃最大值损失。

## 完成通知与特殊路径

普通 StageManager 用 scene setup 和 actor ready 两条件汇合；先发原签名 SceneReady，再 Start，再 spawner.init。相机绑定、SceneReady、Start 可能同步重入，每次之后重验 world/run/substage/actor。发布标记先于回调。基地只保留 SceneReady；原加载主角和战宠没有世界 Ready 所有权。后续换装、成长和损伤不重放出生完成通知。

场景状态使用 `__playerSceneGate`、`__playerSceneSpawn` 与独立普通对象 `__playerSceneActorIdentity`。资源在尾部只结算一次，成功后清除 spawn 的消费 handle；随后到完成通知之间允许合法付款、治疗和伤害。完成通知检查当前 HP/MP 和最终上限有效，不保存 `finalHp/finalMp` 并要求全等。NaN、负 MP、死亡 HP 或非法上限仍不放行；MP=0 和 Lee 的 MP/max=0 保持合法。

主角就绪只以 gate 的 `actorReady` 占位，不另存同步重复的 `spawn.readyNotified`。资源已结算的 `resourcesReady`、场景已发布的 `published` 与刷怪已启动的 `started` 分别对应不同阶段，不能合并。正常与失败路径共用同一身份谓词；正常路径额外拒绝失败 gate，失败出口仍须识别原 owner。

出生失败是场景终态：同步 scene scope、延迟状态/模式尾部和就绪回调异常都通知同一场景 owner。先阻止 setup/Start，再在下一帧交给现有失败出口，避免在属性提交栈内卸载世界；这不是用延迟判断就绪。通知只属于原 world/context/slot/run，重复或过期通知无效。已进入游戏的换装、成长失败继续由对应事务恢复。

初次进场由 `CharacterCreationService` 发送 `scene_initialization_failed`（v=1、attemptId、slotKey、reason）；Host 仅接受当前已派发且尚未进入场景的 load/create 请求，进入已有错误/重试界面，禁止把失败当成 ready，也不重放存档写入。普通关卡复用 StageManager 的失败返回，基地复用“加载失败”页。新 Host 未部署时仍保留原超时兜底，因此提前报错须使用匹配的隔离候选验证。

SceneReady/Start 之前先占用发布标记，监听器异常后不清标记重放。仅在这处冷路径建立 EventBus 恢复令牌，在 catch 中恢复自身进入后的 dispatch depth，不清外层发布栈、不改变热事件总线。

Lee 使用敌人模板外层尾部，MP=0/max=0 合法；Warlord Action 保留战略比例投影；calibration 无主角模式保留原路径。未登记的作弊 identifier 不获得连续资源合同。佣兵按本次快照的槽位、用户 ID、名字在完整模板尾部仅恢复 HP；延迟任务绑定原世界。宠物保持原合同。

Titanium 初始维护 tick 等完整属性和转场资源完成。HealApplier 校验原始有限数值并保留治疗公式；技能在许可回调之前与实际付款之前均检查最终余额/费用。百分比装备在产生资源效果前完成付款。

## 回归与交付边界

```powershell
node tools/resource-transfer/run-source-tests.js <输出JSON路径>
node tools/resource-transfer/test-scene-ready.js
node tools/resource-transfer/test-scene-failure.js
powershell -File scripts/run-resource-transfer-tests.ps1 -TimeoutSeconds 600
```

Node 只执行提取的生产函数，使用明确的 Key 端口覆盖四方向按下/松开和出口受理；原生 Key.isDown 不能通过赋值替换，不能把这种替身当作真实键盘输入。原生两组测试使用真实类、MovieClip 和完整初始化协调器，run/Host 仍有内存夹具。原生出口回归覆盖旧箭头调用序列的拒绝、实际 StageManager 接管后的受理、鼠标点击与几何命中、源世界更替、错误 substage、合法溢出与非法 MP。专用原生工程另使用主 XFL 的原始淡出脚本时间轴，普通 focused runner 使用同步淡出替身并标明证据类型。它们均不代签完整角色素材的延迟首帧、Player20、实际游戏或 NativeHUD。

发布前仍须目标 CS6 新鲜 Compiler 0/0、asLoader 刷新及类/字节码归属；正式 Player20 数值/时序探针；普通 A→B→C 的残血、溢出、MP0/180%、淡出变化和失败矩阵；Lee、Warlord、calibration、Titanium、NativeHUD 首包；再与玩家属性投影的未验清单一并验收。未满足时保持未发布状态。

`PlayerResourceTransferBridgeTest` 保留原 suite 名称以沿用回归入口，测试对象已是 `PlayerSceneLifecycle`。新增合批等待期间真实资源扣费后正常通知、首次关卡与基地不创建转场数据的断言；源码通知探针不代签 AVM1。

场景 owner、调用点、出生字段、完整模板 hook 与消费者字段接线是一个回滚单元；既有负拳力公式、首次 pending 通知修复和打包缺文件修复独立保留。不要回滚成坏值补满。
