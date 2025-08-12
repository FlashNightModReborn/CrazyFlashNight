你好，Claude。我需要你的帮助来为一个基于 ActionScript 2.0 的游戏项目执行一次重要的代码重构。
你将扮演一位精通 ActionScript 2 和事件驱动架构的资深游戏程序员。
项目目标与背景
项目的核心目标是将旧有的攻击目标（仇恨）管理系统从直接属性赋值的方式，全面升级为事件驱动的模式。
目前，代码中大量存在类似 someObject.攻击目标 = "targetName"; 的硬编码。这种方式耦合度高，难以维护和扩展。
新的模式是，当一个单位的攻击目标发生变化时，它应该发布一个事件。其他关心此变化的系统（如 AI、UI）可以订阅这个事件来做出响应。
核心重构任务：从直接赋值到事件广播
你的核心任务是扫描指定的 ActionScript 文件，并将所有直接设置 攻击目标 属性的代码，替换为事件发布代码。
1. 旧的模式 (The "Before" state):
代码中你会看到以下几种模式：
设置一个具体目标:
code
Actionscript
// targetObject 是执行修改的对象
// enemyObject 是新的目标
targetObject.攻击目标 = enemyObject._name;
清空目标:
code
Actionscript
targetObject.攻击目标 = "无"; // "无" 在中文里意为 "None" or "Nothing"
三元表达式条件赋值:
code
Actionscript
targetObject.攻击目标 = (someCondition) ? enemyObject._name : "无";
2. 新的模式 (The "After" state):
你需要将上述代码替换为使用 dispatcher.publish() 的事件广播。我们定义两个关键事件：
"aggroSet": 用于设置或更新一个新的攻击目标。
"aggroClear": 用于清除当前的攻击目标。
假设每个拥有 攻击目标 属性的对象，现在也拥有一个名为 dispatcher 的事件分发器对象。dispatcher 负责处理事件的发布。
转换规则如下:
规则 A: 设置目标
旧代码: targetObject.攻击目标 = enemyObject._name;
新代码: targetObject.dispatcher.publish("aggroSet", targetObject, enemyObject);
解释:
"aggroSet" 是事件名称。
第一个参数 targetObject 是事件的发布者，也就是谁的仇恨目标改变了。
第二个参数 enemyObject 是新的攻击目标。注意，我们传递的是整个对象，而不仅仅是它的名字 (_name)，这样事件的订阅者可以获得更丰富的信息。
规则 B: 清空目标
旧代码: targetObject.攻击目标 = "无";
新代码: targetObject.dispatcher.publish("aggroClear", targetObject);
解释:
"aggroClear" 是事件名称。
第一个参数 targetObject 依然是事件的发布者。
规则 C: 条件赋值
旧代码: targetObject.攻击目标 = (enemy) ? enemy._name : "无";
新代码 (展开为 if/else):
code
Actionscript
if (enemy) {
    targetObject.dispatcher.publish("aggroSet", targetObject, enemy);
} else {
    targetObject.dispatcher.publish("aggroClear", targetObject);
}
需要修改的文件列表 (To-Do List)
以下是根据项目扫描得出的、需要你进行修改的文件和具体位置。请系统地处理以下每一个条目。
1. scripts/逻辑/单位函数/单位函数_lsy_敌人ai.as
* _parent.攻击目标 = _root.集中攻击目标; (约 60行)
* _parent.攻击目标 = "无"; (约 145行, 205行)
* _parent.攻击目标 = (enemy) ? enemy._name : "无"; (约 157行)
2. scripts/逻辑/单位函数/单位函数_fs_佣兵ai.as
* _parent.攻击目标 = "无"; (约 96行, 199行)
* _parent.攻击目标 = _root.集中攻击目标; (约 109行)
* _parent.攻击目标 = 最近的敌人名 ? 最近的敌人名 : "无"; (约 229行)
3. scripts/类定义/org/flashNight/arki/unit/UnitAI/EnemyBehavior.as
* self.攻击目标 = target._name; (约 68行)
* self.攻击目标 = "无"; (约 75行)
* self.攻击目标 = data.target.hp <= 0 ? "无" : data.target._name; (约 116行)
* data.self.攻击目标 = "无"; (约 177行, 191行)
4. scripts/类定义/org/flashNight/arki/unit/UnitAI/PickupEnemyBehavior.as
* self.攻击目标 = target_enemy._name; (约 43行)
* self.攻击目标 = "无"; (约 51行, 70行)
5. scripts/逻辑/单位函数/单位函数_fs_aka_玩家模板迁移.as
* this.攻击目标 = 敌人._name; (约 2478行)
* 攻击目标 = "无"; (约 2692行)
6. scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as
* this.攻击目标 = "无"; (约 525行)
* 攻击目标 = "无"; (约 691行)
7. scripts/逻辑/单位函数/单位函数_fs_ai与特效通用函数.as
* target.攻击目标 = (enemy) ? enemy._name : "无"; (约 16行)
8. scripts/逻辑/功能函数/功能函数_fs_导弹模板.as
* (约 55, 101 行等处) - 请检查此文件中所有对 攻击目标 的赋值并应用转换规则。
输出要求
请针对上面 "To-Do List" 中的每一个文件，提供完整的、被修改后的文件内容。在每个代码块前，请用 Markdown 标题注明文件的完整路径，例如：
code
Markdown
### `scripts/逻辑/单位函数/单位函数_lsy_敌人ai.as`
code
Actionscript
// ... (完整的、修改后的文件内容) ...```

请开始执行任务。