import org.flashNight.arki.spatial.move.Mover;
import org.flashNight.arki.component.Shield.Shield;
import org.flashNight.arki.unit.UnitComponent.Routing.RoutingLifecycle;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentLightController;

/**
 * Special shotgun F skill. Gun/shield art and the player dressup rig live in
 * 战技容器-特勤盾冲; the ordinary weapon and its first-frame icon stay unchanged.
 * All balance values come from the item's skill.parameters. No NPC phase logic.
 */
class org.flashNight.arki.unit.Action.Skill.SheriffShieldRush {
    public static var NAME:String = "特勤盾冲";
    public static var BUFF_SOURCE:String = "特勤盾冲";
    public static var ART_FRAMES:Number = 152;
    public static var TRANSFORM_FRAMES:Number = 15;
    public static var RUN_START:Number = 20;
    public static var RUN_FRAMES:Number = 16;
    public static var BRAKE_BRANCH_START:Number = 57;
    public static var BRAKE_FRAMES:Number = 6;

    public static function install(root:Object):Void {
        root.主动战技函数.长枪.特勤盾冲 = {
            原子释放: true,
            固定资源消耗: true,
            释放许可判定: function(u:MovieClip):Boolean {
                return SheriffShieldRush.canRelease(u);
            },
            释放: function(u:MovieClip):Boolean {
                return SheriffShieldRush.release(u);
            },
            载入: function(man:MovieClip):Void {
                SheriffShieldRush.loaded(man);
            }
        };
    }

    private static function bounded(p:Object, key:String, fallback:Number, low:Number, high:Number):Number {
        var n:Number = Number(p[key]);
        return isNaN(n) ? fallback : Math.max(low, Math.min(high, n));
    }

    public static function tuning(p:Object):Object {
        return {
            maxChargeFrames: Math.round(bounded(p,"maxChargeFrames",36,1,180)),
            reduction: bounded(p,"reduction",50,0,95),
            shieldDefenseRatio: bounded(p,"shieldDefenseRatio",1,0,5),
            maxRushLoops: Math.round(bounded(p,"maxRushLoops",3,1,6)),
            speedBonus: bounded(p,"speedBonus",2,0,50),
            laneSpeedRatio: bounded(p,"laneSpeedRatio",.5,0,1),
            hitInterval: Math.round(bounded(p,"hitInterval",3,1,15)),
            powerMultiplier: bounded(p,"powerMultiplier",.6,0,10),
            chargedPower: bounded(p,"chargedPower",.8,0,10),
            knockback: bounded(p,"knockback",6,0,30),
            chargedKnockback: bounded(p,"chargedKnockback",8,0,30),
            zRange: bounded(p,"zRange",30,1,80)
        };
    }

    public static function canRelease(u:MovieClip):Boolean {
        if (!(u.hp > 0) || u.倒地 || u.浮空 || u.换弹中 || u.__sheriffShieldRush) return false;
        if (u._name != _root.控制目标 || u.攻击模式 != "长枪" || u.长枪数据.name != "特勤霰弹枪") return false;
        return u.状态 == "长枪站立" || u.状态 == "长枪行走" || u.状态 == "长枪跑";
    }

    public static function release(u:MovieClip):Boolean {
        if (!canRelease(u)) return false;
        var skill:Object = u.主动战技.长枪;
        var mp:Number = skill.消耗mp > 0 ? Number(skill.消耗mp) : 0;
        if (u.mp < mp) return org.flashNight.arki.skill.SkillResourceService.reject(u,"mp");
        var p:Object = tuning(u.长枪数据.skill.parameters);
        // Snapshot the real derived running speed, including weight and buffs.
        // This is an additive bonus; fast builds must never be multiplied or
        // silently capped back to the old 9/15 fixed-speed placeholders.
        var runSpeed:Number = Number(u.跑X速度);
        if (!isFinite(runSpeed) || runSpeed < 0) return false;
        var defense:Number = Number(u.防御力);
        if (!(defense > 0) || !isFinite(defense)) defense = 0;
        // Generic battle-skill routing switches the actor to skill bonuses.
        // Preserve only this gun's lifesteal, without restoring gun power or
        // changing the actor's shared skill-mode attributes.
        var weaponVampirism:Number = Number(u.长枪吸血);
        if (!(weaponVampirism > 0) || !isFinite(weaponVampirism)) weaponVampirism = 0;
        // Shield capacity and impact share the same pre-cast defense snapshot.
        // Gun enhancement/passives and damage to the granted shield cannot
        // alter this base during charging or the subsequent run loops.
        var ctx:Object = {
            unit:u, item:u.长枪, world:_root.gameworld, phase:"open", age:0,
            charge:0, released:false, cleaned:false, lastFrame:-1,
            direction:u.方向, tune:p, mp:mp, paid:false, hits:0, blocked:0, distance:0,
            emittedTick:-1, tickId:0, pending:false,
            speed:runSpeed+p.speedBonus,
            shieldCapacity:Math.floor(defense*p.shieldDefenseRatio), shieldContainer:u.shield,
            defenseAtCast:defense, weaponVampirism:weaponVampirism
        };
        u.__sheriffShieldRush = ctx;
        var man:MovieClip = _root.战技路由.战技标签跳转_旧(u,NAME,"container");
        // Timeline length is synchronous. On repeated attachMovie, named child
        // instances may not register until frame 1, so do not reject on them here.
        if (man._totalframes != ART_FRAMES) {
            cleanup(ctx);
            RoutingLifecycle.recoverMissingSkillContainer(u);
            return false;
        }
        ctx.man = man;
        man.__sheriffRushToken = ctx;
        u.mp -= mp;
        ctx.paid = true;
        // The first frame may run inside attachMovie, before the router assigns
        // u.man. Claim the prop again after routing; loaded() covers late children.
        light(ctx);
        return true;
    }

    public static function loaded(man:MovieClip):Void {
        var ctx:Object = man._parent.__sheriffShieldRush;
        if (!ctx || ctx.cleaned) return;
        ctx.man = man;
        man.__sheriffRushToken = ctx;
        man.stop();
        man.盾具.gotoAndStop(1);
        man.冲撞区域._visible = false;
        light(ctx);
        var oldUnload:Function = man.onUnload;
        man.onUnload = function():Void {
            SheriffShieldRush.cleanup(ctx);
            if (oldUnload != undefined) oldUnload.apply(this);
        };
        man.onEnterFrame = function():Void {
            SheriffShieldRush.tick(this,Key.isDown(_root.武器技能键));
        };
    }

    /** keyDown is the configured weapon-skill key, not the active-skill slot. */
    public static function tick(man:MovieClip, keyDown:Boolean):Void {
        var ctx:Object = man.__sheriffRushToken;
        if (!ctx || ctx.cleaned || !ctx.paid || _root.暂停) return;
        var u:MovieClip = ctx.unit;
        if (u.__sheriffShieldRush !== ctx || _root.gameworld !== ctx.world ||
                u.man !== man || !(u.hp > 0) || u.攻击模式 != "长枪" ||
                u.长枪 !== ctx.item || u.长枪数据.name != "特勤霰弹枪" ||
                u.状态 != "战技") {
            var current:Boolean = u.__sheriffShieldRush === ctx && u.man === man && u.状态 == "战技";
            cleanup(ctx);
            if (current) _root.战技路由.动画完毕(man,u);
            return;
        }
        var frame:Number = Number(_root.帧计时器.当前帧数);
        if (!isNaN(frame)) {
            if (frame == ctx.lastFrame) return;
            ctx.lastFrame = frame;
        }
        ctx.tickId++;
        // Like 拔刀术, consume the player's mapped movement intent throughout
        // the action. Only the rush phase translates; other phases can face.
        steer(ctx);
        if (!keyDown && (ctx.phase == "open" || ctx.phase == "hold")) ctx.released = true;
        var p:Object = ctx.tune;
        if (ctx.phase == "open") {
            ctx.age++;
            if (ctx.age < TRANSFORM_FRAMES) {
                pose(ctx,ctx.age+1,ctx.age+1);
            } else {
                guard(ctx);
                if (ctx.released) beginRush(ctx);
            }
        } else if (ctx.phase == "hold") {
            if (ctx.released) {
                beginRush(ctx);
            } else {
                ctx.charge++;
                pose(ctx,16+Math.min(3,Math.floor(ctx.charge*4/p.maxChargeFrames)),15);
                chargeMark(ctx);
                if (!(ctx.charge < p.maxChargeFrames)) beginRush(ctx);
            }
        } else if (ctx.phase == "rush") {
            var oldX:Number = u._x;
            var oldZ:Number = u.Z轴坐标;
            // The generic strict mover samples at up to 50 units. Shield rush
            // needs finer terrain checks even at +2 on a 30-40 speed build.
            var steps:Number = Math.max(1,Math.ceil(ctx.speed/8));
            var direction:Number = ctx.direction=="左" ? -1 : 1;
            var lane:Number = u._name!=_root.控制目标 ? 0 : (u.上行 ? -1 : (u.下行 ? 1 : 0));
            var wall:Boolean = false;
            var laneBlocked:Boolean = false;
            for (var moveIndex:Number=0;moveIndex<steps;moveIndex++) {
                // Anchor each step to the frame origin. Repeated fractional
                // additions otherwise accumulate AVM1 twip truncation on the
                // leftward path (38 / 5 is especially visible over 20 ticks).
                var targetX:Number=oldX+direction*Math.min(ctx.speed,(moveIndex+1)*8);
                var substep:Number=Math.abs(targetX-u._x);
                if (_root.collisionLayer.hitTest(targetX,u.Z轴坐标,true)) {wall=true;break;}
                Mover.move2DStrict(u,ctx.direction,substep);
                if (lane!=0 && !laneBlocked) {
                    var targetZ:Number=oldZ+lane*Math.min(ctx.speed,(moveIndex+1)*8)*p.laneSpeedRatio;
                    if (!_root.collisionLayer.hitTest(u._x,targetZ,true))
                        Mover.move2DStrict(u,lane<0?"上":"下",Math.abs(targetZ-u.Z轴坐标));
                    else laneBlocked=true;
                }
            }
            var step:Number = Math.abs(u._x-oldX);
            ctx.blocked = wall ? 2 : (step < ctx.speed*.15 ? ctx.blocked+1 : 0);
            var bounds:Object = ctx.man.冲撞区域.getBounds(ctx.world);
            ctx.pendingBounds=bounds;ctx.pendingX=u._x;ctx.pendingZ=u.Z轴坐标;ctx.pending=true;
            var span:Number = Math.max(1,(bounds.xMax-bounds.xMin)*.75);
            var ending:Boolean = ctx.age+1>=ctx.rushLength || ctx.blocked>1;
            // Trigger by time OR travel. One swept box per frame covers the
            // entire unsampled path, including the first and last segments;
            // movement substeps never emit overlapping full-damage bullets.
            if (ctx.age-ctx.lastImpactAge>=p.hitInterval || Math.abs(u._x-ctx.lastImpactX)>=span || ending) {
                emitPending(ctx);
            }
            ctx.age++;
            ctx.distance += step;
            // Repeat complete native 16-frame strides. Charge buys 1/2/3 loops;
            // it changes duration, never the saved additive movement speed.
            pose(ctx,RUN_START+(ctx.age%RUN_FRAMES),15);
            if (!(ctx.age < ctx.rushLength) || ctx.blocked > 1) {
                ctx.brakeStart = BRAKE_BRANCH_START+(man._currentframe-20)*BRAKE_FRAMES;
                ctx.phase = "brake";ctx.age = 0;
            }
        } else if (ctx.phase == "brake") {
            // A turn on the last rush tick may have spent that frame's one
            // emission on the old direction. Retire the final new segment now.
            emitPending(ctx);
            pose(ctx,ctx.brakeStart+ctx.age,15);
            ctx.age++;
            if (ctx.age == BRAKE_FRAMES) {
                removeGuard(ctx);
                ctx.phase = "close";ctx.age = 0;
            }
        } else if (ctx.phase == "close") {
            if (ctx.age == TRANSFORM_FRAMES) {
                // Give the fully folded gun and native combat stance a real
                // render interval before replacing the skill container.
                cleanup(ctx);
                _root.战技路由.动画完毕(man,u);
            } else {
                pose(ctx,42+ctx.age,15-ctx.age);
                ctx.age++;
            }
        }
    }

    public static function chargeLevel(charge:Number,p:Object):Number {
        return 1+Math.min(p.maxRushLoops-1,Math.floor(charge*(p.maxRushLoops-1)/p.maxChargeFrames));
    }

    private static function steer(ctx:Object):Void {
        var u:MovieClip=ctx.unit;
        var next:String=u.方向;
        if(u._name==_root.控制目标) {
            if(u.右行)next="右";
            else if(u.左行)next="左";
        }
        if(next!=ctx.direction && !u.锁定方向 && !u.飞行浮空) {
            // Flush the old-facing path before mirroring. Never join the old
            // and new front hitboxes through the player's body as one sweep.
            emitPending(ctx);
            u.方向改变(next);
            ctx.direction=u.方向;
            if(ctx.phase=="rush")resetSweep(ctx);
            light(ctx);
        }
    }

    private static function resetSweep(ctx:Object):Void {
        ctx.lastImpactBounds=ctx.man.冲撞区域.getBounds(ctx.world);
        ctx.lastImpactX=ctx.unit._x;ctx.lastImpactZ=ctx.unit.Z轴坐标;
        ctx.lastImpactAge=ctx.age-ctx.tune.hitInterval;
        ctx.pending=false;
    }

    private static function emitPending(ctx:Object):Void {
        if(!ctx.pending || ctx.emittedTick==ctx.tickId)return;
        impact(ctx,ctx.pendingBounds);
        ctx.emittedTick=ctx.tickId;
        ctx.lastImpactAge=ctx.age;ctx.lastImpactX=ctx.pendingX;ctx.lastImpactZ=ctx.pendingZ;
        ctx.lastImpactBounds=ctx.pendingBounds;ctx.pending=false;
    }

    private static function pose(ctx:Object, frame:Number, weaponFrame:Number):Void {
        var man:MovieClip = ctx.man;
        man.gotoAndStop(frame);
        man.盾具.gotoAndStop(weaponFrame);
        man.冲撞区域._visible = false;
        light(ctx);
    }

    private static function light(ctx:Object):Void {
        EquipmentLightController.setActionVisual(ctx.unit,"长枪",ctx,ctx.man.盾具,syncLamp);
    }

    private static function syncLamp(ctx:Object):Void {
        var prop:MovieClip = ctx.man.盾具;
        // AS2 alpha writes take ownership of this clip's timeline transform.
        // Use the untouched authored port as the shared geometric authority.
        var portMatrix:flash.geom.Matrix = prop.手电口.transform.matrix;
        if (portMatrix != undefined) {
            prop.灯晕.transform.matrix = portMatrix;
            portMatrix.tx -= 3*portMatrix.c;
            portMatrix.ty -= 3*portMatrix.d;
            prop.装备光束.transform.matrix = portMatrix;
        }
        // A single six-tick local glint at launch, never a looping/full-screen
        // strobe or a second gameplay light/buff. Native illumination stays on.
        var pulse:Number = ctx.phase == "rush" ? Math.max(0,1-ctx.age/6) : 0;
        prop.装备光束._alpha = 100 + 30*pulse;
        prop.灯晕._alpha = 55 + 40*pulse;
    }

    private static function guard(ctx:Object):Void {
        ctx.phase = "hold";ctx.age = 0;
        pose(ctx,16,15);
        var p:Object = ctx.tune;
        // Scoped man marker supplies interruption resistance without writing
        // unit.刚体 or taking ownership of another skill's rigid-body source.
        var tag:MovieClip = ctx.man.createEmptyMovieClip("刚体标签",ctx.man.getNextHighestDepth());
        tag._visible = false;
        ctx.rigid = tag;
        var lifetime:Number = p.maxChargeFrames+RUN_FRAMES*p.maxRushLoops+8;
        _root.技能函数.霸体减伤(ctx.unit,p.reduction,lifetime,BUFF_SOURCE);
        ctx.unit.buffManager.update(0);
        // Preserve the concrete layer: AdaptiveShield may otherwise flatten it,
        // leaving an old reference unable to retire precisely this cast's shield.
        if (ctx.shieldCapacity > 0 && ctx.unit.shield === ctx.shieldContainer &&
                typeof ctx.shieldContainer.addShield == "function") {
            var layer:Shield = Shield.createTemporary(ctx.shieldCapacity,ctx.shieldCapacity,lifetime,NAME);
            if (ctx.shieldContainer.addShield(layer,true)) ctx.shieldLayer = layer;
        }
        ctx.guarded = true;
        chargeMark(ctx);
    }

    private static function chargeMark(ctx:Object):Void {
        var man:MovieClip = ctx.man;
        if (!man.蓄力标记) man.createEmptyMovieClip("蓄力标记",man.getNextHighestDepth());
        var bar:MovieClip = man.蓄力标记;
        var level:Number = chargeLevel(ctx.charge,ctx.tune);
        bar.clear();
        // One lit segment per available run loop, including tap's first loop.
        for (var i:Number=0;i<ctx.tune.maxRushLoops;i++) {
            var x:Number = 115+i*12;
            bar.beginFill(i<level ? 0xAECAC4 : 0x343B3B,90);
            bar.moveTo(x,-145);bar.lineTo(x+9,-145);bar.lineTo(x+9,-139);bar.lineTo(x,-139);bar.lineTo(x,-145);
            bar.endFill();
        }
    }

    private static function beginRush(ctx:Object):Void {
        var p:Object = ctx.tune;
        ctx.level=chargeLevel(ctx.charge,p);
        ctx.ratio = p.maxRushLoops>1 ? (ctx.level-1)/(p.maxRushLoops-1) : 0;
        ctx.rushLength = RUN_FRAMES*ctx.level;
        ctx.multiplier = p.powerMultiplier+p.chargedPower*ctx.ratio;
        ctx.phase = "rush";ctx.age = 0;
        resetSweep(ctx);
        ctx.man.蓄力标记.removeMovieClip();
        pose(ctx,RUN_START,15);
        _root.播放音效("speed07.wav");
    }

    private static function impact(ctx:Object,bounds:Object):Void {
        var power:Number = ctx.defenseAtCast*ctx.multiplier;
        // Zero/invalid defense retains the movement and reduction utility but
        // must never emit zero, NaN or infinite damage into combat settlement.
        if (!(power > 0) || !isFinite(power)) return;
        var u:MovieClip = ctx.unit;
        var previous:Object = ctx.lastImpactBounds;
        var a:Object={x:Math.min(previous.xMin,bounds.xMin),y:Math.min(previous.yMin,bounds.yMin)};
        var z:Object={x:Math.max(previous.xMax,bounds.xMax),y:Math.max(previous.yMax,bounds.yMax)};
        ctx.world.localToGlobal(a);ctx.world.localToGlobal(z);
        ctx.man.globalToLocal(a);ctx.man.globalToLocal(z);
        var area:MovieClip = ctx.man.扫掠判定;
        if (!area) area=ctx.man.createEmptyMovieClip("扫掠判定",ctx.man.getNextHighestDepth());
        area._visible=false;area.clear();area.beginFill(0,0);
        area.moveTo(a.x,a.y);area.lineTo(z.x,a.y);area.lineTo(z.x,z.y);area.lineTo(a.x,z.y);area.lineTo(a.x,a.y);area.endFill();
        var props:Object = _root.子弹属性初始化(area,"近战子弹",u);
        props.子弹威力 = power;
        var baseVampirism:Number = Number(u.基础吸血);
        if (!(baseVampirism > 0) || !isFinite(baseVampirism)) baseVampirism = 0;
        // The standard initializer merges this with actor lifesteal by max,
        // so base + gun is counted once and stronger live effects still win.
        props.吸血 = baseVampirism+ctx.weaponVampirism;
        props.霰弹值 = 1;props.子弹散射度 = 0;props.子弹速度 = 0;
        props.角度偏移=ctx.direction==u.方向 ? 0 : 180;
        // Cover the traversed depth interval as well as its screen-space box.
        props.shootZ=(ctx.lastImpactZ+ctx.pendingZ)*.5;
        props.Z轴攻击范围 = ctx.tune.zRange+Math.abs(ctx.pendingZ-ctx.lastImpactZ)*.5;
        props.区域定位area = area;
        props.击倒率 = .25;
        props.水平击退速度 = ctx.tune.knockback+ctx.tune.chargedKnockback*ctx.ratio;
        props.垂直击退速度 = 0;
        props.击中地图效果 = "";props.击中后子弹的效果 = "空手攻击火花";
        _root.子弹区域shoot传递(props);
        ctx.hits++;
    }

    private static function removeGuard(ctx:Object):Void {
        if (!ctx.guarded) return;
        ctx.guarded = false;
        // A plain Shield object never retargets like a MovieClip. Expire this
        // layer even after an old man unloads, without clearing a newer cast or
        // another equipment shield. The pooled container is touched only when
        // it still holds this exact ID/reference.
        var layer:Shield = ctx.shieldLayer;
        if (layer != null) {
            if (ctx.shieldContainer.getShieldById(layer.getId()) === layer) {
                ctx.shieldContainer.removeShield(layer);
            }
            layer.setActive(false);
            delete ctx.shieldLayer;
        }
        // AVM1 MovieClip paths can retarget after replacement. The old callback
        // must never revoke a new cast's buff or its same-named marker.
        if (ctx.unit.__sheriffShieldRush === ctx) {
            _root.技能函数.移除霸体减伤(ctx.unit,BUFF_SOURCE);
            ctx.unit.buffManager.update(0);
        }
        if (ctx.man.__sheriffRushToken === ctx) ctx.rigid.removeMovieClip();
    }

    public static function cleanup(ctx:Object):Void {
        if (!ctx || ctx.cleaned) return;
        ctx.cleaned = true;
        ctx.pending = false;
        removeGuard(ctx);
        EquipmentLightController.clearActionVisual(ctx.unit,"长枪",ctx);
        var man:MovieClip = ctx.man;
        if (man.__sheriffRushToken === ctx) {
            delete man.onEnterFrame;
            man.蓄力标记.removeMovieClip();
            man.扫掠判定.removeMovieClip();
        }
        if (ctx.unit.__sheriffShieldRush === ctx) delete ctx.unit.__sheriffShieldRush;
    }
}
