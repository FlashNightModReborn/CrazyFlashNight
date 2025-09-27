import org.flashNight.arki.item.ItemUtil;
/*
 * 物品图标UI基类
*/

class org.flashNight.arki.item.itemIcon.SelectionIcon extends ItemIcon{
    
    public function SelectionIcon(_icon:MovieClip,__name:String, _item) {
        super(_icon, __name, _item);
    }


    // 新的图标按钮事件
    public function EmptyRollOver():Void{
    }

    public function EmptyRollOut():Void{
    }

    public function Select():Void{
    }
}
