var 限制系统 = new Object();
_root.限制系统 = 限制系统;

限制系统.entries = new Object();
限制系统.discriptions = new Object();

限制系统.addEntry = function(entryName, discription){
	this.addProperty(entryName,function(){
		return this.getEntry(entryName);
	},null);
	this.discriptions[entryName] = discription;
}

限制系统.getEntry = function(entryName){
	return this.entries[entryName] === true;
}

限制系统.setEntries = function(entryArray){
	for(var i=0; i < entryArray.length; i++){
		this.entries[entryArray[i]] = true;
	}
}

限制系统.clearEntries = function(){
	this.entries = new Object();
}

限制系统.getDiscription = function(entryName){
	return this.discriptions[entryName];
}



限制系统.addEntry("DisableCompanion", "无法携带同伴"); //禁用同伴