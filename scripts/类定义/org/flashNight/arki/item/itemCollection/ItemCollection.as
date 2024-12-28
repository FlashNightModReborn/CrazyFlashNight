import org.flashNight.arki.item.itemCollection.ICollection;

/*
 * 物品集合基类
*/

class org.flashNight.arki.item.itemCollection.ItemCollection implements ICollection{
    
    private var items:Object; //物品数据

    public var icons:Object; //物品图标引用
    public var iconMovieClips:Object; //物品图标影片剪辑的引用

    public var isDict:Boolean; //是否为字典集合

    public function ItemCollection(_items:Object) {
        if(!_items) this.items = new Object();
        else this.items = _items;
        icons = new Object();
        iconMovieClips = new Object();
    }

    //获取物品对象
    public function getItem(key:String):Object{
        var item = items[key];
        if(!item) return null;
        return item;
    }

    //获取对应键的值（未使用）
    public function getValue(key:String):Object{
        var value = items[key].value;
        if(!value) return null;
        return value;
    }

    //获取全部物品集合数据
    public function getItems():Object{
        return items;
    }

    //判断某个键是否为空
    public function isEmpty(key:String):Boolean{
        return !(items[key] != null);
    }

    //判断是否能添加指定物品
    public function isAddable(key:String,item:Object):Boolean{
        return true;
    }

    //添加物品
    public function add(key:String,item:Object):Boolean{
        if(isEmpty(key) && isAddable(key,item)){
            items[key] = item;
            if(icons[key]) icons[key].refresh();
            return true;
        }
        return false;
    }

    //移除物品
    public function remove(key:String):Void{
        delete items[key];
        if(icons[key]) icons[key].refresh();
    }

    //物品图标相关函数
    //设置图标索引
    public function setIcon(icon,key:String):Void{
        icons[key] = icon;
        iconMovieClips[key] = icon.getIconMovieClip();
    }

    //移除图标索引
    public function removeIcon(key:String):Void{
        delete icons[key];
        delete iconMovieClips[key];
    }

    //清空图标索引
    public function clearIcon():Void{
        icons = new Object();
        iconMovieClips = new Object();
    }
}
