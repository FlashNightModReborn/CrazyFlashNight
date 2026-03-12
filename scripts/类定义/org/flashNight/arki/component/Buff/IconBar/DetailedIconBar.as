import org.flashNight.arki.component.Buff.*;

/**
 */
class org.flashNight.arki.component.Buff.IconBar.DetailedIconBar {

    // private var iconIdentifier:String = "buff详细图标";
    
    private var barMC:MovieClip;
    private var iconProto:MovieClip;

    private var manager:BuffManager;

    private var iconPool:Array;          // 图标池
    private var buffIdToIconMap:Object;  // 图标池
    private var iconToBuffMap:Array;     // 图标与metabuff映射数组
    private var activeIconList:Array;
    private var buffIdDict:Object;

    private var startX:Number;
    private var startY:Number;
    private var padding:Number;

    /**
     * DetailedIconBar 构造函数
     */
    public function DetailedIconBar(_barMC:MovieClip, _iconProto:MovieClip, _padding:Number) {
        this.barMC = _barMC;
        this.iconProto = _iconProto;

        this.startX = _iconProto._x;
        this.startY = _iconProto._y;
        this.padding = _padding;

        this.iconPool = [];
        buffIdToIconMap = {};
        this.iconToBuffMap = [];

        this.buffIdDict = {};
    }

    public function initialize(_manager:BuffManager):Void{
        return; // 写到一半 一会再写

        this.manager = _manager;
        this.activeIconList = [];

        var metabuffs = _manager.getAllMetaBuffs();
        for(var i=0; i < metabuffs.length; i++){
            this.addIcon(metabuffs[i], null)
        }
    }

    public function deinitialize():Void{
        this.manager = null;
    }

    public function update():Void{
        for(var i=0; i < this.activeIconList.length; i++){
            // 刷新计时
        }
    }

    public function addIcon(_buff, id:String):Void{
        for(var index=0; index<this.iconToBuffMap.length; index++){
            if(this.iconToBuffMap[index] === null){
                break;
            }
        }

        var icon;
        if(index < this.iconToBuffMap.length){
            //
            icon = this.iconPool[index];
        }else{
            //
            icon = iconProto.duplicateMovieClip("icon" + index, index, null);
            this.iconPool[index] = icon;
            this.buffIdToIconMap[id] = index;
            this.activeIconList.push(index);
        }
        
        this.iconToBuffMap[index] = _buff;
        icon._visible = true;

        arrangeIcons();
    }

    public function removeIcon(id:String):Void{
        arrangeIcons();
    }

    private function arrangeIcons():Void{
        var i = 0;
        for(var index = 0; index < this.iconToBuffMap.length; index++){
            if(this.iconToBuffMap[index] != null){
                var icon = this.iconPool[index];
                icon._x = this.startX + i * this.padding;
                i++;
            }
        }
    }

}