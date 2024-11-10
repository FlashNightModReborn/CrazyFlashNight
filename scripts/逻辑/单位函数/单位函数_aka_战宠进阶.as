_root.战宠进阶函数 = new Object();

var 无条件 = function(){
	return true;
}

_root.战宠进阶函数.凑数组的 = {
	初始化:null,
	描述:"",
	消耗金币:0,
	消耗K点:0,
	消耗道具:[],
	次数上限:false,
	条件:function(){
		return false;
	},
	执行:null,
	单位进阶执行:null
}

_root.战宠进阶函数.基础训练 = {
	初始化:null,
	描述:function(){
		if(this.当前宠物信息[1] < 10){
			return "十级以上可以进行基础训练，提升属性"
		}
		if(this.当前宠物属性.基础训练 && this.当前宠物属性.基础训练.次数 >= this.进阶方案.基础训练.次数上限){
			return "已完成基础训练。基础训练可获得的属性提升达到上限"
		}
		return "对于已成型但基础体质较弱的单位可以进行一轮基础训练，通过体能训练、专项锻炼、健康理疗等途径提升身体强度，提高生命值、防御力和攻击力。点击可进行训练，需要消耗"+ this.进阶方案.基础训练.消耗金币+"金币";
	},
	消耗金币:20000,
	消耗K点:0,
	消耗道具:[],
	次数上限:1,
	详情页:true,
	执行按钮文字:"进行训练",
	条件:function(){
		if( this.当前宠物信息[1] < 10){
			this.失败提示 = "";
			return false;
		}else if( _root.金钱 <= this.进阶方案.基础训练.消耗金币){
			this.失败提示 = "金币不足！";
			return false;
		}else if(this.当前宠物属性.基础训练 && this.当前宠物属性.基础训练.次数 >= this.进阶方案.基础训练.次数上限){
			//this.失败提示 = "训练次数已达到上限！";
			this.失败提示 = "";
			return false;
		}
		return true;
	},
	执行:function(){
		_root.最上层发布文字提示("已完成基础训练！");
		_root.金钱 -= this.进阶方案.基础训练.消耗金币;
		if(!this.当前宠物属性.基础训练){
			this.当前宠物属性.基础训练 = {
				次数:1,
				启用:true
			}
		}else if(!this.当前宠物属性.基础训练.次数 || this.当前宠物属性.基础训练.次数<1){
			this.当前宠物属性.基础训练.次数 = 1;
		}
	},
	单位进阶执行:function(){
		if(this.宠物属性.基础训练 && this.宠物属性.基础训练.启用){
			if(this.宠物属性.次数>=1){
				this.hp满血值 += 2000 * _root.难度等级;
				this.防御力 += 100;
				this.空手攻击力 += 50 * _root.难度等级;
				this.韧性系数 += 5;
			}
			if(this.宠物属性.次数>=2){
				this.hp满血值 += 3500 * _root.难度等级;
				this.防御力 += 250;
				this.空手攻击力 += 200 * _root.难度等级;
				this.韧性系数 += 10;
			}
		}
	}
}

_root.战宠进阶函数.强化药剂 = {
	初始化:null,
	描述:function(){
		if(this.当前宠物信息[1] < 25){
			return "二十五级以上可以注射强化药剂，提升属性"
		}
		if(this.当前宠物属性.基础训练 && this.当前宠物属性.基础训练.次数 >= this.进阶方案.强化药剂.次数上限){
			return "已注射强化药剂。注射强化药剂可获得的属性提升达到上限"
		}
		return "对于身体素质中等水平的单位可以注射强化药剂并进行适用性训练，提高生命值、防御力和攻击力。点击可进行强化药剂注射与适应性训练，需要消耗"+ this.进阶方案.强化药剂.消耗金币+"金币";
	},
	消耗金币:50000,
	消耗K点:0,
	消耗道具:[],
	次数上限:2,
	详情页:true,
	执行按钮文字:"进行训练",
	条件:function(){
		if( this.当前宠物信息[1] < 10){
			this.失败提示 = "";
			return false;
		}else if( _root.金钱 <= this.进阶方案.强化药剂.消耗金币){
			this.失败提示 = "金币不足！";
			return false;
		}else if(this.当前宠物属性.基础训练 && this.当前宠物属性.基础训练.次数 >= this.进阶方案.强化药剂.次数上限){
			//this.失败提示 = "训练次数已达到上限！";
			this.失败提示 = "";
			return false;
		}
		return true;
	},
	执行:function(){
		_root.最上层发布文字提示("已完成强化药剂注射与适应性训练！");
		_root.金钱 -= this.进阶方案.强化药剂.消耗金币;
		if(!this.当前宠物属性.基础训练){
			this.当前宠物属性.基础训练 = {
				次数:2,
				启用:true
			}
		}else if(!this.当前宠物属性.基础训练.次数 || this.当前宠物属性.基础训练.次数<2){
			this.当前宠物属性.基础训练.次数 = 2;
		}
	},
	单位进阶执行:_root.战宠进阶函数.基础训练.单位进阶执行
}


_root.战宠进阶函数.切换发型 = {
	初始化:function(){
		if(!this.当前宠物属性.发色){
			this.当前宠物属性.发色 = "橙";
		}
	},
	描述:function(){
		return "染发：当前为"+this.当前宠物属性.发色+"发";
	},
	消耗金币:0,
	消耗K点:0,
	消耗道具:[],
	次数上限:false,
	条件:function(){
		return true;
	},
	执行:function(){
		if(this.当前宠物属性.发色=="橙"){
			this.当前宠物属性.发色="白";
		}else if(this.当前宠物属性.发色=="白"){
			this.当前宠物属性.发色="橙";
		}else{
			this.当前宠物属性.发色="白";
		}
   		_root.删除场景宠物();
   		_root.加载宠物(_root.gameworld[_root.控制目标]._x,_root.gameworld[_root.控制目标]._y);
		//this.JK.gotoAndStop(this.当前宠物属性.发色);
		_root.宠物信息界面["宠物信息显示框"+this.宠物信息数组号].宠物头像.JK.gotoAndStop(this.当前宠物属性.发色);
	}
}