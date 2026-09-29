import org.flashNight.naki.RandomNumberEngine.BaseRandomNumberEngine;
import org.flashNight.naki.RandomNumberEngine.SeededLinearCongruentialEngine;

// 只供表现使用。预算、剔除和显示端切换不消费战斗 RNG。
class org.flashNight.arki.render.VisualRandom {
    private static var seed:Number = new Date().getTime() % 2147483646;
    private static var serial:Number = 0;
    private static var engine:BaseRandomNumberEngine = new SeededLinearCongruentialEngine(seed);

    public static function getEngine():BaseRandomNumberEngine { return engine; }

    // 与战斗 Math.random / BaseRandomNumberEngine 单例分离；供遗留表现路径使用。
    public static function nextFloat():Number { return engine.nextFloat(); }

    // 在实际发射路径先编号，再判显示预算；不随显示成功数量编号。
    public static function eventSeed(kind:Number):Number {
        serial = (serial + 1) % 1000000000;
        return Math.floor((serial * 1664525 + seed + kind * 1013904223) % 2147483646) + 1;
    }
}
