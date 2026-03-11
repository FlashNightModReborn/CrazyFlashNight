import org.flashNight.arki.component.Buff.*;

/**
 */
class org.flashNight.arki.component.Buff.IconBar.DetailedIconBar {

    // private var iconIdentifier:String = "buff详细图标";
    
    private var barMC:MovieClip;
    private var iconProto:MovieClip;

    private var manager:BuffManager;

    private var iconPool:Array;
    private var activeIconList:Array;
    private var buffIdDict:Object;

    private var startX:Number;
    private var startY:Number;
    private var padding:Number;

    /**
     * DetailedIconBar 构造函数
     */
    public function DetailedIconBar(_barMC:MovieClip, _iconProto:MovieClip, _padding:Number) {
        this._barMC = barMC;
        this.iconProto = _iconProto;

        this.startX = _iconProto._x;
        this.startY = _iconProto._y;
        this.padding = _padding;

        this.iconPool = [];

        this.buffIdDict = {};
    }

    public function initialize(_manager:MovieClip):void{
        this.manager = _manager;
        this.activeIconList = [];

        var metabuffs = _manager.getAllMetaBuffs();
    }

    public function deinitialize():void{
        this.manager = null;
    }

    public function update(){
        for(var i=0; i < activeIconList.length; i++){
            // 刷新计时
        }
    }

    public function addIcon(){
        
    }

    public function removeIcon(){
        
    }

}