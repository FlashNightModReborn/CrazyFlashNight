_root.数字化拆分 = function(data)
{
	var _loc2_ = [];
	var _loc6_ = data.split("\n");
	_loc2_.push(_loc6_[0].split(" "));
	_loc2_[0].splice(12,0,"菜鸟");
	if (_loc2_[0][1] == "1")
	{
		_loc2_[0][1] = "男";
	}
	else
	{
		_loc2_[0][1] = "女";
	}
	_loc2_.push(_loc6_[1].split(" "));
	_loc2_[1][0] = _root.脸型库[Number(_loc2_[1][0])];
	_loc2_[1][1] = _root.发型库[Number(_loc2_[1][1])];
	var _loc5_ = 2;
	while (_loc5_ < 16)
	{
		if (_loc2_[1][_loc5_] == "-1")
		{
			_loc2_[1][_loc5_] = "";
		}
		else
		{
			_loc2_[1][_loc5_] = _root.parseXMLs2(_loc2_[1][_loc5_])[0];
		}
		_loc5_ = _loc5_ + 1;
	}
	_loc5_ = 16;
	while (_loc5_ < _loc2_[1].length)
	{
		if (_loc2_[1][_loc5_] == "-1")
		{
			_loc2_[1][_loc5_] = "";
		}
		else
		{
			_loc2_[1][_loc5_] = _root.技能表[_loc2_[1][_loc5_]][0];
		}
		_loc5_ = _loc5_ + 1;
	}
	_loc2_.push([]);
	_loc5_ = 0;
	while (_loc5_ < 40)
	{
		_loc2_[2][_loc5_] = ["空", 0, 0];
		_loc5_ = _loc5_ + 1;
	}
	tempArr = _loc6_[2].split("\t");
	_loc5_ = 0;
	while (_loc5_ < tempArr.length)
	{
		tempArr2 = tempArr[_loc5_].split(" ");
		temp_bbb = tempArr2[1];
		if (temp_bbb == "-1")
		{
			temp_bbb = "空";
			_loc2_[2][Number(tempArr2[0])] = [temp_bbb, tempArr2[2], 0];
		}
		else
		{
			_loc2_[2][Number(tempArr2[0])] = [_root.parseXMLs2(tempArr2[1])[0], tempArr2[2], 0];
		}
		_loc5_ = _loc5_ + 1;
	}
	_loc5_ = 2;
	while (_loc5_ < 13)
	{
		if (_loc2_[1][_loc5_] != "")
		{
			var _loc4_ = 0;
			while (_loc4_ < 40)
			{
				if (_loc2_[2][_loc4_][0] == _loc2_[1][_loc5_])
				{
					if (_loc2_[2][_loc4_][2] != "1")
					{
						_loc2_[2][_loc4_][2] = "1";
						break;
					}
					next;
				}
				_loc4_ = _loc4_ + 1;
			}
		}
		_loc5_ = _loc5_ + 1;
	}
	_loc5_ = 0;
	while (_loc5_ < 40)
	{
		_loc5_ = _loc5_ + 1;
	}
	_loc2_.push(_loc6_[3]);
	_loc2_.push([]);
	var _loc3_ = _loc6_[4].split("\r");
	_loc4_ = 0;
	_loc5_ = 0;
	while (_loc5_ < _loc3_.length - 1)
	{
		_loc3_[_loc5_] = _loc3_[_loc5_].split(" ");
		_loc3_[_loc5_][4] = _root.脸型库[Number(_loc3_[_loc5_][4])];
		_loc3_[_loc5_][5] = _root.发型库[Number(_loc3_[_loc5_][5])];
		_loc4_ = 6;
		while (_loc4_ < _loc3_[_loc5_].length - 1)
		{
			if (_loc3_[_loc5_][_loc4_] == "-1")
			{
				_loc3_[_loc5_][_loc4_] = "";
			}
			else
			{
				_loc3_[_loc5_][_loc4_] = _root.parseXMLs2(_loc3_[_loc5_][_loc4_])[0];
			}
			_loc4_ = _loc4_ + 1;
		}
		if (_loc3_[_loc5_][_loc4_] == "1")
		{
			_loc3_[_loc5_][_loc4_] = "男";
		}
		else
		{
			_loc3_[_loc5_][_loc4_] = "女";
		}
		_loc5_ = _loc5_ + 1;
	}
	_loc2_[4][0] = _loc3_;
	_loc2_[4][1] = _loc3_.length - 1;
	技能数据 = [];
	_loc5_ = 0;
	while (_loc5_ < 80)
	{
		技能数据.push(["", 0, "false"]);
		_loc5_ = _loc5_ + 1;
	}
	技能数据2 = _loc6_[5].split("\t");
	_loc5_ = 0;
	while (_loc5_ < 技能数据2.length)
	{
		技能数据2[_loc5_] = 技能数据2[_loc5_].split(" ");
		if (_root.技能表[Number(技能数据2[_loc5_][0])][0] != undefined)
		{
			技能数据[_loc5_][0] = _root.技能表[Number(技能数据2[_loc5_][0])][0];
			技能数据[_loc5_][1] = 技能数据2[_loc5_][1];
			_loc4_ = 16;
			while (_loc4_ < 22)
			{
				if (技能数据[_loc5_][0] == _loc2_[1][_loc4_])
				{
					技能数据[_loc5_][2] = "true";
					break;
				}
				_loc4_ = _loc4_ + 1;
			}
		}
		_loc5_ = _loc5_ + 1;
	}
	_loc2_.push(技能数据);
	_loc2_.push([]);
	_loc5_ = 0;
	while (_loc5_ < _root.仓库栏总数)
	{
		_loc2_[6][_loc5_] = ["空", 0, 0];
		_loc5_ = _loc5_ + 1;
	}
	tempArr = _loc6_[6].split("\t");
	_loc5_ = 0;
	while (_loc5_ < tempArr.length)
	{
		tempArr2 = tempArr[_loc5_].split(" ");
		temp_bbb = tempArr2[1];
		if (temp_bbb == "-1")
		{
			temp_bbb = "空";
			_loc2_[6][Number(tempArr2[0])] = [temp_bbb, tempArr2[2], 0];
		}
		else
		{
			_loc2_[6][Number(tempArr2[0])] = [_root.parseXMLs2(tempArr2[1])[0], tempArr2[2], 0];
		}
		_loc5_ = _loc5_ + 1;
	}
	return _loc2_;
};