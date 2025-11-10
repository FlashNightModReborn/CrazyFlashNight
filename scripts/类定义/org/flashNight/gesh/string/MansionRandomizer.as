import org.flashNight.gesh.string.*;
import org.flashNight.naki.RandomNumberEngine.*;

class org.flashNight.gesh.string.MansionRandomizer extends BaseNameRandomizer {
    private static var instance:MansionRandomizer;
    private static var mansionNames:Array;
    private static var initialized:Boolean = false;

    private static function ensureNames(target:MansionRandomizer):Void {
        if (!initialized) {
            mansionNames = [
                "角木蛟", "亢金龙", "氐土貉", "房日兔", "心月狐", "尾火虎", "箕水豹", 
                "斗木獬", "牛金牛", "女土蝠", "虚日鼠", "危月燕", "室火猪", "壁水獺", 
                "奎木狼", "娄金狗", "胃土雉", "昴日鸡", "毕月乌", "觜火猴", "参水猿", 
                "井土狗", "鬼金羊", "柳木猴", "星日马", "张月鹿", "翼火蛇", "轸水蚓"
            ];

            initialized = true;
        }

        target.setNames(mansionNames);
    }

    public static function getInstance():MansionRandomizer {
        if (instance == null) {
            instance = new MansionRandomizer();
            getInstance = function():MansionRandomizer {
                return instance;
            };
        }
        return instance;
    }

    private function MansionRandomizer() {
        setRandomEngine(LinearCongruentialEngine.getInstance());
        setUniqueUntilExhaustion(true);
        ensureNames(this);
    }
}
