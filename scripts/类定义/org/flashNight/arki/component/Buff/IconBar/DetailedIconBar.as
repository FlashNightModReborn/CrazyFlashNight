import org.flashNight.arki.component.Buff.*;

/**
 */
class org.flashNight.arki.component.Buff.IconBar.DetailedIconBar {

    // private var iconIdentifier:String = "buff详细图标";
    
    private var barMC:MovieClip;
    private var iconProto:MovieClip;

    private var manager:BuffManager;

    private var iconPool:Array;       // 图标池
    private var iconToBuffMap:Array;  // 图标与metabuff映射数组
    private var activeBuffs:Array;    // buff数组

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
        this.iconToBuffMap = [];
        this.activeBuffs = [];
    }

    public function initialize(_manager:BuffManager):Void{
        if(this.manager){
            this.deinitialize();
        }
        this.manager = _manager;

        var metabuffs = _manager.getAllMetaBuffs();
        for(var i=0; i < metabuffs.length; i++){
            this.addIcon(metabuffs[i].__regId, metabuffs[i]);
        }

        _manager.eventDispatcher.subscribe("add", addIcon, this);
        _manager.eventDispatcher.subscribe("remove", removeIcon, this);
    }

    public function deinitialize():Void{
        if(this.manager && this.manager.eventDispatcher && !this.manager.eventDispatcher.isDestroyed()){
            this.manager.eventDispatcher.unsubscribe("add", addIcon, this);
            this.manager.eventDispatcher.unsubscribe("remove", removeIcon, this);
        }
        this.manager = null;
        for(var i=0; i<this.iconPool.length; i++){
            this.iconPool[i]._visible = false;
            this.iconToBuffMap[i] = null;
        }
        this.activeBuffs = [];
    }

    public function update():Void{
        for(var i=0; i < this.activeBuffs.length; i++){
            var buffInfo = this.activeBuffs[i]
            var buff = buffInfo.buff;
            var iconTimer = buffInfo.icon.buff计时动画;
            // 刷新计时
            var timer = buff.getPrimaryTimer();
            if(timer != null){
                var total = timer.getTotal();
                var remain = timer.getRemaining();
                // 计算计时动画停留的帧（第26帧=白/满，第1帧=黑/空）
                var targetFrame = ((25 * remain / total) | 0) + 1;
                iconTimer._visible = true;
                iconTimer.gotoAndStop(targetFrame);
            }else{
                iconTimer._visible = false;
            }
        }
    }

    public function addIcon(id:String, _buff):Void{
        // 先检查对应buff是否已经存在
        for(var i=0; i<this.activeBuffs.length; i++){
            if(this.activeBuffs[i].id === id){
                return;
            }
        }
        var index;
        var icon;
        for(index=0; index<this.iconToBuffMap.length; index++){
            if(this.iconToBuffMap[index] === null){
                break;
            }
        }

        if(index < this.iconToBuffMap.length){
            //
            icon = this.iconPool[index];
        }else{
            //
            icon = iconProto.duplicateMovieClip("icon" + index, index, null);
            this.iconPool[index] = icon;
        }
        this.activeBuffs.push(
            {id:id, buff:_buff, icon:icon, iconIndex:index}
        );
        
        this.iconToBuffMap[index] = _buff;
        arrangeIcons();
    }

    public function removeIcon(id:String):Void{
        for(var i=0; i<this.activeBuffs.length; i++){
            if(this.activeBuffs[i].id === id){
                var iconIndex = this.activeBuffs[i].iconIndex;
                this.iconToBuffMap[iconIndex] = null;
                this.activeBuffs.splice(i,1);
                break;
            }
        }
        arrangeIcons();
    }

    private function arrangeIcons():Void{
        for(var i = 0; i < this.activeBuffs.length; i++){
            var icon = this.activeBuffs[i].icon;
            icon._x = this.startX + i * this.padding;
        }
        
        for(var i = 0; i < this.iconPool.length; i++){
            var icon = this.iconPool[i];
            icon._visible = this.iconToBuffMap[i] != null;
        }
    }

}