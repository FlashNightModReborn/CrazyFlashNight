_root.根据装备名获得装备id = function(物品名){
	return _root.物品属性列表[物品名].id;
}

_root.根据物品名查找物品id = function(物品名){
	return _root.物品属性列表[物品名].id;
}

_root.根据物品名查找属性 = function(物品名, 属性号){
	return 根据物品名查找全部属性(物品名)[属性号];
}

/**
 * 根据物品名称查找全部属性
 * 
 * 本函数根据传入的物品名称，从全局物品属性列表 (_root.物品属性列表) 中读取对应的物品数据，
 * 并构造一个标准化的属性数组 itemArr。返回的数组包含物品的基本信息、扩展属性及武器/装备/药剂的特殊参数，
 * 适用于游戏中物品的管理、角色属性配置以及物品描述生成。
 * 
 * ### 返回值说明
 * 
 * #### 基本信息
 * - **itemArr[0]** : 物品名称 (String) —— 传入的参数，直接赋值，用于标识物品。
 * - **itemArr[1]** : 图标 (String) —— 从 itemData.icon 获取，未定义时为空字符串 ""，用于界面显示。
 * - **itemArr[2]** : 物品类型 (String) —— 从 itemData.type 获取，未定义时为空字符串 ""，如“武器”、“防具”、“药剂”等。
 * - **itemArr[3]** : 物品用途 (String) —— 从 itemData.use 获取，未定义时为空字符串 ""，如“长枪”、“刀”、“药剂”等。
 * - **itemArr[4]** : 重量 (Number) —— 从 itemData.weight 获取，未定义时为 0，影响角色速度和负重。
 * - **itemArr[5]** : 价格 (Number) —— 从 itemData.price 获取，未定义时为 0，用于交易和商店系统。
 * - **itemArr[6]** : 描述 (String) —— 从 itemData.description 获取，未定义时为空字符串 ""，提供物品的背景或使用说明。
 * 
 * #### 扩展属性
 * - **itemArr[7]** : 友好度 (String|Number) —— 从 itemData.data.friend 获取，未定义时为 0，可能为数字或字符串（如“淬毒”、“净化”），用于药剂的群体效果与特殊效果交互。
 * 命名有待继续讨论。
 * - **itemArr[8]** : 防御值 (Number) —— 从 itemData.data.defence 获取，未定义时为 0，提升角色的防御力。
 * - **itemArr[9]** : 物品等级 (Number) —— 从 itemData.level 获取，未定义时为 0，限制装备或使用的等级需求。原则上，不可装备的物品不适用该值。
 * 
 * #### 血量与魔法值
 * - 若物品用途为 "药剂"：
 *   - **itemArr[10]** : 影响血量 (Number) —— 从 itemData.data.affecthp 获取，未定义时为 0，用于恢复或减少 HP。
 *   - **itemArr[11]** : 影响魔法值 (Number) —— 从 itemData.data.affectmp 获取，未定义时为 0，用于恢复或减少 MP。
 * - 否则（装备类物品）：
 *   - **itemArr[10]** : 装备提供的血量 (Number) —— 从 itemData.data.hp 获取，未定义时为 0，增加角色的最大 HP。
 *   - **itemArr[11]** : 装备提供的魔法值 (Number) —— 从 itemData.data.mp 获取，未定义时为 0，增加角色的最大 MP。
 * 
 * #### 子弹与武器参数
 * - **itemArr[12]** : 附带的子弹数 (Number) —— 从 itemData.data.bullet 获取，未定义时为 0，表示装备时附带的初始弹药量。
 * 
 * #### 武器/装备相关参数
 * 根据物品用途 (itemData.use) 的不同，接下来的两个下标值处理如下：
 * 
 * 1. **若物品用途为 "长枪"、"手枪" 或 "手雷"（远程武器类）**：
 *    - **itemArr[13]** : 固定为 0 —— 不直接存储伤害值，伤害存储在 itemArr[14] 中。
 *    - **itemArr[14]** : 数组，存储远程武器的详细发射参数：
 *        - **[0] capacity**    : 弹夹容量 (Number) —— 从 data.capacity 获取，默认 0，表示弹药最大存储量。
 *        - **[1] split**       : 霰弹值 (Number) —— 从 data.split 获取，默认 0，每次射击散射的子弹数。
 *        - **[2] diffusion**   : 散射度 (Number) —— 从 data.diffusion 获取，默认 0，子弹的分散程度，影响精准性。
 *        - **[3] singleshoot** : 单发射击值 (Number) —— 从 data.singleshoot 获取，默认 0，单发模式的开关。
 *        - **[4]**             : 固定为 false (Boolean) —— 预留标志位，用途未明确，可能用于控制特定功能。
 *        - **[5] interval**    : 射击间隔 (Number) —— 从 data.interval 获取，默认 0，单位毫秒，控制射击频率。
 *        - **[6] velocity**    : 子弹飞行速度 (Number) —— 从 data.velocity 获取，默认 0，影响子弹的移动速度。
 *        - **[7] bullet**      : 子弹类型 (String) —— 从 data.bullet 获取，默认 0，子弹的具体名称或标识符。
 *        - **[8] sound**       : 发射音效 (String) —— 从 data.sound 获取，默认 0，射击时播放的音效文件。
 *        - **[9] muzzle**      : 枪口火焰效果 (String) —— 从 data.muzzle 获取，默认 0，射击时的视觉效果。
 *        - **[10] bullethit**  : 子弹命中效果 (String) —— 从 data.bullethit 获取，默认 0，子弹击中目标时的视觉效果。
 *        - **[11] clipname**   : 弹夹名称 (String) —— 从 data.clipname 获取，默认 0，弹药的名称或类型。
 *        - **[12] bulletsize** : 子弹尺寸 (Number) —— 从 data.bulletsize 获取，默认 0，影响子弹的视觉大小。
 *        - **[13] power**      : 伤害数值 (Number) —— 从 data.power 获取，默认 0，单发子弹的基础伤害。
 *        - **[14] impact**     : 击倒力 (Number) —— 从 data.impact 获取，默认 0，伤害转化成冲击力的比例。
 * 
 * 2. **若物品用途为 "刀"（近战武器）**：
 *    - **itemArr[13]** : 近战伤害 (Number) —— 从 data.power 获取，表示刀的锋利度或伤害值。
 *    - **itemArr[14]** : 默认数组，所有远程武器参数置为默认值：
 *        `[0, 0, 0, false, 0, 0, 0, "", "", "", "", "", 0, 0, 0, ""]`
 * 
 * 3. **若物品用途为 "颈部装备"（颈部饰品）**：
 *    - **itemArr[13]** : 固定为 0 —— 无直接伤害。
 *    - **itemArr[14]** : 数组，首个元素为装备称号 (`equipped.title`)，其余为默认值：
 *        `[equipped.title 或 0, 0, 0, false, 0, 0, 0, "", "", "", "", "", 0, 0, 0, ""]`
 * 
 * 4. **其他用途（如护甲、药剂等）**：
 *    - **itemArr[13]** : 装备提供的伤害 (Number) —— 从 equipped.damage 获取，未定义时为 0，可能为某些特殊装备的伤害加成。
 *    - **itemArr[14]** : 默认数组，所有远程武器参数置为默认值：
 *        `[0, 0, 0, false, 0, 0, 0, "", "", "", "", "", 0, 0, 0, ""]`
 * 
 * #### 其他装备属性
 * - **itemArr[15]** : 装备的装扮效果 (String) —— 从 equipped.dressup 获取，未定义时为空字符串 ""，用于角色外观的显示。
 * - **itemArr[16]** : 空手加成值 (Number) —— 从 equipped.punch 获取，未定义时为 0，影响角色的空手攻击倍率。
 * - **itemArr[17]** : 稳定性 (Number) —— 从 equipped.toughness 获取，未定义时为 0，影响角色的韧性（原 balance ）。
 * - **itemArr[18]** : 命中率 (Number) —— 从 equipped.accuracy 获取，未定义时为 0，提升角色的攻击命中率（原 hitAccuracy ）。
 * - **itemArr[19]** : 躲闪能力 (Number) —— 从 equipped.evasion 获取，未定义时为 0，提升角色的闪避率（原 dodgeAbility ）。
 * 
 * 
 * @param 物品名 {String} 需要查找属性的物品名称
 * @return {Array} 返回包含所有物品属性的数组 itemArr，各索引含义如上所述
 */
_root.根据物品名查找全部属性 = function(物品名) {
    var itemArr = new Array();
    var itemData = _root.物品属性列表[物品名];
    var equipData = itemData.data;
    
    // 基本信息
    itemArr[0] = 物品名;
    itemArr[1] = itemData.icon == undefined ? "" : itemData.icon;
    itemArr[2] = itemData.type == undefined ? "" : itemData.type;
    itemArr[3] = itemData.use == undefined ? "" : itemData.use;
    itemArr[4] = equipData.weight == undefined ? 0 : equipData.weight;
    itemArr[5] = itemData.price == undefined ? 0 : itemData.price;
    itemArr[6] = itemData.description == undefined ? "" : itemData.description;
    
    // 扩展属性
    itemArr[7] = itemData.data.friend == undefined ? 0 : itemData.data.friend;
    itemArr[8] = equipData.defence == undefined ? 0 : equipData.defence;
    itemArr[9] = equipData.level == undefined ? 0 : equipData.level;
    
    // 血量和魔法值，根据物品用途分开处理
    if (itemData.use == "药剂") {
        itemArr[10] = itemData.data.affecthp == undefined ? 0 : itemData.data.affecthp;
        itemArr[11] = itemData.data.affectmp == undefined ? 0 : itemData.data.affectmp;
    } else {
        itemArr[10] = equipData.hp == undefined ? 0 : equipData.hp;
        itemArr[11] = equipData.mp == undefined ? 0 : equipData.mp;
    }
    
    // 附带子弹数
    itemArr[12] = equipData.bullet == undefined ? 0 : equipData.bullet;
    
    // 根据不同物品用途配置武器或装备的特殊参数
    switch (itemData.use) {
        case "长枪":
        case "手枪":
        case "手雷":
            itemArr[13] = 0;
            itemArr[14] = [
                equipData.capacity    == undefined ? 0 : equipData.capacity,   // 弹夹容量
                equipData.split       == undefined ? 0 : equipData.split,      // 霰弹分裂数
                equipData.diffusion   == undefined ? 0 : equipData.diffusion,  // 散射度
                equipData.singleshoot == undefined ? 0 : equipData.singleshoot,// 单发射击值
                false,                                                          // 预留标志位
                equipData.interval    == undefined ? 0 : equipData.interval,   // 射击间隔
                equipData.velocity    == undefined ? 0 : equipData.velocity,   // 子弹速度
                equipData.bullet      == undefined ? 0 : equipData.bullet,     // 子弹类型
                equipData.sound       == undefined ? 0 : equipData.sound,      // 音效
                equipData.muzzle      == undefined ? 0 : equipData.muzzle,     // 枪口火焰
                equipData.bullethit   == undefined ? 0 : equipData.bullethit,  // 子弹命中效果
                equipData.clipname    == undefined ? 0 : equipData.clipname,   // 弹夹名称
                equipData.bulletsize  == undefined ? 0 : equipData.bulletsize, // 子弹尺寸
                equipData.power       == undefined ? 0 : equipData.power,      // 伤害数值
                equipData.impact      == undefined ? 0 : equipData.impact      // 击倒力
            ];
            break;
        case "刀":
            itemArr[13] = equipData.power == undefined ? 0 : equipData.power;
            itemArr[14] = [0, 0, 0, false, 0, 0, 0, "", "", "", "", "", 0, 0, 0, ""];
            break;
        case "颈部装备":
            itemArr[13] = 0;
            itemArr[14] = [
                equipData.title == undefined ? 0 : equipData.title,
                0, 0, false, 0, 0, 0, "", "", "", "", "", 0, 0, 0, ""
            ];
            break;
        default:
            itemArr[13] = equipData.damage == undefined ? 0 : equipData.damage;
            itemArr[14] = [0, 0, 0, false, 0, 0, 0, "", "", "", "", "", 0, 0, 0, ""];
    }
    
    // 其他装备附加属性
    itemArr[15] = equipData.dressup == undefined ? "" : equipData.dressup;
    itemArr[16] = equipData.punch == undefined ? 0 : equipData.punch;
    itemArr[17] = equipData.toughness == undefined ? 0 : equipData.toughness;
    itemArr[18] = equipData.accuracy == undefined ? 0 : equipData.accuracy;
    itemArr[19] = equipData.evasion == undefined ? 0 : equipData.evasion;
    
    return itemArr;
}


_root.强化计算 = function(初始值, 强化等级){
	if (!isNaN(初始值)){
		if(!isNaN(强化等级) && 强化等级 <= 13) return Math.floor(初始值 * (1 + (强化等级 - 1) * (强化等级 - 1) / 100 + 0.05 * (强化等级 - 1)));
		return 初始值;
	}
	return 1;
}

_root.getArr = function(str){
   if(str == ""){
      return [];
   }
   return str.split(",");
}


_root.物品栏总数 = 50;
_root.仓库栏基本总数 = 1240;
_root.仓库栏总数 = 1240;
// _root.仓库页数 = 1;
// _root.暂存仓库页数 = 1;
// _root.暂存后勤战备箱页数 = 31;
// _root.仓库名称 = "仓库";
// _root.仓库显示页数 = 仓库页数;





//对新物品提交与获取函数的引用
_root.itemAcquire = function(itemArray, context):Boolean{
	return org.flashNight.arki.item.ItemUtil.acquire(itemArray, context);
}
_root.itemContain = function(itemArray):Object{
	return org.flashNight.arki.item.ItemUtil.contain(itemArray);
}
_root.itemSubmit = function(itemArray, context):Boolean{
	return org.flashNight.arki.item.ItemUtil.submit(itemArray, context);
}

_root.singleAcquire = function(name,value,context):Boolean{
	return org.flashNight.arki.item.ItemUtil.singleAcquire(name,value,context);
}
_root.singleContain = function(name,value):Object{
	return org.flashNight.arki.item.ItemUtil.singleContain(name,value);
}
_root.singleSubmit = function(name,value,context):Boolean{
	return org.flashNight.arki.item.ItemUtil.singleSubmit(name,value,context);
}

//击杀播报（P2）：统一收口于 enemyKilled 事件链（EnemyKilledEventComponent）。
//同名敌人在 feed 模型合并窗口内累计 ×n；显示名与头像分三档：
//  敌人属性表命中（敌人-* 类型键）→ displayname + 头像 ref；
//  未命中但为 敌人-* → 原键名 + 头像 ref；
//  其余敌方单位（角斗场 主角-男 系斗士等）→ 单位 名字 + 纸娃娃运行时烘焙头像
//  （AS2 只做字段搬运，C# 单点算键，web 侧 dressup 渲染器烘焙；无 脸型 字段走占位块）。
_root.发布击杀播报 = function(unit:MovieClip):Void{
	if (unit == null) return;
	var killKey:String = org.flashNight.arki.unit.UnitUtil.getUnitTypeKey(unit);
	if (killKey == null || killKey.length == 0) return;
	var killName:String = null;
	var iconName:String = null;
	var dollTuple:Object = null;
	var eliteLevel:Number = org.flashNight.arki.unit.UnitUtil.getEliteLevel(unit);
	var enemyInfo:Object = (_root.敌人属性表 != undefined) ? _root.敌人属性表[killKey] : null;
	if (enemyInfo != null && enemyInfo.displayname != undefined && String(enemyInfo.displayname).length > 0) {
		killName = String(enemyInfo.displayname);
		iconName = killKey;
	} else if (killKey.indexOf("敌人-") == 0) {
		killName = killKey;
		iconName = killKey;
	} else {
		// 其余敌方单位（角斗场 主角-男 系斗士等）：显示名用单位 名字；
		// 头像不预计算键，只把外观元组（undefined/null 归一为 ""）透传给 C#——
		// 禁止在此做任何光栅化/哈希，烘焙由 web 侧渲染器异步完成。
		if (unit.名字 != undefined && String(unit.名字).length > 0) {
			killName = String(unit.名字);
		} else {
			killName = killKey;
		}
		if (unit.脸型 != undefined) {
			var dollField:Function = function(v):String { return v == null ? "" : String(v); };
			dollTuple = {
				face: dollField(unit.脸型),
				hair: dollField(unit.发型),
				mask: dollField(unit.面具),
				head: dollField(unit.头部装备),
				body: dollField(unit.上装装备),
				leg: dollField(unit.下装装备),
				hand: dollField(unit.手部装备),
				foot: dollField(unit.脚部装备),
				neck: dollField(unit.颈部装备),
				gender: dollField(unit.性别)
			};
		}
	}
	org.flashNight.arki.scene.StageRunSession.recordKillProjection({
		key:killKey,
		displayName:killName,
		iconName:iconName == null ? "" : iconName,
		doll:dollTuple,
		eliteLevel:eliteLevel
	});
	if (typeof _root.发布战利品消息 != "function") return;
	_root.发布战利品消息("kill", killName, 1, "kill", null, iconName, dollTuple, eliteLevel);
}

// 独立 XFL/SWF 不直接依赖 scripts/类定义 的 classpath：资产时间轴只调用这组
// asLoader 注入的 _root 门面，由主运行时统一选择 PlayerAssetTransaction/ItemUtil
// 的实际版本。领域内的 .as 服务仍可直接使用类库，不必绕回 _root。
_root.开始玩家物资事务 = function(context:Object):Object {
	return org.flashNight.arki.item.PlayerAssetTransaction.begin(context);
}

_root.提交玩家物资事务 = function(transaction:Object):Object {
	return org.flashNight.arki.item.PlayerAssetTransaction.commit(transaction);
}

_root.回滚玩家物资事务 = function(transaction:Object):Boolean {
	return org.flashNight.arki.item.PlayerAssetTransaction.rollback(transaction);
}

_root.结算玩家物资事务异常 = function(transaction:Object,
		preserveCommittedEffects:Boolean):Object {
	return org.flashNight.arki.item.PlayerAssetTransaction.settleAfterException(
		transaction, preserveCommittedEffects);
}

_root.标记玩家物资存档脏 = function():Void {
	org.flashNight.arki.item.PlayerAssetTransaction.markDirtyRequired(_root.存档系统);
}

_root.捕获玩家物资快照 = function():Object {
	return org.flashNight.arki.item.ItemUtil.capturePlayerAssetSnapshot();
}

_root.恢复玩家物资快照 = function(snapshot:Object):Boolean {
	return org.flashNight.arki.item.ItemUtil.restorePlayerAssetSnapshot(snapshot);
}

_root.记录玩家物资变化 = function(direction:String, kind:String, name:String,
		count:Number, context:Object):Void {
	org.flashNight.arki.item.PlayerAssetTransaction.recordEffect(
		direction, kind, name, count, context);
}

_root.记录玩家货币变化 = function(moneyDelta:Number, kpointDelta:Number,
		context:Object):Void {
	org.flashNight.arki.item.PlayerAssetTransaction.recordCurrencyDeltas(
		moneyDelta, kpointDelta, context);
}

_root.玩家物品是否装备 = function(itemName:String):Boolean {
	return org.flashNight.arki.item.ItemUtil.isEquipment(itemName);
}

// 健身房的七个延迟完成按钮共用同一个金币提交点，避免每个 XFL 帧脚本各自
// 扣款、标脏和拼装回执。技能点/K点路径仍由挂机计时器自己的权威支付函数处理。
_root.结算健身金币消耗 = function(rawCost):Boolean {
	var cost:Number = Number(rawCost);
	var moneyBefore:Number = Number(_root.金钱);
	if (isNaN(cost) || !isFinite(cost) || cost <= 0 || Math.floor(cost) != cost
			|| isNaN(moneyBefore) || !isFinite(moneyBefore)) return false;
	_root.金钱 = moneyBefore - cost;
	if (_root.存档系统 != undefined) _root.存档系统.dirtyMark = true;
	_root.记录玩家货币变化(
		Number(_root.金钱) - moneyBefore, 0,
		{source:"gym_training", reason:"training_complete", mergeScope:"operation"});
	return true;
}

//玩家物资流动播报：只消费 PlayerAssetTransaction 已提交回执；socket 离线时静默
//丢弃，不影响权威资产。旧发布战利品消息保留为 gain/kill 兼容 façade。
//kind 可传 null 自动按名称推导；显式 kind 白名单由 Host 与 canonical 文档共同冻结。
//source 是权威变化原因枚举，新增领域必须同时更新 Host/parser 测试与协议文档。
//tier 可选，进阶装备解析进阶名/图标。icon 可选，显式覆盖（击杀播报传敌人头像 ref）。
//doll 可选（仅击杀播报人形斗士）：外观元组 {face,hair,mask,head,body,leg,hand,foot,neck,gender}，
//C# 侧据此外观单点派生 纸娃娃-<hex> 图标键并触发 web 侧运行时胸像烘焙；
//eliteLevel 可选（仅击杀播报）：UnitUtil.getEliteLevel 的 0=普通、1=精英、2=首领。
_root.发布物资变更消息 = function(direction:String, kind:String, name:String, count:Number,
		source:String, tier:String, icon:String, operationId:String,
		mergeScope:String, reason:String, doll:Object, eliteLevel:Number,
		protocolVersion:Number):Void{
	if (name == undefined || count == undefined) return;
	if (isNaN(Number(count)) || Number(count) <= 0) return;
	if (direction != "gain" && direction != "loss" && direction != "neutral") return;

	if (kind == undefined || kind == null || kind == "") {
		if (name == "金钱" || name == "金币") kind = "money";
		else if (name == "K点") kind = "kpoint";
		else if (org.flashNight.arki.item.ItemUtil.isInformation(name)) kind = "intel";
		else if (org.flashNight.arki.item.ItemUtil.isMaterial(name)) kind = "material";
		else if (org.flashNight.arki.item.ItemUtil.isEquipment(name)) kind = "equip";
		else kind = "item";
	}

	var displayName:String = name;
	var iconName:String = null;
	var itemData:Object = org.flashNight.arki.item.ItemUtil.getRawItemData(name);
	if (tier != undefined && tier != null && String(tier).length > 0) {
		// 进阶装备：克隆后应用进阶覆盖（displayname/icon 可能被 tier 改写）
		var tierData:Object = org.flashNight.arki.item.ItemUtil.getItemData(name);
		if (tierData != undefined && tierData != null) {
			org.flashNight.arki.item.equipment.TierSystem.applyTierData(tierData, String(tier), null);
			itemData = tierData;
		}
	}
	if (itemData != undefined && itemData != null) {
		if (itemData.displayname != undefined) displayName = itemData.displayname;
		if (itemData.icon != undefined) iconName = itemData.icon;
	} else if (kind == "money") {
		iconName = "金钱";
	} else if (kind == "kpoint") {
		iconName = "K点";
	}
	if (icon != undefined && icon != null && String(icon).length > 0) {
		iconName = String(icon);
	}

	var msg:Object = org.flashNight.arki.item.PlayerAssetWireProjector.buildMessage({
		version:protocolVersion,
		direction:direction,
		kind:kind,
		itemKey:name,
		name:displayName,
		count:count,
		source:String(source || "unknown"),
		icon:iconName,
		tier:tier,
		operationId:operationId,
		mergeScope:mergeScope,
		reason:reason,
		doll:doll,
		eliteLevel:eliteLevel
	});
	org.flashNight.arki.scene.StageRunSession.recordAssetProjection(msg);
	if (_root.server == undefined || _root.server.sendTaskToNode == undefined) return;
	_root.server.sendTaskToNode("loot", msg, null);
}

// 已提交回执的唯一生产消费者出口。回执中的 name 仍为权威物品键；展示名、tier
// 覆盖和 icon 只在发送边界解析，事务基座不携带易变 catalog 对象。
_root.发布物资事务回执 = function(receipt:Object):Void{
	org.flashNight.arki.item.PlayerAssetWireProjector.forEachEffect(
		receipt,
		function(effect:Object, effectIndex:Number):Void {
			_root.发布物资变更消息(
				String(effect.direction), String(effect.kind), String(effect.name),
				Number(effect.count), String(effect.source || receipt.source || "unknown"),
				String(effect.tier || ""), null, String(receipt.operationId || ""),
				String(effect.mergeScope || ""), String(effect.reason || receipt.reason || ""),
				null, 0, Number(receipt.version));
		},
		function(effectPublishError, effectIndex:Number):Void {
			// 单个 catalog/tier/socket 投影失败只丢该 effect，不能吞掉同一已提交
			// receipt 中后续彼此独立的物资事实。
			trace("[PlayerAssetTransaction] effect " + effectIndex
				+ " publish failed: " + effectPublishError);
		}
	);
}

_root.发布战利品消息 = function(kind:String, name:String, count:Number, source:String,
		tier:String, icon:String, doll:Object, eliteLevel:Number):Void{
	var direction:String = kind == "kill" ? "neutral" : "gain";
	_root.发布物资变更消息(direction, kind, name, count, source, tier, icon,
		null, null, null, doll, eliteLevel);
}

_root.getRequirementFromTask = function(arr){
    return org.flashNight.arki.item.ItemUtil.getRequirementFromTask(arr);
}
