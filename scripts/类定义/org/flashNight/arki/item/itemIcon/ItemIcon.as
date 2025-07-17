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
    // private var fullLevelFrame:MovieClip; //满级框

    public var item;
    public var itemData:Object;
    public var name:String;
    public var value;

    private var locked:Boolean; // 记录物品图标是否锁定，锁定期间图标无法响应点击事件

    public function ItemIcon(_icon:MovieClip,__name:String, _item) {
        this.icon = _icon;
        this.x = icon._x;
        this.y = icon._y;
        this.valuetext = icon.valuetext;
        this.leveltext = icon.leveltext;
        this.locked = false;
        // this.fullLevelFrame = icon.满级框;
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
            icon.满级框._visible = false;
        }else{
            this.itemData = ItemUtil.getItemData(this.name);
            this.icon.gotoAndStop("默认图标");
            this.icon.互动提示.gotoAndStop(this.locked ? "锁定" : "空");
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
        valuetext._visible = false;
        leveltext._visible = false;
        icon.满级框._visible = false;
        if(value > 1){
            valuetext._visible = true;
            valuetext.text = String(value);
        }else if(value.level > 1){
            leveltext._visible = true;
            leveltext.text = String(value.level);
            if(value.level == 13) icon.满级框._visible = true;
        }
    }

    public function lock(){
        this.locked = true;
        this.icon.互动提示.gotoAndStop("锁定");
    }
    public function unlock(){
        this.locked = false;
        this.icon.互动提示.gotoAndStop("空");
    }

    public function dispose(){
        icon = null;
        valuetext = null;
        valuetext = null;
    }


    //图标按钮事件
    public function RollOver():Void{
        _root.物品图标注释(name,value);
    }

    public function RollOut():Void{
        this.icon.互动提示.gotoAndStop(this.locked ? "锁定" : "空");
        _root.注释结束();
    }

    public function Press():Void{
    }

    public function Release():Void{
    }
}
