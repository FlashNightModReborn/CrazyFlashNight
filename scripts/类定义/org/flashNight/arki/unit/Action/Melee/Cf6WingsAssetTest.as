import flash.display.BitmapData;
import flash.geom.Matrix;
import flash.geom.Rectangle;

/** Published Wings vectors, actual timelines and unit-private control; no real saves. */
class org.flashNight.arki.unit.Action.Melee.Cf6WingsAssetTest {
    private static var library:MovieClip, driver:MovieClip;
    private static var loader:MovieClipLoader, listener:Object;
    private static var passed:Number, failed:Number, ticks:Number;
    private static var ready:Boolean, finished:Boolean;
    private static var cases:Array, probes:Array, images:Object, shadows:Array;
    private static var link:String = "敌人-CF6Wings";

    private static function check(ok:Boolean, label:String):Void {
        if(ok)passed++;else {failed++;trace("[TEST_FAIL] Cf6WingsAssetTest: "+label);}
    }
    private static function record():Object {
        return {melee:0,shots:0,done:0,deathChecks:0,moves:0,physics:0,removed:false,
            contract:true,positions:[],side:0,move:"none",bodySeen:false,shadowSamples:0,shadowOK:true};
    }
    public static function runAllTests():Void {
        passed=failed=ticks=0;ready=finished=false;cases=[];probes=[];images={};shadows=[];
        library=_root.createEmptyMovieClip("__wingsLibrary",_root.getNextHighestDepth());
        driver=_root.createEmptyMovieClip("__wingsDriver",_root.getNextHighestDepth());
        library._visible=false;
        _root.gameworld=library;_root.暂停=false;_root.控制目标="__no_player";_root.控制目标全自动=false;
        _root.是否阴影=true;
        _root.播放音效=function():Void {};
        _root.发布消息=function():Void {};
        _root.效果=function():Void {};
        _root.add2map=function():Void {};
        _root.add2map2=function():Void {};
        _root.初始化思考标签=function(mc:MovieClip):Void {mc._name="思考标签";mc.stop();mc._visible=false;};
        _root.敌人二级函数={攻击时移动:function():Void {},Z轴追踪移动:function():Void {}};
        _root.子弹属性初始化=function(marker:MovieClip,kind:String,owner:MovieClip):Object {
            var point:Object={x:0,y:0};marker.localToGlobal(point);_root.gameworld.globalToLocal(point);
            return {子弹种类:kind,发射者:owner._name,shootX:kind=="穿刺子弹"?100000:point.x,shootY:kind=="穿刺子弹"?100000:point.y,shootZ:owner.Z轴坐标};
        };
        _root.子弹区域shoot传递=function(bullet:Object):Void {Cf6WingsAssetTest.capture(bullet);};
        _root.初始化敌人模板=function():Void {
            if(this.fixtureRecord==undefined)this.fixtureRecord=Cf6WingsAssetTest.record();
            this.hp=this.hp满血值=1000;this.空手攻击力=100;this.等级=30;
            this.状态="空手站立";this.攻击模式="空手";this.方向="右";this.攻击目标="无";
            this.Z轴坐标=this._y=200;this._x=200;this.myxscale=100;
            this.是否为敌人=true;this.倒地=this.浮空=this.硬直中=this.刚体=false;
            this.unitAI={data:{xrange:150,zrange:10,xdistance:50}};
            this.swapDepths=function():Void {};
            this.行走=function():Void {};
            this.移动=function(direction:String,speed:Number):Void {this.fixtureRecord.moves++;};
            this.方向改变=function(direction:String):Void {this.方向=direction;this._xscale=direction=="左"?-100:100;};
            this.状态改变=function(state:String):Void {if(this.状态==state)return;this.状态=state;this.gotoAndStop(state);};
            this.动画完毕=function():Void {
                this.fixtureRecord.done++;this.倒地=this.浮空=false;this.攻击目标="无";
                this.状态改变(this.hp>0?"空手站立":"血腥死");
            };
            this.死亡检测=function():Void {
                this.fixtureRecord.deathChecks++;
                if(this.hp<=0){this.fixtureRecord.removed=true;this.removeMovieClip();}
            };
            this.击飞浮空=function():Void {this.fixtureRecord.physics++;this.浮空=true;};
            this.击飞倒地=function():Void {this.fixtureRecord.physics++;this.倒地=true;this._y=this.Z轴坐标;};
            this.stop();
        };
        listener={onLoadInit:function(mc:MovieClip):Void {Cf6WingsAssetTest.loaded(mc);},
            onLoadError:function(mc:MovieClip,error:String):Void {Cf6WingsAssetTest.check(false,"load "+error);Cf6WingsAssetTest.finish();}};
        loader=new MovieClipLoader();loader.addListener(listener);
        check(loader.loadClip("../flashswf/arts/new/CodexWings素材.swf",library),"load published SWF");
        driver.onEnterFrame=function():Void {Cf6WingsAssetTest.tick();};
    }
    private static function loaded(mc:MovieClip):Void {
        mc.stop();
        var states:Array=["空手站立","空手行走","空手跑","躲闪","被投"];
        for(var s:Number=0;s<states.length;s++) {
            var rec:Object=record();
            var probe:MovieClip=library.attachMovie(link,"wingsProbe"+s,library.getNextHighestDepth(),
                {fixtureRecord:rec,_arenaCalibrationUnit:s!=4,WingsAI模式:s==4?"baseline":"enhanced"});
            check(probe!=null,"attach "+states[s]);
            probes.push({actor:probe,state:states[s],record:rec});
        }
        var moves:Array=["combo","shoot","slash","flip","flipSlash","flipShoot","hit0","hit1",
            "down","knockdown","death0","death1","death2","interrupt","dead","interruptFlip"];
        for(var side:Number=0;side<2;side++)for(var m:Number=0;m<moves.length;m++) {
            var r:Object=record();r.move=moves[m];r.side=side;
            var actor:MovieClip=library.attachMovie(link,"wingsCase"+cases.length,library.getNextHighestDepth(),
                {fixtureRecord:r,_arenaCalibrationUnit:true});
            check(actor!=null,"attach "+moves[m]+" side "+side);
            cases.push({actor:actor,move:moves[m],side:side,record:r});
        }
        var shadowStates:Array=["空手站立","空手行走","空手跑","空手跳","近战","空手攻击","拾取","躲闪","被击","击倒","倒地","被投","血腥死","消失"];
        for(var face:Number=0;face<2;face++)for(var st:Number=0;st<shadowStates.length;st++) {
            var shadowActor:MovieClip=library.attachMovie(link,"wingsShadowProbe"+shadows.length,library.getNextHighestDepth(),{fixtureRecord:record()});
            shadows.push({actor:shadowActor,state:shadowStates[st],face:face});
        }
        ready=true;ticks=0;
    }
    private static function target(name:String,dx:Number):MovieClip {
        var t:MovieClip=library.createEmptyMovieClip(name,library.getNextHighestDepth());
        t.hp=1000;t._x=200+dx;t._y=t.Z轴坐标=200;
        var area:MovieClip=t.createEmptyMovieClip("area",1);
        area.beginFill(0);area.moveTo(-15,-120);area.lineTo(15,-120);area.lineTo(15,0);area.lineTo(-15,0);area.endFill();
        return t;
    }
    private static function capture(b:Object):Void {
        var actor:MovieClip=library[b.发射者];var rec:Object=actor.fixtureRecord;
        if(rec==undefined)return;
        var ranged:Boolean=b.子弹种类=="穿刺子弹";
        if(ranged)rec.shots++;else rec.melee++;
        rec.contract=rec.contract && b.子弹威力==100 && b.Z轴攻击范围==30 && b.shootZ==200
            && !isNaN(b.shootX) && !isNaN(b.shootY)
            && (ranged ? Math.abs(b.shootX-actor._x)<250 && Math.abs(b.shootY-actor._y)<250 && b.子弹速度==25 && b.击倒率==10 && b.区域定位area==undefined
                : b.子弹种类=="近战子弹" && b.子弹速度==0 && b.击倒率==2 && b.不硬直===true && b.区域定位area!=null);
        rec.positions.push({x:b.shootX-actor._x,y:b.shootY-actor._y,kind:b.子弹种类});
        if(rec.side==0 && rec.move=="shoot" && rec.shots==1)render(actor,"shoot");
        if(rec.side==0 && rec.move=="combo" && rec.melee==1)render(actor,"combo");
        if(rec.side==0 && rec.move=="flip" && rec.shots==3)render(actor,"flip");
    }
    private static function hex(value:Number):String {
        var digits:String="0123456789abcdef",text:String="";
        for(var shift:Number=28;shift>=0;shift-=4)text+=digits.charAt((value>>>shift)&15);
        return text;
    }
    private static function render(actor:MovieClip,key:String):Void {
        if(images[key])return;images[key]=true;
        var b:Object=actor.man.getBounds(actor.man);
        check(b.xMax>b.xMin && b.yMax>b.yMin,"native bounds "+key);
        var bd:BitmapData=new BitmapData(640,400,true,0);
        var matrix:Matrix=actor.man.transform.matrix;matrix.scale(2,2);matrix.translate(320,365);
        bd.draw(actor.man,matrix);emitImage(bd,key);
    }
    private static function emitImage(bd:BitmapData,key:String):Void {
        var width:Number=bd.width,height:Number=bd.height,visible:Number=0;
        for(var y:Number=0;y<height;y+=3)for(var x:Number=0;x<width;x+=3)if((bd.getPixel32(x,y)>>>24)>128)visible++;
        check(visible>200,"native pixels "+key+" "+visible);
        if(_root.wingsCapture===true || (_root.wingsShadowCapture===true && key.indexOf("shadow-")==0)) {
            trace("[WINGS_IMAGE_BEGIN] "+key+" "+width+" "+height);
            for(var row:Number=0;row<height;row++) {
                var parts:Array=[],last:Number=bd.getPixel32(0,row),count:Number=1;
                for(var col:Number=1;col<width;col++) {
                    var value:Number=bd.getPixel32(col,row);
                    if(value==last)count++;else {parts.push(hex(last)+":"+count);last=value;count=1;}
                }
                parts.push(hex(last)+":"+count);trace("[WINGS_IMAGE_ROW] "+key+" "+row+" "+parts.join(","));
            }
            trace("[WINGS_IMAGE_END] "+key);
        }
        bd.dispose();
    }
    private static function shadowPresent(actor:MovieClip):Boolean {
        return actor.wingsShadow._parent===actor && actor.wingsShadow._width>40 && actor.wingsShadow._height>10;
    }
    private static function shadowGrounded(actor:MovieClip):Boolean {
        if(!shadowPresent(actor))return false;
        var point:Object={x:0,y:0};actor.wingsShadow.localToGlobal(point);library.globalToLocal(point);
        return Math.abs(point.x-actor._x)<0.15 && Math.abs(point.y-actor.Z轴坐标)<0.15;
    }
    private static function shadowVisibility(visible:Boolean):Void {
        for(var i:Number=0;i<shadows.length;i++) {
            var p:Object=shadows[i];var u:MovieClip=p.actor;
            if(p.state=="消失")check(u.wingsShadow==undefined,"disappear has no shadow "+i);
            else check(shadowPresent(u) && u.wingsShadow._visible==visible,"shadow setting "+visible+" "+p.state+" side "+p.face);
        }
    }
    private static function shadowPixels():Void {
        check(library.shadow==undefined,"shadow never registers on the world container");
        for(var i:Number=0;i<shadows.length;i++) {
            var p:Object=shadows[i];var u:MovieClip=p.actor;if(p.state=="消失")continue;
            check(shadowGrounded(u),"ground shadow "+p.state+" side "+p.face);
            var bd:BitmapData=new BitmapData(100,50,true,0);
            if(shadowPresent(u)) {
                var m:Matrix=u.wingsShadow.transform.matrix;m.tx=50;m.ty=25;bd.draw(u.wingsShadow,m);
            }
            var pixels:Rectangle=bd.getColorBoundsRect(0xFF000000,0,false);
            check(pixels.width>40 && pixels.height>10,"rendered shadow pixels "+p.state+" side "+p.face);bd.dispose();
        }
    }
    private static function renderShadowSheet():Void {
        var indices:Array=[14,9,10,11,12,0];
        var bd:BitmapData=new BitmapData(900,620,false,0xFFF1F3F5);
        for(var i:Number=0;i<indices.length;i++) {
            var u:MovieClip=shadows[indices[i]].actor;
            var x:Number=(i%3)*300+150;var y:Number=Math.floor(i/3)*310+295;
            bd.fillRect(new Rectangle(x-120,y,240,1),0xFFD0D5D9);
            var m:Matrix=u.transform.matrix;m.tx=x;m.ty=y+u._y-u.Z轴坐标;
            var hudVisible:Boolean=u.人物文字信息._visible;u.人物文字信息._visible=false;
            bd.draw(u,m);u.人物文字信息._visible=hudVisible;
        }
        trace("[WINGS_SHADOW_CELLS] stand-left,knockdown,down,thrown,death-a0,airborne-mirrored-rotated-scaled");
        images["shadow-states"]=true;emitImage(bd,"shadow-states");
    }
    private static function scaleChecks():Void {
        var stand:MovieClip=probes[0].actor;var saved:Number=stand.man._currentframe;stand.man.gotoAndStop(1);
        render(stand,"stand");
        for(var i:Number=0;i<cases.length;i++) {
            var c:Object=cases[i];if(c.move!="death0")continue;
            var actor:MovieClip=c.actor;var frame:Number=actor.man._currentframe;actor.man.gotoAndStop(1);
            stand.方向改变(c.side==0?"右":"左");
            var live:Object=stand.man.getBounds(library);var dead:Object=actor.man.getBounds(library);
            check(Math.abs((live.yMax-live.yMin)-(dead.yMax-dead.yMin))<0.25,"death height side "+c.side);
            check(Math.abs((live.xMax-live.xMin)-(dead.xMax-dead.xMin))<0.25,"death width side "+c.side);
            check(Math.abs(live.yMax-dead.yMax)<0.25,"death ground side "+c.side);
            trace("[WINGS_DEATH_SCALE] side="+c.side+" standHeight="+(live.yMax-live.yMin)+" deathHeight="+(dead.yMax-dead.yMin)+" groundDelta="+(dead.yMax-live.yMax));
            if(c.side==0)render(actor,"death-start");
            actor.man.gotoAndPlay(frame);
        }
        stand.方向改变("右");stand.man.gotoAndPlay(saved);
    }
    private static function decisionChecks():Void {
        var u:MovieClip=probes[0].actor;
        check(probes[4].actor.WingsAI模式=="enhanced","ordinary unit cannot select calibration baseline");
        u.wingsClock=100;u.wingsReadyAt=u.wingsNextFlip=u.wingsNextCombo=0;
        check(u.wingsChooseAttack(100,0,0)=="combo","close combo");
        u.wingsNextCombo=110;
        check(u.wingsChooseAttack(100,0,0)=="flip","close flip after combo");
        u.wingsNextFlip=110;
        check(u.wingsChooseAttack(100,0,0)=="slash","short slash while cooldowns active");
        check(u.wingsChooseAttack(300,0,0)=="shoot","midrange shooting");
        check(u.wingsChooseAttack(481,0,0)=="none","maximum range");
        check(u.wingsChooseAttack(100,25,0)=="none","lane alignment");
        check(u.wingsChooseAttack(100,0,66)=="none","target height");
        check(u.wingsChooseAttack(Number("bad"),0,0)=="none","invalid coordinate");
        u.wingsReadyAt=110;check(u.wingsChooseAttack(100,0,0)=="none","recovery gate");u.wingsReadyAt=0;
        var t:MovieClip=target("wingsDecisionTarget",300);
        u.攻击目标=t._name;u.wingsTargetName=t._name;
        var original:Function=u.状态改变;
        u.状态改变=function(state:String):Void {this.requestedState=state;this.状态=state;};
        var flags:Array=["paused","manual","硬直中","倒地","浮空","dead","badTarget"];
        for(var j:Number=0;j<flags.length;j++) {
            u.状态="空手站立";u.requestedState="none";u.wingsClock=99;
            var flag:String=flags[j];
            if(flag=="paused")_root.暂停=true;else if(flag=="manual")_root.控制目标=u._name;
            else if(flag=="dead")u.hp=0;else if(flag=="badTarget")t.hp=0;else u[flag]=true;
            u.wingsTick();check(u.requestedState==(flag=="dead"?"血腥死":"none"),"AI guard "+flag);
            _root.暂停=false;_root.控制目标="__no_player";u.hp=t.hp=1000;u.硬直中=u.倒地=u.浮空=false;
        }
        u.状态="空手站立";u.requestedState="none";u.wingsClock=99;
        t.Z轴坐标=t._y=240;u.wingsTick();check(u.requestedState=="空手跑" && u.下行===true,"align before shooting");
        t.Z轴坐标=t._y=200;u.wingsClock=99;u.wingsTick();
        check(u.requestedState=="近战" && u.近战招式=="射击","actual ranged decision");
        check(u.unitAI.data.xrange==0 && u.unitAI.data.zrange==24,"private attack ownership");
        u.状态="近战";u.刚体=true;u.wingsBeginAttack(u.man,"shoot");var stale:Object=u.man.wingsToken;
        u.wingsBeginAttack(u.man,"shoot");u.man.wingsToken=stale;
        check(!u.wingsCanAct(u.man),"stale action token rejected");
        u.man.wingsToken=u.wingsAttackOwner.token;_root.暂停=true;
        check(!u.wingsCanAct(u.man),"paused action cannot emit");_root.暂停=false;
        u.wingsCancelAttack();check(!u.wingsCanAct(u.man) && u.刚体===true,"cancel preserves unrelated rigidity");
        u.刚体=false;u.状态改变=original;u.状态="空手站立";u.攻击目标="无";
        u.左行=u.右行=u.上行=u.下行=false;t.removeMovieClip();
    }
    private static function tick():Void {
        if(finished)return;ticks++;
        if(!ready){if(ticks>300){check(false,"load timeout");finish();}return;}
        if(ticks==3) {
            for(var sp:Number=0;sp<shadows.length;sp++) {
                var shadowCase:Object=shadows[sp];var su:MovieClip=shadowCase.actor;
                su.wingsTick=function():Void {};
                su.动画完毕=function():Void {this.man.stop();};su.死亡检测=function():Void {};
                su.方向改变(shadowCase.face==0?"右":"左");su.近战招式="后空翻";su.状态改变(shadowCase.state);
            }
            for(var p:Number=0;p<probes.length;p++)probes[p].actor.状态改变(probes[p].state);
            for(var i:Number=0;i<cases.length;i++) {
                var c:Object=cases[i];var u:MovieClip=c.actor;u.方向改变(c.side==0?"右":"左");
                if(c.move=="combo" || c.move=="interrupt" || c.move=="dead")u.状态改变("空手攻击");
                else if(c.move=="shoot" || c.move=="slash" || c.move.substr(0,4)=="flip" || c.move=="interruptFlip") {
                    if(c.move=="flipSlash" || c.move=="flipShoot") {
                        var distance:Number=c.move=="flipSlash"?90:300;
                        u.攻击目标=target("wingsChainTarget"+i,c.side==0?distance:-distance)._name;
                    }
                    u.近战招式=c.move=="shoot"?"射击":c.move=="slash"?"斩击":"后空翻";u.状态改变("近战");
                } else if(c.move.substr(0,3)=="hit")u.状态改变("被击");
                else if(c.move=="down")u.状态改变("倒地");
                else if(c.move=="knockdown")u.状态改变("击倒");
                else if(c.move.substr(0,5)=="death"){u.hp=0;u.状态改变("血腥死");}
            }
        }
        if(ticks==4)for(var a:Number=0;a<cases.length;a++) {
            var early:Object=cases[a];
            if(early.move.substr(0,5)=="death")early.actor.man.gotoAndPlay("a"+early.move.substr(5));
            if(early.move=="hit1")early.actor.man.gotoAndPlay("a1");
        }
        if(ticks==4)for(var sf:Number=0;sf<shadows.length;sf++) {
            var pose:Object=shadows[sf];if(pose.actor.man==undefined)continue;
            pose.actor.man.gotoAndStop(pose.state=="血腥死"?55:pose.state=="击倒"?3:pose.state=="近战"?50:1);
        }
        if(ticks>=6)for(var sh:Number=0;sh<cases.length;sh++) {
            var tracked:Object=cases[sh];if(tracked.record.removed || tracked.actor._parent!==library)continue;
            tracked.record.shadowSamples++;tracked.record.shadowOK=tracked.record.shadowOK && shadowGrounded(tracked.actor);
        }
        if(ticks==8){shadowVisibility(true);shadowPixels();}
        if(ticks==10)_root.是否阴影=false;
        if(ticks==12){shadowVisibility(false);_root.是否阴影=true;}
        if(ticks==14)shadowVisibility(true);
        if(ticks==16) {
            var airborne:MovieClip=shadows[0].actor;
            airborne._y=airborne.Z轴坐标-40;airborne._xscale=-160;airborne._yscale=160;airborne._rotation=25;
        }
        if(ticks==18) {
            var elevated:MovieClip=shadows[0].actor;
            check(shadowGrounded(elevated),"shadow stays on ground under lift reflection rotation and scale");
            var shadowBounds:Object=elevated.wingsShadow.getBounds(library);
            check(Math.abs((shadowBounds.xMax-shadowBounds.xMin)-55.9*1.6)<0.5
                && Math.abs((shadowBounds.yMax-shadowBounds.yMin)-22.75*1.6)<0.5,"airborne shadow remains horizontal with authored size");
            renderShadowSheet();
        }
        if(ticks>=3 && ticks<=10)for(var k:Number=0;k<probes.length;k++) {
            var probe:Object=probes[k];if(probe.actor.man._width>0)probe.record.bodySeen=true;
            if(ticks==10)check(probe.record.bodySeen,"body in state "+probe.state);
        }
        if(ticks==5){
            for(var b:Number=0;b<cases.length;b++) {
                var branchCase:Object=cases[b];
                if(branchCase.move.substr(0,5)!="death")continue;
                var branchId:Number=Number(branchCase.move.substr(5));
                var first:Number=branchId==0?1:branchId==1?59:96;
                var last:Number=branchId==0?58:branchId==1?95:132;
                check(branchCase.actor.man._currentframe>=first && branchCase.actor.man._currentframe<=last,"actual death branch "+b);
            }
            scaleChecks();decisionChecks();
        }
        if(ticks==6)for(var q:Number=0;q<cases.length;q++) {
            var interrupt:Object=cases[q];
            if(interrupt.move=="interrupt" || interrupt.move=="interruptFlip")interrupt.actor.状态改变("被击");
            if(interrupt.move=="dead")interrupt.actor.hp=0;
        }
        if(ticks==9)for(var n:Number=0;n<cases.length;n++)if(cases[n].move=="knockdown") {
            cases[n].actor.浮空=false;cases[n].actor.状态改变("倒地");
        }
        if(ticks>5)for(var d:Number=0;d<cases.length;d++) {
            var death:Object=cases[d];if(death.side!=0 || death.move.substr(0,5)!="death" || death.record.removed)continue;
            var branch:Number=Number(death.move.substr(5));var end:Number=branch==0?58:branch==1?95:132;
            if(death.actor.man._currentframe>=end-3 && death.actor.man._currentframe<=end)render(death.actor,"death-a"+branch+"-late");
        }
        if(ticks==145) {
            var expected:Object={combo:[14,0],shoot:[0,4],slash:[3,0],flip:[6,5],flipSlash:[9,5],flipShoot:[6,9]};
            for(var j:Number=0;j<cases.length;j++) {
                var item:Object=cases[j];var rec:Object=item.record;var attacks:Array=expected[item.move];
                check(rec.melee==(attacks?attacks[0]:0) && rec.shots==(attacks?attacks[1]:0),"exact emissions "+j+" "+item.move+" melee="+rec.melee+" shots="+rec.shots);
                check(rec.contract,"bullet and muzzle contract "+j);
                check(rec.shadowSamples>5 && rec.shadowOK,"continuous ground shadow through actual action "+j);
                if(attacks) {
                    check(rec.done==1,"attack finishes once "+j+" done="+rec.done);
                    check(item.actor.wingsAttackOwner==null && item.actor.wingsInvalidMuzzleCount==0,"ownership and muzzle complete "+j+" invalidFrame="+item.actor.wingsInvalidMuzzleFrame);
                } else if(item.move.substr(0,5)=="death" || item.move=="dead")check(rec.removed && rec.deathChecks==1,"death cleanup once "+j);
                else if(item.move=="down" || item.move=="knockdown")check(rec.deathChecks==1 && rec.done==1 && rec.physics>0,"physics delegation and getup "+j);
                else check(rec.done==1,"recovery once "+j);
                if(item.side==1 && attacks) {
                    var other:Object=cases[j-16].record;var same:Boolean=rec.positions.length==other.positions.length;
                    for(var h:Number=0;h<rec.positions.length && same;h++)same=Math.abs(rec.positions[h].x+other.positions[h].x)<0.1 && Math.abs(rec.positions[h].y-other.positions[h].y)<0.1;
                    check(same,"mirrored emission positions "+item.move);
                }
            }
            var expectedImages:Array=["stand","shoot","combo","flip","death-start","death-a0-late","death-a1-late","death-a2-late","shadow-states"];
            for(var im:Number=0;im<expectedImages.length;im++)check(images[expectedImages[im]]===true,"captured "+expectedImages[im]);
            finish();
        }
    }
    private static function finish():Void {
        if(finished)return;finished=true;delete driver.onEnterFrame;
        if(loader!=null)loader.removeListener(listener);
        trace("Cf6WingsAssetTest: "+passed+" passed, "+failed+" failed; "+cases.length+" actual timeline cases");
        library.removeMovieClip();driver.removeMovieClip();_root.cf6WingsAssetComplete();
    }
}
