// import org.flashNight.arki.item.itemCollection.ItemCollection;
import org.flashNight.arki.item.itemIcon.ItemIcon;
/*
 * 属于物品集合的物品图标，继承物品图标基类
*/

class org.flashNight.arki.item.itemIcon.CollectionIcon extends ItemIcon{
    
    public var collection;
    public var index = null;

    private var locked:Boolean = false;

    public function CollectionIcon(_icon:MovieClip, _collection, _index) {
        this.icon = _icon;
        this.x = icon._x;
        this.y = icon._y;
        this.valuetext = icon.valuetext;
        this.leveltext = icon.leveltext;
        //
        this.collection = _collection;
        this.index = _index;
        this.collection.setIcon(this,index)
        init();
    }

    //根据对应的物品集合与索引初始化图标
    public function init():Void{
        if(collection.isDict){
            super.init(String(index),collection.getValue(String(index)));
        }else{
            var _item = collection.getItem(String(index));
            super.init(_item.name,_item);
        }
    }

    //图标刷新
    public function refresh():Void{
        icon.gotoAndStop("刷新");
        init();
    }

    public function refreshValue():Void{
        value = item.value;
        valuetext.text = String(value);
    }

    // public function refreshLevel():Void{
    //     leveltext.text = String(value.level);
    // }
}
