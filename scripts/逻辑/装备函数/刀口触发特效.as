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