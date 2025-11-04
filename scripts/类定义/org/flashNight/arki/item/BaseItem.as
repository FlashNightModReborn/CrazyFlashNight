import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.EquipmentUtil;

/*
 * 物品基类
 */

class org.flashNight.arki.item.BaseItem{
    
    /*
    *  每个物品基类有3个必要属性 name, value, lastUpdate
    */
    // name 为物品的唯一标识符，用于获取物品数据
    public var name:String;

    // 装备物品的 value 为 Object，记录装备强化度，射击次数等所有详细数据；其余物品的 value 为 Number，表示物品数量
    public var value;

    // lastUpdate 表示物品最后更改的时间戳
    public var lastUpdate:Number;



    public var itemData:Object; // 通过 getData() 函数获取的物品数据会储存在物品基类对象中。目前暂未启用

    
    /*
     * 创建物品基类对象的三种函数
     */
    // 通过 name, value(Number), lastUpdate 创建物品对象。value 在创建装备时会自动转换为强化度。
    public static function create(__name:String, __value:Number, __lastUpdate:Number):BaseItem{
        if(__value <= 0 || !ItemUtil.isItem(__name)) return null;
        if(ItemUtil.isEquipment(__name)) {
            return new BaseItem(
                __name,
                __value > 13 ? {level: 1, mods: []} : {level: __value, mods: []},  // 修复：初始化mods为空数组
                __lastUpdate
            );
        }
        return new BaseItem(__name, __value, __lastUpdate);
    }

    // 通过一个 initObject 创建物品对象。
    public static function createFromObject(initObject:Object):BaseItem{
        var __name = initObject.name;
        var __value = initObject.value;
        if(!__value || !ItemUtil.isItem(__name)) return null;
        // 修复：确保装备的mods字段始终是数组
        if(ItemUtil.isEquipment(__name) && __value.mods === undefined){
            __value.mods = [];
        }
        return new BaseItem(__name, __value, initObject.lastUpdate);
    }

    // 通过字符串创建物品对象。输入字符串为 name#value#tier 的形式，value 和 tier 在创建装备时会自动转换为强化度和进阶。
    public static function createFromString(str:String):BaseItem{
        var strArr = str.split("#");
        var __name = strArr[0];
        if(!ItemUtil.isItem(__name)) return null;
        var __value = Number(strArr[1]);
        if(__value <= 0) __value = 1; // 若value不为正数或不为数字则修改为1
        var newItem:BaseItem = create(__name, __value);
        if(ItemUtil.isEquipment(__name)){
            if(strArr[2]) {
                // 为新创建的物品加入多阶参数
                newItem.value.tier = strArr[2];
            }
            if(strArr[3]){
                var modArr = strArr[3].split(",");
                var modList = [];  // 修复：使用数组而非对象
                for(var i = 0; i < modArr.length; i++){
                    if(EquipmentUtil.modDict[modArr[i]]){
                        modList.push(modArr[i]);  // 修复：直接push配件名到数组
                    }
                }
                newItem.value.mods = modList;  // 修复：赋值为数组
            }
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



    /*
     * 根据物品对象获取并缓存物品数据。装备数值会在这个过程中自动计算。
     */
    public function getData():Object{
        // if(this.itemData) return this.itemData; // 如果有缓存的物品数据则直接返回
        var _itemData:Object = ItemUtil.getItemData(this.name);
        if(ItemUtil.isEquipment(this.name)) EquipmentUtil.calculateData(this, _itemData);
        return _itemData; // return this.itemData = _itemData;
    }

    /*
     * 刷新物品的时间戳，并清除缓存的物品数据。
     */
    public function update(__lastupdate:Number):Void{
        if(isNaN(__lastupdate)) this.lastUpdate = new Date().getTime();
        else if(__lastupdate > this.lastUpdate) this.lastUpdate = __lastupdate;
        // this.itemData = null;
    }


    /*
     * 剥离物品的存档数据并返回一个Object。
     */
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
