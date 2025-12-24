import org.flashNight.arki.item.*;
import org.flashNight.arki.item.itemIcon.*;
import org.flashNight.arki.unit.UnitComponent.Initializer.*;

_root.佣兵系统UI = new Object();


_root.佣兵系统UI.创建佣兵装备图标 = function(UI:MovieClip, 佣兵数据:Array, startx:Number, starty:Number){
	var 计算强化度:Number = DressupInitializer.getEquipmentDefaultLevel(佣兵数据[0], 佣兵数据[1]);	
	for (var equipIndex = 6; equipIndex < 17; equipIndex++){
		var 装备物品 = BaseItem.createFromString(佣兵数据[equipIndex]);
		if (装备物品){
			if (装备物品.value.level == 1){
				装备物品.value.level = 计算强化度;
			}
			var 物品图标 = UI.attachMovie("物品图标", "物品图标" + equipIndex, equipIndex,{
				_x: (equipIndex - 6) * 28 + startx, 
				_y: starty
			});
			物品图标.itemIcon = new ItemIcon(物品图标, 装备物品.name, 装备物品);
		}
	}
}

_root.佣兵系统UI.排列佣兵图标 = function(){
	删除佣兵图标();
	删除可雇用佣兵图标();
	gotoAndStop("佣兵管理");
	
	var 同伴最大数量 = Math.max(_root.同伴数, _root.同伴数据.length);
	//while (index < _root.同伴数)
	for (var index = 0; index < 同伴最大数量; index++){
		var 当前同伴数据 = _root.同伴数据[index];
		if (当前同伴数据[0] != null){
			var 佣兵信息显示框 = this.attachMovie("佣兵信息显示框","佣兵信息显示框" + index, index,{
				_x: 8, 
				_y: 31 + index * 70, 
				同伴数据数组号:index, 
				佣兵数据:当前同伴数据, 
				是否出战:_root.佣兵是否出战信息[index], 
				名字:当前同伴数据[1], 
				等级:当前同伴数据[0]
			});
			_root.佣兵系统UI.创建佣兵装备图标(佣兵信息显示框, 当前同伴数据, 15.5, 44);
		}
	}
}

_root.佣兵系统UI.排列可雇用佣兵图标 = function(页数值){
	gotoAndStop("查找佣兵");
	删除佣兵图标();
	删除可雇用佣兵图标();
	当前页数 = Number(页数值);
	页数显示 = 当前页数 + " / " + 总页数;
	
	下一页._visible = false;
	下十页._visible = false;
	上一页._visible = false;
	上十页._visible = false;
	if (当前页数 < 总页数){
		下一页._visible = true;
		下十页._visible = true;
	}
	if (当前页数 > 1){
		上一页._visible = true;
		上十页._visible = true;
	}
	
	for (var index = 0; index < 5; index++){
		var 当前佣兵数据 = 可雇用佣兵列表数据[index];
		if (当前佣兵数据[1] != null){
			if (当前佣兵数据[19].隐藏){
				continue;
			}
			var 当前佣兵等级 = Number(当前佣兵数据[0]);

			var 所需金币 = 当前佣兵数据[18] * 1.5;
			var 所需K点 = _root.isEasyMode() ? 0 : 当前佣兵数据[0] >= 50 ? (当前佣兵数据[0] - 50) * 100 : 0;
			if (当前佣兵数据[19].价格倍率){
				所需金币 = Math.floor(所需金币 * 当前佣兵数据[19].价格倍率 / 500) * 500;
				所需K点 = Math.floor(所需K点 * 当前佣兵数据[19].价格倍率 / 100) * 100;
			}

			var 佣兵列表信息显示框 = this.attachMovie("佣兵列表信息显示框","佣兵列表信息显示框" + index, index,{
				_x:8, 
				_y:31 + index * 60, 
				可雇用佣兵列表数据:当前佣兵数据, 
				名字:当前佣兵数据[1], 
				等级:当前佣兵数据[0], 
				身价:所需K点, 
				金币身价:所需金币, 
				热度:当前佣兵数据[18], 
				鲜度:0
			});
			_root.佣兵系统UI.创建佣兵装备图标(佣兵列表信息显示框, 当前佣兵数据, 15.5, 44);
		}
	}
}
