import flash.display.BitmapData;
import flash.geom.Matrix;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.gesh.depth.DepthManager;
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.arki.unit.UnitComponent.Dressup.DressupReferenceManager;

/** Actual item XML, original CAR RSL, native hero gun rack. No saves or combat. */
class org.flashNight.arki.scene.Cf6ItemVisualTest {
    private static var saved:Object,fixture:MovieClip,world:MovieClip,driver:MovieClip,hero:MovieClip,icon:MovieClip;
    private static var item:Object,cases:Array,index:Number,age:Number,passed:Number,failed:Number;
    private static var stage:String,done:Boolean;
    private static var sampleRegion:Object,baseline:BitmapData,stableDelta:Number,actorDelta:Number,frame:Number;
    private static var legs:Array,samplePhase:String,phaseLimit:Number;
    private static function check(ok:Boolean,label:String):Void {
        if(ok) passed++;else {failed++;trace("[FAIL] Cf6ItemVisual: "+label);}
    }
    public static function initActor(u:MovieClip):Void {
        u.stop();u.hp=u.hp满血值=100;u.身高=175;u.性别="男";u.操控编号=-1;
        u.hasDressup=true;u.syncRefs={};u.dispatcher=new EventDispatcher();u.被动技能={};u.version=index+1;
        u.攻击模式="长枪";u.状态="长枪站立";u.方向="右";u.myxscale=100;
        u.动作A=u.动作B=u.动作C=false;u.行走=function():Void {};u.行走冷却帧=0;
        u.长枪_装扮=item.data.dressup;u.长枪属性=item.data;u.长枪弹匣容量=item.data.capacity;
        u.长枪={name:item.name,value:{level:1,shot:0}};u.头部装备数据={};u.生命周期函数列表=[];
    }
    public static function runAllTests():Void {
        passed=failed=frame=0;index=-1;age=0;done=false;stage="xml";baseline=null;
        saved={gameworld:_root.gameworld,control:_root.控制目标,depth:DepthManager.instance,
            装备引用配置:_root.装备引用配置,主角函数:_root.主角函数,
            初始化玩家模板:_root.初始化玩家模板,初始化主角模板:_root.初始化主角模板,
            是否阴影:_root.是否阴影,暂停:_root.暂停,播放音效:_root.播放音效};
        _root.装备引用配置={配置装扮:DressupReferenceManager.attach,刷新所有装扮:DressupReferenceManager.refreshAll};
        _root.主角函数={};_root.是否阴影=false;_root.暂停=false;_root.播放音效=function():Void {};
        _root.初始化玩家模板=function():Void {org.flashNight.arki.scene.Cf6ItemVisualTest.initActor(this);};
        _root.初始化主角模板=_root.初始化玩家模板;
        fixture=_root.createEmptyMovieClip("__cf6ItemVisualFixture",30060);
        // The unmodified filtered rack must participate in real Stage frames so
        // its cached rendering can commit a child visibility change.
        fixture._visible=true;fixture._x=300;fixture._y=300;
        world=fixture.createEmptyMovieClip("world",0);_root.gameworld=world;
        DepthManager.instance=new DepthManager(world,0,870655,32);DepthManager.instance.calibrate(0,600);
        driver=_root.createEmptyMovieClip("__cf6ItemVisualWatch",30061);
        driver.onEnterFrame=function():Void {org.flashNight.arki.scene.Cf6ItemVisualTest.tick();};
        cases=[{pose:"长枪站立",side:1},{pose:"长枪站立",side:-1},
            {pose:"长枪行走",side:1},{pose:"长枪行走",side:-1}];
        check(_root.__itemHeroRsl!=undefined && _root.__itemBaseRsl!=undefined
            && _root.__itemCarGunRsl!=undefined && _root.__itemCarIconRsl!=undefined,"original hero/base/CAR gun/CAR icon RSL instances");
        var blank:MovieClip=fixture.createEmptyMovieClip("blank",1);
        check(pixels(blank)==0,"pixel counter rejects an actually empty native clip");blank.removeMovieClip();
        var doc:XML=new XML();doc.ignoreWhite=true;
        doc.onLoad=function(ok:Boolean):Void {org.flashNight.arki.scene.Cf6ItemVisualTest.xmlReady(ok,this);};
        doc.load("data/items/武器_长枪_突击步枪.xml");
    }
    public static function xmlReady(ok:Boolean,doc:XML):Void {
        if(done) return;check(ok,"load real production rifle XML");
        if(!ok) {finish();return;}
        var rows:Array=XMLParser.configureDataAsArray(XMLParser.parseXMLNode(doc.firstChild).item);
        for(var i:Number=0;i<rows.length;i++) if(rows[i].name=="SAI GRY 幽灵") item=rows[i];
        check(item!=null && item.name=="SAI GRY 幽灵","actual XMLParser resolves unchanged SAI identity");
        check(item.icon=="CAR" && item.data.dressup=="枪-长枪-CAR","actual XML resolves compatibility appearance");
        if(item==null) {finish();return;}
        icon=fixture.attachMovie("图标-"+item.icon,"itemIcon",2);
        check(icon!=undefined,"attach actual XML icon linkage from original RSL");
        check(icon._totalframes>=2,"actual item icon has UI and ground frames");
        if(icon==undefined) {finish();return;}
        icon.gotoAndStop(1);stage="icon1";age=0;
    }
    public static function tick():Void {
        if(done) return;age++;frame++;
        if(stage=="xml") {if(age>300){check(false,"item XML deadline");finish();}return;}
        if(stage=="icon1" && age>=3) {
            var n:Number=pixels(icon);
            check(icon._currentframe==1,"actual UI icon frame1 selected");check(n>20,"actual UI icon frame1 visible alpha pixels");
            trace("Cf6ItemVisual Icon: frame=1 pixels="+n+" width="+icon._width+" height="+icon._height);
            icon.gotoAndStop(2);stage="icon2";age=0;return;
        }
        if(stage=="icon2" && age>=3) {
            n=pixels(icon);
            check(icon._currentframe==2,"actual ground/drop icon frame2 selected");check(n>20,"actual ground/drop icon frame2 visible alpha pixels");
            trace("Cf6ItemVisual Icon: frame=2 pixels="+n+" width="+icon._width+" height="+icon._height);
            icon.removeMovieClip();nextCase();return;
        }
        if(stage=="pose" && age==3) {hero.stop();hero.man.gotoAndStop(index<2?1:5);}
        if(stage=="pose" && age==4) DressupReferenceManager.refreshAll(hero);
        if(stage=="pose" && age>=6) {beginSample();return;}
        if(stage=="settle" && age>=2) {
            // The two production walking-leg onEnterFrame handlers call play()
            // every frame. Keep them running; inspect the complete native gun rack.
            sampleRegion=hero.man.枪.枪.getBounds(world);
            var skinRegion:Object=hero.长枪_引用.getBounds(world);
            check(sampleRegion.xMin<=skinRegion.xMin && sampleRegion.yMin<=skinRegion.yMin
                && sampleRegion.xMax>=skinRegion.xMax && sampleRegion.yMax>=skinRegion.yMax,
                "native rack region contains the complete CAR skin world bounds "+index);
            trace("Cf6ItemVisual Region: case="+index+" rack="+boundsText(sampleRegion)
                +" skin="+boundsText(skinRegion)+" padding=8 sampling=world");
            baseline=capture(world,sampleRegion);
            samplePhase=phaseKey();tracePhase("baseline");
            stage="stable";age=0;return;
        }
        if((stage=="stable" || stage=="hidden" || stage=="restored") && !sampleReady())return;
        if(stage=="stable" && age>=2) {
            tracePhase("stable");
            var stable:BitmapData=capture(world,sampleRegion);
            stableDelta=difference(baseline,stable);stable.dispose();
            check(stableDelta==0,"same-phase real-frame native rack-region control has zero pixel difference "+index);
            hero.长枪_引用._visible=false;
            trace("Cf6ItemVisual Hide: case="+index+" frame="+frame+" stableDelta="+stableDelta);
            stage="hidden";age=0;return;
        }
        if(stage=="hidden" && age>=2) {
            tracePhase("hidden");
            var hidden:BitmapData=capture(world,sampleRegion);
            actorDelta=difference(baseline,hidden);hidden.dispose();
            check(actorDelta>20,"CAR attachment actually changes visible native actor pixels "+index);
            hero.长枪_引用._visible=true;
            trace("Cf6ItemVisual Restore: case="+index+" frame="+frame+" hiddenWaitFrames="+age+" actorDelta="+actorDelta);
            stage="restored";age=0;return;
        }
        if(stage=="restored" && age>=2) {
            tracePhase("restored");
            var restored:BitmapData=capture(world,sampleRegion);
            var restoreDelta:Number=difference(baseline,restored);restored.dispose();
            check(restoreDelta==0,"restored filtered rack region returns to its exact original pixels "+index);
            trace("Cf6ItemVisual NativeCase: pose="+cases[index].pose+" side="+cases[index].side
                +" frame="+frame+" restoreWaitFrames="+age+" stableDelta="+stableDelta
                +" actorDelta="+actorDelta+" restoreDelta="+restoreDelta+" region="+boundsText(sampleRegion));
            baseline.dispose();baseline=null;nextCase();
        }
    }
    private static function nextCase():Void {
        legs=[];samplePhase=null;phaseLimit=2;
        if(hero!=undefined){DepthManager.instance.removeMovieClip(hero);hero.removeMovieClip();hero=null;}
        if(++index>=cases.length){check(index==4,"all native stance/walk and left/right cases completed");finish();return;}
        var row:Object=cases[index];_root.控制目标="itemHero"+index;
        hero=world.attachMovie("主角-男",_root.控制目标,world.getNextHighestDepth(),{_x:0,_y:0,Z轴坐标:0});
        if(hero==undefined){check(false,"native hero linkage unavailable");finish();return;}
        initActor(hero);hero._x=hero._y=hero.Z轴坐标=0;hero._xscale=row.side*100;hero._yscale=100;
        hero.方向=row.side==1?"右":"左";hero.状态=row.pose;hero.gotoAndStop(row.pose);
        stage="pose";age=0;
    }
    private static function capture(mc:MovieClip,region:Object):BitmapData {
        if(region==null)region=mc.getBounds(mc);
        var width:Number=Math.ceil(region.xMax-region.xMin)+16;
        var height:Number=Math.ceil(region.yMax-region.yMin)+16;
        if(isNaN(width)||isNaN(height)||width<1||height<1||width>2048||height>2048){
            check(false,"finite bounded native capture region");return new BitmapData(1,1,true,0);
        }
        var result:BitmapData=new BitmapData(width,height,true,0);
        var matrix:Matrix=new Matrix();matrix.translate(8-region.xMin,8-region.yMin);
        if(mc!=undefined) result.draw(mc,matrix);
        return result;
    }
    private static function pixels(mc:MovieClip):Number {
        var image:BitmapData=capture(mc),count:Number=0;
        for(var y:Number=0;y<image.height;y++)for(var x:Number=0;x<image.width;x++)if((image.getPixel32(x,y)>>>24)>0)count++;
        image.dispose();return count;
    }
    private static function boundsText(r:Object):String {
        return r.xMin+","+r.yMin+","+r.xMax+","+r.yMax;
    }
    private static function phaseKey():String {
        var m:Matrix=hero.man.transform.matrix;
        var result:String=m.a+","+m.b+","+m.c+","+m.d+","+m.tx+","+m.ty;
        for(var i:Number=0;i<legs.length;i++)result+="|"+legs[i]._name+":"+legs[i]._currentframe+"/"+legs[i]._totalframes;
        return result;
    }
    private static function tracePhase(label:String):Void {
        trace("Cf6ItemVisual Phase: case="+index+" sample="+label+" frame="+frame+" wait="+age
            +" manMatrixAndLegFrames="+phaseKey()+" baseline="+samplePhase);
    }
    private static function sampleReady():Boolean {
        if(age<2)return false;
        if(index<2 || phaseKey()==samplePhase)return true;
        if(age>phaseLimit){
            tracePhase("phase-timeout");check(false,"walking sample returns to both native leg frames and exact man matrix "+index);
            finish();
        }
        return false;
    }
    private static function describeChain(skin:MovieClip):Void {
        var mc:MovieClip=skin;
        for(var i:Number=0;i<6 && mc!=undefined;i++){
            var m:Matrix=mc.transform.matrix;
            trace("Cf6ItemVisual Transform: case="+index+" name="+mc._name+" visible="+mc._visible
                +" alpha="+mc._alpha+" matrix="+m.a+","+m.b+","+m.c+","+m.d+","+m.tx+","+m.ty
                +" boundsWorld="+boundsText(mc.getBounds(world))+" cached="+mc.cacheAsBitmap
                +" filters="+mc.filters.length+" scrollRect="+mc.scrollRect);
            if(mc===world)break;
            mc=mc._parent;
        }
    }
    private static function freezeTree(mc:MovieClip,depth:Number):Void {
        mc.stop();
        if(depth>=16){check(false,"native pose hierarchy exceeds fixture freeze bound");return;}
        for(var key:String in mc){
            var child:MovieClip=mc[key];
            if(typeof child=="movieclip" && child._parent===mc)freezeTree(child,depth+1);
        }
    }
    private static function difference(a:BitmapData,b:BitmapData):Number {
        if(a.width!=b.width || a.height!=b.height)return Number.POSITIVE_INFINITY;
        var count:Number=0;
        for(var y:Number=0;y<a.height;y++)for(var x:Number=0;x<a.width;x++)if(a.getPixel32(x,y)!==b.getPixel32(x,y))count++;
        return count;
    }
    private static function beginSample():Void {
        // Freeze only the upper-body timeline. Authored legs keep playing and
        // moving man; compare complete cycles at the exact same native phase.
        freezeTree(hero.man,0);
        if(index>=2){
            // These two unnamed direct instances have 22 authored frames, bound
            // by prepare.py to the original XFL. Read actual runtime periods;
            // never write a leg frame, matrix, filter or cache setting.
            for(var key:String in hero){
                var child:MovieClip=hero[key];
                if(typeof child=="movieclip" && child._parent===hero && child!==hero.man && child._totalframes==22)legs.push(child);
            }
            check(legs.length==2,"both authored native walking-leg clips resolved with actual frame periods "+index);
            if(legs.length!=2){finish();return;}
            phaseLimit=4*Math.max(legs[0]._totalframes,legs[1]._totalframes);
        }
        var rack:MovieClip=hero.man.枪.枪,skin:MovieClip=hero.长枪_引用;
        check(hero.man!=undefined && hero.man._parent===hero && hero.man._totalframes>1,"native hero active production pose "+index);
        check(rack!=undefined && rack._parent._parent===hero.man,"actual nested long-gun rack "+index);
        check(skin!=undefined && skin._name=="装扮" && rack.装扮===skin,"actual DressupReferenceManager live rack attachment "+index);
        var visiblePixels:Number=pixels(skin);
        check(visiblePixels>20,"actual attached CAR gun alpha pixels "+index);
        check(skin._visible!==false && skin._width>0 && skin._height>0,"attached CAR gun not empty or hidden "+index);
        describeChain(skin);
        check(hero.dressupRegistry!=undefined && skin._parent._parent._parent._parent===hero,"real dressup registration and actor ownership "+index);
        trace("Cf6ItemVisual Settling: case="+index+" frame="+frame+" weaponPixels="+visiblePixels);
        stage="settle";age=0;
    }
    private static function finish():Void {
        if(done)return;done=true;
        if(baseline!=null){baseline.dispose();baseline=null;}
        delete driver.onEnterFrame;driver.removeMovieClip();
        if(hero!=undefined)DepthManager.instance.removeMovieClip(hero);
        fixture.removeMovieClip();DepthManager.instance.dispose();DepthManager.instance=saved.depth;
        _root.gameworld=saved.gameworld;_root.控制目标=saved.control;
        for(var key:String in saved)if(key!="gameworld" && key!="control" && key!="depth")_root[key]=saved[key];
        trace("Cf6ItemVisualTest Tests Passed: "+passed);trace("Cf6ItemVisualTest Tests Failed: "+failed);
        _root.cf6ItemVisualComplete();
    }
}
