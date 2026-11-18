/** A07 presentation adapter. The encounter continues to own movement and emission. */
class org.flashNight.arki.scene.Cf6RoadsterPresentation {
    private static var config:Object = {circumference:200.09555912666826,count:32,fullSpinTurnsPerTick:0.08,maxSpinCount:29.0,spinDownRate:0.33,spinUpAmount:5.0};
    private static var parts:Array = [["part01","nearGunFrame",null],["part02","nearGunFrame",null],["part03","nearGunFrame",null],["part04","nearGunFrame",null],["part05","nearGunFrame",null],["part06","nearGunFrame",null],["part08","farGunFrame",null],["part09","farGunFrame",null],["part10","farGunFrame",null],["part11","farGunFrame",null],["part12","farGunFrame",null],["part13","farGunFrame",null],["part14","wheelFrame","wheel14Blur"],["part15","wheelFrame","wheel15Blur"],["part17","wheelFrame",null],["part19","wheelFrame","wheel19Blur"],["part20","wheelFrame","wheel20Blur"],["part22","wheelFrame",null]];
    private static var roadSteps:Array = [-19.1,-19.1,-19.1,-19.1,-19.15,-19.05,-19.1,-19.15,-19.1,-19.1,-19.1,-19.1,-19.1,-19.1,-19.1,-19.1,-19.1,-19.1,-19.1,-19.1,-19.1,-19.1,-19.15,-19.1,-19.1,-19.1,-19.1,-19.1,-19.1,-19.1,-19.1,-19.1,-19.1,-19.1,-19.1,-19.1,-19.1,-19.1,-19.1,-19.1,-19.15,-19.1,-19.1,-19.1,-19.1,-19.1,-19.1,-19.1,-19.1];
    private static var wheelBlurEnabled:Boolean = true;

    public static function begin(session:Object):Boolean {
        var visual:MovieClip = session.player.p1.roadster;
        if (typeof visual != "movieclip") return false;
        var routes:Array = parts;
        var count:Number = config.count;
        for (var i:Number = 0; i < routes.length; i++) {
            var route:Array = routes[i];
            var part:MovieClip = visual[route[0]];
            if (typeof part != "movieclip" || part._totalframes !== count) return false;
            if (route[2] != null && typeof visual[route[2]] != "movieclip") return false;
        }
        var clock:Object = org.flashNight.arki.scene.RoadsterPhaseClock.create(config);
        if (clock == null) return false;
        session.roadsterClock = clock;
        session.roadsterWheelBlur = -1;
        apply(session, visual, org.flashNight.arki.scene.RoadsterPhaseClock.pose(clock), 0);
        return true;
    }

    private static function apply(session:Object, visual:MovieClip, pose:Object, blur:Number):Void {
        var routes:Array = parts;
        var count:Number = routes.length;
        var blendChanged:Boolean = wheelBlurEnabled && session.roadsterWheelBlur !== blur;
        for (var i:Number = 0; i < count; i++) {
            var route:Array = routes[i];
            var part:MovieClip = visual[route[0]];
            var wheel:Boolean = wheelBlurEnabled && route[1] === "wheelFrame";
            if (!wheel || blur < 100) {
                var frame:Number = pose[route[1]];
                if (part._currentframe !== frame) part.gotoAndStop(frame);
            }
            if (wheel && blendChanged) {
                var softened:MovieClip = route[2] == null ? null : visual[route[2]];
                org.flashNight.arki.scene.RoadsterWheelBlend.apply(part, softened, blur);
            }
        }
        session.roadsterWheelBlur = blur;
    }

    public static function advance(session:Object, heroDistance:Number,
                                   roadFrameBefore:Number, emissions:Number):Void {
        var clock:Object = session.roadsterClock;
        var scroll:Number = session.road._currentframe === roadFrameBefore ? 0 : roadSteps[roadFrameBefore - 1];
        var groundDistance:Number = heroDistance - scroll;
        if (org.flashNight.arki.scene.RoadsterPhaseClock.step(clock, false, groundDistance,
                (emissions & 1) !== 0, (emissions & 2) !== 0)) {
            var blur:Number = wheelBlurEnabled
                ? org.flashNight.arki.scene.RoadsterWheelBlend.percent(groundDistance, clock.count / clock.circumference) : 0;
            apply(session, session.player.p1.roadster, org.flashNight.arki.scene.RoadsterPhaseClock.pose(clock), blur);
        }
    }

    public static function close(session:Object):Void {
        org.flashNight.arki.scene.RoadsterPhaseClock.close(session.roadsterClock);
        session.roadsterClock = null;
        session.roadsterWheelBlur = 0;
    }
}
