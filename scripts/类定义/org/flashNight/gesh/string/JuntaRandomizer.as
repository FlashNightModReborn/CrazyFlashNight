// 保存为 org/flashNight/gesh/string/JuntaRandomizer.as
class org.flashNight.gesh.string.JuntaRandomizer {
    private static var juntaNames:Array;
    private static var currentPool:Array;
    private static var initialized:Boolean = false;
    
    private static function initialize():Void {
        if (!initialized) {
            // 军阀巨大多部队名称
            juntaNames = [
                "赤龙小组", "镇爆部队", "金色军团", "核武小组", "114合成营", "第一近卫军团", "长生军",
                "烈火小组", "快速机动部队", "独狼之师", "铁锤小组", "尘都治安部队", "整编CSSF部队", "11空降部队",
                "沙地组织", "卫国旅", "荒漠秩序部队", "太平洋协作部队", "东南A洲维和部队", "高原突击部队", "破垒专业小组",
                "长枪旅", "橙色军团", "商队护卫部队", "猛虎军团", "曼陀罗旅", "霸王花小组", "黻城治安部队"
            ];
            resetPool();
            initialized = true;
        }
    }
    
    private static function resetPool():Void {
        currentPool = juntaNames.slice();
        // Fisher-Yates洗牌算法
        var i:Number = currentPool.length;
        while (--i) {
            var j:Number = Math.floor(Math.random() * (i + 1));
            var temp = currentPool[i];
            currentPool[i] = currentPool[j];
            currentPool[j] = temp;
        }
    }
    
    public static function getRandomName():String {
        initialize();
        if (currentPool.length < 1) {
            resetPool();
        }
        return String(currentPool.pop());
    }
    
    // 防止实例化
    private function JuntaRandomizer() {} 
}