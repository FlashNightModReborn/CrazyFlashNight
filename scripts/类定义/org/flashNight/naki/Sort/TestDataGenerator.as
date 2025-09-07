class org.flashNight.naki.Sort.TestDataGenerator {
    
    /**
     * 生成随机数组
     */
    public static function random(n:Number):Array {
        var a:Array = [];
        for(var i:Number = 0; i < n; i++) {
            a[i] = Math.floor(Math.random() * n);
        }
        return a;
    }
    
    /**
     * 生成已排序数组
     */
    public static function sorted(n:Number):Array {
        var a:Array = [];
        for(var i:Number = 0; i < n; i++) {
            a[i] = i;
        }
        return a;
    }
    
    /**
     * 生成逆序数组
     */
    public static function reversed(n:Number):Array {
        var a:Array = [];
        for(var i:Number = 0; i < n; i++) {
            a[i] = n - i;
        }
        return a;
    }
    
    /**
     * 生成近乎有序的数组
     * @param n 数组大小
     * @param swaps 交换次数
     */
    public static function nearlySorted(n:Number, swaps:Number):Array {
        var a:Array = sorted(n);
        for(var i:Number = 0; i < swaps; i++) {
            var x:Number = Math.floor(Math.random() * n);
            var y:Number = Math.floor(Math.random() * n);
            var temp:Number = a[x];
            a[x] = a[y];
            a[y] = temp;
        }
        return a;
    }
    
    /**
     * 生成锯齿波数组
     * @param n 数组大小
     * @param period 锯齿周期
     * 典型 period=4 => 0,1,2,3,2,1,0,1,2,3,2,1...
     */
    public static function sawtooth(n:Number, period:Number):Array {
        var a:Array = [];
        for(var i:Number = 0; i < n; i++) {
            var cyclePos:Number = i % (period * 2);  // 完整周期长度是period*2
            if (cyclePos < period) {
                // 上升阶段：0,1,2,3...
                a[i] = cyclePos;
            } else {
                // 下降阶段：2,1,0...
                a[i] = (period * 2 - 1) - cyclePos;
            }
        }
        return a;
    }
    
    /**
     * 生成风琴管数组（中间最大，向两侧递减）
     * 例如：n=10 => [0,1,2,3,4,4,3,2,1,0]
     */
    public static function organPipe(n:Number):Array {
        var a:Array = [];
        var mid:Number = Math.floor(n / 2);
        for(var i:Number = 0; i < n; i++) {
            if (i <= mid) {
                a[i] = i;  // 前半部分递增
            } else {
                a[i] = n - 1 - i;  // 后半部分递减
            }
        }
        return a;
    }
    
    /**
     * 生成交错数组
     * @param n 数组大小
     * @param k 交错步长
     */
    public static function stagger(n:Number, k:Number):Array {
        var a:Array = [];
        for(var i:Number = 0; i < n; i++) {
            a[i] = (i % k) * Math.ceil(n / k) + Math.floor(i / k);
        }
        return a;
    }
    
    /**
     * 生成包含大量重复值的数组
     * @param n 数组大小
     * @param distinctK 不同值的数量
     */
    public static function manyDuplicates(n:Number, distinctK:Number):Array {
        var a:Array = [];
        for(var i:Number = 0; i < n; i++) {
            a[i] = Math.floor(Math.random() * distinctK);
        }
        return a;
    }
    
    /**
     * 生成打乱的块数组
     * @param n 数组大小
     * @param blockSize 块大小
     */
    public static function shuffledBlocks(n:Number, blockSize:Number):Array {
        var a:Array = [];
        
        // 先生成块标签
        for(var i:Number = 0; i < n; i++) {
            a[i] = Math.floor(i / blockSize);
        }
        
        // 创建块标签数组并打乱
        var blockCount:Number = Math.ceil(n / blockSize);
        var blocks:Array = [];
        for(var j:Number = 0; j < blockCount; j++) {
            blocks[j] = j;
        }
        
        // Fisher-Yates洗牌
        for(var k:Number = blockCount - 1; k > 0; k--) {
            var r:Number = Math.floor(Math.random() * (k + 1));
            var temp:Number = blocks[k];
            blocks[k] = blocks[r];
            blocks[r] = temp;
        }
        
        // 映射回数组
        for(var m:Number = 0; m < n; m++) {
            a[m] = blocks[a[m]] * blockSize + (m % blockSize);
        }
        
        return a;
    }
    
    /**
     * 生成所有元素相同的数组
     */
    public static function allSame(n:Number):Array {
        var a:Array = [];
        for(var i:Number = 0; i < n; i++) {
            a[i] = 42;
        }
        return a;
    }
    
    /**
     * 生成交替模式数组（棋盘格）
     */
    public static function alternating(n:Number):Array {
        var a:Array = [];
        for(var i:Number = 0; i < n; i++) {
            a[i] = (i % 2 === 0) ? 0 : n;
        }
        return a;
    }
    
    /**
     * 获取所有测试分布的名称
     */
    public static function getAllDistributions():Array {
        return ["random", "sorted", "reversed", "nearlySorted", "sawtooth2", 
                "sawtooth4", "sawtooth8", "organPipe", "stagger", 
                "manyDuplicates", "allSame", "alternating"];
    }
    
    /**
     * 根据名称生成数组
     */
    public static function generate(n:Number, distribution:String):Array {
        var result;
        
        if (distribution == "random") {
            result = random(n);
        } else if (distribution == "sorted") {
            result = sorted(n);
        } else if (distribution == "reversed") {
            result = reversed(n);
        } else if (distribution == "nearlySorted") {
            result = nearlySorted(n, Math.floor(n * 0.01));
        } else if (distribution == "sawtooth2") {
            result = sawtooth(n, 2);
        } else if (distribution == "sawtooth4") {
            result = sawtooth(n, 4);
        } else if (distribution == "sawtooth8") {
            result = sawtooth(n, 8);
        } else if (distribution == "organPipe") {
            result = organPipe(n);
        } else if (distribution == "stagger") {
            result = stagger(n, 7);
        } else if (distribution == "manyDuplicates") {
            result = manyDuplicates(n, 5);
        } else if (distribution == "allSame") {
            result = allSame(n);
        } else if (distribution == "alternating") {
            result = alternating(n);
        } else {
            result = random(n); // default
        }
        
        return result;
    }
}