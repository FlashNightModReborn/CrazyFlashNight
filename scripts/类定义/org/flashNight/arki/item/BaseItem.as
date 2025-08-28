import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.arki.item.ItemUtil;

/*
 * ItemUtil 静态类，存储物品数据与物品工具函数
 * 
 */

class org.flashNight.arki.item.BaseItem{
    
    public var name:String;
    public var value;
    public var lastUpdate:Number;

    
    /*
     * 创建物品基类对象的三种函数
     */
    public static function create(__name:String, __value:Number, __lastUpdate:Number):BaseItem{
        if(__value <= 0 || !ItemUtil.isItem(__name)) return null;
        if(ItemUtil.isEquipment(__name)) {
            return new BaseItem(
                __name, 
                __value > 13 ? {level: 1} : {level: __value}, 
                __lastUpdate
            );
        }
        return new BaseItem(__name, __value, __lastUpdate);
    }
    public static function createFromObject(initObject:Object):BaseItem{
        var __name = initObject.name;
        var __value = initObject.value;
        if(!__value || !ItemUtil.isItem(__name)) return null;
        return new BaseItem(__name, __value, initObject.lastUpdate);
    }
    public static function createFromString(str:String):BaseItem{
        var strArr = str.split("#");
        var __name = strArr[0];
        if(!ItemUtil.isItem(__name)) return null;
        var __value = Number(strArr[1]);
        if(__value <= 0) __value = 1; // 若value不为正数或不为数字则修改为1
        var newItem:BaseItem = create(__name, __value);
        if(ItemUtil.isEquipment(__name) && strArr[2]) {
            // 为新创建的物品加入多阶参数
            newItem.value.tier = strArr[2];
        }
        return newItem;
    }


    /*
     * 物品基类构造函数，一般情况下不直接调用而是使用上述三种创建函数
     */
    public function BaseItem(__name:String, __value, __lastUpdate:Number){
        this.name = __name;
        this.value = __value;
        this.lastUpdate = isNaN(__lastUpdate) ? new Date().getTime() : __lastUpdate
    }


    public function getData():Object{
        var itemData:Object = ItemUtil.getItemData(this.name);
        if(!ItemUtil.isEquipment(this.name)) return itemData; // 若不为装备则返回原始物品数据
        var data:Object = itemData.data;
        // 获取对应的多阶数据
        if(this.value.tier){
            var tierKey = ItemUtil.equipmentTierDict[this.value.tier];
            var tierData = itemData[tierKey];
            if(tierKey && tierData){
                for(var key in tierData){
                   data[key] = tierData[key];
                }
                itemData[tierKey] = null;
            }
        }
        // 计算强化数值
        if(this.value.level > 1){
            if(this.value.level > 13) this.value.level = 13;
            var levelMultiplier = ItemUtil.equipmentLevelList[this.value.level];
            if(data.power) data.power = data.power * levelMultiplier >> 0;
            if(data.defence) data.defence = data.defence * levelMultiplier >> 0;
            if(data.damage) data.damage = data.damage * levelMultiplier >> 0;
            if(data.force) data.force = data.force * levelMultiplier >> 0;
            if(data.punch) data.punch = data.punch * levelMultiplier >> 0;
            if(data.knifepower) data.knifepower = data.knifepower * levelMultiplier >> 0;
            if(data.gunpower) data.gunpower = data.gunpower * levelMultiplier >> 0;
            if(data.hp) data.hp = data.hp * levelMultiplier >> 0;
            if(data.mp) data.mp = data.mp * levelMultiplier >> 0;
        }
        return itemData;
    }

    public function update(__lastupdate:Number):Void{
        if(isNaN(__lastupdate)) this.lastUpdate = new Date().getTime();
        else if(__lastupdate > this.lastUpdate) this.lastUpdate = __lastupdate;
    }

    public function toObject():Object{
        return {
            name: this.name,
            value: ObjectUtil.clone(this.value),
            lastUpdate: this.lastUpdate
        };
    }

    public function toString():String{
        return this.name;
    }
}
