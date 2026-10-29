import org.flashNight.arki.scene.*;

/** One map-asset transform; actors, physics coordinates and camera remain independent. */
class org.flashNight.arki.scene.Cf6MapPresentation {
    private static var loadingCover:Object;
    /** 在标准加载幕下先覆盖新世界；只承接CF6随后异步图层装配的视觉空档。 */
    public static function beginLoadingCover(world:MovieClip, owner:Object):Boolean {
        var run:Object=_root._saveExt.bookRun;
        if(world!==_root.gameworld || owner==null || owner!==world.__stageReturnWorldIdentity
                || _root.淡出动画.__returnFadeActive!==true || run.bookId!=="cf6-sting"
                || !BookDefinition.isCf6Route(run.routeId) || run.outcome!=="active" || run.slot!==String(_root.savePath)) return false;
        if(loadingCover!=null && loadingCover.world===world && loadingCover.owner===owner) return true;
        if(loadingCover!=null) clearLoadingCover(loadingCover.world,loadingCover.owner);
        var clip:MovieClip=_root.createEmptyMovieClip("__cf6LoadingCover",_root.getNextHighestDepth());
        var token:Object={};clip.__cf6LoadingCoverOwner=token;
        loadingCover={world:world,owner:owner,clip:clip,token:token,readyFrames:0,width:0,height:0};
        drawLoadingCover(loadingCover);
        return true;
    }
    private static function drawLoadingCover(value:Object):Void {
        var clip:MovieClip=value.clip,w:Number=Stage.width,h:Number=Stage.height;
        if(clip.getDepth()<_root.getNextHighestDepth()-1) clip.swapDepths(_root.getNextHighestDepth());
        if(value.width===w && value.height===h) return;
        value.width=w;value.height=h;
        clip.clear();clip.beginFill(0x081018,100);clip.moveTo(0,0);clip.lineTo(w,0);clip.lineTo(w,h);clip.lineTo(0,h);clip.lineTo(0,0);clip.endFill();
        if(clip.caption==undefined) clip.createTextField("caption",1,0,0,1,1);
        clip.caption._x=w*0.1;clip.caption._y=h*0.72;clip.caption._width=w*0.8;clip.caption._height=42;
        clip.caption.selectable=false;
        var format:TextFormat=new TextFormat();format.font="Microsoft YaHei";format.size=22;format.color=0xDDEFFF;format.align="center";
        clip.caption.setNewTextFormat(format);clip.caption.text="正在加载地图…";
    }
    public static function hasLoadingCover(world:MovieClip,owner:Object):Boolean {
        return loadingCover!=null && loadingCover.world===world && loadingCover.owner===owner;
    }
    public static function refreshLoadingCover(world:MovieClip,owner:Object):Void {
        if(hasLoadingCover(world,owner)) drawLoadingCover(loadingCover);
    }
    /** 调用方已核对背景、动态层与摆件；两次实际watch tick让显示树稳定后再露出。 */
    public static function loadingCoverReady(world:MovieClip,owner:Object):Boolean {
        if(!hasLoadingCover(world,owner)) return true;
        var value:Object=loadingCover;
        if(world!==_root.gameworld || owner!==world.__stageReturnWorldIdentity) {clearLoadingCover(world,owner);return false;}
        drawLoadingCover(value);
        if(++value.readyFrames<2) return false;
        clearLoadingCover(world,owner);return true;
    }
    public static function clearLoadingCover(world:MovieClip,owner:Object):Void {
        if(!hasLoadingCover(world,owner)) return;
        var value:Object=loadingCover;loadingCover=null;
        if(value.clip.__cf6LoadingCoverOwner===value.token) value.clip.removeMovieClip();
    }

    public static function valid(value:Object):Boolean {
        if (typeof value.scale != "number" || !(value.scale > 0) || !(value.scale < 4)
                || typeof value.backgroundX != "number" || typeof value.backgroundY != "number") return false;
        return (value.scale-value.scale) == 0
            && (value.backgroundX-value.backgroundX) == 0 && (value.backgroundY-value.backgroundY) == 0
            && Math.abs(value.backgroundX) < 4000 && Math.abs(value.backgroundY) < 4000;
    }

    private static function valueFor(world:MovieClip, owner:Object, background:MovieClip):Object {
        var run:Object = _root._saveExt.bookRun;
        var manager:Object = StageManager.instance;
        var index = manager.currentStage;
        if (owner == undefined || world !== _root.gameworld || world._parent == undefined
                || owner !== StageReturnFlow.worldIdentity(world) || background !== world.背景
                || background._parent !== world || manager.gameworld !== world
                || typeof index != "number" || (index-index) != 0 || index < 0 || Math.floor(index) != index
                || _root.当前关卡名 !== "书中历险-毒刺行动" || run.slot !== String(_root.savePath)
                || !BookRunRules.sameCf6Run(run, run)) return null;
        var map:Object = BookDefinition.get("cf6-sting").maps[index];
        var value:Object = map.presentation;
        if (!valid(value) || !Cf6MapMechanism.knownMap(map.id)
                || map.background !== (map.id === "TUTORIAL" ? "cf6/CF6_Tutorial_BG.swf" : "cf6/CF6_"+map.id+"_BG.swf")
                || world.场景背景url !== "flashswf/backgrounds/"+map.background) return null;
        return value;
    }

    public static function applyBackground(world:MovieClip, owner:Object, background:MovieClip):Boolean {
        var value:Object = valueFor(world, owner, background);
        if (value == null) return false;
        // Absolute assignment is idempotent, including a second bake request in the same room.
        background._x = value.backgroundX; background._y = value.backgroundY;
        background._xscale = background._yscale = value.scale * 100;
        return true;
    }

    public static function matchesBake(world:MovieClip, owner:Object, background:MovieClip, receipt:Object):Boolean {
        var value:Object = valueFor(world, owner, background);
        var matrix:Object = receipt.assetMatrix;
        if (value == null || matrix == null) return false;
        // Display coordinates are quantized to twips; compare the actual committed matrix.
        return Math.abs(matrix.x-value.backgroundX) < 0.06 && Math.abs(matrix.y-value.backgroundY) < 0.06
            && Math.abs(matrix.scaleX-value.scale*100) < 0.001
            && Math.abs(matrix.scaleY-value.scale*100) < 0.001;
    }
}
