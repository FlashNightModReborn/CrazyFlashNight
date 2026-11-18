/**
 * Unwired offline template. No display, input, health, reward or save authority.
 * One step per active vehicle simulation tick, after successful-shot results.
 * groundDistance is signed, unwrapped travel relative to the road, in the same
 * source units as circumference. Never pass camera motion or wrapped tile X.
 * Shot flags coalesce successful emissions per gun/tick, like M134's isFiring.
 * held drops this tick's inputs and freezes phase AND spin; it queues nothing.
 * The caller closes on death/disposal and creates a fresh clock on new life.
 * Full-spin turns/tick requires calibration; there is no assumed frame ratio.
 */
class org.flashNight.arki.scene.RoadsterPhaseClock {
    private static function finite(value:Number):Boolean {
        return typeof value=="number" && !isNaN(value) && value!=Infinity && value!=-Infinity;
    }

    public static function create(config:Object):Object {
        if(config==null) return null;
        var count:Number=config.count;
        var fullStep:Number=count*config.fullSpinTurnsPerTick;
        if(!org.flashNight.arki.scene.RoadsterPhaseClock.finite(count)
                || Math.floor(count)!=count || count<1 || count>256
                || !org.flashNight.arki.scene.RoadsterPhaseClock.finite(config.circumference)
                || !(config.circumference>0)
                || !org.flashNight.arki.scene.RoadsterPhaseClock.finite(config.fullSpinTurnsPerTick)
                || !(config.fullSpinTurnsPerTick>0)
                || !org.flashNight.arki.scene.RoadsterPhaseClock.finite(fullStep)
                || !(fullStep>0)
                || !org.flashNight.arki.scene.RoadsterPhaseClock.finite(config.maxSpinCount)
                || !(config.maxSpinCount>0)
                || !org.flashNight.arki.scene.RoadsterPhaseClock.finite(config.spinUpAmount)
                || !(config.spinUpAmount>0)
                || !org.flashNight.arki.scene.RoadsterPhaseClock.finite(config.spinDownRate)
                || !(config.spinDownRate>0)) return null;
        return {count:count,circumference:config.circumference,fullStep:fullStep,
            maxSpinCount:config.maxSpinCount,spinUpAmount:config.spinUpAmount,
            spinDownRate:config.spinDownRate,wheel:0,nearPhase:0,farPhase:0,
            nearSpin:0,farSpin:0,closed:false};
    }

    private static function phase(value:Number, count:Number):Boolean {
        return org.flashNight.arki.scene.RoadsterPhaseClock.finite(value) && value>=0 && value<count;
    }

    private static function valid(clock:Object):Boolean {
        return clock!=null && clock.closed===false
            && org.flashNight.arki.scene.RoadsterPhaseClock.finite(clock.count)
            && Math.floor(clock.count)==clock.count && clock.count>=1 && clock.count<=256
            && org.flashNight.arki.scene.RoadsterPhaseClock.finite(clock.circumference) && clock.circumference>0
            && org.flashNight.arki.scene.RoadsterPhaseClock.finite(clock.fullStep) && clock.fullStep>0
            && org.flashNight.arki.scene.RoadsterPhaseClock.finite(clock.maxSpinCount) && clock.maxSpinCount>0
            && org.flashNight.arki.scene.RoadsterPhaseClock.finite(clock.spinUpAmount) && clock.spinUpAmount>0
            && org.flashNight.arki.scene.RoadsterPhaseClock.finite(clock.spinDownRate) && clock.spinDownRate>0
            && org.flashNight.arki.scene.RoadsterPhaseClock.phase(clock.wheel,clock.count)
            && org.flashNight.arki.scene.RoadsterPhaseClock.phase(clock.nearPhase,clock.count)
            && org.flashNight.arki.scene.RoadsterPhaseClock.phase(clock.farPhase,clock.count)
            && org.flashNight.arki.scene.RoadsterPhaseClock.finite(clock.nearSpin)
            && clock.nearSpin>=0 && clock.nearSpin<=clock.maxSpinCount
            && org.flashNight.arki.scene.RoadsterPhaseClock.finite(clock.farSpin)
            && clock.farSpin>=0 && clock.farSpin<=clock.maxSpinCount;
    }

    private static function wrap(value:Number, count:Number):Number {
        var phase:Number=value%count;
        // Tiny negative remainders can round phase+count to count itself.
        if(phase<0) phase+=count;
        return phase==count?0:phase;
    }

    public static function step(clock:Object, held:Boolean, groundDistance:Number,
                                nearShot:Boolean, farShot:Boolean):Boolean {
        if(!org.flashNight.arki.scene.RoadsterPhaseClock.valid(clock)
                || (held!==true && held!==false)) return false;
        if(held===true) return true;
        if(!org.flashNight.arki.scene.RoadsterPhaseClock.finite(groundDistance)
                || (nearShot!==true && nearShot!==false)
                || (farShot!==true && farShot!==false)) return false;
        var count:Number=clock.count, maximum:Number=clock.maxSpinCount;
        var up:Number=clock.spinUpAmount, down:Number=clock.spinDownRate;
        var nearSpin:Number=nearShot?Math.min(clock.nearSpin+up,maximum):Math.max(0,clock.nearSpin-down);
        var farSpin:Number=farShot?Math.min(clock.farSpin+up,maximum):Math.max(0,clock.farSpin-down);
        var wheel:Number=org.flashNight.arki.scene.RoadsterPhaseClock.wrap(
            clock.wheel+(groundDistance/clock.circumference)*count,count);
        var nearPhase:Number=org.flashNight.arki.scene.RoadsterPhaseClock.wrap(
            clock.nearPhase+(nearSpin/maximum)*clock.fullStep,count);
        var farPhase:Number=org.flashNight.arki.scene.RoadsterPhaseClock.wrap(
            clock.farPhase+(farSpin/maximum)*clock.fullStep,count);
        // Validate all derived values before mutating any field.
        if(!org.flashNight.arki.scene.RoadsterPhaseClock.phase(wheel,count)
                || !org.flashNight.arki.scene.RoadsterPhaseClock.phase(nearPhase,count)
                || !org.flashNight.arki.scene.RoadsterPhaseClock.phase(farPhase,count)) return false;
        clock.wheel=wheel;clock.nearPhase=nearPhase;clock.farPhase=farPhase;
        clock.nearSpin=nearSpin;clock.farSpin=farSpin;
        return true;
    }

    public static function pose(clock:Object):Object {
        if(!org.flashNight.arki.scene.RoadsterPhaseClock.valid(clock)) return null;
        return {wheelFrame:Math.floor(clock.wheel)+1,
            nearGunFrame:Math.floor(clock.nearPhase)+1,farGunFrame:Math.floor(clock.farPhase)+1};
    }

    public static function close(clock:Object):Void {
        if(clock!=null) clock.closed=true;
    }
}
