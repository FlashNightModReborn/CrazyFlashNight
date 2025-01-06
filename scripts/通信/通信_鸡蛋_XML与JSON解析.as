_root.GetFileByPath = function(path, out)
{
	var _loc2_ = new LoadVars();
	_loc2_.onData = function(src)
	{
		out.push(src);
		/*var _loc2_ = 0;
		while (_loc2_ < src.length)
		{
			out.push(src.charAt(_loc2_));
			_loc2_ += 1;
		}*/
	};
	_loc2_.load(path,_loc2_,"GET");
};

_root.XmlNodeToDict = function(root, indexNodeName, processor)
{
	var _loc4_ = {};
	if (root.firstChild.nodeType == 3)
	{
		return processor(root.nodeName, root.firstChild.nodeValue);
	}
	for (var _loc5_ in root.childNodes)
	{
		if (root.childNodes[i].nodeName == undefined)
		{
		}
		var _loc6_ = root.childNodes[_loc5_].nodeName;
		var _loc7_ = 0;
		while (_loc7_ < root.childNodes[_loc5_].childNodes.length)
		{
			if (root.childNodes[_loc5_].childNodes[_loc7_].nodeName == indexNodeName)
			{
				_loc6_ = root.childNodes[_loc5_].childNodes[_loc7_].firstChild.nodeValue;
			}
			_loc7_ += 1;
		}
		_loc4_[_loc6_] = _root.XmlNodeToDict(root.childNodes[_loc5_], indexNodeName, processor);
	}
	return _loc4_;
};

_root.duplicateOf = function(ori)
{
	var _loc2_ = false;
	if (ori.__proto__ == Array.prototype)
	{
		var _loc3_ = new Array();
		var _loc4_ = 0;
		while (_loc4_ < ori.length)
		{
			_loc3_.push(_root.duplicateOf(ori[_loc4_]));
			_loc2_ = true;
			_loc4_ += 1;
		}
	}
	else
	{
		_loc3_ = new Object();
		for (var _loc5_ in ori)
		{
			_loc3_[_loc5_] = _root.duplicateOf(ori[_loc5_]);
			_loc2_ = true;
		}
	}
	if (_loc2_)
	{
		return _loc3_;
	}
	return ori;
};

_root.StringClassify = function(str)
{
	if (str == "true")
	{
		return true;
	}
	if (str == "false")
	{
		return false;
	}
	if (str == "null" || str == "")
	{
		return null;
	}
	if (str == "undefined")
	{
		return undefined;
	}
	if (!isNaN(Number(str)))
	{
		return Number(str);
	}
	return str;
};

_root.MakeArray = function(len, content)
{
	var _loc3_ = [];
	var _loc4_ = 0;
	while (_loc4_ < len)
	{
		_loc3_.push(content(_loc4_));
		_loc4_ += 1;
	}
	return _loc3_;
};

_root.json_parser = new JSON();


//物品
_root.getItemData = function(index){
	return org.flashNight.arki.item.ItemUtil.getItemData(index);
};

//关卡
_root.isStageUnlocked = function(name)
{
	return _root.stages_unlock[name] <= _root.主线任务进度 ? true : false;
}

//商店
_root.getNPCShop = function(name)
{
	var _loc3_ = _root.MakeArray(80, function (index)
	{
	return null;
	});
	for (var _loc4_ in _root.shops[name])
	{
		_loc3_[Number(_loc4_)] = [_root.shops[name][_loc4_]];
	}
	return _loc3_;
}

//兵种
_root.getUnitData = function(index)
{
	if (isNaN(Number(index)))
	{
		return _root.duplicateOf(_root.units[_root.unit_indices_by_name[index]]);
	}
	return _root.duplicateOf(_root.units[_root.unit_indices_by_id[Number(index)]]);
}

//任务
_root.getTaskData = function(index, chain)
{
	if (chain == undefined)
	{
		if (isNaN(Number(index)))
		{
			return _root.duplicateOf(_root.tasks[_root.task_indices_by_title[index]]);
		}
		return _root.duplicateOf(_root.tasks[_root.task_indices_by_id[Number(index)]]);
	}
	return _root.duplicateOf(_root.tasks[_root.task_chains[chain][String(index)]]);
}

//任务文本
_root.getTaskText = function(str)
{
	if (str.charAt(0) == "$")
	{
		return _root.task_texts[str];
	}
	return str;
}

//佣兵
_root.getMercData = function(index)
{
	return _root.duplicateOf(_root.mercs_list[_root.merc_indices_by_id[index]]);
};
_root.getMercEasyData = function(index)
{
	return _root.duplicateOf(_root.mercs_easy_list[_root.merc_easy_indices_by_id[index]]);
};