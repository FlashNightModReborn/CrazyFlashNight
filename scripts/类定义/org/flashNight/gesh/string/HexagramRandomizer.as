// 保存为 org/flashNight/gesh/string/HexagramRandomizer.as
class org.flashNight.gesh.string.HexagramRandomizer {
    private static var hexagramNames:Array;
    private static var currentPool:Array;
    private static var initialized:Boolean = false;
    
    private static function initialize():Void {
        if (!initialized) {
            // 六十四卦标准名称
            hexagramNames = [
                "乾为天", "坤为地", "水雷屯", "山水蒙", "水天需", "天水讼", "地水师",
                "水地比", "风天小畜", "天泽履", "地天泰", "天地否", "天火同人", "火天大有",
                "地山谦", "雷地豫", "泽雷随", "山风蛊", "地泽临", "风地观", "火雷噬嗑",
                "山火贲", "山地剥", "地雷复", "天雷无妄", "山天大畜", "山雷颐", "泽风大过",
                "坎为水", "离为火", "泽山咸", "雷风恒", "天山遯", "雷天大壮", "火地晋",
                "地火明夷", "风火家人", "火泽睽", "水山蹇", "雷水解", "山泽损", "风雷益",
                "泽天夬", "天风姤", "泽地萃", "地风升", "泽水困", "水风井", "泽火革",
                "火风鼎", "震为雷", "艮为山", "风山渐", "雷泽归妹", "雷火丰", "火山旅",
                "巽为风", "兑为泽", "风水涣", "水泽节", "风泽中孚", "雷山小过", "水火既济",
                "火水未济"
            ];
            resetPool();
            initialized = true;
        }
    }
    
    private static function resetPool():Void {
        currentPool = hexagramNames.slice();
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
    private function HexagramRandomizer() {} 
}