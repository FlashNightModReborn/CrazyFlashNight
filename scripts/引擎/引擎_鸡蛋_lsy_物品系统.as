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
    itemArr[4] = itemData.weight == undefined ? 0 : itemData.weight;
    itemArr[5] = itemData.price == undefined ? 0 : itemData.price;
    itemArr[6] = itemData.description == undefined ? "" : itemData.description;
    
    // 扩展属性
    itemArr[7] = itemData.data.friend == undefined ? 0 : itemData.data.friend;
    itemArr[8] = equipData.defence == undefined ? 0 : equipData.defence;
    itemArr[9] = itemData.level == undefined ? 0 : itemData.level;
    
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



/* 创建物品函数在root上的引用，暂未启用
_root.createItem = function(name, value):Object{
    return org.flashNight.arki.item.ItemUtil.createItem(name, value);
}
*/

//对新物品提交与获取函数的引用
_root.itemAcquire = function(itemArray):Boolean{
	return org.flashNight.arki.item.ItemUtil.acquire(itemArray);
}
_root.itemContain = function(itemArray):Object{
	return org.flashNight.arki.item.ItemUtil.contain(itemArray);
}
_root.itemSubmit = function(itemArray):Boolean{
	return org.flashNight.arki.item.ItemUtil.submit(itemArray);
}

_root.singleAcquire = function(name,value):Boolean{
	return org.flashNight.arki.item.ItemUtil.singleAcquire(name,value);
}
_root.singleContain = function(name,value):Object{
	return org.flashNight.arki.item.ItemUtil.singleContain(name,value);
}
_root.singleSubmit = function(name,value):Boolean{
	return org.flashNight.arki.item.ItemUtil.singleSubmit(name,value);
}

_root.getRequirementFromTask = function(arr){
    return org.flashNight.arki.item.ItemUtil.getRequirementFromTask(arr);
}