import flash.display.BitmapData;
import flash.geom.Matrix;
import org.flashNight.arki.scene.*;
import org.flashNight.gesh.depth.DepthManager;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.arki.unit.UnitComponent.Dressup.DressupReferenceManager;
import org.flashNight.neur.Event.EventDispatcher;

/** Published hero + XML equipment + original authored mask; isolated presentation, no player save. */
class org.flashNight.arki.scene.Cf6ActorAppearanceTest {
    private static var saved:Object,room:Object,session:Object,hero:MovieClip,fixture:MovieClip,world:MovieClip,driver:MovieClip;
    private static var clothing:Object,gun:Object,layers:Array,cases:Array,t:Object,p:Object;
    private static var stage:String,index:Number,age:Number,passed:Number,failed:Number,pending:Number;
    private static var frontPixels:Number,backPixels:Number,done:Boolean;
    private static function check(ok:Boolean,label:String):Void {
        if(ok) passed++;else {failed++;trace("[FAIL] Cf6ActorAppearance: "+label);}
    }
    public static function initActor(u:MovieClip):Void {
        u.stop();u.hp=100;u.hp满血值=100;u.身高=175;u.性别="男";u.操控编号=-1;u.是否为敌人=false;
        u.hasDressup=true;u.syncRefs={};u.dispatcher=new EventDispatcher();u.被动技能={};u.version=index+1;
        u.攻击模式="长枪";u.状态="长枪站立";u.方向="右";u.myxscale=100;
        u.动作A=u.动作B=u.动作C=false;u.行走=function():Void {};u.行走冷却帧=0;
        u.身体="男"+clothing.data.dressup+"身体";u.上臂="男"+clothing.data.dressup+"上臂";
        u.左下臂="男"+clothing.data.dressup+"左下臂";u.右下臂="男"+clothing.data.dressup+"右下臂";
        u.长枪_装扮=gun.data.dressup;u.长枪属性=gun.data;u.长枪弹匣容量=gun.data.capacity;
        u.长枪={name:gun.name,value:{level:1,shot:0}};u.上装装备={name:clothing.name,value:{level:1}};
        u.头部装备数据={};u.生命周期函数列表=[];
    }
    public static function runAllTests():Void {
        passed=failed=frontPixels=backPixels=0;index=-1;done=false;stage="xml";age=0;pending=2;
        saved={world:_root.gameworld,depth:DepthManager.instance,control:_root.控制目标,
            skin:_root.装备引用配置,functions:_root.主角函数,initPlayer:_root.初始化玩家模板,
            initHero:_root.初始化主角模板,shadow:_root.是否阴影,pause:_root.暂停,sound:_root.播放音效};
        _root.装备引用配置={配置装扮:DressupReferenceManager.attach,刷新所有装扮:DressupReferenceManager.refreshAll};
        _root.主角函数={};_root.是否阴影=false;_root.暂停=false;
        _root.播放音效=function():Void {};
        _root.初始化玩家模板=function():Void {org.flashNight.arki.scene.Cf6ActorAppearanceTest.initActor(this);};
        _root.初始化主角模板=_root.初始化玩家模板;
        fixture=_root.createEmptyMovieClip("__cf6NativeAppearance",30050);fixture._visible=false;
        world=fixture.createEmptyMovieClip("world",0);world._x=37;world._y=23;
        world.__stageReturnWorldIdentity={};world.getNextHighestDepth=function():Number {
            return 900000+(this.__next=this.__next==undefined ? 1 : this.__next+1);
        };
        _root.gameworld=world;DepthManager.instance=new DepthManager(world,0,870655,32);DepthManager.instance.calibrate(0,600);
        room={world:world,owner:world.__stageReturnWorldIdentity};world.__cf6Mechanism=room;
        session=Cf6PropDepthService.begin(world,room.owner,room);
        driver=_root.createEmptyMovieClip("__cf6NativeAppearanceWatch",30051);
        driver.onEnterFrame=function():Void {org.flashNight.arki.scene.Cf6ActorAppearanceTest.tick();};
        cases=[{pose:"长枪站立",side:1,z:210},{pose:"长枪站立",side:-1,z:320},
            {pose:"长枪行走",side:1,z:320},{pose:"长枪行走",side:-1,z:210}];
        check(_root.__cadenceRsl!=undefined && _root.__appearanceEquipmentRsl!=undefined,"published things0/things RSL anchors instantiated");
        loadXml("data/items/防具_0-19级.xml","clothing");loadXml("data/items/武器_长枪_突击步枪.xml","gun");
    }
    private static function xmlCallback(key:String):Function {
        return function(ok:Boolean):Void {org.flashNight.arki.scene.Cf6ActorAppearanceTest.xmlReady(key,ok,this);};
    }
    private static function loadXml(url:String,key:String):Void {
        var doc:XML=new XML();doc.ignoreWhite=true;doc.onLoad=xmlCallback(key);doc.load(url);
    }
    public static function xmlReady(key:String,ok:Boolean,doc:XML):Void {
        if(done) return;check(ok,"actual equipment XML "+key);
        if(!ok) {finish();return;}
        var rows:Array=XMLParser.configureDataAsArray(XMLParser.parseXMLNode(doc.firstChild).item);
        var wanted:String=key=="gun" ? "M4A1" : "Andy上装-NPC";
        for(var i:Number=0;i<rows.length;i++) if(rows[i].name==wanted) {
            if(key=="gun") gun=rows[i];else clothing=rows[i];
        }
        check(key=="gun" ? gun.data.dressup=="枪-长枪-M4A1" : clothing.data.dressup=="变装-Andy上装","declared production appearance mapping "+wanted);
        if(--pending==0) loadLayers();
    }
    private static function loadLayers():Void {
        stage="assets";age=0;pending=3;layers=[];
        var names:Array=["Back","Front","Mask"];
        for(var i:Number=0;i<3;i++) {
            var ticket:Object=Cf6PropDepthService.create(session,names[i],250,250,i==0?249:i==1?251:250);
            ticket.holder._visible=false;
            var row:Object={ticket:ticket,part:names[i],art:ticket.holder.createEmptyMovieClip("art",0)};
            row.loader=new MovieClipLoader();row.listener={row:row,
                onLoadInit:function(mc:MovieClip):Void {org.flashNight.arki.scene.Cf6ActorAppearanceTest.artReady(this.row,mc);},
                onLoadError:function(mc:MovieClip,error:String):Void {org.flashNight.arki.scene.Cf6ActorAppearanceTest.artError(error);}};
            row.loader.addListener(row.listener);layers.push(row);
            check(row.loader.loadClip("flashswf/backgrounds/cf6/preparation/CF6_Traversal1720_"+names[i]+".swf",row.art),"load actual door "+names[i]);
        }
        var broad:Object=Cf6PropDepthService.create(session,"fullMask",0,0,250);
        var art:MovieClip=broad.holder.createEmptyMovieClip("art",0);
        art.beginFill(0xFFFFFF,100);art.moveTo(0,0);art.lineTo(600,0);art.lineTo(600,600);art.lineTo(0,600);art.endFill();
        broad.holder._visible=false;layers.push({ticket:broad,art:art});
    }
    public static function artReady(row:Object,mc:MovieClip):Void {
        if(done || row.ready || mc!==row.art) return;
        row.ready=true;mc.gotoAndStop(150);
        check(mc._totalframes==174 && mc._width>0 && mc._height>0,"native active door frame "+row.part);
        if(--pending==0) nextCase();
    }
    public static function artError(error:String):Void {check(false,"door load "+error);finish();}
    private static function nextCase():Void {
        Cf6ActorMaskPresentation.release(p);p=null;
        if(hero!=undefined) {DepthManager.instance.removeMovieClip(hero);hero.removeMovieClip();}
        if(++index==cases.length) {
            check(frontPixels>0 && backPixels>20,"actual Front and Back each have non-vacuous native-hero pixel overlap");
            finish();return;
        }
        for(var i:Number=0;i<layers.length;i++) layers[i].ticket.holder._visible=false;
        var row:Object=cases[index],name:String="nativeHero"+index;_root.控制目标=name;
        var init:Object=Cf6ActorMaskState.prepare(world,room.owner,name,{_x:278,_y:row.z,Z轴坐标:row.z,性别:"男"});
        hero=world.attachMovie("主角-男",name,world.getNextHighestDepth(),init);Cf6ActorMaskState.bind(hero,init);
        initActor(hero);hero._x=278;hero._y=hero.Z轴坐标=row.z;hero._xscale=row.side*100;hero._yscale=100;
        hero.方向=row.side==1?"右":"左";hero.状态=row.pose;hero.gotoAndStop(row.pose);
        DepthManager.instance.updateDepth(hero,250);
        var token:Object={};hero.__cf6TraversalOwner=token;
        t={room:room,actor:hero,token:token,closed:false,acquired:true,lastVisible:true};
        stage="pose";age=0;
    }
    public static function tick():Void {
        if(done) return;age++;
        if(stage=="xml" || stage=="assets") {if(age>300) {check(false,"native load timeout "+stage);finish();}return;}
        if(stage=="pose" && age==3) {
            hero.stop();hero.man.gotoAndStop(index<2 ? 1 : 5);
            var mask:MovieClip=hero.attachMovie("Cf6NativeAuthoredMask","nativeMask",10);
            mask._x=-20;mask._y=-90;mask._xscale=mask._yscale=30;mask.nativeShape.gotoAndStop(4);
        }
        if(stage=="pose" && age>5) {exercise();nextCase();}
    }
    private static function capture():BitmapData {
        var result:BitmapData=new BitmapData(600,600,true,0);result.draw(fixture);return result;
    }
    private static function compareInterior(a:BitmapData,b:BitmapData):Object {
        var tested:Number=0,wrong:Number=0;
        for(var y:Number=2;y<598;y+=2) for(var x:Number=2;x<598;x+=2) {
            var color:Number=a.getPixel32(x,y);
            if((color>>>24)!=255 || a.getPixel32(x-1,y)!==color || a.getPixel32(x+1,y)!==color
                || a.getPixel32(x,y-1)!==color || a.getPixel32(x,y+1)!==color) continue;
            tested++;if(b.getPixel32(x,y)!==color) wrong++;
        }
        return {tested:tested,wrong:wrong};
    }
    private static function exercise():Void {
        check(Cf6ActorMaskState.isKnownNone(hero) && hero.man._parent===hero && hero.man._totalframes>1,
            "actual born hero and production pose "+index);
        check(hero.身体_引用._name=="装扮" && hero.身体_引用._width>0
            && hero.长枪_引用._name=="装扮" && hero.长枪_引用._width>0,"real clothing and weapon attachments "+index);
        check(hero.nativeMask.nativeShape._totalframes>3 && hero.nativeMask._width>0,"original script-free authored mask is instantiated "+index);
        var baseline:BitmapData=capture();
        p=Cf6ActorMaskPresentation.create(t,session,layers[3].ticket);
        var rendered:Boolean=p!=null && Cf6ActorMaskPresentation.render(p,250,true);
        check(rendered,"native appearance proxy captures "+index+" reason="+p.failure);
        if(!rendered) {baseline.dispose();return;}
        hero._visible=false;t.lastVisible=false;
        var proxy:BitmapData=capture();var comparison:Object=compareInterior(baseline,proxy);
        check(comparison.tested>50 && comparison.wrong==0,"native clothing/weapon/authored-mask interior pixels retained "+index);
        proxy.dispose();
        layers[0].ticket.holder._visible=true;layers[1].ticket.holder._visible=true;
        check(layers[0].ticket.holder.getDepth()<p.ticket.holder.getDepth()
            && p.ticket.holder.getDepth()<layers[1].ticket.holder.getDepth() && p.ticket.sortY===250
            && hero.Z轴坐标!==250,"fixed actorSortY brackets moving display-Z between real Back and Front "+index);
        var composite:BitmapData=capture();
        layers[0].ticket.holder._visible=false;p.ticket.holder._visible=false;
        var front:BitmapData=capture();layers[1].ticket.holder._visible=false;p.ticket.holder._visible=true;
        proxy=capture();var wrong:Number=0,frontCount:Number=0,backCount:Number=0;
        for(var y:Number=2;y<598;y+=2) for(var x:Number=2;x<598;x+=2) {
            var f:Number=front.getPixel32(x,y),v:Number=proxy.getPixel32(x,y);
            if((f>>>24)==255 && (v>>>24)>0) {frontCount++;if(composite.getPixel32(x,y)!==f) wrong++;}
            else if((f>>>24)==0 && (v>>>24)==255) {backCount++;if(composite.getPixel32(x,y)!==v) wrong++;}
        }
        frontPixels+=frontCount;backPixels+=backCount;
        check(wrong==0 && backCount>20,"actual layer composite respects front occlusion and actor-over-back pixels "+index);
        front.dispose();composite.dispose();proxy.dispose();
        Cf6ActorMaskPresentation.release(p);p=Cf6ActorMaskPresentation.create(t,session,layers[2].ticket);
        rendered=p!=null && Cf6ActorMaskPresentation.render(p,250,false);
        check(rendered,"actual native door Mask clips the native hero proxy "+index);
        if(rendered) {
            proxy=capture();var inside:Number=0,outside:Number=0;
            for(y=2;y<598;y+=2) for(x=2;x<598;x+=2) if((proxy.getPixel32(x,y)>>>24)>0) {
                if(x>242 && x<331 && y>187 && y<358) inside++;
                else if(x<238 || x>336 || y<182 || y>363) outside++;
            }
            check(inside>0 && outside==0,"real 1720 mask keeps pixels within its transformed fixed window "+index);
            proxy.dispose();
        } else check(false,"native mask pixels unavailable "+index);
        Cf6ActorMaskPresentation.release(p);p=null;hero._visible=true;t.lastVisible=true;
        proxy=capture();comparison=compareInterior(baseline,proxy);
        check(comparison.tested>50 && comparison.wrong==0 && Cf6ActorMaskState.isKnownNone(hero),"release preserves original equipped actor "+index);
        trace("Cf6ActorAppearance NativeCase: pose="+cases[index].pose+" side="+cases[index].side+" displayZ="+hero.Z轴坐标
            +" sortY=250 frontPixels="+frontCount+" bodyPixels="+backCount+" compared="+comparison.tested);
        baseline.dispose();proxy.dispose();
    }
    private static function finish():Void {
        if(done) return;done=true;Cf6ActorMaskPresentation.release(p);
        for(var i:Number=0;i<layers.length;i++) if(layers[i].loader!=undefined) layers[i].loader.removeListener(layers[i].listener);
        Cf6PropDepthService.end(session);DepthManager.instance.dispose();fixture.removeMovieClip();
        delete driver.onEnterFrame;driver.removeMovieClip();
        _root.gameworld=saved.world;DepthManager.instance=saved.depth;_root.控制目标=saved.control;
        _root.装备引用配置=saved.skin;_root.主角函数=saved.functions;_root.初始化玩家模板=saved.initPlayer;
        _root.初始化主角模板=saved.initHero;_root.是否阴影=saved.shadow;_root.暂停=saved.pause;_root.播放音效=saved.sound;
        trace("Cf6ActorAppearanceTest Tests Passed: "+passed);trace("Cf6ActorAppearanceTest Tests Failed: "+failed);
        _root.cf6ActorAppearanceComplete();
    }
}
