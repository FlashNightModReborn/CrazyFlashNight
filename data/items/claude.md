我已经把装备插件的运算链路摸清了，下面按你关心的几个点说明，并给出新增运算符要改的所有模块位置。

1. 现有运算符在哪儿起效？（数据入口）

配件定义与文档：

文件：data/items/equipment_mods.xml
顶部注释已经详细说明了 flat / percentage / override / merge / cap 的含义和示例。
每个 <mod> 里 stats 结构类似：
<flat>...</flat>
<percentage>...</percentage>
<override>...</override>
<merge>...</merge>
<cap>...</cap>
XML 加载入口：

scripts/类定义/org/flashNight/gesh/xml/LoadXml/EquipModDataLoader.as
只是包装了 BaseXMLLoader，指定路径 data/items/equipment_mods.xml，不做运算。
scripts/asLoader/LIBRARY/asLoader.xml:570+
var moddata_loader = org.flashNight.gesh.xml.LoadXml.EquipModDataLoader.getInstance();
moddata_loader.loadModData(
    function(data:Object):Void {
        org.flashNight.arki.item.EquipmentUtil.loadModData(data.mod);
    },
    ...
);
这里把 XML 中的 <mod> 数组传进 EquipmentUtil.loadModData，从这一步开始，运算符逻辑进入核心计算代码。
2. 运算逻辑核心：在哪里做加减乘、override、merge？

核心都在：scripts/类定义/org/flashNight/arki/item/EquipmentUtil.as

1）运算符函数表

位置：文件开头附近

代码（简化）：

public static var propertyOperators:Object = {
    add: addProperty,
    multiply: multiplyProperty,
    override: overrideProperty,
    merge: mergeProperty,
    applyCap: applyCapProperty
};
这里相当于一个“运算符实现表”，各个运算的具体逻辑在同一文件里：

addProperty(prop, addProp, initValue)：用在 flat、percentage、cap 的累加阶段。
multiplyProperty(prop, multiProp)：真正把倍数乘到属性上。
overrideProperty(prop, overProp)：浅覆盖。
mergeProperty(prop, mergeProp)：深度合并 + 数值智能合并。
applyCapProperty(prop, capProp, baseProp)：基于变化量/绝对值的封顶/封底。
2）加载 mods 时对 percentage 的预处理

函数：EquipmentUtil.loadModData(modData:Array)
关键逻辑：
// 百分比：把 XML 里的“5”变成 0.05，只做一次
if(!mod._percentageNormalized){
    var percentage:Object = mod.stats ? mod.stats.percentage : null;
    if(percentage){
        for(var key:String in percentage){
            percentage[key] *= 0.01;
        }
        mod._percentageNormalized = true;
    }
}
说明：
XML 里 <power>5</power> → 内存中变成 percentage.power = 0.05。
后面所有逻辑都以小数形式处理。
3）把所有插件的 stats 聚合起来

函数：private static function accumulateModifiers(mods:Array):Object
作用：遍历 value.mods，把所有配件的 flat / percentage / override / merge / cap 分别累计到 5 个桶里。
关键代码：
var adder:Object = {};
var multiplier:Object = {};
var overrider:Object = {};
var merger:Object = {};
var capper:Object = {};
...
for (i in mods) {
    var modInfo:Object = modDict[mods[i]];
    ...
    var overrideStat:Object   = modInfo.stats.override;
    var percentageStat:Object = modInfo.stats.percentage;
    var flatStat:Object       = modInfo.stats.flat;
    var mergeStat:Object      = modInfo.stats.merge;
    var capStat:Object        = modInfo.stats.cap;

    if(flatStat)       operators.add(adder, flatStat, 0);
    if(percentageStat) operators.add(multiplier, percentageStat, 1);
    if(overrideStat)   operators.override(overrider, overrideStat);
    if(mergeStat)      operators.merge(merger, mergeStat);
    if(capStat)        operators.add(capper, capStat, 0);
    ...
}
return { adder, multiplier, overrider, merger, capper, skill };
要点：
percentageStat 通过 addProperty(multiplier, percentageStat, 1) 累加，等价于把所有 (1 + p) 加到一起，暂存在 modifiers.multiplier。
4）等级倍率与 percentage 的“加法合并乘区”逻辑

函数：private static function buildBaseMultiplier(level:Number):Object

根据强化等级取 levelStatList[level]，生成一套基础倍数 baseMultiplier（power/defence等相同）。
函数：private static function applyOperatorsInOrder(data:Object, baseMultiplier:Object, modifiers:Object):Void

这就是你问的 “percentage 当前算法” 的核心。
关键部分（已经有详细中文注释）：
// 先把 baseMultiplier 转成“增量”（去掉 1）
var finalMultiplier:Object = {};
for (key in baseMultiplier) {
    var baseValue = Number(baseMultiplier[key]);
    if (!isNaN(baseValue)) finalMultiplier[key] = baseValue - 1;
}

// 再把所有 percentage 累加进来（modifiers.multiplier 已经是 1 + p）
if (modifiers.multiplier) {
    for (modKey in modifiers.multiplier) {
        var modValue = Number(modifiers.multiplier[modKey]);
        var increment = modValue - 1;    // 提取 p
        if (!isNaN(finalMultiplier[modKey])) finalMultiplier[modKey] += increment;
        else finalMultiplier[modKey] = increment;
    }
}

// 最后统一加回 1，得到最后乘数
for (finalKey in finalMultiplier) {
    finalMultiplier[finalKey] = 1 + finalMultiplier[finalKey];
}

// 应用到 data 上
operators.multiply(data, finalMultiplier);
数学形式：
最终倍率 = 1 + (等级倍率 - 1) + Σ(各插件百分比)
然后一次性 data[prop] *= 最终倍率。
这就是你说的「加法合并，再作为一个乘区」，避免多段乘法导致爆炸成长。
5）整体应用顺序（和装备数值如何协同）

函数：public static function calculateData(item:BaseItem, itemData:Object):Void

调用链：
applyTierData(itemData, value)：根据 tier 用 override 覆盖基础 data。
buildBaseMultiplier(level)：算出强化等级带来的倍率。
accumulateModifiers(value.mods)：把所有插件的 flat/percentage/override/merge/cap 累成一份。
applyOperatorsInOrder(data, baseMultiplier, modifiers)：
先把“等级倍率 + 所有 percentage”合成一个乘区 → multiply.
再应用 flat→ add.
再做 override.
再做深度 merge.
最后 cap。
若有技能覆盖，替换 itemData.skill。
入口：BaseItem.getData()

文件：scripts/类定义/org/flashNight/arki/item/BaseItem.as
核心：
var _itemData:Object = ItemUtil.getItemData(this.name);
if(ItemUtil.isEquipment(this.name)) EquipmentUtil.calculateData(this, _itemData);
return _itemData;
装备的所有显示（属性面板/tooltip）最终都基于这份带插件+强化+tier 计算后的 itemData.data。
3. 注释/说明文本在哪里显示？（插件词条显示链路）

1）配件自己的“说明词条”

XML 中：
每个 <mod> 通常会有 <tag> 或类似字段，作为你在 tooltip 中看到的短标签。
加载阶段：
EquipmentUtil.loadModData：
if(mod.tag){
    mod.tagValue = mod.tag; // 保存 tag 用于显示
}
同时 modDict[name] = mod;，以后 UI 用 EquipmentUtil.modDict 查信息。
2）装备 Tooltip 中的“已安装配件 + 简短说明”

文件：scripts/类定义/org/flashNight/gesh/tooltip/builder/ModsBlockBuilder.as
函数：ModsBlockBuilder.build(result, baseItem, item, value)
显示“已安装 X 个配件”：
if (!value.mods || value.mods.length <= 0) return;
result.push("<font color='" + TooltipConstants.COL_HL + "'>已安装", value.mods.length, "个配件：</font><BR>");
每个配件一行：
var modName:String = value.mods[i];
var modInfo:Object = EquipmentUtil.modDict[modName];

// 基础：显示名字
result.push("  • ", modName);

// 若有 tagValue，则显示为 [xxx]
if (modInfo && modInfo.tagValue) {
    result.push(" <font color='" + TooltipConstants.COL_INFO + "'>[", modInfo.tagValue, "]</font>");
}
对 percentage 的简要数值展示：
if (modInfo && modInfo.stats && modInfo.stats.percentage) {
    var enhancements:Array = [];
    var percentage:Object = modInfo.stats.percentage;
    for (var prop:String in percentage) {
        var percentValue:Number = Number(percentage[prop]);
        if (!isNaN(percentValue) && percentValue != 0) {
            var sign:String = percentValue > 0 ? "+" : "";
            var percent:Number = Math.round(percentValue * 100);
            enhancements.push(sign + percent + "%");
        }
    }
    if (enhancements.length > 0) {
        result.push(" <font color='" + TooltipConstants.COL_ENHANCE + "'>(", enhancements.join(", "), ")</font>");
    }
}
整体：
XML 的 <tag> → mod.tagValue → ModsBlockBuilder 中的 [xxx] 标签。
XML 的 <percentage> → 参与数值计算，同时在 ModsBlockBuilder 中压缩成 “(+5%, +10%)” 这样的短描述。
3）装备本体属性/描述的显示

描述文本：

TooltipTextBuilder.buildBasicDescription 会优先使用 baseItem.getData() 之后的 description。
如果 tier 或 mod 的 override/merge 修改了 description，就通过这里呈现。
属性面板数值：

TooltipTextBuilder + EquipmentStatsComposer（在 scripts/类定义/org/flashNight/gesh/tooltip/builder/EquipmentStatsComposer.as）从 baseItem.getData().data 读取数值，已经是应用了所有运算符之后的结果。
4. 新运算符的设计：作为 percentage 的“增强区分者”

你想要的特性：

功能定位：
依然是“百分比类”的属性增强，但逻辑区别于现有 percentage。
当前 percentage：所有百分比和等级倍率用加法合并到一个乘区中 → 抑制指数膨胀。
新运算符：希望“每个数值都是独立乘区”，用于更强/更精细的数值控制。
一个自然的设计是：

保留旧的 percentage 不变（仍然是加法合并乘区）。
新增一个运算符（比如先用代号说明：percentageStack 或 multiPercentage，具体命名你决定）：
XML：
<stats>
    <percentage> ... </percentage>           <!-- 旧逻辑 -->
    <multiPercentage>                       <!-- 新逻辑：每一项是一个独立乘区 -->
        <power>10</power>    <!-- 每条表示 1.10 倍 -->
        <defence>20</defence>
    </multiPercentage>
</stats>
算法目标：
旧区：finalMultiplier_old[prop] = 1 + (等级 - 1) + Σ percentage[prop]
新区：finalMultiplier_new[prop] = Π (1 + multiPercentage_i[prop])（以单个 mod 的每一项为一个乘区）。
最终：data[prop] *= finalMultiplier_old[prop] * finalMultiplier_new[prop]。
注意：乘法是交换的，从结果上它还是“多个乘区的乘积”，但在逻辑组织上你可以把它清楚地与原来的“加法合并乘区”区分开，方便在 XML 和策划层面精细控制。

5. 为新增运算符要改的模块（系统性列出）

下面按“必须改 / 建议改 / 显示相关”三个层级给出：

5.1 必须修改的核心模块

1）XML 配置与文档

文件：data/items/equipment_mods.xml
修改点：
顶部“【五种核心运算符】”文档块中，新增第六个运算符的说明（名称、运算公式、使用场景示例）。
在示例中增加你新运算符的 <stats> 用法示例。
影响：
只是文档 + 数据约定，不会直接影响运行。但便于以后维护和策划理解。
2）配件数据加载：新增字段预处理（和 percentage 类似）

文件：scripts/类定义/org/flashNight/arki/item/EquipmentUtil.as
函数：loadModData(modData:Array)
需要增加的逻辑：
假设你的新字段叫 multiPercentage（名称你自定，下面用这个举例）：
在处理 percentage 的地方旁边增加一段：
if(!mod._multiPercentageNormalized){
    var mp:Object = mod.stats ? mod.stats.multiPercentage : null;
    if(mp){
        for(var key:String in mp){
            mp[key] *= 0.01;  // 10 -> 0.10
        }
        mod._multiPercentageNormalized = true;
    }
}
目的：
与 percentage 一致：XML 中写的是“百分数”，内部统一使用小数。
3）聚合 modifier 时，新增一个“独立乘区”桶

文件：EquipmentUtil.as
函数：accumulateModifiers(mods:Array)
新增一个累积对象，比如：
var multiZoneMultiplier:Object = {};
在循环中读取：
var mpStat:Object = modInfo.stats.multiPercentage;
...
if (mpStat) {
    // 乘法聚合：每一条是一个乘区
    for (var key:String in mpStat) {
        var p:Number = mpStat[key];    // 已是小数，例如 0.10
        var factor:Number = 1 + p;     // 1.10
        if (!multiZoneMultiplier[key]) multiZoneMultiplier[key] = 1;
        multiZoneMultiplier[key] *= factor;   // 连乘
    }
}
返回值中增加：
return {
    adder: adder,
    multiplier: multiplier,
    overrider: overrider,
    merger: merger,
    capper: capper,
    multiZoneMultiplier: multiZoneMultiplier,
    skill: skill
};
4）运算顺序中应用新乘区

文件：EquipmentUtil.as

函数：applyOperatorsInOrder(data, baseMultiplier, modifiers)

现有顺序概要：

构造 finalMultiplier（基于等级 + percentage 的“加法合并乘区”）。
multiply(data, finalMultiplier).
add(flat).
override.
merge.
cap.
修改建议：

在第 1 步之后、调用 multiply 之前或之后插入对新乘区的乘法（顺序数学上等价，你可以按逻辑组织）：
// 1. 原有 finalMultiplier 计算逻辑保持不变 (等级 + percentage)

// 2. 应用“加法合并乘区”
operators.multiply(data, finalMultiplier);

// 3. 应用新运算符：独立乘区
if (modifiers.multiZoneMultiplier) {
    operators.multiply(data, modifiers.multiZoneMultiplier);
}

// 4. flat / override / merge / cap 保持原顺序
operators.add(data, modifiers.adder, 0);
operators.override(data, ObjectUtil.clone(modifiers.overrider));
operators.merge(data, modifiers.merger);
operators.applyCap(data, modifiers.capper, baseData);
这样：
原来的平衡不受影响（没有新运算符时，multiZoneMultiplier 默认是空对象）。
新运算符明确地作为“额外乘区”插入。
5.2 建议同步修改（让调试和工具链更清晰）

1）插入调试 trace

文件：EquipmentUtil.as
函数：applyOperatorsInOrder
类似 merge 部分的调试：
if (modifiers.multiZoneMultiplier && DEBUG_MODE) {
    debugLog("Applying multiPercentage operator: " + ObjectUtil.toString(modifiers.multiZoneMultiplier));
}
方便你在调试窗口看到新的乘区是否按预期生效。
2）AGENTS/文档中对新运算符的说明

在 data/merc/mercenaries_README.md 中，运算符说明部分（如果有），同步加上你的新运算符介绍和示例。
5.3 显示相关模块（让新运算符在 UI 里“说得清楚”）

1）ModsBlockBuilder：可选地展示新运算符的效果

文件：scripts/类定义/org/flashNight/gesh/tooltip/builder/ModsBlockBuilder.as
现状：
只对 modInfo.stats.percentage 做了一个 ( +5%, -10% ) 的简短展示。
为了让玩家看懂新运算符，你可以：
增加对 modInfo.stats.multiPercentage 的遍历，标记为不同标签，例如：
if (modInfo && modInfo.stats && modInfo.stats.multiPercentage) {
    var multiEnhancements:Array = [];
    var mp:Object = modInfo.stats.multiPercentage;
    for (var prop:String in mp) {
        var v:Number = Number(mp[prop]);
        if (!isNaN(v) && v != 0) {
            var sign:String = v > 0 ? "+" : "";
            var percent:Number = Math.round(v * 100);
            multiEnhancements.push(sign + percent + "%");
        }
    }
    if (multiEnhancements.length > 0) {
        result.push(" <font color='" + TooltipConstants.COL_ENHANCE + "'>{", multiEnhancements.join(", "), "}</font>");
    }
}
用不同符号（比如 {} 或特殊颜色）把“独立乘区”的百分比与普通 percentage 区分开。
2）如有需要，在 Tooltip 文本中加上运算类型前缀

文件：TooltipTextBuilder.as
有一个辅助函数 buildOperationPrefix(operationType:String) 用来在文本前加 “[分解] / [合成]” 等前缀。
如果你有某些特殊装备是“专门展示这种新乘区玩法”的，可以在 XML description 里用这个机制统一前缀风格（非必需）。
6. 总结：新增运算符需要动到的核心点清单

你要做的修改可以概括为：

数据定义层

data/items/equipment_mods.xml：
文档块里增加新运算符说明。
在具体 <mod> 中加入 <stats><你的新标签>...</你的新标签></stats>。
运算逻辑层（全部在 EquipmentUtil）

EquipmentUtil.loadModData：
像 percentage 一样，把新运算符的百分值转成小数。
EquipmentUtil.accumulateModifiers：
新增一个 multiZoneMultiplier（或你命名的字段），用乘法（factor=1+p）来逐个累积。
EquipmentUtil.applyOperatorsInOrder：
在现有“等级+percentage”的乘区之后，插入对 multiZoneMultiplier 的额外 multiply 调用。
可选：增加 DEBUG trace 方便调试。
显示层

ModsBlockBuilder.build：
可选：为新运算符的百分比提供额外展示（不同颜色/括号），让“这条是独立乘区”能在词条中看出来。
TooltipTextBuilder：
如需要，在描述中增加对这种新玩法的前缀/注释。
如果你确定好新运算符的具体名字（XML 标签名）和精确公式（比如是否支持负数、是否只对某些属性生效），我可以按这个名字帮你把上述改动点再细化成具体伪代码/补全式修改清单方便你直接在 Flash CS6 里改。