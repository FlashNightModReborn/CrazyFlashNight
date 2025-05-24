_root.读盘商城已购买物品 = function()
{
	本地loadgame = SharedObject.getLocal("crazyflasher7_saves");
	if (本地loadgame.data.商城已购买物品.length > 0)
	{
		_root.商城已购买物品 = 本地loadgame.data.商城已购买物品;
	}
}
_root.存盘商城已购买物品 = function()
{
	if (_root.商城已购买物品.length >= 0)
	{
		mysave = SharedObject.getLocal("crazyflasher7_saves");
		mysave.data.商城已购买物品 = _root.商城已购买物品;
		mysave.flush();
	}
}
_root.获取购物车信息 = function()
{
	本地loadgame = SharedObject.getLocal("crazyflasher7_saves");
	if (本地loadgame.data.商城购物车.length > 0)
	{
		_root.商城购物车 = 本地loadgame.data.商城购物车;
	}
}
_root.保存购物车 = function()
{
	if (_root.商城购物车.length >= 0)
	{
		mysave = SharedObject.getLocal("crazyflasher7_saves");
		mysave.data.商城购物车 = _root.商城购物车;
		mysave.flush();
	}
}
_root.获取已购买物品 = function()
{
}
_root.获取虚拟币值 = function()
{
	if (isNaN(_root.虚拟币))
	{
		_root.虚拟币 = 0;
	}
	信息load状态(false);
}
_root.获取购物车总价 = function()
{
	count = 0;
	var _loc1_ = 0;
	while (_loc1_ < 商城购物车.length)
	{
		count += 商城购物车[_loc1_][4] * 商城购物车[_loc1_][3];
		_loc1_ += 1;
	}
	return count;
}
_root.单机版之商城购物车买单 = function()
{
	var _loc1_ = 0;
	while (_loc1_ < 商城购物车.length)
	{
		商城已购买物品.push(商城购物车[_loc1_]);
		_loc1_ += 1;
	}
}
_root.清空购物车 = function(){
	_root.商城购物车 = new Array();
}
_root.商城物品查询 = function(item){
	var i = 0;
	while (i < _root.商城购物车.length)
	{
		if (_root.商城购物车[i][0] == item[0])
		{
			return i;
		}
		i += 1;
	}
	return -1;
}
_root.购物车物品添加 = function(item2, 数量){
	item = item2.slice();
	n = _root.商城物品查询(item);
	if (n == -1){
		item.push(数量);
		商城购物车.push(item);
	}else{
		商城购物车[n][商城购物车[n].length - 1] += 数量;
	}
	_root.商城主mc.刷新购物清单(商城购物车);
	购物车总价 = 获取购物车总价();
	_root.商城主mc.shopCart.购物车按钮.onRelease();
	_root.保存购物车();
}
_root.购物车物品删除 = function(item, 数量)
{
	n = 商城物品查询(item);
	if (n != -1)
	{
		if (商城购物车[n][商城购物车[n].length - 1] > 数量)
		{
			商城购物车[n][商城购物车[n].length - 1] -= 数量;
		}
		else if (商城购物车[n][商城购物车[n].length - 1] == 数量)
		{
			商城购物车.splice(n,1);
		}
	}
	_root.商城主mc.shopCart.购物车按钮.onRelease();
	_root.商城主mc.刷新购物清单(商城购物车);
	购物车总价 = 获取购物车总价();
}
_root.刷新商城信息 = function()
{
}
_root.购物车结账 = function()
{
	_root.购物车总价 = _root.获取购物车总价();
	if (_root.虚拟币支付(_root.购物车总价))
	{
		单机版之商城购物车买单();
		_root.最上层发布文字提示(_root.获得翻译("购买成功！"));
		_root.播放音效("收银机.mp3");
		_root.获取虚拟币值();
		_root.清空购物车();
		_root.保存购物车();
		_root.商城主mc.刷新购物清单();
		_root.购物车总价 = _root.获取购物车总价();
		_root.存盘商城已购买物品();
		_root.商城主mc.shopCart.已买装备按钮.onRelease();
	}
	return undefined;
}
_root.虚拟币支付 = function(amount)
{
	if (虚拟币 > amount)
	{
		_root.虚拟币 -= amount;
		return true;
	}
	_root.最上层发布文字提示(_root.获得翻译("K点不足！"));
	return false;
}
_root.商城已购买物品领取后列表删除 = function(item)
{
	var _loc3_ = new Array();
	var i = 0;
	var 已领取 = false;
	while (i < 商城已购买物品.length)
	{
		if (item[0] != 商城已购买物品[i][0] || 已领取)
		{
			_loc3_.push(商城已购买物品[i]);
			
		}else if(!已领取){
			已领取 = true;
		}
		i += 1;
	}
	商城已购买物品 = _loc3_.slice();
	_root.存盘商城已购买物品();
}

_root.领取商品 = function(item){
	if (_root.物品栏.背包.getFirstVacancy() == -1) _root.最上层发布文字提示(_root.获得翻译("物品栏已满，无法领取！"));
	else _root.领取商品2(item);
}

_root.领取商品2 = function(item)
{
	// if (_root.物品栏添加(item[1], item[item.length - 1], 0) == true){
    if(org.flashNight.arki.item.ItemUtil.singleAcquire(item[1],item[item.length - 1])){
		_root.最上层发布文字提示(_root.获得翻译("成功领取！"));
		商城已购买物品领取后列表删除(item);
	}else{
		_root.最上层发布文字提示(_root.获得翻译("背包空间不足，无法领取！"));
	}
	_root.商城主mc.刷新已买清单();
}

_root.刷新makeList3 = function()
{
	_root.主体load状态(true);
	lv = new LoadVars();
	lv_r = new LoadVars();
	lv.operate = "getShopCarAwards";
	lv.userId = _root.userID;
	lv.sendAndLoad("http://" + _root.address + "/skGame/login.do?" + random(9999),lv_r,"post");
	lv_r.onLoad = function(flag)
	{
		temp = new Array();
		temp2 = new Array();
		arr = new Array();
		temp = this.receiveData.split("|");
		var i = 0;
		while (i < temp.length)
		{
			temp2 = temp[i].split(",");
			arr.push(temp2);
			i += 1;
		}
		_root.商城主mc.shopList.makeList3(arr);
		_root.主体load状态(false);
	};
}
_root.主体load状态 = function(flag)
{
	if (flag)
	{
		商城主mc.shopList.shopListContent._visible = false;
		商城主mc.商城loading1._visible = true;
	}
	else
	{
		商城主mc.shopList.shopListContent._visible = true;
		商城主mc.商城loading1._visible = false;
	}
}
_root.信息load状态 = function(flag)
{
	if (flag)
	{
		商城主mc.商城loading2._visible = true;
		_root.商城主mc.shopCart.商城用户信息._visible = false;
	}
	else
	{
		商城主mc.商城loading2._visible = false;
		_root.商城主mc.shopCart.商城用户信息._visible = true;
	}
}
_root.清单load状态 = function(flag)
{
	if (flag)
	{
		商城主mc.商城loading3._visible = true;
		_root.商城主mc.shopCart.shopCartContent._visible = false;
	}
	else
	{
		商城主mc.商城loading3._visible = false;
		_root.商城主mc.shopCart.shopCartContent._visible = true;
	}
}

System.security.allowDomain("*");
_root.商城购物车 = new Array();
_root.购物车上一次记录 = new Array();
_root.商城已购买物品 = new Array();
// 虚拟币 = -1;
_root.购物车总价 = -1;
_root.商城url = new Object();
_root.订单发送中 = false;
_root.获取虚拟币值();
_root.商城主mc.刷新购物清单();
_root.购物车总价 = _root.获取购物车总价();