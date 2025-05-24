//这里的对比数据无视掉就行
_root.存档数字化 = function(中文数据, 对比数据)
{
	var _loc4_ = "";
	if (中文数据[0].toString() != 对比数据[0])
	{
		_loc4_ += _root.数字化组装(中文数据[0], 0, 对比数据);
		对比数据[0] = 中文数据[0].toString();
		存储标识 += "1";
	}
	else
	{
		存储标识 += "0";
		_loc4_ += "\n";
	}
	if (中文数据[1].toString() != 对比数据[1])
	{
		_loc4_ += "\n";
		_loc4_ += _root.数字化组装(中文数据[1], 1, 对比数据);
		对比数据[1] = 中文数据[1].toString();
		存储标识 += "1";
	}
	else
	{
		存储标识 += "0";
		_loc4_ += "\n";
	}
	if (中文数据[2].toString() != 对比数据[2])
	{
		_loc4_ += "\n";
		_loc4_ += _root.数字化组装(中文数据[2], 2, 对比数据);
		对比数据[2] = 中文数据[2].toString();
		存储标识 += "1";
	}
	else
	{
		存储标识 += "0";
		_loc4_ += "\n";
	}
	if (中文数据[3].toString() != 对比数据[3])
	{
		_loc4_ += "\n";
		_loc4_ += _root.数字化组装(中文数据[3], 3, 对比数据);
		对比数据[3] = 中文数据[3].toString();
		存储标识 += "1";
	}
	else
	{
		存储标识 += "0";
		_loc4_ += "\n";
	}
	//因为格式不同所以同伴数据不保存
	if (中文数据[4].toString() == 对比数据[4])
	{
		_loc4_ += "\n";
		_loc4_ += _root.数字化组装(中文数据[4], 4, 对比数据);
		对比数据[4] = 中文数据[4].toString();
		存储标识 += "1";
	}
	else
	{
		存储标识 += "0";
		_loc4_ += "\n";
	}
	if (中文数据[5].toString() != 对比数据[5])
	{
		_loc4_ += "\n";
		_loc4_ += _root.数字化组装(中文数据[5], 5, 对比数据);
		对比数据[5] = 中文数据[5].toString();
		存储标识 += "1";
	}
	else
	{
		存储标识 += "0";
		_loc4_ += "\n";
	}
	if (中文数据[6].toString() != 对比数据[6])
	{
		_loc4_ += "\n";
		_loc4_ += _root.数字化组装(中文数据[6], 6, 对比数据);
		对比数据[6] = 中文数据[6].toString();
		存储标识 += "1";
	}
	else
	{
		存储标识 += "0";
		_loc4_ += "\n";
	}
	存储标识 += "\n";
	return _loc4_;
};



_root.数字化组装 = function(data2, n, 比较数据)
{
	var _loc2_ = data2.slice();
	数据包 = "";
	if (n == 0)
	{
		if (_loc2_[1] == "男")
		{
			_loc2_[1] = 1;
		}
		else if (_loc2_[1] == "女")
		{
			_loc2_[1] = 0;
		}
		_loc2_.splice(12,1);
		数据包 += _loc2_.join(" ");
		return 数据包;
	}
	if (n == 1)
	{
		_loc2_[0] = _root.查找脸型(_loc2_[0]);
		_loc2_[1] = _root.查找发型(_loc2_[1]);
		var _loc3_ = 2;
		while (_loc3_ < 16)
		{
			_loc2_[_loc3_] = _root.parseXMLs3(_loc2_[_loc3_]);
			if (_loc2_[_loc3_] == undefined)
			{
				_loc2_[_loc3_] = -1;
			}
			_loc3_ = _loc3_ + 1;
		}
		_loc3_ = 16;
		while (_loc3_ < 28)
		{
			_loc2_[_loc3_] = _root.查找技能(_loc2_[_loc3_]);
			_loc3_ = _loc3_ + 1;
		}
		数据包 += _loc2_.join(" ");
		return 数据包;
	}
	var _loc8_ = false;
	if (n == 2)
	{
		var _loc6_ = [];
		_loc3_ = 0;
		while (_loc3_ < 比较数据[2].split(",").length / 3)
		{
			_loc6_[_loc3_] = [];
			_loc3_ = _loc3_ + 1;
		}
		var _loc9_ = 0;
		_loc3_ = 0;
		while (_loc3_ < 比较数据[2].split(",").length)
		{
			_loc6_[_loc9_].push(比较数据[2].split(",")[_loc3_]);
			if ((_loc3_ + 1) % 3 == 0)
			{
				_loc9_ = _loc9_ + 1;
			}
			_loc3_ = _loc3_ + 1;
		}
		_loc3_ = 0;
		while (_loc3_ < 40)
		{
			if ("" + _loc6_[_loc3_] != "" + _loc2_[_loc3_])
			{
				if (_loc8_)
				{
					数据包 += "\t";
				}
				else
				{
					_loc8_ = true;
				}
				tmp_aaa = _root.parseXMLs3(_loc2_[_loc3_][0]);
				if (tmp_aaa == undefined)
				{
					tmp_aaa = -1;
				}
				if (_loc2_[_loc3_][1] == undefined)
				{
					_loc2_[_loc3_][1] = -1;
				}
				数据包 += _loc3_ + " " + tmp_aaa + " " + _loc2_[_loc3_][1];
				if ("" + _loc6_[_loc3_] == "" + _loc2_[_loc3_])
				{
				}
			}
			_loc3_ = _loc3_ + 1;
		}
		return 数据包;
	}
	if (n == 3)
	{
		数据包 += data2;
		return 数据包;
	}
	if (n == 4)
	{
		_loc2_ = [[], data2[1]];
		_loc3_ = 0;
		while (_loc3_ < Number(data2[1]))
		{
			_loc2_[0].push(_root.同伴数据[_loc3_].slice());
			_loc3_ = _loc3_ + 1;
		}
		var _loc7_ = [];
		_loc3_ = 0;
		while (_loc3_ < Number(_loc2_[1]))
		{
			_loc7_[_loc3_] = _loc2_[0][_loc3_][2];
			_loc2_[0][_loc3_][4] = _root.查找脸型(_loc2_[0][_loc3_][4]);
			_loc2_[0][_loc3_][5] = _root.查找发型(_loc2_[0][_loc3_][5]);
			var _loc4_ = 6;
			while (_loc4_ < 17)
			{
				_loc2_[0][_loc3_][_loc4_] = _root.parseXMLs3(_loc2_[0][_loc3_][_loc4_]);
				if (_loc2_[0][_loc3_][_loc4_] == undefined)
				{
					_loc2_[0][_loc3_][_loc4_] = -1;
				}
				_loc4_ = _loc4_ + 1;
			}
			if (_loc2_[0][_loc3_][17] == "男")
			{
				_loc2_[0][_loc3_][17] = 1;
			}
			else
			{
				_loc2_[0][_loc3_][17] = 0;
			}
			_loc3_ = _loc3_ + 1;
		}
		_loc4_ = 0;
		while (_loc4_ < 3)
		{
			if (_loc7_.length > _loc4_)
			{
				if (_loc7_[_loc4_] != undefined)
				{
					数据包 += _loc7_[_loc4_];
				}
				else
				{
					数据包 += "0";
				}
			}
			else
			{
				数据包 += "0";
			}
			if (_loc4_ != 2)
			{
				数据包 += "\t";
			}
			_loc4_ = _loc4_ + 1;
		}
		return 数据包;
	}
	if (n == 5)
	{
		_loc8_ = false;
		_loc3_ = 0;
		while (_loc3_ < 80)
		{
			if (_loc2_[_loc3_][0] != "")
			{
				if (_loc8_)
				{
					数据包 += "\t";
				}
				else
				{
					_loc8_ = true;
				}
				数据包 += _root.查找技能(_loc2_[_loc3_][0]) + " " + _loc2_[_loc3_][1];
			}
			_loc3_ = _loc3_ + 1;
		}
		return 数据包;
	}
	_loc8_ = false;
	if (n == 6)
	{
		_loc6_ = [];
		_loc3_ = 0;
		while (_loc3_ < 比较数据[6].split(",").length / 3)
		{
			_loc6_[_loc3_] = [];
			_loc3_ = _loc3_ + 1;
		}
		_loc9_ = 0;
		_loc3_ = 0;
		while (_loc3_ < 比较数据[6].split(",").length)
		{
			_loc6_[_loc9_].push(比较数据[6].split(",")[_loc3_]);
			if ((_loc3_ + 1) % 3 == 0)
			{
				_loc9_ = _loc9_ + 1;
			}
			_loc3_ = _loc3_ + 1;
		}
		_loc3_ = 0;
		while (_loc3_ < _root.仓库栏总数)
		{
			if ("" + _loc6_[_loc3_] != "" + _loc2_[_loc3_])
			{
				if (_loc8_)
				{
					数据包 += "\t";
				}
				else
				{
					_loc8_ = true;
				}
				tmp_aaa = _root.parseXMLs3(_loc2_[_loc3_][0]);
				if (tmp_aaa == undefined)
				{
					tmp_aaa = -1;
				}
				数据包 += _loc3_ + " " + tmp_aaa + " " + _loc2_[_loc3_][1];
				if ("" + _loc6_[_loc3_] == "" + _loc2_[_loc3_])
				{
				}
			}
			_loc3_ = _loc3_ + 1;
		}
		return 数据包;
	}
	return "";
};



