﻿_root.健身房训练类型 = [];
_root.健身房训练类型[0] = {属性名:"全局健身HP加成", 加成名:"HP上限", 加成:10, 货币名:"金钱", 消耗:50000, 时长:10000, 上限:2000};
_root.健身房训练类型[1] = {属性名:"全局健身HP加成", 加成名:"HP上限", 加成:10, 货币名:"K点", 消耗:1000, 时长:10000, 上限:2000};
_root.健身房训练类型[2] = {属性名:"全局健身MP加成", 加成名:"MP上限", 加成:10, 货币名:"金钱", 消耗:50000, 时长:10000, 上限:2000};
_root.健身房训练类型[3] = {属性名:"全局健身MP加成", 加成名:"MP上限", 加成:10, 货币名:"K点", 消耗:1000, 时长:10000, 上限:2000};
_root.健身房训练类型[4] = {属性名:"全局健身空攻加成", 加成名:"空手攻击力", 加成:3, 货币名:"金钱", 消耗:90000, 时长:10000, 上限:500};
_root.健身房训练类型[5] = {属性名:"全局健身空攻加成", 加成名:"空手攻击力", 加成:3, 货币名:"K点", 消耗:3000, 时长:10000, 上限:500};
_root.健身房训练类型[6] = {属性名:"全局健身防御加成", 加成名:"防御力", 加成:5, 货币名:"K点", 消耗:2500, 时长:10000, 上限:1000};
_root.健身房训练类型[7] = {属性名:"技能点", 加成名:"技能点", 加成:25, 货币名:"K点", 消耗:1250, 时长:1000};
_root.健身房训练类型[8] = {属性名:"技能点", 加成名:"技能点", 加成:100, 货币名:"K点", 消耗:5000, 时长:1000};
_root.健身房训练类型[9] = {属性名:"技能点", 加成名:"技能点", 加成:500, 货币名:"K点", 消耗:25000, 时长:1000};
_root.健身房训练类型[10] = {属性名:"技能点", 加成名:"技能点", 加成:1000, 货币名:"K点", 消耗:35000, 时长:1000};
_root.健身房训练类型[11] = {属性名:"技能点", 加成名:"技能点", 加成:2000, 货币名:"K点", 消耗:70000, 时长:1000};
_root.健身房训练类型[12] = {属性名:"技能点", 加成名:"技能点", 加成:5000, 货币名:"K点", 消耗:100000, 时长:1000};


_root.获取木人桩训练项 = function(){
		_root.健身房训练类型 = [];
		_root.健身房训练类型[0] = {属性名:"全局健身空攻加成", 加成名:"空手攻击力", 加成:3, 货币名:"金钱", 消耗:60000, 时长:10000, 上限:500};
		_root.健身房训练类型[1] = {属性名:"全局健身空攻加成", 加成名:"空手攻击力", 加成:9, 货币名:"K点", 消耗:6000, 时长:10000, 上限:500};
		_root.健身房训练类型[2] = {属性名:"全局健身空攻加成", 加成名:"空手攻击力", 加成:30, 货币名:"金钱", 消耗:800000, 时长:10000, 上限:500};
		_root.健身房训练类型[3] = {属性名:"全局健身内力加成", 加成名:"内力", 加成:20, 货币名:"金钱", 消耗:800000, 时长:20000, 上限:100};
		if(_root.主线任务进度 >=68){
			_root.健身房训练类型[4] = {属性名:"全局健身空攻加成", 加成名:"空手攻击力", 加成:120, 货币名:"金钱", 消耗:3600000, 时长:10000, 上限:500};
			_root.健身房训练类型[5] = {属性名:"全局健身空攻加成", 加成名:"空手攻击力", 加成:120, 货币名:"K点", 消耗:120000, 时长:10000, 上限:500};
		}
		if(_root.主线任务进度 >=120){
			_root.健身房训练类型[6] = {属性名:"全局健身空攻加成", 加成名:"空手攻击力", 加成:500, 货币名:"K点", 消耗:600000, 时长:30000, 上限:500};
		}
		_root.健身房训练类型[7] = {属性名:"技能点", 加成名:"技能点", 加成:25, 货币名:"K点", 消耗:1250, 时长:1000};
		_root.健身房训练类型[8] = {属性名:"技能点", 加成名:"技能点", 加成:100, 货币名:"K点", 消耗:5000, 时长:1000};
		_root.健身房训练类型[9] = {属性名:"技能点", 加成名:"技能点", 加成:500, 货币名:"K点", 消耗:25000, 时长:1000};
		if(_root.等级>=35){
			_root.健身房训练类型[10] = {属性名:"技能点", 加成名:"技能点", 加成:1000, 货币名:"K点", 消耗:35000, 时长:1000};
			_root.健身房训练类型[11] = {属性名:"技能点", 加成名:"技能点", 加成:2000, 货币名:"K点", 消耗:70000, 时长:1000};
		}
		if(_root.等级>=50){
			_root.健身房训练类型[12] = {属性名:"技能点", 加成名:"技能点", 加成:5000, 货币名:"K点", 消耗:100000, 时长:1000};
		}
}

_root.获取深蹲杠铃训练项 = function(){
		_root.健身房训练类型 = [];
		_root.健身房训练类型[0] = {属性名:"全局健身MP加成", 加成名:"MP上限", 加成:10, 货币名:"金钱", 消耗:50000, 时长:10000, 上限:2000};
		_root.健身房训练类型[1] = {属性名:"全局健身MP加成", 加成名:"MP上限", 加成:50, 货币名:"K点", 消耗:8000, 时长:10000, 上限:2000};
		_root.健身房训练类型[2] = {属性名:"全局健身防御加成", 加成名:"防御力", 加成:20, 货币名:"金钱", 消耗:300000, 时长:10000, 上限:1000};
		if(_root.主线任务进度 >=68){
			_root.健身房训练类型[3] = {属性名:"全局健身MP加成", 加成名:"MP上限", 加成:300, 货币名:"金钱", 消耗:1800000, 时长:10000, 上限:2000};
			_root.健身房训练类型[4] = {属性名:"全局健身防御加成", 加成名:"防御力", 加成:200, 货币名:"K点", 消耗:100000, 时长:10000, 上限:1000};
		}
		if(_root.主线任务进度 >=120){
			_root.健身房训练类型[5] = {属性名:"全局健身MP加成", 加成名:"MP上限", 加成:2000, 货币名:"K点", 消耗:360000, 时长:30000, 上限:2000};
			_root.健身房训练类型[6] = {属性名:"全局健身防御加成", 加成名:"防御力", 加成:1000, 货币名:"K点", 消耗:600000, 时长:30000, 上限:1000};
		}
		_root.健身房训练类型[7] = {属性名:"技能点", 加成名:"技能点", 加成:25, 货币名:"K点", 消耗:1250, 时长:1000};
		_root.健身房训练类型[8] = {属性名:"技能点", 加成名:"技能点", 加成:100, 货币名:"K点", 消耗:5000, 时长:1000};
		_root.健身房训练类型[9] = {属性名:"技能点", 加成名:"技能点", 加成:500, 货币名:"K点", 消耗:25000, 时长:1000};
		if(_root.等级>=35){
			_root.健身房训练类型[10] = {属性名:"技能点", 加成名:"技能点", 加成:1000, 货币名:"K点", 消耗:35000, 时长:1000};
			_root.健身房训练类型[11] = {属性名:"技能点", 加成名:"技能点", 加成:2000, 货币名:"K点", 消耗:70000, 时长:1000};
		}
		if(_root.等级>=50){
			_root.健身房训练类型[12] = {属性名:"技能点", 加成名:"技能点", 加成:5000, 货币名:"K点", 消耗:100000, 时长:1000};
		}
}

_root.获取哑铃训练项 = function(){
		_root.健身房训练类型 = [];
		_root.健身房训练类型[0] = {属性名:"全局健身HP加成", 加成名:"HP上限", 加成:10, 货币名:"金钱", 消耗:50000, 时长:10000, 上限:2000};
		_root.健身房训练类型[1] = {属性名:"全局健身HP加成", 加成名:"HP上限", 加成:50, 货币名:"K点", 消耗:8000, 时长:10000, 上限:2000};
		_root.健身房训练类型[2] = {属性名:"全局健身防御加成", 加成名:"防御力", 加成:5, 货币名:"金钱", 消耗:60000, 时长:10000, 上限:1000};
		if(_root.主线任务进度 >=68){
			_root.健身房训练类型[3] = {属性名:"全局健身HP加成", 加成名:"HP上限", 加成:200, 货币名:"金钱", 消耗:1200000, 时长:10000, 上限:2000};
			_root.健身房训练类型[4] = {属性名:"全局健身HP加成", 加成名:"HP上限", 加成:500, 货币名:"K点", 消耗:85000, 时长:10000, 上限:2000};
			_root.健身房训练类型[5] = {属性名:"全局健身防御加成", 加成名:"防御力", 加成:120, 货币名:"K点", 消耗:50000, 时长:10000, 上限:1000};
		}
		if(_root.主线任务进度 >=120){
			_root.健身房训练类型[6] = {属性名:"全局健身HP加成", 加成名:"HP上限", 加成:2000, 货币名:"K点", 消耗:360000, 时长:30000, 上限:2000};
		}
		_root.健身房训练类型[7] = {属性名:"技能点", 加成名:"技能点", 加成:25, 货币名:"K点", 消耗:1250, 时长:1000};
		_root.健身房训练类型[8] = {属性名:"技能点", 加成名:"技能点", 加成:100, 货币名:"K点", 消耗:5000, 时长:1000};
		_root.健身房训练类型[9] = {属性名:"技能点", 加成名:"技能点", 加成:500, 货币名:"K点", 消耗:25000, 时长:1000};
		if(_root.等级>=35){
			_root.健身房训练类型[10] = {属性名:"技能点", 加成名:"技能点", 加成:1000, 货币名:"K点", 消耗:35000, 时长:1000};
			_root.健身房训练类型[11] = {属性名:"技能点", 加成名:"技能点", 加成:2000, 货币名:"K点", 消耗:70000, 时长:1000};
		}
		if(_root.等级>=50){
			_root.健身房训练类型[12] = {属性名:"技能点", 加成名:"技能点", 加成:5000, 货币名:"K点", 消耗:100000, 时长:1000};
		}
}



















