import org.flashNight.arki.scene.*;

/**
 * 外置大脑全局初始器
 * 负责对各种单例和静态对象进行初始化，防止初始化顺序不一导致的冲突。
 * 由于在gesh包中，并且是外置大脑第一个执行的类，所以也可以叫做原神启动器
 */
class org.flashNight.gesh.init.GlobalInitializer{
    private static var initialized:Boolean;

    private function GlobalInitializer(){
    }

    public static function initialize():Void{
        if(initialized) return;
        // arki.scene
        SceneManager.getInstance();
        StageManager.getInstance();
        WaveSpawner.getInstance();
        WaveSpawnWheel.getInstance();

        initialized = true;
    }
}
