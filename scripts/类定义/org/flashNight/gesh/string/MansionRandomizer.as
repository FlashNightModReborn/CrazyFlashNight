// 保存为 org/flashNight/gesh/string/MansionRandomizer.as
class org.flashNight.gesh.string.MansionRandomizer {
    private static var mansionNames:Array;
    private static var currentPool:Array;
    private static var initialized:Boolean = false;

    // 初始化函数
    private static function initialize():Void {
        if (!initialized) {
            // 二十八宿的名称
            mansionNames = [
                "角木蛟", "亢金龙", "氐土貉", "房日兔", "心月狐", "尾火虎", "箕水豹", 
                "斗木獬", "牛金牛", "女土蝠", "虚日鼠", "危月燕", "室火猪", "壁水獺", 
                "奎木狼", "娄金狗", "胃土雉", "昴日鸡", "毕月乌", "觜火猴", "参水猿", 
                "井土狗", "鬼金羊", "柳木猴", "星日马", "张月鹿", "翼火蛇", "轸水蚓"
            ];
            resetPool();
            initialized = true;
        }
    }

    // 重置当前池
    private static function resetPool():Void {
        currentPool = mansionNames.slice();
        // Fisher-Yates洗牌算法
        var i:Number = currentPool.length;
        while (--i) {
            var j:Number = Math.floor(Math.random() * (i + 1));
            var temp = currentPool[i];
            currentPool[i] = currentPool[j];
            currentPool[j] = temp;
        }
    }

    // 获取随机的二十八宿名称
    public static function getRandomName():String {
        initialize();
        if (currentPool.length < 1) {
            resetPool();
        }
        return String(currentPool.pop());
    }

    // 防止实例化
    private function MansionRandomizer() {}
}
