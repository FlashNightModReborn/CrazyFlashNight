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
        name = __name;
        item = _item;
        if(!name || !item){
            this.itemData = null;
            icon.gotoAndStop("空");
            valuetext._visible = false;
            leveltext._visible = false;
        }else{
            //检测是否来自集合
            if(!isNaN(item)) this.value = item;
            else this.value = item.value;
            //
            this.itemData = _root.getItemData(name);
            icon.gotoAndStop("默认图标");
            if(!isNaN(value)){
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
            // icon.图标壳.attachMovie("图标-" + itemData.icon, "图标", 0);
            // if(icon.图标壳.图标) icon.图标壳.基本款._visible = false;
        }
    }

    public function getIconMovieClip():MovieClip{
        return icon;
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
