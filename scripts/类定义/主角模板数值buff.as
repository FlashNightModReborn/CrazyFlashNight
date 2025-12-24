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
速度            → 更新以下所有：
                  - 行走X速度 = 基础速度 * 倍率 + 加算
                  - 跳跃中移动速度 = 行走X速度
                  - 行走Y速度 = 行走X速度 / 2
                  - 跑X速度 = 行走X速度 * 2
                  - 跑Y速度 = 行走X速度
                  - 起跳速度 = -10 * 重量速度关系(重量, 等级)
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

import org.flashNight.arki.unit.UnitUtil;

class 主角模板数值buff
{
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
		this.基础值 = {
			空手攻击力:this.自机.空手攻击力, 
			伤害加成:this.自机.伤害加成, 
			防御力:this.自机.防御力, 
			//魔法抗性:this.自机.魔法抗性, 
			魔法抗性:{}, 
			hp满血值:this.自机.hp满血值, 
			mp满血值:this.自机.mp满血值, 
			速度:this.自机.行走X速度, 
			长枪威力:this.自机.长枪属性.power, 
			手枪威力:this.自机.手枪属性.power, 
			手枪2威力:this.自机.手枪2属性.power, 
			刀锋利度:this.自机.刀属性.power,
			韧性系数:this.自机.韧性系数,
			内力:this.自机.内力
		};
		
		for(var key in this.自机.魔法抗性){
			this.基础值.魔法抗性[key] = this.自机.魔法抗性[key];
		}
		//_root.发布消息('空手攻击力基础值：'+this.基础值.空手攻击力);
	}

	function 赋值(属性名, 类型, 数值, 增减类型, 换算上限, 换算下限)
	{
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
			if(类型 == "倍率"){
				delete this.buff倍率[属性名];
				this.更新(属性名);
			}else if(类型 == "加算"){
				delete this.buff加算[属性名];
				this.更新(属性名);
			}
		}else{
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
			else if (属性名 == '速度')
			{
				this.自机.行走X速度 = this.基础值.速度 * 计算buff倍率.速度 + 计算buff加算.速度;
				this.自机.跳跃中移动速度 = this.自机.行走X速度;
				//this.自机.跳跃中上下方向 = "无";
				//this.自机.跳跃中左右方向 = "无";
				this.自机.行走Y速度 = this.自机.行走X速度 / 2;
				this.自机.跑X速度 = this.自机.行走X速度 * 2;
				this.自机.跑Y速度 = this.自机.行走X速度;
				//this.自机.被击硬直度 = _root.根据等级计算值(this.自机.被击硬直度_min, this.自机.被击硬直度_max, this.自机.等级) / 速度系数;
				this.自机.起跳速度 = -10 * UnitUtil.getWeightSpeedRatio(this.自机.重量, this.自机.等级);
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
				else if (属性名key == '速度')
				{
					this.自机.行走X速度 = this.基础值.速度 * 计算buff倍率.速度 + 计算buff加算.速度;
					this.自机.跳跃中移动速度 = this.自机.行走X速度;
					//this.自机.跳跃中上下方向 = "无";
					//this.自机.跳跃中左右方向 = "无";
					this.自机.行走Y速度 = this.自机.行走X速度 / 2;
					this.自机.跑X速度 = this.自机.行走X速度 * 2;
					this.自机.跑Y速度 = this.自机.行走X速度;
					//this.自机.被击硬直度 = _root.根据等级计算值(this.自机.被击硬直度_min, this.自机.被击硬直度_max, this.自机.等级) / 速度系数;
					this.自机.起跳速度 = -10 * UnitUtil.getWeightSpeedRatio(this.自机.重量, this.自机.等级);
				}
				else
				{
					this.自机[属性名key] = this.基础值[属性名key] * 计算buff倍率[属性名key] + 计算buff加算[属性名key];
				}
			}
		}
	}

	function 卸载()
	{
		this.buff倍率 = {};
		this.buff加算 = {};
		this.buff限时倍率 = {};
		this.buff限时加算 = {};
		this.更新('全部');
	}
}