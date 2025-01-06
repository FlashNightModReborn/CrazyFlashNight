import org.flashNight.arki.item.ItemUtil;
/*
 * 物品图标UI基类
*/

class org.flashNight.arki.item.itemIcon.ItemIcon{
    
    private var icon:MovieClip; //物品图标影片剪辑

    private var x:Number; //物品图标起始x坐标
    private var y:Number; //物品图标起始y坐标
    private var valuetext:TextField; //数量文本
    private var leveltext:TextField; //强化度文本

    public var item;
    public var itemData:Object;
    public var name:String;
    public var value;

    public function ItemIcon(_icon:MovieClip,__name:String, _item) {
        this.icon = _icon;
        this.x = icon._x;
        this.y = icon._y;
        this.valuetext = icon.valuetext;
        this.leveltext = icon.leveltext;
        init(__name, _item);
    }

    //初始化图标
    public function init(__name:String, _item):Void{
        this.icon.gotoAndStop("空");
        this.name = __name;
        this.item = _item;
        if(!this.name || !this.item){
            this.itemData = null;
            valuetext._visible = false;
            leveltext._visible = false;
        }else{
            this.itemData = ItemUtil.getItemData(this.name);
            this.icon.gotoAndStop("默认图标");
            refreshValue();
        }
    }

    public function getIconMovieClip():MovieClip{
        return this.icon;
    }

    //图标刷新
    public function refresh():Void{
        this.icon.gotoAndStop("刷新");
        init();
    }

    public function refreshValue():Void{
        //检测是否来自集合
        if(!isNaN(item)) this.value = item;
        else this.value = item.value;
        if(value > 1){
            valuetext._visible = true;
            leveltext._visible = false;
            valuetext.text = String(value);
        }else if(value.level > 1){
            valuetext._visible = false;
            leveltext._visible = true;
            leveltext.text = String(value.level);
        }else{
            valuetext._visible = false;
            leveltext._visible = false;
        }
    }


    //图标按钮事件
    public function RollOver():Void{
        _root.物品图标注释(name,value);
    }

    public function RollOut():Void{
        icon.互动提示.gotoAndStop("空");
        _root.注释结束();
    }

    public function Press():Void{
    }

    public function Release():Void{
    }
}
