import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.KillEventComponent;
import org.flashNight.arki.unit.UnitComponent.Updater.HitUpdater;
import org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel;

/** Unit-local phase ownership. Existing AI, attacks and final death stay shared. */
class org.flashNight.arki.unit.UnitAI.Custom.PhoenixPhaseController {
    public static var KIND:String="敌人-粉红头发御姐";
    public static var VISUAL:String="火凤转阶段演出";

    public static function install(root:Object):Void {
        root.火凤阶段初始化=function(u:MovieClip):Void {PhoenixPhaseController.initialize(u);};
    }

    public static function initialize(u:MovieClip):Void {
        if(u.__phoenixPhase || u.NPC || u._parent!==_root.gameworld)return;
        var c:Object={unit:u,world:u._parent,hp:Number(u.hp),phase:0,transition:false,
            nirvana:Boolean(u.宠物属性.涅槃重生),count:0,impacts:0,frame:0,
            oldState:u.状态改变,externalInvincible:u.无敌===true};
        u.__phoenixPhase=c;
        u.addProperty("hp",function():Number {return this.__phoenixPhase.hp;},
            function(value:Number):Void {PhoenixPhaseController.setHP(this,Number(value));});
        u.addProperty("无敌",function():Boolean {
            return this.__phoenixPhase.transition || this.__phoenixPhase.externalInvincible;
        },function(value:Boolean):Void {this.__phoenixPhase.externalInvincible=value===true;});
        u.状态改变=function(state:String):Void {
            var context:Object=this.__phoenixPhase;
            if(!context.transition)context.oldState.apply(this,arguments);
        };
        var guarded:Array=["行走","移动","被击移动","强制移动","动画完毕","死亡检测","击飞浮空","击飞倒地"];
        for(var i:Number=0;i<guarded.length;i++)guard(u,guarded[i]);
        // The legacy enemy facade reads an unqualified myxscale from its loader.
        // Keep direction and scale on this unit, including calls from class AI.
        u.myxscale=Math.abs(u._yscale);
        u.方向改变=function(direction:String):Void {
            if(this.__phoenixPhase.transition || this.锁定方向)return;
            if(direction!="左" && direction!="右")return;
            this.方向=direction;
            this._xscale=direction=="右"?this.myxscale:-this.myxscale;
            this.新版人物文字信息._xscale=direction=="右"?100:-100;
        };
        u.方向改变(u.方向);
        c.hit=HitUpdater.getUpdater(u);
        u.dispatcher.subscribeSingle("hit",function():Void {
            if(!this.__phoenixPhase.transition)this.__phoenixPhase.hit.apply(this,arguments);
        },u);
        u.dispatcher.subscribeSingle("kill",function(target:MovieClip):Void {
            if(!target.__phoenixPhase.transition && target.hp<=0 && !target._killed)
                KillEventComponent.onKill(target);
        },u);
        var thinker:MovieClip=u.createEmptyMovieClip("__phoenixPhaseThink",u.getNextHighestDepth());
        thinker.onEnterFrame=function():Void {PhoenixPhaseController.tick(this._parent);};
        thinker.context=c;
        thinker.onUnload=function():Void {
            if(this.context.unit.__phoenixPhase===this.context)PhoenixPhaseController.dispose(this.context.unit);
        };
        c.thinker=thinker;
        if(c.nirvana) {
            secondPhase(u);c.hp=u.hp满血值;
        }
        u.变身阶段=c.phase;u.已使用兴奋剂=c.phase>0;
        // The shared initializer also uses an unqualified state in gotoAndStop.
        // Stop the actor on its own ready state before its root timeline drifts.
        u.gotoAndStop(u.状态);
    }

    private static function guard(u:MovieClip,name:String):Void {
        var original:Function=u[name];
        if(typeof original!="function")return;
        u[name]=function() {
            if(!this.__phoenixPhase.transition)return original.apply(this,arguments);
        };
    }

    public static function setHP(u:MovieClip,value:Number):Void {
        var c:Object=u.__phoenixPhase;
        if(isNaN(value) || c.transition)return;
        if(c.phase<2 && value<=0) {
            // Zero never reaches shared kill/death consumers between lives.
            c.hp=1;c.transition=true;c.pending=true;c.count++;
            c.x=u._x;c.z=u.Z轴坐标;
            c.lift=Math.min(0,(u._y-c.z)*100/u._yscale);
            // Original demo: stage ty 669.5 -> 460.55, a 208.95px rise.
            c.apex=Math.min(c.lift,-208.95);u.man.stop();
            return;
        }
        c.hp=value;
        if(value<=0)dispose(u);
    }

    private static function secondPhase(u:MovieClip):Void {
        var c:Object=u.__phoenixPhase;
        c.phase=1;u.变身阶段=1;u.已使用兴奋剂=true;
        u.空手攻击力*=.7;
        // Other speeds are already derived from X by SpeedDeriveInitializer.
        u.行走X速度*=1.5;
    }

    private static function hold(u:MovieClip):Void {
        var c:Object=u.__phoenixPhase;
        u._x=c.x;u._y=c.z;u.Z轴坐标=c.z;u.垂直速度=0;
        u.左行=false;u.右行=false;u.上行=false;u.下行=false;
        u.动作A=false;u.动作B=false;
    }

    private static function begin(u:MovieClip):Void {
        var c:Object=u.__phoenixPhase;
        c.pending=false;c.age=0;c.fired=false;
        if(u.flyID!=null) {
            EnhancedCooldownWheel.I().removeTask(u.flyID);u.flyID=null;
        }
        if(u.stiffID!=null) {
            EnhancedCooldownWheel.I().removeTask(u.stiffID);u.stiffID=null;
        }
        hold(u);
        if(c.phase==0) {
            u.浮空=false;u.倒地=true;
            c.oldState.call(u,"倒地");
            // The destination man is materialized after the frame switch returns.
            // Do not read or drive the outgoing standing/attack clip here.
            c.step="down-ready";
        } else {
            // The shared float task is retired; only the authored presentation
            // changes height. X and ground/depth remain the captured anchor.
            u.浮空=true;u.倒地=false;
            show(u);
        }
        u.aabbCollider.updateFromUnitArea(u);
    }

    private static function show(u:MovieClip):Void {
        var c:Object=u.__phoenixPhase;
        c.visual=u.attachMovie(VISUAL,"__phoenixTransition",u.getNextHighestDepth());
        if(!c.visual)throw new Error("Missing Phoenix transition art: "+VISUAL);
        u.man._visible=false;
        c.step="show";c.frame=c.phase==0?1:82;
        c.last=c.phase==0?80:182;c.impactFrame=c.phase==0?35:159;
        updateVisual(c);
    }

    private static function updateVisual(c:Object):Void {
        c.visual._y=visualHeight(c);
        c.visual.gotoAndStop(c.frame);
        // A graphic-only flame layer shares this frame clock; no new emitter,
        // damage event or independently running MovieClip is introduced.
        var flame:MovieClip=c.visual.charge;
        if(c.phase==1 && c.frame<128) {
            if(c.frame>82 && !flame)throw new Error("Missing Phoenix charge layer");
            var strength:Number=Math.min(1,(c.frame-82)/11);
            flame.gotoAndStop(1+(c.frame-82)%32);
            flame._xscale=80+20*strength;flame._yscale=95+55*strength;
            flame._alpha=c.frame<118?15+75*strength:90*(128-c.frame)/10;
        } else {
            flame._alpha=0;flame.stop();
        }
    }

    private static function visualHeight(c:Object):Number {
        if(c.phase==0 || c.frame>=159)return 0;
        var t:Number;
        // Hold for flame gathering, then ascend with zero speed at both ends.
        // Preserve a higher airborne entry; never lower it before the descent.
        if(c.frame<94)return c.lift;
        if(c.frame<121) {
            t=(c.frame-94)/27;
            return c.lift+(c.apex-c.lift)*t*t*(3-2*t);
        }
        if(c.frame>150) {
            t=(c.frame-150)/9;
            return c.apex*(1-t*t);
        }
        return c.apex;
    }

    public static function tick(u:MovieClip):Void {
        var c:Object=u.__phoenixPhase;
        if(!c)return;
        if(c.world!==_root.gameworld) {dispose(u);return;}
        if(_root.暂停 || !c.transition)return;
        if(c.pending) {begin(u);return;}
        hold(u);
        if(c.step=="down-ready") {
            u.man._visible=true;u.man.gotoAndStop(1);
            c.age=0;c.downFrames=30;c.step="down";
            return;
        }
        if(c.step=="ready") {
            u.man._visible=true;u.man.play();
            c.visual.removeMovieClip();c.impactArea.removeMovieClip();
            c.transition=false;c.externalInvincible=false;
            u.aabbCollider.updateFromUnitArea(u);
            return;
        }
        if(c.step=="down") {
            c.age++;
            if(c.age<c.downFrames)u.man.gotoAndStop(c.age+1);
            else show(u);
            return;
        }
        c.frame++;
        if(c.frame>c.last) {complete(u);return;}
        updateVisual(c);
        if(c.frame==c.impactFrame && !c.fired) {
            c.fired=true;
            if(c.phase==1) {u.浮空=false;c.visual._y=0;}
            impact(u);
        }
    }

    private static function impact(u:MovieClip):Void {
        var c:Object=u.__phoenixPhase;
        var area:MovieClip=u.createEmptyMovieClip("__phoenixImpact",u.getNextHighestDepth());
        // Local strike core, deliberately smaller than the decorative halo.
        var radius:Number=c.phase==0?75:90;
        area.beginFill(0,0);area.moveTo(-radius,-65);area.lineTo(radius,-65);
        area.lineTo(radius,8);area.lineTo(-radius,8);area.lineTo(-radius,-65);area.endFill();
        area._visible=false;c.impactArea=area;
        var p:Object=_root.子弹属性初始化(area,"近战子弹",u);
        p.子弹威力=Math.max(1,u.空手攻击力*(c.phase==0?.02:2));
        p.伤害类型="魔法";p.魔法伤害属性="热";
        p.霰弹值=1;p.子弹散射度=0;p.子弹速度=0;
        p.shootX=c.x;p.shootY=c.z;p.shootZ=c.z;p.Z轴攻击范围=30;
        p.区域定位area=area;p.击倒率=c.phase==0?1:.25;
        p.水平击退速度=c.phase==0?8:20;p.垂直击退速度=0;
        p.击中地图效果="";p.击中后子弹的效果="空手攻击火花";
        _root.子弹区域shoot传递(p);c.impacts++;
        _root.播放音效("爆炸 较深邃 01.mp3");
    }

    private static function complete(u:MovieClip):Void {
        var c:Object=u.__phoenixPhase;
        if(c.phase==0) {
            secondPhase(u);c.hp=u.hp满血值;
            _root.发布消息("燎原烈火……");
        } else {
            c.phase=2;u.变身阶段=2;u.hp满血值=1500;c.hp=1500;
            c.aura=u.attachMovie("火凤余烬","火凤余烬",u.getNextHighestDepth(),{_xscale:100,_yscale:150});
            c.aura.onEnterFrame=function():Void {
                if(_root.暂停) {this.stop();return;}
                if(this._currentframe>=this._totalframes-1)this.gotoAndPlay(1);
                else this.play();
            };
            _root.发布消息("涅槃重生……");
        }
        // Retain the final authored pose until the new standing clip has loaded.
        // The shared state wrapper remains blocked for this one handoff tick.
        c.step="ready";
        u.浮空=false;u.倒地=false;u.已使用兴奋剂=true;
        c.oldState.call(u,u.攻击模式+"站立");
    }

    public static function dispose(u:MovieClip):Void {
        var c:Object=u.__phoenixPhase;
        if(!c)return;
        c.visual.removeMovieClip();c.impactArea.removeMovieClip();c.aura.removeMovieClip();
        c.visual=null;c.impactArea=null;c.aura=null;
        delete c.thinker.onEnterFrame;
    }
}
