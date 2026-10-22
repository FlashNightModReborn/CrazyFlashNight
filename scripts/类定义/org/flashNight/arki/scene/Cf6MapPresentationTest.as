import org.flashNight.arki.scene.*;
import flash.display.BitmapData;

class org.flashNight.arki.scene.Cf6MapPresentationTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(value:Boolean, message:String):Void {
        if (value) passed++; else {failed++;trace("[FAIL] Cf6MapPresentation: "+message);}
    }
    public static function runAllTests():Void {
        passed=failed=0;
        var saved:Object={world:_root.gameworld,ext:_root._saveExt,slot:_root.savePath,stage:_root.当前关卡名,
            zoom:_root.basicZoomScale,toggle:_root.cameraZoomToggle};
        var definition:Object=org.flashNight.arki.scene.BookDefinition;
        var stageApi:Object=org.flashNight.arki.scene.StageManager;
        var oldDefinition:Object=definition._cf6,oldManager:Object=stageApi.instance;
        var world:MovieClip,background:MovieClip,owner:Object;
        try {
            check(Cf6MapPresentation.valid({scale:1,backgroundX:0,backgroundY:0}),"unit transform is valid");
            check(!Cf6MapPresentation.valid({scale:0,backgroundX:0,backgroundY:0}),"zero scale rejected");
            check(!Cf6MapPresentation.valid({scale:Number.NaN,backgroundX:0,backgroundY:0}),"AVM1 NaN scale rejected");
            check(!Cf6MapPresentation.valid({scale:Number.POSITIVE_INFINITY,backgroundX:0,backgroundY:0}),"infinite scale rejected");
            check(!Cf6MapPresentation.valid({scale:"2",backgroundX:0,backgroundY:0}),"coerced string scale rejected");
            check(!Cf6MapPresentation.valid({scale:2,backgroundX:Number.NaN,backgroundY:0}),"NaN translation rejected");
            check(!Cf6MapPresentation.valid({scale:2,backgroundX:0,backgroundY:4000}),"out of range translation rejected");
            world=_root.createEmptyMovieClip("__cf6PresentationFixture",_root.getNextHighestDepth());
            _root.gameworld=world;owner=StageReturnFlow.worldIdentity(world);
            background=world.createEmptyMovieClip("背景",0);
            background.beginFill(0x44AA77);background.moveTo(0,0);background.lineTo(20,0);
            background.lineTo(20,10);background.lineTo(0,10);background.endFill();
            var hero:MovieClip=world.createEmptyMovieClip("hero",1);
            hero.beginFill(0xFFAA00);hero.moveTo(0,0);hero.lineTo(10,0);hero.lineTo(10,30);hero.lineTo(0,30);hero.endFill();
            hero._x=80;hero._y=70;
            _root.savePath="cf6.presentation.fixture";_root.当前关卡名="书中历险-毒刺行动";
            _root._saveExt={bookRun:{bookId:"cf6-sting",routeId:"historical",outcome:"active",
                slot:String(_root.savePath),seed:123,startedAt:1792550000000}};
            _root.basicZoomScale=1;_root.cameraZoomToggle=false;
            world.场景背景url="flashswf/backgrounds/cf6/CF6_A01_BG.swf";
            var map:Object={id:"A01",background:"cf6/CF6_A01_BG.swf",presentation:{scale:2,backgroundX:12,backgroundY:18}};
            definition._cf6={maps:[map]};stageApi.instance={currentStage:0,gameworld:world};
            check(Cf6MapPresentation.applyBackground(world,owner,background),"exact live room accepts asset transform");
            check(background._x==12 && background._y==18,"absolute asset origin is applied");
            check(background._width==40 && background._height==20,"native MovieClip dimensions scale uniformly");
            check(hero._width==10 && hero._height==30 && hero._x==80 && hero._y==70,"actor body and position are untouched by asset transform");
            check(world._xscale==100 && world._yscale==100 && _root.basicZoomScale===1,"camera and world root remain at unit scale");
            check(Cf6MapPresentation.applyBackground(world,owner,background) && background._width==40,"repeated preparation cannot multiply scale again");
            var pixels:BitmapData=new BitmapData(80,60,true,0);
            pixels.draw(background,background.transform.matrix);
            trace("Cf6MapPresentation DrawPixel raw="+pixels.getPixel32(13,19)+" rgb="+pixels.getPixel(13,19)+" alpha="+(pixels.getPixel32(13,19)>>>24));
            check(pixels.getPixel(13,19)===0x44AA77 && (pixels.getPixel32(13,19)>>>24)===255,"actual bitmap draw uses the transformed origin");
            check(pixels.getPixel(50,36)===0x44AA77 && (pixels.getPixel32(50,36)>>>24)===255,"actual bitmap draw fills the scaled far corner");
            check(pixels.getPixel32(52,38)==0 && pixels.getPixel32(11,17)==0,"draw remains inside transformed footprint");
            pixels.dispose();
            var receipt:Object={assetMatrix:{x:background._x,y:background._y,scaleX:background._xscale,scaleY:background._yscale}};
            check(Cf6MapPresentation.matchesBake(world,owner,background,receipt),"actual committed matrix matches current presentation");
            map.presentation.scale=1.5;
            check(!Cf6MapPresentation.matchesBake(world,owner,background,receipt),"old bake cannot claim a different map scale");
            map.presentation.scale=2;map.presentation.backgroundX=20;
            check(!Cf6MapPresentation.matchesBake(world,owner,background,receipt),"old bake cannot claim a different asset origin");
            map.presentation.backgroundX=12;
            check(!Cf6MapPresentation.matchesBake(world,owner,background,{}),"legacy receipt without actual matrix is insufficient");
            map.presentation.scale=Number.NaN;
            check(!Cf6MapPresentation.applyBackground(world,owner,background) && background._width==40,"invalid policy leaves current visual untouched");
            map.presentation.scale=2;world.场景背景url="flashswf/backgrounds/cf6/CF6_A02_BG.swf";
            check(!Cf6MapPresentation.applyBackground(world,owner,background),"different resource cannot borrow current map transform");
            world.场景背景url="flashswf/backgrounds/cf6/CF6_A01_BG.swf";
            check(!Cf6MapPresentation.applyBackground(world,{},background),"foreign world identity rejected");
            _root.savePath="another.slot";
            check(!Cf6MapPresentation.applyBackground(world,owner,background),"foreign active slot rejected");
            _root.savePath="cf6.presentation.fixture";_root._saveExt.bookRun.bookId="repair-campus";
            check(!Cf6MapPresentation.applyBackground(world,owner,background),"other books keep their original asset behavior");
            _root._saveExt.bookRun.bookId="cf6-sting";stageApi.instance.currentStage=0.5;
            check(!Cf6MapPresentation.applyBackground(world,owner,background),"noninteger map index rejected");
            stageApi.instance.currentStage=1;
            check(!Cf6MapPresentation.applyBackground(world,owner,background),"missing map rejected");
            stageApi.instance.currentStage=0;
            var detached:MovieClip=world.createEmptyMovieClip("other",3);
            check(!Cf6MapPresentation.applyBackground(world,owner,detached),"nonbackground child cannot receive transform");
            var oldWorld:MovieClip=world;world.removeMovieClip();
            world=_root.createEmptyMovieClip("__cf6PresentationFixture",_root.getNextHighestDepth());
            _root.gameworld=world;StageReturnFlow.worldIdentity(world);
            background=world.createEmptyMovieClip("背景",0);stageApi.instance.gameworld=world;
            world.场景背景url="flashswf/backgrounds/cf6/CF6_A01_BG.swf";
            check(oldWorld===world,"real AVM1 replacement reuses the old MovieClip reference path");
            check(!Cf6MapPresentation.applyBackground(oldWorld,owner,background) && background._xscale==100,"captured old identity cannot resize same-path replacement");
        } catch(error) {check(false,"unexpected exception "+error);}
        definition._cf6=oldDefinition;stageApi.instance=oldManager;
        if(world._parent!=undefined) world.removeMovieClip();
        _root.gameworld=saved.world;_root._saveExt=saved.ext;_root.savePath=saved.slot;_root.当前关卡名=saved.stage;
        _root.basicZoomScale=saved.zoom;_root.cameraZoomToggle=saved.toggle;
        trace("Cf6MapPresentationTest Tests Passed: "+passed);
        trace("Cf6MapPresentationTest Tests Failed: "+failed);
    }
}
