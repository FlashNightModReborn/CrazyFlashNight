/*
================================================================================
                        主角模板数值buff系统重构规划
================================================================================

重构目标：将现有的主角模板数值buff系统迁移到新的BuffManager架构
重构方式：采用事件驱动的级联系统，与现有EventDispatcher体系深度集成

一、架构设计
------------
1. 核心组件：
   - BuffManager：管理Buff的增删改查和生命周期
   - PropertyContainer：处理属性值的计算和缓存
   - EventDispatcher：处理属性变化事件和级联触发
   - CascadeComponent：处理各类属性的级联逻辑

2. 数据流：
   Buff应用 → PropertyContainer计算 → 发布propertyChanged事件 →
   CascadeComponent响应 → 触发级联操作（如初始化射击函数）

二、迁移计划
------------
第一阶段：基础架构集成（保持向后兼容）
  - 在BuffManagerInitializer中添加事件发布机制
  - 创建BuffCascadeEventComponent基础组件
  - 保留现有主角模板数值buff作为备份

第二阶段：级联组件开发
  - WeaponCascadeComponent：处理武器威力变化的级联
    * 长枪威力 → 初始化长枪射击函数()
    * 手枪威力 → 初始化手枪射击函数() + 初始化双枪射击函数()
    * 手枪2威力 → 初始化手枪2射击函数() + 初始化双枪射击函数()
    * 刀锋利度 → 直接赋值（无级联）

  - MovementCascadeComponent：处理速度变化的级联
    * 速度 → 更新行走X/Y速度、跑步速度、跳跃速度、起跳速度

  - DefenseCascadeComponent：处理防御相关级联
    * 防御力 → 直接赋值
    * 魔法抗性 → 遍历所有魔法类型更新

  - VitalsCascadeComponent：处理生命值相关
    * hp满血值 → 检查是否需要更新当前hp
    * mp满血值 → 检查是否需要更新当前mp

第三阶段：特殊处理
  - 支持嵌套属性（如"长枪属性.power"）
  - 魔法抗性的对象型属性处理
  - 限时Buff的定时器管理迁移

第四阶段：完全迁移
  - 替换所有buff.赋值()调用为buffManager.addBuff()
  - 替换所有buff.调整()调用为buffManager.addBuff()（累加型）
  - 替换所有buff.限时赋值()为带TimeLimitComponent的MetaBuff
  - 废弃主角模板数值buff类

三、级联规则映射表
-----------------
属性名称        → 级联操作
长枪威力        → 初始化长枪射击函数()
手枪威力        → 初始化手枪射击函数() + 初始化双枪射击函数()
手枪2威力       → 初始化手枪2射击函数() + 初始化双枪射击函数()
刀锋利度        → 无
空手攻击力      → 无
伤害加成        → 无
防御力          → 无
魔法抗性        → 遍历更新所有魔法伤害类型
hp满血值        → 判断并更新当前hp（如果需要）
mp满血值        → 判断并更新当前mp（如果需要）
速度            → 【已迁移到BuffManager】映射到行走X速度
                  - 行走Y/跑X/跑Y速度通过getter自动派生(SpeedDeriveInitializer)
                  - 起跳速度由换装初始器管理(DressupInitializer)，不参与buff
韧性系数        → 无
内力            → 无

四、兼容性保证
-------------
1. 过渡期保持双系统运行
2. 提供适配器模式转换旧API调用
3. 逐步迁移，每次只替换一个模块
4. 充分测试后再废弃旧系统

五、性能优化考虑
---------------
1. 使用脏标记避免重复计算
2. 批量更新时暂停事件发布，结束后统一触发
3. 缓存频繁访问的属性值
4. 使用对象池管理Buff实例

六、测试要点
-----------
1. 属性计算正确性（倍率、加算、上下限）
2. 级联触发完整性（所有武器初始化函数）
3. 限时Buff的定时清除
4. 内存泄漏检查（事件订阅清理）
5. 性能对比测试（新旧系统）

================================================================================
*/

// UnitUtil不再需要，起跳速度由换装初始器管理
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;

class 主角模板数值buff
{
	// 已桥接到BuffManager的属性列表（无级联操作的简单直接属性）
	// 注意：刀锋利度映射到刀属性.power，是嵌套属性，暂不桥接
	// 速度：映射到行走X速度，其他速度通过getter自动派生，起跳速度由换装初始器管理
	private static var 桥接属性:Object = {
		空手攻击力: true,
		伤害加成: true,
		防御力: true,
		韧性系数: true,
		内力: true,
		速度: true
	};
	/*
	buff的属性名种类分为：
		空手攻击力、伤害加成、防御力、魔法抗性、hp满血值、mp满血值、速度、长枪威力、手枪威力、刀锋利度、韧性系数。
	类型分为：
		倍率、加算。
	倍率数值默认为1，下限需大于0，示例： 1.5(即为 * 150%倍率)
	加算数值默认为0，允许负值，示例：100(即为+100)

	以下是实际场景代码示例。
	单次赋值的buff，无增减类型时会覆盖当前值，"增益"类型时会与当前值取最高，"减益"类型时会与当前值取最低。加算类可为负值，倍率类需大于0。加算类可规定最终buff值的百分比上下限，倍率型可规定最终buff值的加算值上下限：
	
		var buff属性名 = "防御力";
		var buff类型 = "倍率";
		var buff值 = 1.2;
		var buff增减类型 = "增益";
		var 对应buff值换算上限 = 500;
		var 对应buff值换算下限 = -300;
		自机.buff.赋值(buff属性名, buff类型, buff值, buff增减类型,对应buff值换算上限,对应buff值换算下限);
		
		以上五行的含义是：赋予 * 1.2倍 的防御力乘算buff，如果已有其他增益buff时取最大值，buff实际改变的防御力数值在增加500点和减少300点的范围之间，如果超出则以上下限重新计算倍率。也可简写为：
		自机.buff.赋值("防御力", "倍率", 1.2, "增益",500, -300);
		
		其中buff增减类型、换算上限、换算下限对应的最后三个参数可省略，但不建议省略。
		
		如果是限时类buff，则改用限时函数，且在第一个参数前添加时间参数，单位为毫秒，如以下持续10s的最大生命值减少200：
		自机.buff.限时赋值(10000, "hp满血值","加算", -200, "减益",0.5,-0.8);
		
		注意：此处是加算类型的buff，其中最后的换算上下限代表的不再是加算值上下区间，而是百分比上下区间，表示该buff值的影响比例会在 增加50% 到 减少80% 的区间范围内，如果超出则以上下限重新计算值。
		
	多次触发叠加的buff，需规定该buff的当前调整值，也可规定上限值、下限值。加算类均可为负值，如果是倍率类，调整值可为负值，但下限需大于0：
	
		var buff属性名 = "伤害加成";
		var buff类型 = "加算";
		var 调整值 = 20;
		var 上限值 = 300;
		var 下限值 = -300;
		自机.buff.调整(buff属性名, buff类型, 调整值, 上限值, 下限值);
		
		以上六行也可简写为：
		自机.buff.调整("伤害加成", "加算", 20, 300, -300);
		
		其中上限值和下限值对应的参数可省略，但不建议省略。
		如果是限时类buff，则改用限时函数，且在第一个参数前添加时间参数，单位为毫秒，如以下持续20s的空手攻击力减少10%，范围为30%-200%：
		自机.buff.限时调整(20000, "空手攻击力", "倍率", -0.1, 2, 0.3);
		
	限时类buff消耗更高且有bug隐患，应避免过于频繁使用，且非必要时不建议使用。
	限时类buff无法手动删除。非限时类的buff可以手动删除，需要传入属性名和buff类型，但多个buff叠加后的总值也会同时删除。格式如下：
		自机.buff.删除("防御力","倍率")
	*/
	var 自机;
	var 基础值;
	var buff倍率;
	var buff加算;
	var buff限时倍率;
	var buff限时加算;
	var buff限时id;
	function 主角模板数值buff(自机)
	{
		//_root.发布消息('已触发class');
		this.自机 = 自机;
		this.buff倍率 = {};
		this.buff加算 = {};
		this.buff限时倍率 = {};
		this.buff限时加算 = {};
		this.buff限时id = {};
		this.初始();
	}
	
	function 初始()
	{
		// 已桥接到BuffManager的属性不再在此读取，避免读到buff后的值污染基础值
		// 桥接属性列表：空手攻击力、伤害加成、防御力、韧性系数、内力、速度
		// 注意：刀锋利度映射到 刀属性.power（嵌套属性），暂不桥接
		// 速度：映射到行走X速度，起跳速度由换装初始器管理（依赖重量，不参与buff）
		this.基础值 = {
			// 以下属性已桥接到BuffManager，由PropertyAccessor管理
			// 空手攻击力、伤害加成、防御力、韧性系数、内力、速度(行走X速度)
			// （刀锋利度暂不桥接，因为它是嵌套属性 刀属性.power）

			// 以下属性仍由老系统管理（有级联操作或特殊处理）
			魔法抗性:{},
			hp满血值:this.自机.hp满血值,
			mp满血值:this.自机.mp满血值,
			长枪威力:this.自机.长枪属性.power,
			手枪威力:this.自机.手枪属性.power,
			手枪2威力:this.自机.手枪2属性.power,
			刀锋利度:this.自机.刀属性.power
		};

		for(var key in this.自机.魔法抗性){
			this.基础值.魔法抗性[key] = this.自机.魔法抗性[key];
		}
	}

	function 赋值(属性名, 类型, 数值, 增减类型, 换算上限, 换算下限)
	{
		// 桥接属性代理到BuffManager
		if (桥接属性[属性名]) {
			this.桥接赋值(属性名, 类型, 数值, 增减类型, 换算上限, 换算下限);
			return;
		}
		if (类型 == "倍率")
		{
			var 当前数值 = 增减类型==="增益"? (this.buff倍率[属性名] ? Math.max(this.buff倍率[属性名], 数值) : 数值) : 增减类型==="减益"? (this.buff倍率[属性名] || this.buff倍率[属性名] === 0 ? Math.min(this.buff倍率[属性名], 数值) : 数值): 数值;
			当前数值 = Math.max(Math.min((换算上限? 1 + 换算上限 / this.基础值[属性名] : 当前数值),当前数值),(换算下限? 1 + 换算下限 / this.基础值[属性名] : 当前数值));
			this.buff倍率[属性名] = 当前数值;
		}
		else if (类型 == "加算")
		{
			var 当前数值 = 增减类型==="增益"? (this.buff加算[属性名] ? Math.max(this.buff加算[属性名], 数值) : 数值) : 增减类型==="减益"? (this.buff加算[属性名] || this.buff加算[属性名] === 0 ? Math.min(this.buff加算[属性名], 数值) : 数值): 数值;
			当前数值 = Math.max(Math.min((换算上限? this.基础值[属性名] * 换算上限 : 当前数值),当前数值),(换算下限? this.基础值[属性名] * 换算下限 : 当前数值));
			this.buff加算[属性名] = 当前数值;
		}
		this.更新(属性名);
	}
	
	function 调整(属性名, 类型, 数值, 上限, 下限)
	{
		// 桥接属性代理到BuffManager
		if (桥接属性[属性名]) {
			this.桥接调整(属性名, 类型, 数值, 上限, 下限);
			return;
		}
		if (类型 == "倍率")
		{
			var 临时数值 = this.buff倍率[属性名] || this.buff倍率[属性名] === 0  ?  this.buff倍率[属性名] + 数值: 1 + 数值;
			this.buff倍率[属性名] = isNaN(上限) ? isNaN(下限)? 临时数值:Math.max(临时数值,下限) :isNaN(下限)? Math.min(临时数值,上限):Math.max( Math.min(临时数值,上限),下限);
		}
		else if (类型 == "加算")
		{
			var 临时数值 = this.buff加算[属性名] || this.buff加算[属性名] === 0  ?  this.buff加算[属性名] + 数值: 0 + 数值;
			this.buff加算[属性名] = isNaN(上限) ? isNaN(下限)? 临时数值:Math.max(临时数值,下限) :isNaN(下限)? Math.min(临时数值,上限):Math.max( Math.min(临时数值,上限),下限);
		}
		this.更新(属性名);
	}

	function 限时赋值(时间, 属性名, 类型, 数值, 增减类型, 换算上限, 换算下限)
	{
		// 桥接属性代理到BuffManager
		if (桥接属性[属性名]) {
			this.桥接限时赋值(时间, 属性名, 类型, 数值);
			return;
		}
		var 当前自机 = this.自机;
		var 当前任务id = _root.帧计时器.任务ID计数器 +1;
		if(this.buff限时id[当前任务id]){
			当前任务id += 1000 + random(1000);
		}
		this.buff限时id[当前任务id] = true;
		if (类型 == "倍率")
		{
			var 当前最大倍率 = this.buff限时倍率[属性名]? (this.buff倍率[属性名]?Math.max(this.buff限时倍率[属性名],this.buff倍率[属性名]): this.buff限时倍率[属性名]): this.buff倍率[属性名]? this.buff倍率[属性名]: 数值;
			var 当前最小倍率 = this.buff限时倍率[属性名]? (this.buff倍率[属性名]?Math.min(this.buff限时倍率[属性名],this.buff倍率[属性名]): this.buff限时倍率[属性名]): this.buff倍率[属性名]? this.buff倍率[属性名]: 数值;
			var 当前数值 = 增减类型==="增益"?  Math.max(当前最大倍率, 数值) : (增减类型==="减益"?  Math.min(当前最大倍率, 数值): 数值);
			当前数值 = Math.max(Math.min((换算上限? 1 + 换算上限 / this.基础值[属性名] : 当前数值),当前数值),(换算下限? 1 + 换算下限 / this.基础值[属性名] : 当前数值));
			this.buff限时倍率[属性名] = 当前数值;
			_root.帧计时器.添加或更新任务(this.自机, "主角限时倍率buff", function(){
				if(当前自机.buff.buff限时id[当前任务id]){
					delete 当前自机.buff.buff限时id[当前任务id];
					delete 当前自机.buff.buff限时倍率[属性名];
					当前自机.buff.更新(属性名);
				}
			},时间)
		}
		else if (类型 == "加算")
		{
			var 当前最大加算 = this.buff限时加算[属性名]? (this.buff加算[属性名]?Math.max(this.buff限时加算[属性名],this.buff加算[属性名]): this.buff限时加算[属性名]): this.buff加算[属性名]? this.buff加算[属性名]: 数值;
			var 当前最小加算 = this.buff限时加算[属性名]? (this.buff加算[属性名]?Math.min(this.buff限时倍率[属性名],this.buff倍率[属性名]): this.buff限时加算[属性名]): this.buff加算[属性名]? this.buff加算[属性名]: 数值;
			var 当前数值 = 增减类型==="增益"?  Math.max(当前最大加算, 数值) : (增减类型==="减益"?  Math.min(当前最大加算, 数值): 数值);
			当前数值 = Math.max(Math.min((换算上限? this.基础值[属性名] * 换算上限 : 当前数值),当前数值),(换算下限? this.基础值[属性名] * 换算下限 : 当前数值));
			this.buff限时加算[属性名] = 当前数值;
//_root.发布消息("当前buff值:" + this.buff限时加算[属性名] + "/" + 换算上限 + "/" + 换算下限 + "/差值：" + 当前数值 + "/" + 属性名 + "/任务id" + 当前任务id);
			_root.帧计时器.添加或更新任务(this.自机, "主角限时倍率buff", function(){
//_root.发布消息("帧计时器执行："+当前任务id+"/" + 当前自机.buff.buff限时加算[属性名] + "/" + 属性名);
				if(当前自机.buff.buff限时id[当前任务id]){
					delete 当前自机.buff.buff限时id[当前任务id];
					delete 当前自机.buff.buff限时加算[属性名];
					当前自机.buff.更新(属性名);
				}
			},时间)
		}
		this.更新(属性名);
	}
	
	function 限时调整(时间, 属性名, 类型, 数值, 上限, 下限)
	{
		// 桥接属性代理到BuffManager
		if (桥接属性[属性名]) {
			this.桥接限时调整(时间, 属性名, 类型, 数值);
			return;
		}
		var 当前自机 = this.自机;
		var 当前任务id = _root.帧计时器.任务ID计数器 +1;
		if(this.buff限时id[当前任务id]){
			当前任务id += 1000 + random(1000);
		}
		this.buff限时id[当前任务id] = true;
		if (类型 == "倍率")
		{
			var 当前buff数值 = this.buff限时倍率[属性名] || this.buff限时倍率[属性名] === 0 ? this.buff限时倍率[属性名]: ( this.buff倍率[属性名] || this.buff倍率[属性名] === 0 ? this.buff倍率[属性名]: 1);
			var 临时数值 = 当前buff数值 + 数值;
			this.buff限时倍率[属性名] = isNaN(上限) ? (isNaN(下限)? 临时数值:Math.max(临时数值,下限)) :(isNaN(下限)? Math.min(临时数值,上限):Math.max( Math.min(临时数值,上限),下限));
			var 差值 = this.buff限时倍率[属性名] - 当前buff数值;
//_root.发布消息("当前buff值:" + this.buff限时倍率[属性名] + "/" + 上限 + "/" + 下限 + "/差值：" + 差值 + "/" + 属性名 + "/任务id" + 当前任务id);
			_root.帧计时器.添加单次任务(function(){
//_root.发布消息("帧计时器执行："+当前任务id);
				if(当前自机.buff.buff限时id[当前任务id] && 当前自机.buff.buff限时倍率[属性名]){
					delete 当前自机.buff.buff限时id[当前任务id];
					当前自机.buff.buff限时倍率[属性名] -= 差值;
					if(当前自机.buff.buff限时倍率[属性名]===1){
						delete 当前自机.buff.buff限时倍率[属性名];
					}
					当前自机.buff.更新(属性名);
				}
			},时间)
		}
		else if (类型 == "加算")
		{
			var 当前buff数值 = this.buff限时加算[属性名] || this.buff限时加算[属性名] === 0 ? this.buff限时加算[属性名]: ( this.buff加算[属性名] || this.buff加算[属性名] === 0 ? this.buff加算[属性名]: 0);
			var 临时数值 = 当前buff数值 + 数值;
			this.buff限时加算[属性名] = isNaN(上限) ? isNaN(下限)? 临时数值:Math.max(临时数值,下限) :isNaN(下限)? Math.min(临时数值,上限):Math.max( Math.min(临时数值,上限),下限);
			var 差值 = this.buff限时加算[属性名] - 当前buff数值;
			_root.帧计时器.添加单次任务(function(){
				if(当前自机.buff.buff限时id[当前任务id] && 当前自机.buff.buff限时加算[属性名]){
					delete 当前自机.buff.buff限时id[当前任务id];
					当前自机.buff.buff限时加算[属性名] -= 差值;
					if(当前自机.buff.buff限时加算[属性名]===0){
						delete 当前自机.buff.buff限时加算[属性名];
					}
					当前自机.buff.更新(属性名);
				}
			},时间)
		}
		this.更新(属性名);
	}

	function 删除(属性名,类型)
	{
		if (属性名 && 属性名 != '全部')
		{
			// 桥接属性代理到BuffManager
			if (桥接属性[属性名]) {
				this.桥接删除(属性名, 类型);
				return;
			}
			if(类型 == "倍率"){
				delete this.buff倍率[属性名];
				this.更新(属性名);
			}else if(类型 == "加算"){
				delete this.buff加算[属性名];
				this.更新(属性名);
			}
		}else{
			// 删除全部时，也要清理BuffManager中的桥接buff
			this.桥接删除全部();
			if(类型 == "倍率"){
				this.buff倍率 = {};
				this.更新('全部');
			}else if(类型 == "加算"){
				this.buff加算 = {};
				this.更新('全部');
			}else if(!类型 || 类型 == "全部"){
				this.buff倍率 = {};
				this.buff加算 = {};
				this.更新('全部');
			}
		}
	}

	function 更新(属性名)
	{
		var 计算buff倍率 = {};
		var 计算buff加算 = {};
		if (属性名 && 属性名 != '全部')
		{
			计算buff倍率[属性名] = this.buff限时倍率[属性名] || this.buff限时倍率[属性名] === 0 ? this.buff限时倍率[属性名]: ( this.buff倍率[属性名] || this.buff倍率[属性名] === 0 ? this.buff倍率[属性名]: 1);
			计算buff加算[属性名] = this.buff限时加算[属性名] || this.buff限时加算[属性名] === 0 ? this.buff限时加算[属性名]: ( this.buff加算[属性名] || this.buff加算[属性名] === 0 ? this.buff加算[属性名]: 0);
			if (属性名 == '长枪威力')
			{
				this.自机.长枪属性.power = this.基础值.长枪威力 * 计算buff倍率.长枪威力 + 计算buff加算.长枪威力;
				if(this.自机.man.初始化长枪射击函数){
					this.自机.man.初始化长枪射击函数();
				}
			}
			else if (属性名 == '手枪威力')
			{
				this.自机.手枪属性.power = this.基础值.手枪威力 * 计算buff倍率.手枪威力 + 计算buff加算.手枪威力;
				if(this.自机.man.初始化手枪射击函数){
					this.自机.man.初始化手枪射击函数();
				}
				if(this.自机.man.初始化双枪射击函数){
					this.自机.man.初始化双枪射击函数();
				}
			}
			else if (属性名 == '手枪2威力')
			{
				this.自机.手枪2属性.power = this.基础值.手枪2威力 * 计算buff倍率.手枪2威力 + 计算buff加算.手枪2威力;
				if(this.自机.man.初始化手枪2射击函数){
					this.自机.man.初始化手枪2射击函数();
				}
				if(this.自机.man.初始化双枪射击函数){
					this.自机.man.初始化双枪射击函数();
				}
			}
			else if (属性名 == '刀锋利度')
			{
				this.自机.刀属性.power = this.基础值.刀锋利度 * 计算buff倍率.刀锋利度 + 计算buff加算.刀锋利度;
			}
			else if (属性名 == '魔法抗性')
			{
				for (var key in this.自机.魔法抗性)
				{
						//_root.发布消息(key + "/基础值：" + this.基础值.魔法抗性[key]);
					this.自机.魔法抗性[key] = this.基础值.魔法抗性[key] * 计算buff倍率.魔法抗性 + 计算buff加算.魔法抗性;
						//_root.发布消息(key + "/" + this.自机.魔法抗性[key] +"/"+this.基础值.魔法抗性[key]+"/"+计算buff倍率.魔法抗性+"/"+计算buff加算.魔法抗性);
				}
			}
			else if (桥接属性[属性名])
			{
				// 桥接属性由BuffManager管理，跳过老系统的更新
			}
			else
			{
				this.自机[属性名] = this.基础值[属性名] * 计算buff倍率[属性名] + 计算buff加算[属性名];
			}
//_root.发布消息('当前'+属性名+"："+ this.自机[属性名] + "/当前倍率：" + 计算buff倍率[属性名] + "/当前加算：" + 计算buff加算[属性名]);
		}
		else
		{
			for (var 属性名key in this.基础值)
			{
				计算buff倍率[属性名key] = this.buff限时倍率[属性名key] || this.buff限时倍率[属性名key] === 0 ? this.buff限时倍率[属性名key]: ( this.buff倍率[属性名key] || this.buff倍率[属性名key] === 0 ? this.buff倍率[属性名key]: 1);
				计算buff加算[属性名key] = this.buff限时加算[属性名key] || this.buff限时加算[属性名key] === 0 ? this.buff限时加算[属性名key]: ( this.buff加算[属性名key] || this.buff加算[属性名key] === 0 ? this.buff加算[属性名key]: 0);
				if (属性名key == '长枪威力')
				{
					this.自机.长枪属性.power = this.基础值.长枪威力 * 计算buff倍率.长枪威力 + 计算buff加算.长枪威力;
					if(this.自机.man.初始化长枪射击函数){
						this.自机.man.初始化长枪射击函数();
					}
				}
				else if (属性名key == '手枪威力')
				{
					this.自机.手枪属性.power = this.基础值.手枪威力 * 计算buff倍率.手枪威力 + 计算buff加算.手枪威力;
					if(this.自机.man.初始化手枪射击函数){
						this.自机.man.初始化手枪射击函数();
					}
					if(this.自机.man.初始化双枪射击函数){
						this.自机.man.初始化双枪射击函数();
					}
				}
				else if (属性名key == '手枪2威力')
				{
					this.自机.手枪2属性.power = this.基础值.手枪2威力 * 计算buff倍率.手枪2威力 + 计算buff加算.手枪2威力;
					if(this.自机.man.初始化手枪2射击函数){
						this.自机.man.初始化手枪2射击函数();
					}
					if(this.自机.man.初始化双枪射击函数){
						this.自机.man.初始化双枪射击函数();
					}
				}
				else if (属性名key == '刀锋利度')
				{
					this.自机.刀属性.power = this.基础值.刀锋利度 * 计算buff倍率.刀锋利度 + 计算buff加算.刀锋利度;
				}
				else if (属性名key == '魔法抗性')
				{
					for (var key in this.自机.魔法抗性)
					{
						this.自机.魔法抗性[key] = this.基础值.魔法抗性[key] * 计算buff倍率.魔法抗性 + 计算buff加算.魔法抗性;
					}
				}
				else
				{
					// 速度已桥接到BuffManager，跳过老系统的更新
					this.自机[属性名key] = this.基础值[属性名key] * 计算buff倍率[属性名key] + 计算buff加算[属性名key];
				}
			}
		}
	}

	// =========================================================================
	// 桥接函数：将老API调用转换为BuffManager操作
	//
	// 设计原则：
	// 1. 语义对齐：老系统"累加到同一个值"→ 新系统"业务层累加 + 同ID替换"
	// 2. 增益/减益：保留原有逻辑（取max/min）
	// 3. 帧率：使用 _root.帧计时器.帧率，避免硬编码
	// 4. fallback：buffManager未就绪时走老逻辑
	// =========================================================================

	// 桥接用的累加值缓存（与老系统的buff倍率/buff加算对应）
	private var 桥接buff倍率:Object;
	private var 桥接buff加算:Object;

	/**
	 * 确保桥接缓存已初始化
	 */
	private function 确保桥接缓存():Void
	{
		if (!this.桥接buff倍率) this.桥接buff倍率 = {};
		if (!this.桥接buff加算) this.桥接buff加算 = {};
	}

	/**
	 * 获取桥接属性的基础值
	 * 从PropertyContainer获取，或从自机属性获取原始值
	 */
	private function 获取桥接基础值(属性名:String):Number
	{
		var 目标属性:String = this.获取目标属性名(属性名);
		var buffManager:BuffManager = this.自机.buffManager;
		if (buffManager) {
			// 从BuffManager的PropertyContainer获取基础值
			var container:PropertyContainer = buffManager.getPropertyContainer(目标属性);
			if (container) {
				return container.getBaseValue();
			}
		}
		// 回退到自机当前属性值（注意：这可能已经被buff修改过）
		return this.自机[目标属性] || 0;
	}

	/**
	 * 毫秒转帧数（使用实际帧率）
	 */
	private function 毫秒转帧数(毫秒:Number):Number
	{
		var fps:Number = _root.帧计时器.帧率 || 30;
		return Math.ceil(毫秒 / 1000 * fps);
	}

	/**
	 * 获取属性名到实际目标属性的映射
	 * 速度 -> 行走X速度（其他速度通过getter自动派生）
	 */
	private function 获取目标属性名(属性名:String):String
	{
		if (属性名 == "速度") return "行走X速度";
		return 属性名;
	}

	/**
	 * 应用桥接buff到BuffManager
	 * 使用同一buffId替换，实现"业务层累加值"的语义
	 */
	private function 应用桥接Buff(属性名:String, 类型:String):Void
	{
		var buffManager:BuffManager = this.自机.buffManager;
		if (!buffManager) return;

		var buffId:String = "老buff_" + 属性名 + "_" + 类型;
		var 目标属性:String = this.获取目标属性名(属性名);
		var calcType:String;
		var value:Number;

		if (类型 == "倍率") {
			value = this.桥接buff倍率[属性名];
			if (value == undefined || value == 1) {
				// 倍率为1或未设置，移除buff
				buffManager.removeBuff(buffId);
				buffManager.update(0);
				return;
			}
			// 老系统倍率是直接乘数(如1.2)，对应MULTIPLY
			calcType = BuffCalculationType.MULTIPLY;
		} else {
			value = this.桥接buff加算[属性名];
			if (value == undefined || value == 0) {
				// 加算为0或未设置，移除buff
				buffManager.removeBuff(buffId);
				buffManager.update(0);
				return;
			}
			calcType = BuffCalculationType.ADD;
		}

		var podBuff:PodBuff = new PodBuff(目标属性, calcType, value);
		var childBuffs:Array = [podBuff];
		var components:Array = [];
		var metaBuff:MetaBuff = new MetaBuff(childBuffs, components, 0);

		buffManager.addBuff(metaBuff, buffId);
		buffManager.update(0);
	}

	/**
	 * 桥接赋值 - 将赋值操作代理到BuffManager
	 * 保留增益/减益逻辑和上下限换算
	 *
	 * @param 属性名 目标属性
	 * @param 类型 "倍率" 或 "加算"
	 * @param 数值 buff值
	 * @param 增减类型 "增益"/"减益"/null
	 * @param 换算上限 可选，限制buff效果的上限值
	 * @param 换算下限 可选，限制buff效果的下限值
	 */
	function 桥接赋值(属性名:String, 类型:String, 数值:Number, 增减类型:String, 换算上限:Number, 换算下限:Number):Void
	{
		var buffManager:BuffManager = this.自机.buffManager;
		if (!buffManager) {
			// fallback到老逻辑（但由于基础值已移除，这里只能警告）
			trace("警告: buffManager未就绪，桥接属性" + 属性名 + "的赋值操作被忽略");
			return;
		}

		this.确保桥接缓存();

		// 获取基础值用于换算上下限
		var 基础值:Number = this.获取桥接基础值(属性名);

		if (类型 == "倍率") {
			var 当前倍率:Number = this.桥接buff倍率[属性名];
			var 新倍率:Number;
			if (增减类型 === "增益") {
				新倍率 = (当前倍率 != undefined) ? Math.max(当前倍率, 数值) : 数值;
			} else if (增减类型 === "减益") {
				新倍率 = (当前倍率 != undefined) ? Math.min(当前倍率, 数值) : 数值;
			} else {
				新倍率 = 数值;
			}
			// 换算上下限：老系统倍率换算公式 = 1 + 换算值/基础值
			// 例如：基础值100，换算上限500 => 倍率上限 = 1 + 500/100 = 6
			if (!isNaN(换算上限) && 基础值 != 0) {
				var 倍率上限:Number = 1 + 换算上限 / 基础值;
				新倍率 = Math.min(新倍率, 倍率上限);
			}
			if (!isNaN(换算下限) && 基础值 != 0) {
				var 倍率下限:Number = 1 + 换算下限 / 基础值;
				新倍率 = Math.max(新倍率, 倍率下限);
			}
			this.桥接buff倍率[属性名] = 新倍率;
		} else {
			var 当前加算:Number = this.桥接buff加算[属性名];
			var 新加算:Number;
			if (增减类型 === "增益") {
				新加算 = (当前加算 != undefined) ? Math.max(当前加算, 数值) : 数值;
			} else if (增减类型 === "减益") {
				新加算 = (当前加算 != undefined) ? Math.min(当前加算, 数值) : 数值;
			} else {
				新加算 = 数值;
			}
			// 加算的换算上下限：老系统加算换算公式 = 基础值 * 换算值
			// 例如：基础值100，换算上限5 => 加算上限 = 100 * 5 = 500
			if (!isNaN(换算上限) && 基础值 != 0) {
				var 加算上限:Number = 基础值 * 换算上限;
				新加算 = Math.min(新加算, 加算上限);
			}
			if (!isNaN(换算下限) && 基础值 != 0) {
				var 加算下限:Number = 基础值 * 换算下限;
				新加算 = Math.max(新加算, 加算下限);
			}
			this.桥接buff加算[属性名] = 新加算;
		}

		this.应用桥接Buff(属性名, 类型);
	}

	/**
	 * 桥接调整 - 将调整操作代理到BuffManager
	 * 累加到同一个值，然后用同ID替换buff
	 *
	 * @param 属性名 目标属性
	 * @param 类型 "倍率" 或 "加算"
	 * @param 数值 调整值（增量）
	 * @param 上限 可选，调整后的值上限
	 * @param 下限 可选，调整后的值下限
	 */
	function 桥接调整(属性名:String, 类型:String, 数值:Number, 上限:Number, 下限:Number):Void
	{
		var buffManager:BuffManager = this.自机.buffManager;
		if (!buffManager) {
			trace("警告: buffManager未就绪，桥接属性" + 属性名 + "的调整操作被忽略");
			return;
		}

		this.确保桥接缓存();

		if (类型 == "倍率") {
			// 老系统倍率调整是增量(如+0.1)，基础值是1
			var 当前倍率:Number = this.桥接buff倍率[属性名];
			if (当前倍率 == undefined) 当前倍率 = 1;
			var 新倍率:Number = 当前倍率 + 数值;
			// 应用上下限
			if (!isNaN(上限)) 新倍率 = Math.min(新倍率, 上限);
			if (!isNaN(下限)) 新倍率 = Math.max(新倍率, 下限);
			this.桥接buff倍率[属性名] = 新倍率;
		} else {
			// 加算调整是增量，基础值是0
			var 当前加算:Number = this.桥接buff加算[属性名];
			if (当前加算 == undefined) 当前加算 = 0;
			var 新加算:Number = 当前加算 + 数值;
			// 应用上下限
			if (!isNaN(上限)) 新加算 = Math.min(新加算, 上限);
			if (!isNaN(下限)) 新加算 = Math.max(新加算, 下限);
			this.桥接buff加算[属性名] = 新加算;
		}

		this.应用桥接Buff(属性名, 类型);
	}

	/**
	 * 桥接限时赋值 - 将限时赋值操作代理到BuffManager
	 * 使用TimeLimitComponent实现自动过期
	 * 限时buff使用唯一ID，允许多个同属性限时buff叠加
	 *
	 * @param 时间 持续时间（毫秒）
	 * @param 属性名 目标属性
	 * @param 类型 "倍率" 或 "加算"
	 * @param 数值 buff值
	 */
	function 桥接限时赋值(时间:Number, 属性名:String, 类型:String, 数值:Number):Void
	{
		var buffManager:BuffManager = this.自机.buffManager;
		if (!buffManager) {
			trace("警告: buffManager未就绪，桥接属性" + 属性名 + "的限时赋值操作被忽略");
			return;
		}

		var frames:Number = this.毫秒转帧数(时间);
		var buffId:String = "老buff限时_" + 属性名 + "_" + 类型 + "_" + getTimer();
		var 目标属性:String = this.获取目标属性名(属性名);

		var calcType:String;
		if (类型 == "倍率") {
			calcType = BuffCalculationType.MULTIPLY;
		} else {
			calcType = BuffCalculationType.ADD;
		}

		var podBuff:PodBuff = new PodBuff(目标属性, calcType, 数值);
		var childBuffs:Array = [podBuff];
		var timeLimitComp:TimeLimitComponent = new TimeLimitComponent(frames);
		var components:Array = [timeLimitComp];
		var metaBuff:MetaBuff = new MetaBuff(childBuffs, components, 0);

		buffManager.addBuff(metaBuff, buffId);
		buffManager.update(0);
	}

	/**
	 * 桥接限时调整 - 将限时调整操作代理到BuffManager
	 * 使用TimeLimitComponent实现自动过期
	 * 限时调整的倍率使用PERCENT模式：result *= (1 + value)
	 *
	 * @param 时间 持续时间（毫秒）
	 * @param 属性名 目标属性
	 * @param 类型 "倍率" 或 "加算"
	 * @param 数值 调整值（增量）
	 */
	function 桥接限时调整(时间:Number, 属性名:String, 类型:String, 数值:Number):Void
	{
		var buffManager:BuffManager = this.自机.buffManager;
		if (!buffManager) {
			trace("警告: buffManager未就绪，桥接属性" + 属性名 + "的限时调整操作被忽略");
			return;
		}

		var frames:Number = this.毫秒转帧数(时间);
		var buffId:String = "老buff限时调整_" + 属性名 + "_" + 类型 + "_" + getTimer();
		var 目标属性:String = this.获取目标属性名(属性名);

		var calcType:String;
		if (类型 == "倍率") {
			// 限时调整的倍率是增量(如+0.1变成1.1倍)
			// PERCENT模式：result *= (1 + value)，正好匹配
			calcType = BuffCalculationType.PERCENT;
		} else {
			calcType = BuffCalculationType.ADD;
		}

		var podBuff:PodBuff = new PodBuff(目标属性, calcType, 数值);
		var childBuffs:Array = [podBuff];
		var timeLimitComp:TimeLimitComponent = new TimeLimitComponent(frames);
		var components:Array = [timeLimitComp];
		var metaBuff:MetaBuff = new MetaBuff(childBuffs, components, 0);

		buffManager.addBuff(metaBuff, buffId);
		buffManager.update(0);
	}

	/**
	 * 桥接删除 - 删除指定属性的老buff
	 *
	 * @param 属性名 目标属性
	 * @param 类型 "倍率" 或 "加算"
	 */
	function 桥接删除(属性名:String, 类型:String):Void
	{
		this.确保桥接缓存();

		// 清除缓存
		if (类型 == "倍率") {
			delete this.桥接buff倍率[属性名];
		} else {
			delete this.桥接buff加算[属性名];
		}

		var buffManager:BuffManager = this.自机.buffManager;
		if (!buffManager) return;

		// 删除对应的buffId
		var buffId:String = "老buff_" + 属性名 + "_" + 类型;
		buffManager.removeBuff(buffId);
		buffManager.update(0);
	}

	/**
	 * 桥接删除全部 - 删除所有桥接属性的老buff
	 * 注意：限时类buff会自动过期，这里只删除非限时的赋值/调整类buff
	 */
	function 桥接删除全部():Void
	{
		// 清除所有桥接缓存
		this.桥接buff倍率 = {};
		this.桥接buff加算 = {};

		var buffManager:BuffManager = this.自机.buffManager;
		if (!buffManager) return;

		// 遍历所有桥接属性，删除对应的buff
		for (var prop:String in 桥接属性) {
			buffManager.removeBuff("老buff_" + prop + "_倍率");
			buffManager.removeBuff("老buff_" + prop + "_加算");
		}
		buffManager.update(0);
	}

	function 卸载()
	{
		// 清除桥接缓存
		this.桥接buff倍率 = {};
		this.桥接buff加算 = {};
		this.桥接删除全部();

		this.buff倍率 = {};
		this.buff加算 = {};
		this.buff限时倍率 = {};
		this.buff限时加算 = {};
		this.更新('全部');
	}
}