_root.UI系统 = {};
_root.UI系统.血条刷新显示 = function() 
{
    var 控制对象 = _root.gameworld[_root.控制目标];
    var 血槽数字当前HP = 控制对象.hp;
    var 血槽数字最大HP = 控制对象.hp满血值;

    if (isNaN(血槽数字当前HP) || isNaN(血槽数字最大HP)) return;

    var 血条格数 = 128;
    var 血量比 = 血槽数字当前HP / 血槽数字最大HP; // 计算HP百分比

    this.gotoAndStop(Math.max(1, 血条格数 + 1 - Math.floor(血量比 * 血条格数))); // 控制血条动画

    this.HP当前值.text = Math.floor(血槽数字当前HP); // 刷新血槽数字
    this.HP最大值.text = Math.floor(血槽数字最大HP);
    this.HP百分比.text = Math.floor(血量比 * 100);
}

_root.UI系统.蓝条刷新显示 = function() 
{
    var 控制对象 = _root.gameworld[_root.控制目标];
    var 蓝条数字当前MP = 控制对象.mp;
    var 蓝条数字最大MP = 控制对象.mp满血值;

	if (isNaN(蓝条数字当前MP) || isNaN(蓝条数字最大MP)) return;

    // 格式化当前MP和最大MP为五位数，前面补零
    var 格式化当前MP = _root.常用工具函数.补零到宽度(蓝条数字当前MP, 5);
    var 格式化最大MP = _root.常用工具函数.补零到宽度(蓝条数字最大MP, 5);
    var 蓝量比 = 蓝条数字当前MP / 蓝条数字最大MP; // 计算MP百分比
	var 蓝条格数 = 100;

    this.MP数据显示.text = 格式化当前MP + "/" + 格式化最大MP;
    this.当前MP.text = Math.floor(蓝条数字当前MP);
    this.最大MP.text = Math.floor(蓝条数字最大MP);
    this.MP百分比.text = Math.floor(蓝量比 * 100) + "%"; 
    this.gotoAndStop(Math.max(1, 蓝条格数 + 1 - Math.floor(蓝量比 * 蓝条格数))); // 控制蓝条动画
}


_root.UI系统.韧性刷新显示 = function() 
{
    var target:MovieClip = _root.gameworld[_root.控制目标];
    var poiseNumber:Number = target.nonlinearMappingResilience; // 获取韧性百分比

    // _root.发布消息("韧性百分比", poiseNumber); // 发布韧性百分比消息

	if (isNaN(poiseNumber)) return;

	var frameCount:Number = 30;

    this.poise = Math.floor(poiseNumber * 100) + "%"; 
    this.gotoAndStop(Math.max(1, frameCount + 1 - Math.floor(poiseNumber * frameCount))); // 控制蓝条动画
}
