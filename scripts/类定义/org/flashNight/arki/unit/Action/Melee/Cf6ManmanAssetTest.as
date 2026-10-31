import flash.display.BitmapData;
import flash.geom.Matrix;
import flash.geom.Rectangle;

/** Actual published Manman rig and private AI. Damage/initialization are in-memory fixtures. */
class org.flashNight.arki.unit.Action.Melee.Cf6ManmanAssetTest {
    private static var library:MovieClip, driver:MovieClip;
    private static var loader:MovieClipLoader, listener:Object;
    private static var passed:Number, failed:Number, ticks:Number;
    private static var ready:Boolean, finished:Boolean;
    private static var cases:Array, probes:Array;
    private static var motionAtlases:Array, motionSeen:Array;
    private static var link:String = "敌人-CF6蛮蛮";

    private static function check(ok:Boolean, label:String):Void {
        if (ok) passed++;
        else { failed++; trace("[TEST_FAIL] Cf6ManmanAssetTest: " + label); }
    }

    public static function runAllTests():Void {
        passed=failed=ticks=0;ready=finished=false;cases=[];probes=[];
        motionAtlases=[];motionSeen=[{},{}];
        if(_root.manmanMotionCapture===true) {
            motionAtlases=[new BitmapData(2400,1920,true,0),new BitmapData(2400,1920,true,0)];
        }
        library=_root.createEmptyMovieClip("__manmanLibrary",_root.getNextHighestDepth());
        driver=_root.createEmptyMovieClip("__manmanDriver",_root.getNextHighestDepth());
        library._visible=false;
        _root.gameworld=library;_root.暂停=false;_root.控制目标="__no_player";_root.控制目标全自动=false;
        _root.是否阴影=true;
        _root.播放音效=function():Void {};
        _root.发布消息=function():Void {};
        _root.效果=function():Void {};
        _root.add2map=function():Void {};
        _root.add2map2=function():Void {};
        _root.初始化思考标签=function(mc:MovieClip):Void {mc._name="思考标签";mc.stop();mc._visible=false;};
        _root.敌人二级函数={攻击时移动:function():Void {},X轴追踪移动:function():Void {},
            Z轴追踪移动:function():Void {},计算攻击角度:function():Void {},固定角度移动:function():Void {}};
        _root.子弹区域shoot=function(sound:String,pellets:Number,spread:Number,effect:String,kind:String,
            power:Number,speed:Number,lane:Number,hitEffect:String,shooter:String,sx:Number,sy:Number,
            sz:Number,friendly:Boolean,knockdown:Number,spark:String,horizontal:Number,vertical:Number,
            accuracy:Number,solid:Number,percent:Number,crumble:Number,ignore:Object,area:MovieClip):Void {
            Cf6ManmanAssetTest.capture(shooter,kind,power,lane,knockdown,sx,sz,friendly,crumble,area);
        };
        _root.子弹区域shoot传递=function(p:Object):Void {
            Cf6ManmanAssetTest.capture(p.发射者,p.子弹种类,p.子弹威力,p.Z轴攻击范围,p.击倒率,
                p.shootX,p.shootZ,p.子弹敌我属性,p.血量上限击溃,p.区域定位area);
            var unit:MovieClip=library[p.发射者];
            check(p.区域定位area._width>0 && p.区域定位area._height>0,"wolf landing area exists");
            check(unit.man._currentframe==31 && Math.abs(unit._y-unit.Z轴坐标)<0.01,"wolf impact on landing only");
        };
        _root.初始化敌人模板=function():Void {
            this.hp=this.hp满血值=1000;this.mp=0;this.空手攻击力=100;this.等级=30;
            this.状态="空手站立";this.攻击模式="空手";this.方向="右";this.攻击目标="无";
            this.Z轴坐标=this._y=200;this._x=200;this.myxscale=100;
            this.是否为敌人=true;this.倒地=this.浮空=this.硬直中=this.刚体=false;
            this.x轴攻击范围=100;this.y轴攻击范围=10;this.x轴保持距离=50;
            this.unitAI={data:{xrange:100,zrange:10,xdistance:50}};
            this.swapDepths=function():Void {};
            this.行走=function():Void {};
            this.移动=function(dir:String,speed:Number):Void {
                var next:Number=this._x+(dir=="右"?speed:dir=="左"?-speed:0);
                if(this.fixtureBlocked!==true || Math.abs(next-200)<=100)this._x=next;
                if(dir=="上" || dir=="下")this._y=this.Z轴坐标+=(dir=="上"?-speed:speed);
                this.fixtureRecord.moves++;
            };
            this.aabbCollider={updateFromUnitArea:function():Void {}};
            this.方向改变=function(dir:String):Void {this.方向=dir;this._xscale=dir=="左"?-100:100;};
            this.状态改变=function(state:String):Void {
                if(this.状态==state)return;
                this.状态=state;this.gotoAndStop(state);
            };
            this.动画完毕=function():Void {
                if(this.fixtureCase==11 || this.fixtureCase==32)
                    Cf6ManmanAssetTest.captureMotionFrame(this,this.fixtureCase==11?0:1);
                this.fixtureRecord.done++;
                this.倒地=false;
                this.状态改变(this.hp>0?"空手站立":"血腥死");
            };
            this.死亡检测=function():Void {
                this.fixtureRecord.deathChecks++;
                if(this.hp<=0) {
                    this.fixtureRecord.removed=true;
                    this.removeMovieClip();
                }
            };
            this.stop();
        };
        listener={
            onLoadInit:function(mc:MovieClip):Void {Cf6ManmanAssetTest.loaded(mc);},
            onLoadError:function(mc:MovieClip,error:String):Void {Cf6ManmanAssetTest.check(false,"load "+error);Cf6ManmanAssetTest.finish();}
        };
        loader=new MovieClipLoader();loader.addListener(listener);
        check(loader.loadClip("../flashswf/arts/new/Codex蛮蛮素材.swf",library),"load published native SWF");
        driver.onEnterFrame=function():Void {Cf6ManmanAssetTest.tick();};
    }

    private static function record():Object {
        return {shots:0,done:0,deathChecks:0,removed:false,moves:0,powerOk:true,laneOk:true,
            knockdownOk:true,sideOk:true,crumbleOk:true,areaOk:true,expectedCrumble:0.25,dx:0,wolf:false,maxHeight:0};
    }

    private static function loaded(mc:MovieClip):Void {
        mc.stop();
        var states:Array=["空手站立","空手行走","空手跑","躲闪","被投"];
        for(var s:Number=0;s<states.length;s++) {
            var pr:Object=record();
            var p:MovieClip=library.attachMovie(link,"manmanProbe"+s,library.getNextHighestDepth(),
                {fixtureRecord:pr,_arenaCalibrationUnit:s!=4,蛮蛮击溃模式:s==4?"off":"on"});
            check(p!=null,"attach "+states[s]);
            probes.push({actor:p,state:states[s],bodySeen:false});
        }
        var moves:Array=["cleave","advance","hit0","hit1","down","knockdown","death","interrupt","dead","cleaveOff","advanceOff",
            "wolf","wolfOff","wolfInterrupt","wolfDead","wolfPause","wolfBlocked","wolfAirInterrupt","wolfAirDead","wolfShallow","wolfRigidHit"];
        for(var side:Number=0;side<2;side++)for(var m:Number=0;m<moves.length;m++) {
            var rec:Object=record();
            var move:String=moves[m];
            var crumbleOff:Boolean=move=="cleaveOff" || move=="advanceOff";
            if(move=="wolfOff")crumbleOff=true;
            if(crumbleOff){move=move.substr(0,move.length-3);rec.expectedCrumble=0;}
            rec.wolf=move.indexOf("wolf")==0;
            rec.wolfComplete=move=="wolf" || move=="wolfPause" || move=="wolfBlocked" || move=="wolfShallow" || move=="wolfRigidHit";
            rec.expectedDepth=move=="wolfShallow"?5:60;
            var actor:MovieClip=library.attachMovie(link,"manmanCase"+cases.length,library.getNextHighestDepth(),
                {fixtureRecord:rec,_arenaCalibrationUnit:true,fixtureCase:cases.length,蛮蛮击溃模式:crumbleOff?"off":"on"});
            check(actor!=null,"attach "+moves[m]+" side "+side);
            cases.push({actor:actor,move:move,side:side,record:rec});
        }
        ready=true;ticks=0;
    }

    private static function capture(name:String,kind:String,power:Number,lane:Number,kd:Number,
        sx:Number,sz:Number,friendly:Boolean,crumble:Number,area:MovieClip):Void {
        var actor:MovieClip=library[name];var rec:Object=actor.fixtureRecord;
        if(rec==undefined)return;
        rec.shots++;
        rec.shotFrame=actor.man._currentframe;
        rec.powerOk=rec.powerOk && power==100 && kind=="近战子弹";
        rec.laneOk=rec.laneOk && lane==(rec.wolf?36:30) && sz==actor.Z轴坐标 && !isNaN(sx);
        rec.knockdownOk=rec.knockdownOk && kd==1;
        rec.sideOk=rec.sideOk && friendly===false;
        rec.crumbleOk=rec.crumbleOk && crumble===rec.expectedCrumble;
        var b:Object=area.getBounds(library);
        rec.areaOk=rec.areaOk && (b.xMax-b.xMin)>=60 && (b.yMax-b.yMin)>=60;
        rec.dx+=sx-actor._x;
    }

    private static function pixelHex(value:Number):String {
        var digits:String="0123456789abcdef",text:String="";
        for(var shift:Number=28;shift>=0;shift-=4)text+=digits.charAt((value>>>shift)&15);
        return text;
    }

    private static function render(actor:MovieClip,key:String):Void {
        var b:Object=actor.man.getBounds(actor.man);
        check(b.xMax>b.xMin && b.yMax>b.yMin,"native bounds "+key);
        // Use the actual parent placement and a fixed scale; auto-fit hid the death shrink.
        var bd:BitmapData=new BitmapData(640,400,true,0);
        var matrix:Matrix=actor.man.transform.matrix;
        matrix.scale(actor._xscale/100,actor._yscale/100);
        matrix.translate(320,330+actor._y-actor.Z轴坐标);
        bd.draw(actor.man,matrix);
        emitImage(bd,key);
    }

    private static function captureMotionFrame(actor:MovieClip,side:Number):Void {
        if(_root.manmanMotionCapture!==true || actor.状态!="狼跳")return;
        var frame:Number=actor.man._currentframe;
        if(frame<1 || frame>48 || motionSeen[side][frame]===true)return;
        motionSeen[side][frame]=true;
        if(frame==1) {
            check(actor.man.wolfHit._alpha===0,"landing marker hidden before load callback side "+side);
            shadowChecks(actor,"first frame side "+side);
        }
        var column:Number=(frame-1)%8,row:Number=Math.floor((frame-1)/8);
        var matrix:Matrix=actor.man.transform.matrix;
        matrix.scale(actor._xscale/100*.7,actor._yscale/100*.7);
        matrix.translate(column*300+150,row*320+280+(actor._y-actor.Z轴坐标)*.7);
        motionAtlases[side].draw(actor.man,matrix,null,null,new Rectangle(column*300,row*320,300,320));
        trace("[MANMAN_MOTION_FRAME] side="+side+" frame="+frame+" height="+(actor.Z轴坐标-actor._y));
    }

    private static function shadowChecks(actor:MovieClip,label:String):Void {
        var shadow:MovieClip=actor.man.wolfShadow;
        check(shadow!=null && shadow._visible===(_root.是否阴影==true) && shadow._width>1 && shadow._height>1,"wolf native shadow "+label);
        var actual:Object={x:0,y:0},expected:Object={x:-3.5,y:-0.35};
        shadow.localToGlobal(actual);actor._parent.globalToLocal(actual);
        actor.localToGlobal(expected);actor._parent.globalToLocal(expected);
        expected.y+=actor.Z轴坐标-actor._y;
        check(Math.abs(actual.x-expected.x)<0.2 && Math.abs(actual.y-expected.y)<0.2,"wolf shadow follows ground and depth "+label);
        check(Math.abs(shadow._rotation)<0.01,"wolf shadow does not somersault "+label);
    }

    private static function emitImage(bd:BitmapData,key:String):Void {
        var width:Number=bd.width,height:Number=bd.height;
        var visible:Number=0;
        for(var y:Number=0;y<height;y+=3)for(var x:Number=0;x<width;x+=3)if((bd.getPixel32(x,y)>>>24)>128)visible++;
        check(visible>300,"native vector pixels "+key+" "+visible);
        if(_root.manmanCapture===true || (_root.manmanMotionCapture===true && key.indexOf("wolf-motion-")==0)) {
            trace("[MANMAN_IMAGE_BEGIN] "+key+" "+width+" "+height);
            for(var row:Number=0;row<height;row++) {
                var parts:Array=[],last:Number=bd.getPixel32(0,row),count:Number=1;
                for(var col:Number=1;col<width;col++) {
                    var value:Number=bd.getPixel32(col,row);
                    if(value==last)count++;
                    else {parts.push(pixelHex(last)+":"+count);last=value;count=1;}
                }
                parts.push(pixelHex(last)+":"+count);
                trace("[MANMAN_IMAGE_ROW] "+key+" "+row+" "+parts.join(","));
            }
            trace("[MANMAN_IMAGE_END] "+key);
        }
        bd.dispose();
    }

    private static function deathScaleChecks():Void {
        var reference:MovieClip=probes[0].actor;
        var referenceFrame:Number=reference.man._currentframe;
        reference.man.gotoAndStop(1);
        render(reference,"stand");
        for(var i:Number=0;i<cases.length;i++) {
            var entry:Object=cases[i];
            if(entry.move!="death")continue;
            var actor:MovieClip=entry.actor;
            var deathFrame:Number=actor.man._currentframe;
            actor.man.gotoAndStop(1);
            reference.方向改变(entry.side==0?"右":"左");
            var standing:Object=reference.man.getBounds(library);
            var dying:Object=actor.man.getBounds(library);
            check(Math.abs((dying.yMax-dying.yMin)-(standing.yMax-standing.yMin))<0.25,"death preserves body height side "+entry.side);
            check(Math.abs((dying.xMax-dying.xMin)-(standing.xMax-standing.xMin))<0.25,"death preserves body width side "+entry.side);
            check(Math.abs(dying.yMax-standing.yMax)<0.25,"death preserves ground position side "+entry.side);
            check(Math.abs(dying.xMin-standing.xMin)<0.25,"death preserves horizontal placement side "+entry.side);
            trace("[MANMAN_DEATH_SCALE] side="+entry.side+" standHeight="+(standing.yMax-standing.yMin)+" deathHeight="+(dying.yMax-dying.yMin)+" groundDelta="+(dying.yMax-standing.yMax));
            if(entry.side==0) {
                render(actor,"death-start");
                var comparison:BitmapData=new BitmapData(640,320,true,0);
                var left:Matrix=reference.man.transform.matrix;left.translate(160,250);
                var right:Matrix=actor.man.transform.matrix;right.translate(480,250);
                comparison.draw(reference.man,left);comparison.draw(actor.man,right);
                emitImage(comparison,"death-transition");
            }
            actor.man.gotoAndPlay(deathFrame);
        }
        reference.方向改变("右");reference.man.gotoAndPlay(referenceFrame);
    }

    private static function decisionChecks():Void {
        var u:MovieClip=probes[0].actor;
        check(probes[4].actor.manmanCrumblePercent===0.25,"ordinary unit cannot opt out of crumble");
        var target:MovieClip=library.createEmptyMovieClip("manmanDecisionTarget",library.getNextHighestDepth());
        target.hp=1000;target._x=380;target._y=target.Z轴坐标=200;
        var area:MovieClip=target.createEmptyMovieClip("area",1);
        area.beginFill(0);area.moveTo(-20,-120);area.lineTo(20,-120);area.lineTo(20,0);area.lineTo(-20,0);area.endFill();
        u.manmanClock=100;u.manmanReadyAt=0;u.manmanNextAdvance=u.manmanNextWolf=0;
        check(u.manmanChooseAttack(90,0,0)=="cleave","close cleave");
        check(u.manmanChooseAttack(180,0,0)=="advance","midrange advance");
        check(u.manmanChooseAttack(201,0,0)=="wolf","outside advance selects wolf");
        check(u.manmanChooseAttack(440,72,0)=="wolf","bounded distant and cross-lane wolf");
        check(u.manmanChooseAttack(441,0,0)=="none","outside wolf range");
        check(u.manmanChooseAttack(300,73,0)=="none","outside wolf depth window");
        u.manmanNextWolf=101;
        check(u.manmanChooseAttack(300,0,0)=="cleave","wolf cooldown falls back to long-range cleave charge harass");
        u.manmanNextCleave=101;
        check(u.manmanChooseAttack(300,0,0)=="none","wolf and cleave cooldown");
        u.manmanNextCleave=0;
        check(u.manmanChooseAttack(180,0,0)=="advance","wolf cooldown retains advance");
        u.manmanNextWolf=0;
        check(u.manmanChooseAttack(90,23,0)=="none","lane alignment required");
        check(u.manmanChooseAttack(90,0,66)=="none","airborne target rejected");
        check(u.manmanChooseAttack(Number("bad"),0,0)=="none","invalid coordinate rejected");
        u.manmanReadyAt=110;
        check(u.manmanChooseAttack(90,0,0)=="none","recovery window");
        u.manmanReadyAt=0;u.manmanNextAdvance=110;
        check(u.manmanChooseAttack(180,0,0)=="none","advance cooldown");
        u.manmanNextAdvance=0;
        var realChange:Function=u.状态改变;
        u.状态改变=function(state:String):Void {this.requestedState=state;this.状态=state;};
        u.攻击目标=target._name;u.manmanTargetName=target._name;
        var flags:Array=["暂停","manual","硬直中","倒地","浮空","dead","badTarget"];
        for(var i:Number=0;i<flags.length;i++) {
            u.状态="空手站立";u.requestedState="none";u.manmanClock=99;
            var flag:String=flags[i];
            if(flag=="暂停")_root.暂停=true;
            else if(flag=="manual")_root.控制目标=u._name;
            else if(flag=="dead")u.hp=0;
            else if(flag=="badTarget")target.hp=0;
            else u[flag]=true;
            u.manmanTick();
            check(u.requestedState==(flag=="dead"?"血腥死":"none"),"AI guard "+flag);
            _root.暂停=false;_root.控制目标="__no_player";u.hp=1000;target.hp=1000;
            u.硬直中=u.倒地=u.浮空=false;
        }
        u.状态="空手站立";u.requestedState="none";u.manmanClock=99;
        target.Z轴坐标=target._y=230;u.manmanTick();
        check(u.requestedState=="none" && u.下行===true,"align before attacking");
        target.Z轴坐标=target._y=200;u.manmanClock=99;u.manmanTick();
        check(u.requestedState=="近战","actual private decision requests advance");
        check(u.unitAI.data.xrange==0 && u.unitAI.data.zrange==22,"private attack ownership cached");
        target._x=560;target.Z轴坐标=target._y=245;u.状态="空手站立";u.manmanClock=99;
        u.manmanTick();check(u.requestedState=="狼跳","actual distant cross-lane decision requests wolf");
        u.状态="空手攻击";u.manmanBeginAttack(u.man,"cleave");
        var stale:Object=u.man.manmanToken;
        u.manmanBeginAttack(u.man,"cleave");
        check(!u.manmanCanHit(stale) && u.manmanCanHit(u.man.manmanToken),"stale action token rejected");
        u.manmanCancelAttack();check(!u.manmanCanHit(u.man.manmanToken),"cancelled action cannot hit");
        var ramArea:MovieClip=u.manmanEnsureRamArea();
        var rb:Object=ramArea.getBounds(u);
        check(Math.abs((rb.xMax-rb.xMin)-105)<0.5 && Math.abs((rb.yMax-rb.yMin)-115)<0.5,"drag-axe ram collider bounds");
        u.状态改变=realChange;u.状态="空手站立";u.攻击目标="无";
        u.左行=u.右行=u.上行=u.下行=false;target.removeMovieClip();
    }

    private static function tick():Void {
        if(finished)return;ticks++;
        if(!ready) {if(ticks>300){check(false,"load timeout");finish();}return;}
        if(ticks==3) {
            for(var s:Number=0;s<probes.length;s++)probes[s].actor.状态改变(probes[s].state);
            for(var i:Number=0;i<cases.length;i++) {
                var c:Object=cases[i];var u:MovieClip=c.actor;
                u.方向改变(c.side==0?"右":"左");
                if(c.record.wolf) {
                    var target:MovieClip=library.createEmptyMovieClip("wolfTarget"+i,library.getNextHighestDepth());
                    target.hp=1000;target._x=200+(c.side==0?360:-360);
                    target.Z轴坐标=200+(c.side==0?1:-1)*(c.move=="wolfShallow"?5:95);
                    u.攻击目标=target._name;u.fixtureBlocked=c.move=="wolfBlocked";
                    u.状态改变("狼跳");
                    c.target=target;
                } else if(c.move=="cleave" || c.move=="interrupt" || c.move=="dead")u.状态改变("空手攻击");
                else if(c.move=="advance"){u.近战招式="a0";u.状态改变("近战");}
                else if(c.move.substr(0,3)=="hit"){u.状态改变("被击");u.man.gotoAndPlay("a"+c.move.substr(3));}
                else if(c.move=="down")u.状态改变("倒地");
                else if(c.move=="knockdown")u.状态改变("击倒");
                else if(c.move=="death"){u.hp=0;u.状态改变("血腥死");}
            }
        }
        // Dodge starts on a random frame and may finish during a frame boundary.
        // Observe its visible body or completed recovery instead of sampling one boundary.
        if(ticks>=3 && ticks<=10) {
            for(var p:Number=0;p<probes.length;p++) {
                var probe:Object=probes[p];
                var inState:Boolean=probe.actor.状态==probe.state;
                var recovered:Boolean=probe.state=="躲闪" && probe.actor.fixtureRecord.done==1 && probe.actor.状态=="空手站立";
                if((inState || recovered) && probe.actor.man._width>0)probe.bodySeen=true;
                if(ticks==10)check(probe.bodySeen,"state has body "+probe.state);
            }
        }
        if(ticks==5) {
            deathScaleChecks();
            decisionChecks();
        }
        if(ticks==9) {
            for(var j:Number=0;j<cases.length;j++) {
                var q:Object=cases[j];
                if(q.move=="interrupt" || q.move=="wolfInterrupt"){q.actor.状态改变("被击");q.actor.man.gotoAndPlay("a0");}
                else if(q.move=="dead" || q.move=="wolfDead")q.actor.hp=0;
            }
        }
        for(var w:Number=0;w<cases.length;w++) {
            var wolf:Object=cases[w];if(!wolf.record.wolf)continue;
            var unit:MovieClip=wolf.actor;
            var height:Number=unit.Z轴坐标-unit._y;
            if(height>wolf.record.maxHeight)wolf.record.maxHeight=height;
            if(ticks==10) {wolf.target._x+=500;wolf.target.Z轴坐标+=200;}
            if(ticks==16 && wolf.move!="wolfInterrupt" && wolf.move!="wolfDead") {
                check(unit._x==200 && unit.Z轴坐标==200 && wolf.record.shots==0,"wolf readable windup "+w);
                check(unit.刚体===false,"wolf windup is punishable "+w);
            }
            if(ticks==25 && wolf.move=="wolfAirInterrupt") {unit.状态改变("被击");unit.man.gotoAndPlay("a0");}
            if(ticks==25 && wolf.move=="wolfAirDead")unit.hp=0;
            if(ticks==25 && wolf.move=="wolfRigidHit") {
                check(unit.刚体===true && unit.状态=="狼跳","rigid wolf keeps action while movement-staggered "+w);
                unit.硬直中=true;
            }
            if(ticks==36 && wolf.move=="wolfRigidHit")unit.硬直中=false;
            if(ticks==27 && (wolf.move=="wolfAirInterrupt" || wolf.move=="wolfAirDead"))
                check(unit._y==unit.Z轴坐标 && unit.刚体===false,"interrupted flight releases height and armor "+w);
            if(ticks==24 && wolf.move=="wolfPause") {
                var bx:Number=unit._x,bz:Number=unit.Z轴坐标,by:Number=unit._y,clock:Number=unit.manmanClock;
                _root.暂停=true;unit.manmanTick();unit.manmanWolfStep(unit.man);unit.manmanWolfImpact(unit.man);
                check(unit._x==bx && unit.Z轴坐标==bz && unit._y==by && unit.manmanClock==clock && wolf.record.shots==0,"paused wolf has no movement/time/damage");
                _root.暂停=false;
            }
            if(ticks==40 && wolf.record.wolfComplete) {
                check(unit.状态=="狼跳" && unit.刚体===false,"wolf landing recovery can be punished "+w);
                wolf.recoveryX=unit._x;wolf.recoveryZ=unit.Z轴坐标;
            }
        }
        if(ticks==16 || ticks==26 || ticks==34 || ticks==40) {
            shadowChecks(cases[11].actor,"right tick "+ticks);
            shadowChecks(cases[32].actor,"left tick "+ticks);
        }
        if(ticks==16) {
            _root.是否阴影=false;
            for(var shadowSide:Number=0;shadowSide<2;shadowSide++) {
                var shadowActor:MovieClip=cases[shadowSide==0?11:32].actor;
                shadowActor.manmanSyncWolfShadow(shadowActor.man);
                check(shadowActor.man.wolfShadow._visible===false,"wolf respects disabled shadow side "+shadowSide);
            }
            _root.是否阴影=true;
            for(var restoreSide:Number=0;restoreSide<2;restoreSide++) {
                var restoreActor:MovieClip=cases[restoreSide==0?11:32].actor;
                restoreActor.manmanSyncWolfShadow(restoreActor.man);
                check(restoreActor.man.wolfShadow._visible===true,"wolf restores enabled shadow side "+restoreSide);
            }
        }
        if(ticks==26) {
            var scaled:MovieClip=cases[11].actor;
            scaled._yscale=65;scaled.manmanSyncWolfShadow(scaled.man);
            shadowChecks(scaled,"scaled airborne unit");
            scaled._yscale=100;scaled.manmanSyncWolfShadow(scaled.man);
        }
        if(ticks==16)render(cases[11].actor,"wolf-windup");
        if(ticks==26)render(cases[11].actor,"wolf-flight");
        if(ticks==34)render(cases[11].actor,"wolf-impact");
        if(ticks==40)render(cases[11].actor,"wolf-recovery");
        if(ticks==26)render(cases[cases.length/2+11].actor,"wolf-left");
        captureMotionFrame(cases[11].actor,0);
        captureMotionFrame(cases[32].actor,1);
        if(ticks==14 || ticks==27) {
            for(var r:Number=0;r<cases.length;r++) {
                var a:Object=cases[r];
                if(a.move=="cleave" || a.move=="advance"){
                    var guarded:Boolean=a.move=="cleave" || ticks==14;
                    check(a.actor.刚体===guarded,"armor window "+a.move+" "+ticks);
                    if(a.move=="cleave")check(a.actor.免疫击退===true,"drag charge keeps displacement immunity through its middle "+ticks);
                }
            }
        }
        if(ticks==17)render(cases[0].actor,"cleave-impact");
        if(ticks==80)render(cases[6].actor,"death-late");
        if(ticks==155) {
            check(cases[11].actor.man.wolfShadow==null,"wolf shadow removed on right recovery");
            check(cases[32].actor.man.wolfShadow==null,"wolf shadow removed on left recovery");
            for(var k:Number=0;k<cases.length;k++) {
                var item:Object=cases[k];var rec:Object=item.record;
                var wolfAttack:Boolean=rec.wolfComplete===true;
                var attacks:Boolean=item.move=="cleave" || item.move=="advance" || wolfAttack;
                check(rec.shots==(wolfAttack?1:item.move=="cleave"?4:attacks?3:0),"exact emissions "+k+" "+item.move+" "+rec.shots);
                check(rec.powerOk && rec.laneOk && rec.knockdownOk && rec.sideOk && rec.crumbleOk && rec.areaOk,"damage contract "+k);
                if(attacks) {
                    check(rec.done==1,"attack terminal once "+k);
                    check(item.side==0?rec.dx>0:rec.dx<0,"mirrored hit placement "+k);
                    check(item.actor.manmanAttackOwner==null && item.actor.刚体===false,"attack ownership released "+k);
                    if(wolfAttack) {
                        check(rec.shotFrame==31 && rec.maxHeight>85,"wolf flight and principal impact "+k);
                        check(Math.abs(item.actor.Z轴坐标-200)==rec.expectedDepth,"wolf capped and shallow depth correction "+k);
                        var distance:Number=Math.abs(item.actor._x-200);
                        trace("[MANMAN_WOLF_RESULT] case="+k+" x="+item.actor._x+" z="+item.actor.Z轴坐标+" distance="+distance+" maxHeight="+rec.maxHeight+" shots="+rec.shots);
                        // MovieClip coordinates are quantized to twips; both facings stay within half a pixel.
                        check(item.move=="wolfBlocked"?(distance>95 && distance<=100):Math.abs(distance-290)<0.5,"wolf locks original target and respects wall "+k);
                        check(item.actor._y==item.actor.Z轴坐标,"wolf releases height "+k);
                        check(item.actor._x==item.recoveryX && item.actor.Z轴坐标==item.recoveryZ,"wolf cannot move during recovery "+k);
                    }
                } else if(item.move=="death" || item.move=="dead" || item.move=="wolfDead" || item.move=="wolfAirDead") {
                    check(rec.removed && rec.deathChecks==1,"death cleanup once "+k+" checks="+rec.deathChecks);
                } else if(item.move=="down" || item.move=="knockdown") {
                    check(rec.deathChecks==2 && rec.done==1,"down checks and recovery "+k);
                } else check(rec.done==1,"hit/interrupt recovery "+k+" "+rec.done);
            }
            finish();
        }
    }

    private static function finish():Void {
        if(finished)return;finished=true;delete driver.onEnterFrame;
        if(_root.manmanMotionCapture===true) {
            for(var side:Number=0;side<2;side++) {
                var complete:Boolean=true;
                for(var frame:Number=1;frame<=48;frame++)if(motionSeen[side][frame]!==true)complete=false;
                check(complete,"all 48 native wolf frames side "+side);
                emitImage(motionAtlases[side],side==0?"wolf-motion-right":"wolf-motion-left");
            }
        }
        if(loader!=null)loader.removeListener(listener);
        trace("Cf6ManmanAssetTest: "+passed+" passed, "+failed+" failed; "+cases.length+" actual timeline cases");
        library.removeMovieClip();driver.removeMovieClip();_root.cf6ManmanAssetComplete();
    }
}
