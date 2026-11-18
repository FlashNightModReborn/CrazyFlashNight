_root.GetFileByPath = function(path, out)
{
	// 全局在途文件加载计数：boot 期 BootSequencer S6 据此等异步 preload 落地再抽 loader 队列（塌缩压没了原版帧间隔）
	if (_root.__pendingFileLoads == undefined) _root.__pendingFileLoads = 0;
	_root.__pendingFileLoads++;
	var _loc2_ = new LoadVars();
	_loc2_.onData = function(src)
	{
		out.push(src);
		if (_root.__pendingFileLoads > 0) _root.__pendingFileLoads--;
		/*var _loc2_ = 0;
		while (_loc2_ < src.length)
		{
			out.push(src.charAt(_loc2_));
			_loc2_ += 1;
		}*/
	};
	_loc2_.load(path,_loc2_,"GET");
};

_root.XmlNodeToDict = function(root, indexNodeName, processor){
	var dict = {};
	if (root.firstChild.nodeType == 3){
		return processor(root.nodeName, root.firstChild.nodeValue);
	}
	for (var _loc5_ in root.childNodes){
		var nodename = root.childNodes[_loc5_].nodeName;
		var index = 0;
		while (index < root.childNodes[_loc5_].childNodes.length){
			if (root.childNodes[_loc5_].childNodes[index].nodeName == indexNodeName){
				nodename = root.childNodes[_loc5_].childNodes[index].firstChild.nodeValue;
			}
			index++;
		}
		dict[nodename] = _root.XmlNodeToDict(root.childNodes[_loc5_], indexNodeName, processor);
	}
	return dict;
};

_root.duplicateOf = function(ori){
	var _loc2_ = false;
	if (ori.__proto__ == Array.prototype){
		var _loc3_ = new Array();
		var _loc4_ = 0;
		while (_loc4_ < ori.length){
			_loc3_.push(_root.duplicateOf(ori[_loc4_]));
			_loc2_ = true;
			_loc4_ += 1;
		}
	}else{
		_loc3_ = new Object();
		for (var _loc5_ in ori){
			_loc3_[_loc5_] = _root.duplicateOf(ori[_loc5_]);
			_loc2_ = true;
		}
	}if (_loc2_){
		return _loc3_;
	}
	return ori;
};

// 未使用 - 可移除
/*_root.StringClassify = function(str){
	if (str == "true") return true;
	if (str == "false") return false;
	if (str == "null" || str == "") return null;
	if (str == "undefined") return undefined;
	if (!isNaN(Number(str))) return Number(str);
	return str;
};*/

// 未使用 - 可移除
/*_root.MakeArray = function(len, content){
	var newArray = [];
	var i = 0;
	while (i < len)
	{
		newArray.push(content(i));
		i += 1;
	}
	return newArray;
};*/


//物品
_root.getItemData = function(index){
	return org.flashNight.arki.item.ItemUtil.getItemData(index);
};

//商店
_root.getNPCShop = function(name){
	return _root.shops[name];
	var shopData = _root.shops[name];
	if(shopData == null) return null;
	// var shop = new Array(80);
	// for (var i in shopData){
	// 	shop[Number(i)] = [shopData[i]];
	// }
}

//兵种
// 未使用 - 可移除
/*_root.getUnitData = function(index){
	if (isNaN(Number(index))){
		return _root.duplicateOf(_root.units[_root.unit_indices_by_name[index]]);
	}
	return _root.duplicateOf(_root.units[_root.unit_indices_by_id[Number(index)]]);
}*/
