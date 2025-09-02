import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.arki.item.*;

/*
 * 物品基类
 */

class org.flashNight.arki.item.itemRequirement.ItemRequirement{
    
    /*
    *  每个物品基类有3个必要属性 name, value, lastUpdate
    */
    public var gold:Number;
    public var kpoint:Number;
    public var exp:Number;
    public var sp:Number;

    public var items:Array;

    private static var nonItemFuncs:Object = {
        金币: addGold,
        K点: addKPoint,
        经验值: addExp,
        技能点:addSp
    }


    /*
     * 物品基类构造函数，一般情况下不直接调用而是使用上述三种创建函数
     */
    public function ItemRequirement(){
        gold = 0;
        kpoint = 0;
    }

    public function add(itemStr:String){
        var itemArr = itemStr.split("#");
        var name:String = itemArr[0];
        var value:Number = Number(itemArr[1]);
        if(!name) return;
        if(value <= 0) value = 1;
        var nonItemFunc:Function = nonItemFuncs[name];
        if(nonItemFunc){
            nonItemFunc(this, value);
            return;
        }
        items.push(BaseItem.createFromString(itemStr));
    }

    public static function addGold(req:ItemRequirement, value){
        req.gold += value;
    }
    public static function addKPoint(req:ItemRequirement, value){
        req.kpoint += value;
    }
    public static function addExp(req:ItemRequirement, value){
        req.exp += value;
    }
    public static function addSp(req:ItemRequirement, value){
        req.sp += value;
    }

    public function destroy(){
        gold = 0;
        kpoint = 0;
        exp = 0;
        sp = 0;
    }

}
