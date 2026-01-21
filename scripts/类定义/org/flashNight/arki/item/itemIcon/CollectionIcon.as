// import org.flashNight.arki.item.itemCollection.ItemCollection;
import org.flashNight.arki.item.itemIcon.ItemIcon;
import org.flashNight.neur.Event.LifecycleEventDispatcher;
/*
 * 属于物品集合的物品图标，继承物品图标基类
*/

class org.flashNight.arki.item.itemIcon.CollectionIcon extends ItemIcon{
    
    public var collection;
    public var index = null;

    private var locked:Boolean = false;

    private var dispatcher:LifecycleEventDispatcher; //
    private var refreshCallback:Function;
    private var refreshValueCallback:Function;

    public function CollectionIcon(_icon:MovieClip, _collection, _index) {
        this.icon = _icon;
        this.x = icon._x;
        this.y = icon._y;
        this.valuetext = icon.valuetext;
        this.leveltext = icon.leveltext;
        //
        this.collection = _collection;
        this.index = _index;
        setDispatcher();
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

    //重设物品集合与索引
    public function reset(_collection, _index):Void{
        this.collection = _collection;
        this.index = _index;
        setDispatcher();
        init();
    }

    public function refreshValue():Void{
        //检测是否来自集合，若来自集合则手动刷新一次value
        if(!isNaN(item)) this.item = collection.getValue(String(index));
        super.refreshValue();
    }

    private function setDispatcher():Void{
        //卸载之前的事件监听
        // [v2.3] 使用精确退订模式，传入 scope 参数
        if(this.dispatcher){
            this.dispatcher.unsubscribe("ItemAdded", this.refreshCallback, this);
            this.dispatcher.unsubscribe("ItemRemoved", this.refreshCallback, this);
            this.dispatcher.unsubscribe("ItemValueChanged", this.refreshValueCallback, this);
        }
        if(!this.collection.hasDispatcher()) return;
        this.dispatcher = this.collection.getDispatcher();
        this.refreshCallback = function(_collection, _key){
            if(_collection === this.collection && _key == this.index) this.refresh();
        }
        this.refreshValueCallback = function(_collection, _key){
            if(_collection === this.collection && _key == this.index) this.refreshValue();
        }
        //注册对应的事件监听
        this.dispatcher.subscribe("ItemAdded", this.refreshCallback, this);
        this.dispatcher.subscribe("ItemRemoved", this.refreshCallback, this);
        this.dispatcher.subscribe("ItemValueChanged", this.refreshValueCallback, this);
    }
}
