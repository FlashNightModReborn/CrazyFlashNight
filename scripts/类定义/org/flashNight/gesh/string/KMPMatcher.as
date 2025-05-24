class org.flashNight.gesh.string.KMPMatcher {
    private var pattern:String;
    private var pmt:Array;

    // 构造函数，初始化模式字符串和部分匹配表
    public function KMPMatcher(pattern:String) {
        this.pattern = pattern;
        this.pmt = computePMT(pattern);
    }

    // 计算部分匹配表（Partial Match Table）
    private function computePMT(pattern:String):Array {
        var pmt:Array = [];
        var j:Number = 0;
        pmt[0] = 0; // PMT的第一个值总是0

        for (var i:Number = 1; i < pattern.length; i++) {
            while (j > 0 && pattern.charAt(i) != pattern.charAt(j)) {
                j = pmt[j - 1];
            }
            if (pattern.charAt(i) == pattern.charAt(j)) {
                j++;
            }
            pmt[i] = j;
        }

        return pmt;
    }

    // KMP搜索算法
    public function search(text:String):Number {
        var j:Number = 0;

        for (var i:Number = 0; i < text.length; i++) {
            while (j > 0 && text.charAt(i) != pattern.charAt(j)) {
                j = pmt[j - 1];
            }
            if (text.charAt(i) == pattern.charAt(j)) {
                j++;
                if (j == pattern.length) {
                    return i - j + 1; // 匹配成功，返回模式在文本中的起始索引
                }
            }
        }
        return -1; // 如果没有找到匹配，返回-1
    }
}