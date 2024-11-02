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
	执行:null
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
		return "对于已成型但基础体质仍有提升空间的单位可以进行一轮基础训练，通过体能训练、专项培训、锻炼甚至药物等途径提升身体强度，提高生命值、防御力和攻击力。点击可进行训练，需要消耗"+ this.进阶方案.基础训练.消耗金币+"金币";
	},
	消耗金币:50000,
	消耗K点:0,
	消耗道具:[],
	次数上限:1,
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
		}else{
			this.当前宠物属性.基础训练.次数 += 1;
		}
	},
	单位进阶执行:function(){
		this.hp满血值 += 5000 * _root.难度等级;
		this.防御力 += 300;
		this.空手攻击力 += 200 * _root.难度等级;
		this.韧性系数 += 10;
	}
}
// _root.战宠进阶函数.基础训练.条件 = function(){
// 	return true;
// }

// _root.战宠进阶函数.基础训练.执行 = function(){
// 	return true;
// }

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
		this.JK.gotoAndStop(this.当前宠物属性.发色);
	}
}