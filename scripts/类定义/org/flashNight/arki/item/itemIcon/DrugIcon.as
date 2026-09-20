import org.flashNight.arki.item.itemIcon.CollectionIcon;
import org.flashNight.arki.item.DrugSlotAffinityService;
/*
 * 药剂栏物品图标，继承CollectionIcon
*/

class org.flashNight.arki.item.itemIcon.DrugIcon extends CollectionIcon{

    private var coolDownBar:MovieClip;

    public function DrugIcon(_icon:MovieClip, _collection, _index, _coolDownBar:MovieClip) {
        super(_icon, _collection, _index);
        coolDownBar = _coolDownBar;
    }

    public function isCoolDown():Boolean{
        return coolDownBar.冷却 == true;
    }

    public function RollOver():Void{
        _root.物品图标注释(this.name,this.value);
        if (!this.locked && isCoolDown()) icon.互动提示.gotoAndPlay("卸下");
    }

    public function Press():Void{
        _root.注释结束();
        if (this.locked || !isCoolDown()) return;

        var current:Object = collection.getItem(String(index));
        var result:Object = org.flashNight.arki.item.DrugHudMutationService.unequip(
            _root, Number(index), current, Number(current.value), this.locked);
        if (result.error == "bag_full") _root.发布消息("背包空间不足！");
        else if (result.error == "not_ready") _root.发布消息("药剂槽状态尚未就绪，请稍后重试！");

    }
}
