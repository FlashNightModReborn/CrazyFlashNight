import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

_root.获得随机坐标偏离 = function(target:Object, offset:Number)
{
	var xOffset:Number = (_root.basic_random() - 0.5) * 2 * offset;
	var yOffset:Number = (_root.basic_random() - 0.5) * 2 * offset;
	return {x:target._x + xOffset, y:target._y + yOffset};
};


_root.寻找攻击目标基础函数 = function(target:Object) 
{
   	if (target.攻击目标 == "无" or _root.gameworld[target.攻击目标].hp <= 0) 
	{
        var enemy:Object = TargetCacheManager.findNearestEnemy(target, 30);
        target.攻击目标 = (enemy) ? enemy._name : "无";
    }
};
