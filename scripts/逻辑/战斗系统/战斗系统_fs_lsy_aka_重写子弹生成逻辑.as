//重写子弹生成逻辑
_root.子弹生成计数 = 0;

//加入新参数水平击退速度和垂直击退速度。未填写的话默认分别为10和5（和子弹区域shoot一致），最大击退速度可以调节下方常数（目前为33）。
//额外添加了命中率,固伤,百分比伤害，血量上限击溃，防御粉碎，命中率未输入则寻找发射者的命中，固伤与百分比未输入默认为0
_root.最大水平击退速度 = 33;
_root.最大垂直击退速度 = 15;

_root.子弹区域shoot = function(声音, 霰弹值, 子弹散射度, 发射效果, 子弹种类, 子弹威力, 子弹速度, Z轴攻击范围, 击中地图效果, 发射者, shootX, shootY, shootZ, 子弹敌我属性, 击倒率, 击中后子弹的效果, 水平击退速度, 垂直击退速度, 命中率, 固伤, 百分比伤害, 血量上限击溃, 防御粉碎, 区域定位area, 吸血, 毒, 最小霰弹值, 不硬直, 伤害类型, 魔法伤害属性, 速度X, 速度Y, ZY比例, 斩杀, 暴击, 水平击退反向, 角度偏移)
{
	var 子弹属性 = {
		声音:声音,
		霰弹值:霰弹值,
		子弹散射度:子弹散射度,
		发射效果:发射效果,
		子弹种类:子弹种类,
		子弹威力:子弹威力,
		子弹速度:子弹速度,
		Z轴攻击范围:Z轴攻击范围,
		击中地图效果:击中地图效果,
		发射者:发射者,
		shootX:shootX,
		shootY:shootY,
		shootZ:shootZ,
		子弹敌我属性:子弹敌我属性,
		击倒率:击倒率,
		击中后子弹的效果:击中后子弹的效果,
		水平击退速度:水平击退速度,
		垂直击退速度:垂直击退速度,
		命中率:命中率,
		固伤:固伤,
		百分比伤害:百分比伤害,
		血量上限击溃:血量上限击溃,
		防御粉碎:防御粉碎,
		区域定位area:区域定位area,
		吸血:吸血,
		毒:毒,
		最小霰弹值:最小霰弹值,
		不硬直:不硬直,
		伤害类型:伤害类型,
		魔法伤害属性:魔法伤害属性,
		速度X:速度X,
		速度Y:速度Y,
		ZY比例:ZY比例,
		斩杀:斩杀,
		暴击:暴击,
		水平击退反向:水平击退反向,
		角度偏移:角度偏移
	};
	_root.子弹区域shoot传递(子弹属性);
}

_root.子弹区域shoot传递 = function(Obj){
	//暂停判定
	if (_root.暂停 || isNaN(Obj.子弹威力)) return;
	
	//控制部分
	Obj.角度偏移 = isNaN(Obj.角度偏移) ? 0 : Number(Obj.角度偏移);
	var 基础射击角度:Number = 0;
	// var 按键偏移角度:Number = 30; //根据按键上下偏移30度 
	var 游戏世界 = _root.gameworld;
	var 发射对象 = 游戏世界[Obj.发射者];
	var 发射方向 = 发射对象.方向;
	var 射击角度 = 0;
	if (Obj.子弹速度 < 0) 
	{
    	Obj.子弹速度 *= -1;
		发射方向 = 发射方向 === "右" ? "左" : "右";
	}
	if(发射方向 === "左")
	{
		基础射击角度 = 180;
		Obj.角度偏移 = -Obj.角度偏移;
	}

    射击角度 = 基础射击角度 + 发射对象._rotation + Obj.角度偏移;// 兼容喷气背包的角度
	
	var depth = _root.随机整数(0, _root.发射效果上限);
	var f_name = "f" + depth;
	
	var 发射效果对象 = 游戏世界.效果.attachMovie(Obj.发射效果, f_name, depth, {_xscale:发射对象._xscale, _x:Obj.shootX, _y:Obj.shootY, _rotation:Obj.角度偏移});
	//_root.服务器.发布服务器消息(f_name + " " + depth + " " + 发射效果 + " " + 发射对象._xscale + " " + shootX + " " + shootY);
	_root.弹壳系统.发射弹壳(Obj.子弹种类, Obj.shootX, Obj.shootY, 发射对象._xscale);
	_root.播放音效(Obj.声音);
	
	Obj.近战检测 = Obj.子弹种类.indexOf("近战") != -1;//额外控制是否鞭尸
	Obj.联弹检测 = Obj.子弹种类.indexOf("联弹") != -1;//判断是否解析子弹种类分割
	Obj.穿刺检测 =  Obj.穿刺检测 || Obj.子弹种类.indexOf("穿刺") != -1;//判断是否短路消耗霰弹值
	Obj.透明检测 = Obj.透明检测 || Obj.子弹种类 === "近战子弹" || Obj.子弹种类 === "近战联弹" || Obj.子弹种类 === "透明子弹";//判断生成子弹时是否使用带线框的Object而非MovieClip
	Obj.手雷检测 = Obj.手雷检测 || Obj.子弹种类.indexOf("手雷") != -1;//判断是否为手雷
	Obj.爆炸检测 = Obj.爆炸检测 || Obj.子弹种类.indexOf("爆炸") != -1;//判断是否为爆炸
	Obj.普通检测 = !Obj.穿刺检测 && !Obj.爆炸检测  && !Obj.穿刺检测 && ( Obj.近战检测 ||  Obj.透明检测 || Obj.子弹种类.indexOf("普通") > -1  || Obj.子弹种类.indexOf("能量子弹") > -1 || Obj.子弹种类=="精制子弹")
	Obj.固伤 = isNaN(Obj.固伤) ? 0 : Obj.固伤;//未初始化则为0
	Obj.命中率 = isNaN(Obj.命中率) ? 发射对象.命中率 : Obj.命中率;
	Obj.最小霰弹值 = isNaN(Obj.最小霰弹值) ? 1 : Obj.最小霰弹值;//未初始化则为0
	Obj.远距离不消失 = Obj.手雷检测 || Obj.爆炸检测;
	
	var 子弹实例种类;
	var 联弹霰弹值;

	if(Obj.联弹检测)
	{
		子弹实例种类 = Obj.子弹种类.split("-")[0];
		联弹霰弹值 = Obj.霰弹值;
	}
	else
	{
		子弹实例种类 = Obj.子弹种类;
		联弹霰弹值 = 1;
	}
	Obj.子弹实例种类 = 子弹实例种类;
	Obj.伤害类型 = !Obj.伤害类型 && 发射对象.伤害类型 ? 发射对象.伤害类型 : Obj.伤害类型;
	Obj.魔法伤害属性 = !Obj.魔法伤害属性 && 发射对象.魔法伤害属性 ? 发射对象.魔法伤害属性 : Obj.魔法伤害属性;
	Obj.吸血 = Obj.吸血 || 发射对象.吸血? Math.max((isNaN(Obj.吸血) ? 0 : Obj.吸血), (isNaN(发射对象.吸血) ? 0 : 发射对象.吸血)) : Obj.吸血;
	Obj.击溃 = Obj.血量上限击溃 || 发射对象.击溃? Math.max((isNaN(Obj.血量上限击溃) ? 0 : Obj.血量上限击溃), (isNaN(发射对象.击溃) ? 0 : 发射对象.击溃)) : Obj.血量上限击溃;

	Obj.水平击退速度 = (isNaN(Obj.水平击退速度) || Obj.水平击退速度 < 0) ? 10 : Math.min(Obj.水平击退速度, _root.最大水平击退速度);
	Obj.垂直击退速度 = Math.min(Obj.垂直击退速度, _root.最大垂直击退速度);

	Obj.发射者名 = Obj.发射者;
	Obj.子弹敌我属性值 = Obj.子弹敌我属性;
	Obj._x = Obj.shootX;
	Obj._y = Obj.shootY;
	Obj.Z轴坐标 = Obj.shootZ;
	Obj.子弹区域area = Obj.区域定位area;

	//创建子弹
	var 子弹总数 = Obj.联弹检测 ? 1 : Obj.霰弹值;
	var 子弹实例;
	for (var 子弹计数 = 0; 子弹计数 < 子弹总数; 子弹计数++)
	{
		var 散射角度 = Obj.近战检测 ? 0 : 射击角度 + (Obj.联弹检测 ? 0 : _root.随机偏移(Obj.子弹散射度));//根据散射度偏转非联弹子弹角度,近战子弹取消散射
		var 形状偏角 = 0;
		if(Obj.ZY比例 && Obj.速度X && Obj.速度Y){
			形状偏角 = Math.atan2(Obj.速度Y, Obj.速度X) * (180 / Math.PI);
			if (形状偏角 < 0) {
    			形状偏角 += 360;
			}
		}else{
			形状偏角 = 散射角度;
		}
		Obj._rotation = 形状偏角;
		var angle = 散射角度 * (Math.PI / 180);//角度转弧度
		if(Obj.透明检测){
			子弹实例 = _root.对象浅拷贝(Obj);//使用Object而非影片剪辑
		}else{
			_root.子弹生成计数 = (_root.子弹生成计数 + 1) % 100;//通过计数，控制非近战子弹编号在0-99之间
			var depth = 游戏世界.子弹区域.getNextHighestDepth();
			var b_name = Obj.发射者名 + Obj.子弹种类 + depth + 散射角度 + _root.子弹生成计数;
			子弹实例 = 游戏世界.子弹区域.attachMovie(子弹实例种类, b_name, depth, Obj);//联弹兼容
		}
		子弹实例.xmov = 子弹实例.子弹速度 * Math.cos(angle);
		子弹实例.ymov = 子弹实例.子弹速度 * Math.sin(angle);
		子弹实例.霰弹值 = 联弹霰弹值;

		//在子弹之前取实际的吸血、毒、击溃值
		if(Obj.毒 || 发射对象.淬毒 || 发射对象.毒)
		{
			var 发射者淬毒 = isNaN(发射对象.淬毒) ? 0 : 发射对象.淬毒;
			Obj.毒 = Math.max((isNaN(Obj.毒) ? 0 : Obj.毒),(isNaN(发射对象.毒) ? 0 : 发射对象.毒));
			if(发射者淬毒 && 发射者淬毒 > Obj.毒)
			{
				子弹实例.毒 = 发射者淬毒;
				子弹实例.淬毒衰减 = 1;
				if(!子弹实例.近战检测 && 发射对象.淬毒 > 10)
				{
					发射对象.淬毒 -= 1;
				}
			}
			else
			{
				子弹实例.毒 = Obj.毒;
			}
		}
		//若透明检测通过则立即进行伤害判定（然后扔了等gc）
		if(子弹实例.透明检测){
			子弹实例.子弹生命周期 = _root.子弹生命周期;
			子弹实例.子弹生命周期();
		}else{
			子弹实例.onEnterFrame = _root.子弹生命周期;
		}
	}
	return 子弹实例;//返回生成的最后一个子弹 计划是联弹全覆盖后每次函数只生成一次子弹
};

_root.子弹生命周期 = function()
{
	if(!this.area && !this.透明检测){
		_root.子弹基础运动控制(this);
		return;
	}

	var 检测area:MovieClip;
	var area线框:Object;
	if(this.透明检测 && !this.子弹区域area){
		area线框 = {left: this._x - 12.5, right: this._x + 12.5, top: this._y - 12.5, bottom: this._y + 12.5};//近战子弹默认线框
	}else{
		if(this.子弹区域area){
			检测area = this.子弹区域area;
		}else{
			检测area = this.area;
		}
		//var area_key = 检测area._x + "_" + 检测area._y + "_" + 检测area._width + "_" + 检测area._height;
		var area_key:String = (检测area._x ^ 检测area._height) + "_" + (检测area._width ^ 检测area._y);//异或节约运算字符串成本
		if (!this[area_key]) this[area_key] = {area:_root.areaToRectGameworld(检测area),x:this._x,y:this._y};
		var cache_area:MovieClip = this[area_key].area;//哈希缓存线框，期望对常规子弹只需要计算一次
		var x_offsst:Number = this._x - this[area_key].x;
		var y_offsst:Number = this._y - this[area_key].y;
		area线框 = {left: cache_area.left + x_offsst, right: cache_area.right + x_offsst, top: cache_area.top + y_offsst, bottom: cache_area.bottom + y_offsst};//缓存线框
	}
	
	var 点集碰撞检测许可:Boolean = this.联弹检测 && this._rotation != 0 && this._rotation != 180;//联弹检测且子弹旋转时才进行点集碰撞检测
	if(点集碰撞检测许可)
	{
		var area点集 = _root.影片剪辑至游戏世界点集(检测area);//缓存点集
		var area面积 = _root.点集面积系数(area点集);
		var area点集边向量 = [];//缓存边向量
		var 击中点集 = [
			_root.创建向量(矩形a[0].x - 矩形a[3].x, 矩形a[0].y - 矩形a[3].y),
			_root.创建向量(矩形a[1].x - 矩形a[0].x, 矩形a[1].y - 矩形a[0].y),
			_root.创建向量(矩形a[2].x - 矩形a[1].x, 矩形a[2].y - 矩形a[1].y),
			_root.创建向量(矩形a[3].x - 矩形a[2].x, 矩形a[3].y - 矩形a[2].y)
		];
	}
	else
	{
		var 击中矩形 = {};
		var area面积 = _root.calculateRectArea(area线框);
	}

	if (_root.调试模式)
	{
		_root.绘制线框(检测area);
	}
	var 游戏世界 = _root.gameworld;
	var 发射对象 = 游戏世界[this.发射者名];
	var 遍历敌人表 = _root.帧计时器.获取敌人缓存(发射对象,5);
	if(this.友军伤害){
		var 遍历友军表 = _root.帧计时器.获取友军缓存(发射对象,5);
		遍历敌人表 = 遍历敌人表.concat(遍历友军表);
	}
	var 击中次数 = 0;
	var 是否生成击中后效果 = true;
	
	for (i = 0; i < 遍历敌人表.length ; ++i)
	{
		this.命中对象 = 遍历敌人表[i];
		var Z轴坐标差 = this.命中对象.Z轴坐标 - this.Z轴坐标;

		if (Math.abs(Z轴坐标差) >= this.Z轴攻击范围 || !(this.命中对象.是否为敌人 == this.子弹敌我属性值))
		{
			continue;//过滤掉远距离的敌人与非敌人
		}
		if ((this.命中对象._name != this.发射者名 || this.友军伤害) && this.命中对象.防止无限飞 != true || (this.命中对象.hp <= 0 && !this.近战检测))
		{
			var 覆盖率 = 1;// 对于非联弹情况，击中判定已经由 AABB 检测确定
			var 目标线框 = this.命中对象.area.getRect(游戏世界);
			var 碰撞中心;
			if (_root.aabb碰撞检测(area线框, 目标线框, Z轴坐标差)) {
				if (this.联弹检测) {
					if(点集碰撞检测许可){
						击中点集 = _root.点集碰撞检测(area点集, this.命中对象.area, area点集边向量,Z轴坐标差);// 进行更精细的点集碰撞检测
						if(击中点集.length < 3)
						{
							continue;// 未击中
						}
						覆盖率 = _root.点集面积系数(击中点集) / area面积;// 计算覆盖率
						碰撞中心 = {x:this._x,y:this._y};
					}
					else{
						击中矩形 = _root.rectHitTest(area线框, this.命中对象.area, Z轴坐标差);// 计算矩形交集
						覆盖率 = _root.calculateRectArea(击中矩形) / area面积;// 计算覆盖率
						if(覆盖率 <= 0)
						{
							continue;// 未击中
						}
						碰撞中心 = {x:(击中矩形.left + 击中矩形.right) / 2, y:(击中矩形.top + 击中矩形.bottom) / 2};
					}
				}else{
					//获取aabb的碰撞中心
					碰撞中心 = {
						x:(Math.max(area线框.left,目标线框.xMin) + Math.min(area线框.right,目标线框.xMax)) / 2,
						y:(Math.max(area线框.top,目标线框.yMin) + Math.min(area线框.bottom,目标线框.yMax)) / 2
					};
				}
			} else {
				continue; // AABB 检测未通过，无碰撞
			}
			//击中
			击中次数++;
			if(_root.调试模式)
			{
				_root.绘制线框(this.命中对象.area);
			}
			var 命中对象血槽 = this.命中对象.新版人物文字信息 ? this.命中对象.新版人物文字信息.头顶血槽 : this.命中对象.人物文字信息.头顶血槽;
			命中对象血槽._visible = true;
			命中对象血槽.gotoAndPlay(2);
			this.命中对象.攻击目标 = 发射对象._name;

			//刷新冲击力的状态
			_root.冲击力刷新(this.命中对象);

			//伤害结算
			if(this.命中对象.无敌 || this.命中对象.man.无敌标签 || this.命中对象.NPC){
				if(this.击中时触发函数){
					this.击中时触发函数();
				}
			}
			else if (this.命中对象.hp != 0)
			{
				var 伤害字符 = "";
				var 伤害数字颜色 = this.子弹敌我属性值 ? "#FFCC00" : "#FF0000";
				
				this.命中对象.防御力 = isNaN(this.命中对象.防御力) ? 1 : Math.min(this.命中对象.防御力, 99000);//控制上限并做异常处理
				//子弹击中时进行一定的操作
				if(this.击中时触发函数){
					this.击中时触发函数();
				}
				this.破坏力 = Number(this.子弹威力) + (isNaN(发射对象.伤害加成) ? 0 : 发射对象.伤害加成);//计算防御减伤
				var 伤害波动数字 = this.破坏力 * ((!_root.调试模式 || this.霰弹值 > 1) ? (0.85 + _root.basic_random() * 0.3) : 1);//上下波动 15% 
				var 百分比伤 = isNaN(this.百分比伤害) ? 0 : this.命中对象.hp * this.百分比伤害 / 100;//未初始化则为0
				this.破坏力 = 伤害波动数字 + this.固伤 + 百分比伤;
				
				//暴击函数处理伤害，暴击参数应为一个函数，传参为子弹本身，返回值应为默认为1的倍率
				if(this.暴击){
					this.破坏力 = this.破坏力 * this.暴击(this);
				}
				
				if(this.伤害类型 === "真伤"){
					伤害数字颜色 = this.子弹敌我属性值 ? "#4A0099" : "#660033";
					伤害字符 += '<font color="'+伤害数字颜色+'" size="20"> 真</font>';
					this.命中对象.损伤值 = this.破坏力;
				}else if(this.伤害类型 === "魔法"){
					伤害数字颜色 = this.子弹敌我属性值 ? "#0099FF" : "#AC99FF";
					var 魔法伤害属性字符 = this.魔法伤害属性 ? this.魔法伤害属性 : "能";
					伤害字符 += '<font color="' + 伤害数字颜色 + '" size="20"> ' + 魔法伤害属性字符 + '</font>';
					var 敌人法抗 = this.魔法伤害属性 ? (this.命中对象.魔法抗性 && (this.命中对象.魔法抗性[this.魔法伤害属性] || this.命中对象.魔法抗性[this.魔法伤害属性]===0) ? this.命中对象.魔法抗性[this.魔法伤害属性]: (this.命中对象.魔法抗性 && (this.命中对象.魔法抗性["基础"] ||this.命中对象.魔法抗性["基础"]===0) ? this.命中对象.魔法抗性["基础"]: 10 +this.命中对象.等级 / 2 )  ):(this.命中对象.魔法抗性 && (this.命中对象.魔法抗性["基础"] || this.命中对象.魔法抗性["基础"]===0) ? this.命中对象.魔法抗性["基础"]: 10 +this.命中对象.等级 / 2 );
					敌人法抗 = isNaN(敌人法抗) ? 20:Math.min(Math.max(敌人法抗,-1000),100);
					this.命中对象.损伤值 = Math.floor(this.破坏力 *(100 - 敌人法抗) / 100);
				}else{
					this.命中对象.损伤值 = this.破坏力 * _root.防御减伤比(this.命中对象.防御力);
				}
				
				
				//为踩人命中倒地敌人时增加暴击伤害                                                                                          
				if (this.发射者名 == "玩家0" && 发射对象.getSmallState() == "踩人中" && (this.命中对象.状态 == "击倒" || this.命中对象.状态 == "倒地"))
				{
					this.命中对象.损伤值 *= 1.5;
				}
				
				//所有闪避后结算的附加层的伤害计算值
				this.附加层伤害计算 = 0;
				var 淬毒量 = 0;       
				var 击溃量 = 0;
				if (this.毒 > 0)
				{
					淬毒量 = this.毒;
					//if(this.穿刺检测){
					//if(!this.穿刺检测 && this.子弹实例种类.indexOf("爆炸") == -1 && ( this.近战检测 || this.透明检测 || this.子弹实例种类.indexOf("普通") > -1  || this.子弹实例种类.indexOf("能量子弹") > -1 )){
					if(this.普通检测){
						淬毒量 *= 1;
					}else{
						淬毒量 *= 0.3;
					}
					this.附加层伤害计算 += 淬毒量;
				}                                                          
				if (this.击溃 > 0 && this.命中对象.hp满血值 > 0)
				{
					击溃量 = Math.floor(this.命中对象.hp满血值 * this.击溃 / 100);
					this.附加层伤害计算 += 击溃量;
				}

				//var 伤害波动数字 = this.命中对象.损伤值 * ((!_root.调试模式 || this.霰弹值 > 1) ? (0.85 + _root.basic_random() * 0.3) : 1);
				var 伤害数字 = this.命中对象.损伤值;
				var 伤害数字大小 = 28;
				var 显示数字;
				var 躲闪状态 = this.伤害类型 == "真伤" ? "未躲闪": _root.躲闪状态计算(this.命中对象,_root.根据命中计算闪避结果(发射对象, this.命中对象, 命中率),this);//计算躲闪命中情况,如果命中未赋值则查找发射者属性
				var 躲闪状态字符 = "";
				var 原始伤害数字 = 伤害数字;
				switch (躲闪状态)
				{
					case "跳弹" :
						伤害数字 = _root.跳弹伤害计算(伤害数字, this.命中对象.防御力);
						this.命中对象.损伤值 = 伤害数字;//_root.发布调试消息("跳弹");
						伤害数字大小 *= 0.3 + 0.7 * 伤害数字 / 原始伤害数字;
						伤害数字颜色 = this.子弹敌我属性值 ? "#7F6A00" : "#7F0000";
						break;
					case "过穿" :
						伤害数字 = _root.过穿伤害计算(伤害数字, this.命中对象.防御力);
						this.命中对象.损伤值 = 伤害数字;//_root.发布调试消息("过穿");
						伤害数字大小 *= 0.3 + 0.7 * 伤害数字 / 原始伤害数字;
						伤害数字颜色 = this.子弹敌我属性值 ? "#FFE770" : "#FF7F7F";
						break;
					case "躲闪" :
					case "直感" :
						伤害数字 = NaN;
						this.命中对象.损伤值 = 0;//_root.发布调试消息("躲闪");
						伤害数字大小 *= 0.5;
						break;
					case "格挡" :
						伤害数字 = this.命中对象.受击反制(伤害数字,this);
						if(伤害数字){
							this.命中对象.损伤值 = 伤害数字;
							伤害数字大小 *= 0.3 + 0.7 * this.命中对象.损伤值 / 原始伤害数字;
						}else if(伤害数字 === 0){
							this.命中对象.损伤值 = 0;
							伤害数字大小 *= 1.2;
							break;
						}else{
							伤害数字 = NaN;
							this.命中对象.损伤值 = 0;
							伤害数字大小 *= 0.5;
							break;
						}
					default :
						伤害数字 = Math.max(Math.floor(伤害数字), 1);// 向下取整且确保不小于1
						this.命中对象.损伤值 = 伤害数字;
						_root.受击变红(120,this.命中对象);//未躲闪则变红
				}
						
				var 消耗霰弹值 = Math.min(this.霰弹值,Math.ceil(Math.min(this.最小霰弹值 + 覆盖率 * ((this.霰弹值-this.最小霰弹值) + 1) * 1.2,this.命中对象.hp / this.命中对象.损伤值)));
				if (this.联弹检测 && !this.穿刺检测) {
					this.霰弹值 -= 消耗霰弹值;
				}
				//_root.发布调试消息("消耗霰弹值"+消耗霰弹值+"+"+this.霰弹值);
				this.命中对象.损伤值 *= 消耗霰弹值;
				伤害数字 *= 消耗霰弹值;
				//var 控制字符串 ="数字特效" + ( 子弹敌我属性 ? 1 : 2);
				var 控制字符串 = "";
				//额外进行的对于怪物属性的吸血、击溃、淬毒
				//淬毒结算
				if (淬毒量 > 0 && 伤害数字)
				{//this.命中对象.损伤值 += 淬毒量 * Math.max(1,消耗霰弹值 * 0.5);//多段下淬毒收益减半
					this.命中对象.损伤值 += 淬毒量;
					伤害数字 = this.命中对象.损伤值;
					//伤害字符 += "(毒)";
					伤害字符 += '<font color="#66dd00" size="20"> 毒</font>';
					if(this.淬毒衰减 && this.近战检测 && 发射对象.淬毒 > 10){
						发射对象.淬毒 -= this.淬毒衰减;
					}
					if (this.命中对象.毒返 > 0)
					{
						var 毒返淬毒值 = 淬毒量 * this.命中对象.毒返;
						if(this.命中对象.毒返函数){
							this.命中对象.毒返函数(淬毒量, 毒返淬毒值);
						}
						/*if (this.命中对象.淬毒 < 毒返淬毒值 || this.命中对象.淬毒 == undefined)
						{
							this.命中对象.近战招式 = "毒返";
							this.命中对象.状态改变("近战");
							this.命中对象.man.gotoAndPlay("毒返");
						}*/
						this.命中对象.淬毒 = 毒返淬毒值;
					}
				}
				//吸血
				if (this.吸血 > 0 && this.命中对象.损伤值 > 1)
				{
					var 吸血量 = Math.floor(Math.max(Math.min(this.命中对象.损伤值 * this.吸血 /100, this.命中对象.hp), 0));//吸血量不高于敌人hp且非负
					发射对象.hp += Math.min(吸血量,发射对象.hp满血值 * 1.5 - 发射对象.hp);//伤害字符 = " 汲:" + Math.floor(吸血量 / 消耗霰弹值).toString() + 伤害字符;
					伤害字符 = '<font color="#bb00aa" size="15"> 汲:'+ Math.floor(吸血量 / 消耗霰弹值).toString() +"</font>" + 伤害字符;
				}                                                               
				//击溃
				if (this.击溃 > 0 && this.命中对象.损伤值 > 1)
				{
					击溃量 = 击溃量 && !isNaN(击溃量) ? 击溃量 : 1;
					if(this.命中对象.hp满血值 > 0){
						this.命中对象.hp满血值 -= 击溃量;
						this.命中对象.损伤值 += 击溃量;
					}
					伤害字符 += '<font color="#FF3333" size="20"> 溃</font>'; //#662200
					伤害数字 = Math.floor(this.命中对象.损伤值);
				}
				//斩杀
				if(this.斩杀){
					if(this.命中对象.hp < this.命中对象.hp满血值 * this.斩杀 / 100){
						this.命中对象.损伤值 += this.命中对象.hp;
						this.命中对象.hp = 0;
						伤害字符 = this.子弹敌我属性值 ? '<font color="#4A0099" size="20"> 斩</font>' : '<font color="#660033" size="20"> 斩</font>'; 
					}
					伤害数字 = Math.floor(this.命中对象.损伤值);
				}

				//联弹
				if (消耗霰弹值 > 1)
				{
					for (var 联弹索引 = 0; 联弹索引 < 消耗霰弹值 - 1; ++联弹索引)
					{
						var 波动伤害 = (伤害数字 / (消耗霰弹值 - 联弹索引)) * (100 + _root.随机偏移(50 / 消耗霰弹值)) / 100;
						伤害数字 -= 波动伤害;
						显示数字 = '<font color="' + 伤害数字颜色 + '" size="' + 伤害数字大小 + '">' + 躲闪状态字符 + (isNaN(波动伤害) ? "MISS" : Math.floor(波动伤害)) + "</font>";
						_root.打击数字特效(控制字符串, 显示数字 + 伤害字符,this.命中对象._x,this.命中对象._y);
					}
				}
				显示数字 = '<font color="' + 伤害数字颜色 + '" size="' + 伤害数字大小 + '">' + 躲闪状态字符 + (isNaN(伤害数字) ? "MISS" : Math.floor(伤害数字)) +  "</font>";
				_root.打击数字特效(控制字符串,显示数字 + 伤害字符,this.命中对象._x,this.命中对象._y);
				this.命中对象.hp = isNaN(this.命中对象.损伤值) ? this.命中对象.hp : Math.floor(this.命中对象.hp - this.命中对象.损伤值);//对损失值异常检查
			}
			this.命中对象.hp = (this.命中对象.hp < 0 || isNaN(this.命中对象.hp)) ? 0 : this.命中对象.hp;//异常检查且限制为不小于0
			if (this.命中对象._name === _root.控制目标)
			{
				_root.玩家信息界面.刷新hp显示();
			}
			//伤害结算完毕
			
			var 被击方向 = (this.命中对象._x < 发射对象._x) ? "左" : "右" ;
			if(this.水平击退反向){
				被击方向 = 被击方向 === "左" ? "右" : "左";
			}
			this.命中对象.方向改变(被击方向 === "左" ? "右" : "左");

			//水平速度非负且低于最大水平速度时应用水平击退速度
			if (_root.血腥开关)
			{
				var 子弹效果碎片 = "";
				switch (this.命中对象.击中效果) 
				{
					case "飙血":
						子弹效果碎片 = "子弹碎片-飞血";
						break;
					case "异形飙血":
						子弹效果碎片 = "子弹碎片-异形飞血";
						break;
					default:
				}

				if(子弹效果碎片 != "")
				{
					var 效果对象 = _root.效果(子弹效果碎片, 碰撞中心.x, 碰撞中心.y, 发射对象._xscale);
					效果对象.出血来源 = this.命中对象._name;
				}
			}

			var 刚体检测 = this.命中对象.刚体 || this.命中对象.man.刚体标签;
			if (!this.命中对象.浮空 && !this.命中对象.倒地)
			{
				//完成残余冲击力计算
				_root.冲击力结算(this.命中对象.损伤值,this.击倒率,this.命中对象);//_root.发布调试消息(伤害数字 + " " +this.命中对象.残余冲击力 + " " + this.命中对象.韧性上限);
				this.命中对象.血条变色状态 = "常态";

				if (!isNaN(this.命中对象.hp) && this.命中对象.hp <= 0)
				{
					this.命中对象.状态改变(_root.血腥开关 ? "血腥死" : "击倒");
				}
				else if (躲闪状态 == "躲闪")
				{
					this.命中对象.被击移动(被击方向,this.水平击退速度,3);
				}
				else
				{
					//冲击力累计到踉跄阶段后稳定被击，积累超出上限击倒并重置冲击力
					//踉跄阶段由闪避能力决定，躲闪率越高越接近理论极限
					if (this.命中对象.残余冲击力 > this.命中对象.韧性上限)
					{
						if (!刚体检测)
						{
							this.命中对象.状态改变("击倒");
							this.命中对象.血条变色状态 = "击倒";
						}
						this.命中对象.残余冲击力 = 0;
						this.命中对象.被击移动(被击方向,this.水平击退速度,0.5);
					}
					else if (this.命中对象.残余冲击力 > this.命中对象.韧性上限 / _root.踉跄判定 / this.命中对象.躲闪率)
					{
						if (!刚体检测)
						{
							this.命中对象.状态改变("被击");
							this.命中对象.血条变色状态 = "被击";
						}

						this.命中对象.被击移动(被击方向,this.水平击退速度,2);
					}
					else
					{
						this.命中对象.被击移动(被击方向,this.水平击退速度,3);
					}
				}
			}
			else
			{
				this.命中对象.残余冲击力 = 0;
				if (!刚体检测)
				{
					this.命中对象.状态改变("击倒");
					this.命中对象.血条变色状态 = "击倒";
					if (!(this.垂直击退速度 > 0))
					{
						//拆出垂直击退速度
						var y速度 = 5;
						/*
						//var y速度 = 5+垂直击退速度;
						if(isNaN(y速度) || y速度<0){
						y速度 = 5;
						}
						y速度 = Math.min(y速度, _root.最大垂直击退速度);
						*/
						this.命中对象.man.垂直速度 = -y速度;
						//_root.发布调试消息(y速度+"/"+垂直击退速度+"/"+this.命中对象.man.垂直速度+"/"+this.命中对象.倒地);
					}
				}
				this.命中对象.被击移动(被击方向,this.水平击退速度,0.5);
			}
			if(!this.近战检测 && !this.爆炸检测 && this.命中对象.hp <= 0)
			{
				this.命中对象.状态改变("血腥死");
			}
			switch (this.命中对象.血条变色状态)
			{
				case "常态": _root.重置色彩(命中对象血槽);
					break;
				default: _root.暗化色彩(命中对象血槽);
			}

			_root.效果(this.命中对象.击中效果, 碰撞中心.x, 碰撞中心.y, 发射对象._xscale);
			if(this.命中对象.击中效果 == this.击中后子弹的效果) {
				是否生成击中后效果 = false;//若至少一个敌人的被击中效果与子弹的击中效果相同，则不生成击中效果
			}

			//为部分位移技能取消硬直，避免位移持续帧数过多、距离过长
			if (this.近战检测 && !this.不硬直) // and 发射对象.getSmallState() != "闪现中" and 发射对象.getSmallState() != "六连中"
			{
				发射对象.硬直(发射对象.man,_root.钝感硬直时间);
			}
			else if(!this.穿刺检测)
			{
				this.gotoAndPlay("消失");
			}
			//应用垂直击退速度
			//_root.发布调试消息("测试测试应该击飞"+this.命中对象);
			if (this.垂直击退速度 > 0)
			{
				this.命中对象.man.play();
				clearInterval(this.命中对象.pauseInterval);
				this.命中对象.硬直中 = false;
				clearInterval(this.命中对象.pauseInterval2);

				_root.fly(this.命中对象,this.垂直击退速度,0);
			}
		}
	}
	if(是否生成击中后效果 && 击中次数 > 0){
		_root.效果(this.击中后子弹的效果,this._x,this._y,发射对象._xscale);
	}
	
	var 击中地图判定 = false;
	if(this._x < _root.Xmin || this._x > _root.Xmax || this.Z轴坐标 < _root.Ymin || this.Z轴坐标 > _root.Ymax){
		if(this.ZY比例){
			// if(this.Z轴坐标 < _root.Ymin * this.ZY比例 || this.Z轴坐标 > _root.Ymax * this.ZY比例){
			// 	击中地图判定 = true;
			// }
		}else{
			击中地图判定 = true;
		}
	}else if(this._y > this.Z轴坐标 && !this.近战检测){
		击中地图判定 = true;
	}else{
		var 子弹地面坐标 = {x:this._x, y:this.Z轴坐标};
		游戏世界.localToGlobal(子弹地面坐标);
		if (游戏世界.地图.hitTest(子弹地面坐标.x, 子弹地面坐标.y, true)){
			击中地图判定 = true;
		}
	}
	if (击中地图判定){
		//疑似没有名叫子弹碎片的效果元件，这几行先注释掉
		// var 子弹碎片depth = random(50);
		// var 子弹碎片b_name = "zidan子弹碎片" + 子弹碎片depth;
		// 游戏世界.效果.attachMovie("子弹碎片",子弹碎片b_name,游戏世界.效果.getNextHighestDepth(),{_x:this._x, _y:this._y});
		this.击中地图 = true;
		this.霰弹值 = 1;
		_root.效果(this.击中地图效果,this._x,this._y);
		if(this.击中时触发函数){
			this.击中时触发函数();
		}
		this.gotoAndPlay("消失");
	}

	_root.子弹基础运动控制(this);
};

_root.子弹基础运动控制 = function(子弹:MovieClip){
	if(子弹.速度X && 子弹.速度Y && 子弹.ZY比例){
		子弹._x += 子弹.速度X;
		子弹._y += 子弹.速度Y;
		子弹.Z轴坐标 = 子弹._y * 子弹.ZY比例;
	}else{
		子弹._x += 子弹.xmov;
		子弹._y += 子弹.ymov;
	}
	if (!子弹.远距离不消失 && (Math.abs(子弹._x - _root.gameworld[子弹.发射者名]._x) > 900 || Math.abs(子弹._y - _root.gameworld[子弹.发射者名]._y) > 900))
	{
		子弹.removeMovieClip();
	}
}


_root.子弹区域shoot表演 = function(声音, 霰弹值, 子弹散射度, 发射效果, 子弹种类, 子弹威力, 子弹速度, Z轴攻击范围, 击中地图效果, 发射者, shootX, shootY, shootZ, 子弹敌我属性, 击倒率, 击中后子弹的效果)
{
	if (_root.暂停 == false)
	{
		if (_root.控制目标全自动 == false and _root.控制目标 == _root.gameworld[发射者]._name)
		{
			if (_root.gameworld[发射者]._xscale > 0)
			{
				if (Key.isDown(_root.下键))
				{
					射击角度 = 30;
				}
				else if (Key.isDown(_root.上键))
				{
					射击角度 = 330;
				}
				else
				{
					射击角度 = 0;
				}
			}
			else if (Key.isDown(_root.下键))
			{
				射击角度 = 150;
			}
			else if (Key.isDown(_root.上键))
			{
				射击角度 = 210;
			}
			else
			{
				射击角度 = 180;
			}
		}
		else if (_root.gameworld[发射者]._xscale > 0)
		{
			射击角度 = 0;
		}
		else
		{
			射击角度 = 180;
		}
		f_name = "f" + depth;
		_root.gameworld.效果.attachMovie(发射效果,f_name,random(20));
		_root.gameworld.效果[f_name]._xscale = _root.gameworld[发射者]._xscale;
		_root.gameworld.效果[f_name]._x = shootX;
		_root.gameworld.效果[f_name]._y = shootY;
		_root.播放音效(声音);
		i = 1;
		while (i <= 霰弹值)
		{
			depth++;
			if (depth > 100)
			{
				depth = 0;
			}
			if (random(2) == 0)
			{
				散射角度 = 射击角度 - random(子弹散射度);
			}
			else
			{
				散射角度 = 射击角度 + random(子弹散射度);
			}
			angle = 散射角度 * 3.14 / 180;
			b_name = 发射者 + "zidan" + depth + 散射角度;
			_root.gameworld.子弹区域.attachMovie(子弹种类,b_name,_root.gameworld.子弹区域.getNextHighestDepth(),{_rotation:散射角度, _x:shootX, _y:shootY});
			_root.gameworld.子弹区域[b_name].发射者名 = 发射者;
			_root.gameworld.子弹区域[b_name].子弹敌我属性值 = 子弹敌我属性;
			_root.gameworld.子弹区域[b_name].子弹威力 = 子弹威力;
			_root.gameworld.子弹区域[b_name].Z轴坐标 = shootZ;
			_root.gameworld.子弹区域[b_name].xmov = 子弹速度 * Math.cos(angle);
			_root.gameworld.子弹区域[b_name].ymov = 子弹速度 * Math.sin(angle);
			_root.gameworld.子弹区域[b_name].onEnterFrame = function()
			{
				var _loc3_ = {x:0, y:0};
				this.localToGlobal(_loc3_);
				for (each in _root.gameworld)
				{
					if (_root.gameworld[each].是否允许发送联机数据 == true)
					{
						if (_root.gameworld[each].是否为敌人 == 子弹敌我属性 and _root.gameworld[each]._name != 发射者 and _root.gameworld[each].area.hitTest(this.area) == true and Math.abs(this.Z轴坐标 - _root.gameworld[each].Z轴坐标) < Z轴攻击范围)
						{
							_root.gameworld[each].攻击目标 = _root.gameworld[发射者]._name;
							if (_root.gameworld[each]._name === _root.控制目标)
							{
								_root.玩家信息界面.刷新hp显示();
							}
							被击移动速度 = 10;
							if (_root.血腥开关 == true)
							{
								if (_root.gameworld[each].击中效果 == "飙血")
								{
									临时效果名 = 效果("子弹碎片-飞血", this._x, _root.gameworld[each]._y, _root.gameworld[发射者]._xscale);
									_root.gameworld.效果[临时效果名].出血来源 = each;
								}
								else if (_root.gameworld[each].击中效果 == "异形飙血")
								{
									临时效果名 = 效果("子弹碎片-异形飞血", this._x, _root.gameworld[each]._y, _root.gameworld[发射者]._xscale);
									_root.gameworld.效果[临时效果名].出血来源 = each;
								}
							}
							效果(_root.gameworld[each].击中效果,this._x,this._y,_root.gameworld[发射者]._xscale);
							效果(击中后子弹的效果,this._x,this._y,_root.gameworld[发射者]._xscale);
							if (子弹种类 != "近战子弹")
							{
								this.gotoAndPlay("消失");
							}
						}
					}
				}
				if (this._y > this.Z轴坐标 and 子弹种类 != "近战子弹" )
				{
					效果(击中地图效果,this._x,this._y);
					this.gotoAndPlay("消失");
				}
				if (_root.gameworld.地图.hitTest(_loc3_.x, _loc3_.y, true))
				{
					效果(击中地图效果,this._x,this._y);
					子弹碎片depth = random(50);
					子弹碎片b_name = "zidan子弹碎片" + 子弹碎片depth;
					_root.gameworld.效果.attachMovie("子弹碎片",子弹碎片b_name,_root.gameworld.效果.getNextHighestDepth(),{_x:this._x, _y:this._y});
					this.gotoAndPlay("消失");
				}
				this._x += this.xmov;
				this._y += this.ymov;
				if (Math.abs(this._x - _root.gameworld[发射者]._x) > 800 || Math.abs(this._y - _root.gameworld[发射者]._y) > 800)
				{
					this.removeMovieClip();
				}
			};
			i++;
		}
	}
};



//将传递参数改为对象，需要严格对应属性名，使用格式详情见下方注释
_root.子弹属性初始化 = function(子弹元件:MovieClip,子弹种类:String,发射者:MovieClip){
	var myPoint = {x:子弹元件._x,y:子弹元件._y};
	子弹元件._parent.localToGlobal(myPoint);
	var 转换中间y = myPoint.y;
	_root.gameworld.globalToLocal(myPoint);
	shootX = myPoint.x;
	shootY = myPoint.y;
	if(!发射者){
		发射者 = 子弹元件._parent._parent;
	}
	var 子弹属性 = {
		声音:"",
		霰弹值:1,
		子弹散射度:1,
		发射效果:"",
		子弹种类:子弹种类 == undefined ? "普通子弹" : 子弹种类,
		子弹威力:10,
		子弹速度:10,
		Z轴攻击范围:10,
		击中地图效果:"火花",
		发射者:发射者._name,
		shootX:shootX,
		shootY:shootY,
		转换中间y:转换中间y,
		shootZ:发射者.Z轴坐标,
		子弹敌我属性:!发射者.是否为敌人,
		击倒率:10,
		击中后子弹的效果:"",
		水平击退速度:NaN,
		垂直击退速度:NaN,
		命中率:NaN,
		固伤:NaN,
		百分比伤害:NaN,
		血量上限击溃:NaN,
		防御粉碎:NaN,
		吸血:NaN,
		毒:NaN,
		最小霰弹值:1,
		不硬直:false,
		区域定位area:undefined,
		伤害类型:undefined,
		魔法伤害属性:undefined,
		速度X:undefined,
		速度Y:undefined,
		ZY比例:undefined,
		斩杀:undefined,
		暴击:undefined,
		水平击退反向:false,
		角度偏移:0
	}
	return 子弹属性;
}


/*使用示例：

	子弹属性 = _root.子弹属性初始化(this);
	
	//以下部分只需要更改需要更改的属性,其余部分可注释掉
	子弹属性.声音 = "";
	子弹属性.霰弹值 = 1;
	子弹属性.子弹散射度 = 1;
	子弹属性.子弹种类 = "普通子弹";
	子弹属性.子弹威力 = 10;
	子弹属性.子弹速度 = 10;
	子弹属性.Z轴攻击范围 = 10.
	子弹属性.击倒率 = 10;
	子弹属性.水平击退速度 = NaN;
	子弹属性.垂直击退速度 = NaN;
	
	//非常用
	子弹属性.发射效果 = "";
	子弹属性.击中地图效果 = "火花".
	子弹属性.击中后子弹的效果 = "".
	子弹属性.命中率 = NaN.
	子弹属性.固伤 = NaN;
	子弹属性.百分比伤害 = NaN;
	子弹属性.血量上限击溃 = NaN;
	子弹属性.防御粉碎 = NaN;
	子弹属性.区域定位area = undefinded;
	
	//已初始化内容，通常不需要重复赋值，可注释掉
	子弹属性.发射者 = 子弹属性.发射者.
	子弹属性.shootX = 子弹属性.shootX;
	子弹属性.shootY = 子弹属性.shootY;
	子弹属性.shootZ = 子弹属性.shootZ;
	子弹属性.子弹敌我属性 = 子弹属性.子弹敌我属性;
	
	_root.子弹区域shoot传递(子弹属性);


*/






