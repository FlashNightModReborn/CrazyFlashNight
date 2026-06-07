import org.flashNight.arki.scene.*;
import org.flashNight.arki.weather.*;
// import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

_root.关卡回调函数 = new Object();

_root.关卡回调函数.AVP_重设光照 = function(最大光照, 最小光照){
	if(_root.难度等级 >= 2){
		var envInfo:Object = WeatherSystem.getInstance().getEnvConfig().getInfiniteMapEnvInfo();
		envInfo.最大光照 = 最大光照;
		envInfo.最小光照 = 最小光照;
	}
}

// 角斗场
_root.关卡回调函数.角斗场加载 = function(){
	var playerX = _root.linearEngine.randomIntegerStrict(420,760);
	var playerY = _root.linearEngine.randomIntegerStrict(250,600);
	var enemyX = _root.linearEngine.randomIntegerStrict(420,760);
	var enemyY = _root.linearEngine.randomIntegerStrict(250,600);
	if(_root.linearEngine.randomCheckHalf()) playerX += 540;
	else enemyX += 540;
	_root.gameworld.出生地._x = playerX;
	_root.gameworld.出生地._y = playerY;
	_root.加载敌方人物(enemyX, enemyY);
}
_root.关卡回调函数.角斗场计算敌人数 = function(){
	WaveSpawner.instance.finishRequirement = -_root.敌人同伴数;
}
_root.关卡回调函数.角斗场获胜 = function(){
	_root.金钱 += _root.角斗场奖金;
	_root.最上层发布文字提示("你赢了！获得奖金" + _root.角斗场奖金 + "元！");
}


