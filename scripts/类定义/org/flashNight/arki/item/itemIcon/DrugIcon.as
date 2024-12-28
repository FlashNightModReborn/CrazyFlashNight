import org.flashNight.arki.item.itemIcon.CollectionIcon;
// import org.flashNight.arki.item.ItemUtil;
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

        var 背包 = _root.物品栏.背包;
        var targetIndex = 背包.getFirstVacancy();
        if(targetIndex == -1) {
            _root.发布消息("背包空间不足！");
            return;
        }
        //卸下装备
        var result = collection.move(背包,index,targetIndex);
        if(!result) return;
        _root["快捷物品栏" + this.index] = "";
    }
}
