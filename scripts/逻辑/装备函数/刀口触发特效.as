_root.刀口触发特效 = {};
_root.刀口触发特效.十文字大剑特效 = function(状态名)
{
    var range = 4;
    var xOffset = (Math.random() - 0.5) * 2 * range;
    var yOffset = (Math.random() - 0.5) * 2 * range;
    var shooter = this.自机;
    var myPoint = {x:shooter._x + xOffset, y:shooter._y + yOffset};
    声音 = "";
    霰弹值 = 1;
    子弹散射度 = 0;
    发射效果 = "";
    switch (状态名)
    {
        case "兵器一段中" :
            子弹种类 = "黑龙1段正斩";
            子弹威力 = 120;
            break;
        case "兵器二段中" :
            子弹种类 = "黑龙2段斜斩";
            子弹威力 = 120;
            break;
        case "兵器三段中" :
            子弹种类 = "黑龙3段突刺";
            子弹威力 = 120;
            break;
        case "兵器四段中" :
            子弹种类 = "黑龙4段上斩";
            子弹威力 = 120;
            break;
        case "兵器五段中" :
            子弹种类 = "黑龙5段重斩";
            子弹威力 = 120;
            break;
        case "兵器冲击" :
            子弹种类 = "黑龙3段突刺";
            子弹威力 = 240;
            break;
        default :
            return;
    }
    子弹速度 = 0;
    击中地图效果 = "";
    Z轴攻击范围 = 50;
    击倒率 = 50;
    击中后子弹的效果 = "";
    发射者名 = this.自机._name;
    shootX = myPoint.x;
    Z轴坐标 = shootY = this.自机._y;
    _root.子弹区域shoot(声音,霰弹值,子弹散射度,发射效果,子弹种类,子弹威力,子弹速度,Z轴攻击范围,击中地图效果,发射者名,shootX,shootY,Z轴坐标,null,击倒率,击中后子弹的效果);
};


_root.刀口触发特效.黑铁的剑特效 = function(状态名)
{
    var range = 4;
    var xOffset = (Math.random() - 0.5) * 2 * range;
    var yOffset = (Math.random() - 0.5) * 2 * range;
    var shooter = this.自机;
    var myPoint = {x:shooter._x + xOffset, y:shooter._y + yOffset};
    声音 = "";
    霰弹值 = 1;
    子弹散射度 = 0;
    发射效果 = "";
    switch (状态名)
    {
        case "兵器一段中" :
            子弹种类 = "黑铁1段正斩";
            子弹威力 = 240;
            break;
        case "兵器二段中" :
            子弹种类 = "黑铁2段斜斩";
            子弹威力 = 240;
            break;
        case "兵器三段中" :
            子弹种类 = "黑铁3段突刺";
            子弹威力 = 240;
            break;
        case "兵器四段中" :
            子弹种类 = "黑铁4段上挑";
            子弹威力 = 240;
            break;
        case "兵器五段中" :
            子弹种类 = "黑铁5段下劈";
            子弹威力 = 240;
            break;
			// case "兵器冲击" :
			// 	子弹种类 = "黑龙3段突刺";
			// 	子弹威力 = 240;
			// 	break;
        default :
            return;
    }
    子弹速度 = 0;
    击中地图效果 = "";
    Z轴攻击范围 = 60;
    击倒率 = 50;
    击中后子弹的效果 = "";
    发射者名 = this.自机._name;
    shootX = myPoint.x;
    Z轴坐标 = shootY = this.自机._y;
    
    _root.子弹区域shoot(声音,霰弹值,子弹散射度,发射效果,子弹种类,子弹威力,子弹速度,Z轴攻击范围,击中地图效果,发射者名,shootX,shootY,Z轴坐标,null,击倒率,击中后子弹的效果);

    if (_root.成功率(20))
    {
        var range = 4;
        var xOffset = (Math.random() - 0.5) * 2 * range;
        var yOffset = (Math.random() - 0.5) * 2 * range;
        var shooter = _parent._parent._parent._parent._parent;
        var myPoint = {x:shooter._x + xOffset, y:shooter._y + yOffset};
        声音 = "";
        霰弹值 = 1;
        子弹散射度 = 0;
        发射效果 = "";
        子弹种类 = "剑光特效";
        子弹威力 = 200;
        子弹速度 = 0;
        击中地图效果 = "";
        Z轴攻击范围 = 120;
        击倒率 = 1;
        击中后子弹的效果 = "";
        发射者名 = this.自机._name;
        shootX = myPoint.x;
        Z轴坐标 = shootY = this.自机._y;
        _root.子弹区域shoot(声音,霰弹值,子弹散射度,发射效果,子弹种类,子弹威力,子弹速度,Z轴攻击范围,击中地图效果,发射者名,shootX,shootY,Z轴坐标,null,击倒率,击中后子弹的效果);
    }
    if (_root.成功率(5))
    {
        var range = 4;
        var xOffset = (Math.random() - 0.5) * 2 * range;
        var yOffset = (Math.random() - 0.5) * 2 * range;
        var shooter = this.自机;
        var myPoint = {x:shooter._x + xOffset, y:shooter._y + yOffset};
        声音 = "";
        霰弹值 = 1;
        子弹散射度 = 0;
        发射效果 = "";
        子弹种类 = "黑铁集气";
        子弹威力 = 0;
        子弹速度 = 0;
        击中地图效果 = "";
        Z轴攻击范围 = 60;
        击倒率 = 1;
        击中后子弹的效果 = "";
        发射者名 = this.自机._name;
        shootX = myPoint.x;
        Z轴坐标 = shootY = this.自机._y;
        _root.子弹区域shoot(声音,霰弹值,子弹散射度,发射效果,子弹种类,子弹威力,子弹速度,Z轴攻击范围,击中地图效果,发射者名,shootX,shootY,Z轴坐标,null,击倒率,击中后子弹的效果);
    }
};


_root.刀口触发特效.主唱光剑光刃 = function(状态名)
{
    this.自机.dispatcher.publish("主唱光剑光刃", 状态名);
};


// ============================================================================
//  烬灭裁决 / 秋月 段位特效（火属性追加子弹）
//  调用约定：from MC onClipEvent(enterFrame) via .call({自机:u}, u.getSmallState())
// ============================================================================

// 内部发射器：从自机附近随机扰动位置发射追加子弹
_root.刀口触发特效.__发射火子弹 = function(unit, 子弹种类, 威力)
{
    var range = 4;
    var xOffset = (Math.random() - 0.5) * 2 * range;
    var yOffset = (Math.random() - 0.5) * 2 * range;
    var shootX = unit._x + xOffset;
    var shootY = unit._y + yOffset;
    _root.子弹区域shoot("", 1, 0, "", 子弹种类, 威力, 0, 50, "",
        unit._name, shootX, shootY, shootY, null, 50, "");
};

// 长柄形态：5 段 + 兵器冲击；300ms 节流
_root.刀口触发特效.烬灭裁决长柄特效 = function(状态名)
{
    var unit = this.自机;
    if (!isNaN(unit.上次烬灭特效时间) &&
        getTimer() - unit.上次烬灭特效时间 < 300) return;
    unit.上次烬灭特效时间 = getTimer();

    var 子弹种类;
    var 子弹威力 = 120;
    switch (状态名)
    {
        case "兵器一段中": 子弹种类 = "__长柄1段占位"; break;
        case "兵器二段中": 子弹种类 = "__长柄2段占位"; break;
        case "兵器三段中": 子弹种类 = "__长柄3段占位"; break;
        case "兵器四段中": 子弹种类 = "__长柄4段占位"; break;
        case "兵器五段中": 子弹种类 = "__长柄5段占位"; break;
        case "兵器冲击":   子弹种类 = "__长柄冲击占位"; 子弹威力 = 240; break;
        default: return;
    }
    _root.刀口触发特效.__发射火子弹(unit, 子弹种类, 子弹威力);
};

// 双刀形态：只到 4 段（双刀连招无段5/兵器冲击）；300ms 节流
_root.刀口触发特效.烬灭裁决双刀特效 = function(状态名)
{
    var unit = this.自机;
    if (!isNaN(unit.上次烬灭特效时间) &&
        getTimer() - unit.上次烬灭特效时间 < 300) return;
    unit.上次烬灭特效时间 = getTimer();

    var 子弹种类;
    switch (状态名)
    {
        case "兵器一段中": 子弹种类 = "__双刀1段占位"; break;
        case "兵器二段中": 子弹种类 = "__双刀2段占位"; break;
        case "兵器三段中": 子弹种类 = "__双刀3段占位"; break;
        case "兵器四段中": 子弹种类 = "__双刀4段占位"; break;
        default: return;
    }
    _root.刀口触发特效.__发射火子弹(unit, 子弹种类, 120);
};

// 秋月迁移：MP 门控 + 0.5s 冷却 + 段位四档并列判定（1:1 复刻 刀-秋月.xml:17-210）
_root.刀口触发特效.秋月特效 = function(状态名)
{
    var unit = this.自机;
    var 冷却时间间隔 = 0.5;
    var 当前时间 = getTimer();
    if (!isNaN(unit.上次释放时间) &&
        当前时间 - unit.上次释放时间 <= 冷却时间间隔 * 1000) return;
    unit.上次释放时间 = 当前时间;

    unit.man.攻击时可改变移动方向(1);

    var 耗蓝比例 = 1;
    var 耗蓝量 = Math.floor(unit.mp满血值 / 100 * 耗蓝比例);
    var 是控制目标 = (unit == _root.gameworld[_root.控制目标]);

    // 段 2：金起 + 黄金集气
    var 特效许可 = (状态名 == "兵器二段中");
    if (特效许可)
    {
        if (unit.mp >= 耗蓝量)
        {
            _root.刀口触发特效.__发射火子弹(unit, "金起", 耗蓝量 * 50);
        }
        else if (是控制目标)
        {
            _root.发布消息("气力不足，难以发挥装备的真正力量……");
        }
    }

    // 段 2 / 段 5：黄金集气（段2 100% 触发；段5 成功率 0 —— 实际不触发，保留与原 MC 一致）
    特效许可 = false;
    switch (状态名)
    {
        case "兵器二段中": 特效许可 = true; break;
        case "兵器五段中": 特效许可 = _root.成功率(0); break;
    }
    if (特效许可)
    {
        if (unit.mp >= 耗蓝量)
        {
            _root.刀口触发特效.__发射火子弹(unit, "黄金集气", 耗蓝量 * 15);
        }
        else if (是控制目标)
        {
            _root.发布消息("气力不足，难以发挥装备的真正力量……");
        }
    }

    // 段 3 / 兵器冲击：圣刺（扣蓝）
    特效许可 = (状态名 == "兵器三段中" || 状态名 == "兵器冲击");
    if (特效许可)
    {
        if (unit.mp >= 耗蓝量)
        {
            unit.mp -= 耗蓝量;
            _root.刀口触发特效.__发射火子弹(unit, "圣刺", 耗蓝量 * 75);
        }
        else if (是控制目标)
        {
            _root.发布消息("气力不足，难以发挥装备的真正力量……");
        }
    }

    // 段 4 / 兵器冲击：圣爆（扣蓝；兵器冲击走默认成功率 0 分支，实际不触发）
    特效许可 = false;
    switch (状态名)
    {
        case "兵器四段中": 特效许可 = true; break;
        case "兵器冲击":   特效许可 = _root.成功率(0); break;
    }
    if (特效许可)
    {
        if (unit.mp >= 耗蓝量)
        {
            unit.mp -= 耗蓝量;
            _root.刀口触发特效.__发射火子弹(unit, "圣爆", 耗蓝量 * 70);
        }
    }
};