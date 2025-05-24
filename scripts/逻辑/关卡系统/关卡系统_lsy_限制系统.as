var 限制系统 = new Object();
_root.限制系统 = 限制系统;

限制系统.entries = new Object();
限制系统.discriptions = new Object();

//设置限制词条 同时设置以词条名为键的property，方便直接访问词条是否开启
//如设置DisableCompanion后，可以直接访问_root.限制系统.DisableCompanion
限制系统.addEntry = function(entryName, discription){
	this.addProperty(entryName,function(){
		return this.getEntry(entryName);
	},null);
	this.discriptions[entryName] = discription;
}

限制系统.getEntry = function(entryName){
	return this.entries[entryName] === true;
}

//开启限制词条
限制系统.openEntries = function(entryArray){
	for(var i=0; i < entryArray.length; i++){
		this.entries[entryArray[i]] = true;
	}
}

//添加限制难度等级
限制系统.addLimitLevel = function(limitLevel){
	this.limitLevel = limitLevel;
}

//清空所有限制词条
限制系统.clearEntries = function(){
	this.entries = new Object();
}

限制系统.getDiscription = function(entryName){
	return this.discriptions[entryName];
}



限制系统.addEntry("DisableCompanion", "无法携带同伴"); //禁用同伴
限制系统.addEntry("DisableKnockdownProtection", "被击飞和击倒状态下无法免疫攻击"); //禁用落地保护
限制系统.addEntry("DisableResurrection", "无法使用复活币"); //禁用复活