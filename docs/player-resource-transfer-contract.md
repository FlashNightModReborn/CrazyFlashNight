# 普通战斗转场资源合同

本实现依赖同批玩家属性投影的 PlayerStatRefreshCoordinator 完整初始化屏障。HP/MP 权威仍在 actor，只有转场边界创建一次性内存快照。

## 受理、清场和消费

门/nextStage 先冻结 run、context、slot、源 world/actor 普通对象身份及目标 substage；fade 返回 true 或 prepareDoor 成功后才登记意图，拒绝不替换旧 owner。药剂、治疗和淡出期间的正常资源变化不撤销意图。

普通无限过图的绿色箭头由 `flashswf/levels/wuxianguotu_1.swf` 内的门处理，其本地 `切换场景` 函数不是全局门函数。StageManager 在通关开放出口之前绑定该门，保留方向键、鼠标点击和双重命中检查，经实际 `nextStage` 受理后才停门动画。绑定持有源 world 普通对象身份，旧出口回调不能操作同名重建的世界；不得依赖早于子元件首帧的赋值，也不得让旧脚本直接淡出绕过意图登记。

SceneManager 在 Loot 收敛及 placement 预检后、第一次 release 前读取 HP/MP/旧最终最大值。整份校验失败保留旧世界并取消本次遮罩，不重试资源、不取旧数组。成功销毁后才提交；release/teardown 异常只撤销自己的票据，不能宣称已回滚清场。

拒绝原因区分转场身份和资源数值：缺失意图、run/world/actor/slot/substage 不匹配等记录具体字段并提示转场状态失效；仅资源样本非法提示生命或能量数据异常。身份检查不因 HP 溢出而放宽，有限的合法溢出仍按下述投影合同传递。

目标 attachMovie 的 initObject 带独立 actor identity。最终属性和外层状态跳转完成后，协调器在 derive/ready 之前调用资源 hook，先验证两项再同步写入、消费一次。普通对象身份隔离同名 MovieClip 重建。死亡、返回、换档、新生、新 run、关闭 run 撤销旧 generation。死亡仅保留同一世界、run、角色及已完成属性初始化的复活 owner。life authority 确认同一主角真实复活后，建立新的 gate 与 actor 普通对象身份，使用复活后的当前 HP/MP；不消费旧快照，也不重发 SceneReady/Start/刷怪。失败复活可保留原 owner，返回、换档或更换世界则撤销；旧 gate、意图及迟到清场均不能借复活复用。

相同或提高最大值保持 current 绝对值；降低普通资源最大值取 min(current,newMax)。原有 overflow 只服从有效的显式 cap；没有新 cap 合同则保留绝对值并诊断，不猜 1.5/2 倍，不延长击溃最大值损失。

## 完成通知与特殊路径

普通 StageManager 用 scene setup 和 actor ready 两条件汇合；先发原签名 SceneReady，再 Start，再 spawner.init。相机绑定、SceneReady、Start 可能同步重入，每次之后重验 world/run/substage/actor。发布标记先于回调。基地只保留 SceneReady；原加载主角和战宠没有世界 Ready 所有权。后续换装、成长和损伤不重放出生完成通知。

Lee 使用敌人模板外层尾部，MP=0/max=0 合法；Warlord Action 保留战略比例投影；calibration 无主角模式保留原路径。未登记的作弊 identifier 不获得连续资源合同。佣兵按本次快照的槽位、用户 ID、名字在完整模板尾部仅恢复 HP；延迟任务绑定原世界。宠物保持原合同。

Titanium 初始维护 tick 等完整属性和转场资源完成。HealApplier 校验原始有限数值并保留治疗公式；技能在许可回调之前与实际付款之前均检查最终余额/费用。百分比装备在产生资源效果前完成付款。

## 回归与交付边界

```powershell
node tools/resource-transfer/run-source-tests.js <输出JSON路径>
powershell -File scripts/run-resource-transfer-tests.ps1 -TimeoutSeconds 600
```

Node 只执行提取的生产函数，使用明确的 Key 端口覆盖四方向按下/松开和出口受理；原生 Key.isDown 不能通过赋值替换，不能把这种替身当作真实键盘输入。原生两组测试使用真实类、MovieClip 和完整初始化协调器，run/Host 仍有内存夹具。原生出口回归覆盖旧箭头调用序列的拒绝、实际 StageManager 接管后的受理、鼠标点击与几何命中、源世界更替、错误 substage、合法溢出与非法 MP。专用原生工程另使用主 XFL 的原始淡出脚本时间轴，普通 focused runner 使用同步淡出替身并标明证据类型。它们均不代签完整角色素材的延迟首帧、Player20、实际游戏或 NativeHUD。

发布前仍须目标 CS6 新鲜 Compiler 0/0、asLoader 刷新及类/字节码归属；正式 Player20 数值/时序探针；普通 A→B→C 的残血、溢出、MP0/180%、淡出变化和失败矩阵；Lee、Warlord、calibration、Titanium、NativeHUD 首包；再与玩家属性投影的未验清单一并验收。未满足时保持未发布状态。

边界服务、完整模板 hook 和 Ready 门是一个回滚单元；付款类型检查可单独保留。不要回滚成坏值补满。
