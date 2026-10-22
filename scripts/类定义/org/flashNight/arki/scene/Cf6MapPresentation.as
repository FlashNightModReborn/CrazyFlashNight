import org.flashNight.arki.scene.*;

/** One map-asset transform; actors, physics coordinates and camera remain independent. */
class org.flashNight.arki.scene.Cf6MapPresentation {
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
