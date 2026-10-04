# 大学怪物时间轴专项

此专项加载 `flashswf/arts/new/大学人员.swf` 中实际导出的黑铁派学员、剑道社社员，播放其 AVM1 时间轴，并调用生产 `BladeShootCore`、敌人行走/移动与攻击位移函数、`Mover` 和追击 `EnemyAI`。
初始化、纸娃娃装载、出弹接收端及空碰撞平面使用隔离夹具；不读取玩家档案，不写存档，不替代实际关卡的障碍碰撞、伤害结算或肉鸽整体验收。

## 先发布对应资源

```powershell
chcp.com 65001 > $null
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target 'flashswf/arts/new/大学人员/大学人员.xfl' -PublishOnly -VerifySwf 'flashswf/arts/new/大学人员.swf' -TimeoutSeconds 180
```

要求本轮 Compiler Errors `0/0`、正确 SWF 刷新。不能以主文件或 asLoader 的发布代替此目标。迁移源工程后，原 FLA 只在原生发布与回读验证通过前保留；随后以完整 XFL 为唯一编辑源。

## 专项行为回归

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-runners/run-focused-testloader.ps1 -DomainId university-enemies -TemplateRelativePath 'scripts/test-runners/university-enemies/TestLoader.as.template' -SuiteRelativePaths 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/UniversityEnemyAssetTest.as' -SuiteFqns 'org.flashNight.arki.unit.Action.Melee.UniversityEnemyAssetTest' -ExpectedTracePatterns 'UniversityEnemyAssetTest: \d+ passed, 0 failed; 96 actual timeline cases' -SuccessSummary '大学怪物实际时间轴专项通过' -TimeoutSeconds 240 -AsyncBehaviorTimeoutSeconds 30
```

统一 runner 负责 TestLoader scratch 的备份、唯一 runId、编译锁、新鲜 trace 和恢复。不要直接覆盖现有 TestLoader.as，不要删除异常 marker 后继续编译。

96 个实际时间轴案例包括：

- 两个导出角色、男女、左右朝向与六套动作，共 48 个连招案例。
- 短攻击入口 4 个、原有被动和 MP 攻击加成公式 2 个。
- 迅捷、直剑、长刀分类回退 6 个。
- 受击、死亡、移除和目标死亡中断 8 个。
- 四向行走、左右跑步与真实 AI 追击 28 个，覆盖两个角色和男女；同时检查暂停、恢复及清空方向标志后的停步。

完整连招的出弹接收次数为 33 / 57 / 48 / 36 / 60 / 54，对应通用、狂野、长柄、刀剑、长枪、长棍。计数包含每次刀口发射和每个区域发射请求；区域发射中的霰弹值保持原值，不将接收次数当作实际命中次数。

检查五段顺序、完整命中窗口、有限坐标和威力、区域来源、实际坐标位移、收招、行走载体消费 AI 方向标志及中断后无迟到出弹。旧索敌循环停用，但行走载体必须保留：新 AI 只设置方向标志，坐标更新仍由载体每帧调用行走函数。

专项通过仅证明上述合同。剑道社 539 帧之后的独立战技没有接入本次敌人技能池，本次不为其新增玩法、伤害或 AI 决策。
