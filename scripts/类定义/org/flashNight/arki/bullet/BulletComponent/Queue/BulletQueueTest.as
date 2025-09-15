// ============================================================================
// BulletQueueTest.as
// org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueTest
// 子弹队列（混合排序）正确性与性能测试套件（类形式）
// - 覆盖多分布、非降序与稳定性断言
// - 输出汇总表与结果对象到 _root.gameworld.BulletQueueBench
// - 不依赖新增 MovieClip，仅用轻量对象模拟 aabbCollider
// ============================================================================

import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueue;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;
 
class org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueTest {

    // -------------------- 对外入口 --------------------
    public static function runSuite(config:Object):Object {
        var self:org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueTest =
            new org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueTest();
        return self._run(config);
    }

    // -------------------- 成员（为了兼容 AS2 环境） --------------------
    private var sizes:Array;
    private var repeats:Number;
    private var results:Array;

    private var assertTotal:Number;
    private var assertFailed:Number;

    private var rngSeed:Number;
    private var rng:LinearCongruentialEngine; // 可复现随机数引擎（LCG）

    // -------------------- 主过程 --------------------
    private function _run(config:Object):Object {
        // 默认配置
        this.sizes   = (config && config.sizes)   ? config.sizes   : [32, 64, 128, 1000, 5000, 10000];
        this.repeats = (config && !isNaN(config.repeats)) ? Number(config.repeats) : 3;

        this.results = [];
        this.assertTotal = 0;
        this.assertFailed = 0;

        if (!_root.gameworld) _root.gameworld = {};
        _root.gameworld.BulletQueueBench = { results: this.results, assertTotal:0, assertFailed:0 };

        log("============================================================");
        log(" BulletQueue 测试/基准开始（类版）");
        log(" sizes=" + this.sizes.join(", ") + "  repeats=" + this.repeats);
        log("============================================================");
        
        // 先运行鲁棒性测试
        // 初始化可复现 RNG（LCG），并设置固定种子，确保测试可控
        this.initRNG();
        this.resetRNG(1234567);
        
        this.runRobustnessTests();

        // 打印表头
        var header:String = padRight("dist",14) + padRight("n",7) + padRight("ms_avg",10) + "ms/1k";
        log(header);
        log("------------------------------------------------------------");

        // 逐分布逐规模跑
        var dists:Array = [
            "ascending", "descending", "random", "nearlySorted",
            "sawtooth", "endsHeavy", "fewUniques", "altHighLow",
            "withInvalid", "allSame"
        ];

        // 固定随机种子，保证可复现
        this.resetRNG(1234567);

        for (var i:Number = 0; i < dists.length; i++) {
            var dist:String = dists[i];
            for (var s:Number = 0; s < this.sizes.length; s++) {
                var n:Number = this.sizes[s];
                var r:Object = this.runOneCase(dist, n);
                // 打印行
                var line:String = padRight(dist,14)
                                + padRight(String(n),7)
                                + padRight(String(Math.round(r.ms*100)/100),10)
                                + String(Math.round(r.msPer1k*100)/100);
                log(line);
                this.results.push(r);
            }
        }

        log("------------------------------------------------------------");
        log(" 断言统计: total=" + this.assertTotal + ", failed=" + this.assertFailed);
        if (this.assertFailed == 0) log(" ✅ 全部断言通过");
        else log(" ❌ 存在断言失败，请检查上方 FAIL 日志");

        log("============================================================");
        log(" 完成，结果已写入 _root.gameworld.BulletQueueBench.results");
        log("============================================================");

        _root.gameworld.BulletQueueBench.assertTotal  = this.assertTotal;
        _root.gameworld.BulletQueueBench.assertFailed = this.assertFailed;

        return _root.gameworld.BulletQueueBench;
    }

    // -------------------- 单个用例（正确性+计时） --------------------
    private function runOneCase(dist:String, n:Number):Object {
        var msTotal:Number = 0;

        // 正确性：选一轮严格断言 + 若干轮计时平滑
        var base:Array = this.makeData(dist, n);
        var q:BulletQueue = new BulletQueue();
        // 填充
        for (var i:Number = 0; i < base.length; i++) this.queueAdd(q, base[i]);

        // 排序并取数组
        var t0:Number = nowMS();
        var it:Object = this.queueIter(q);
        var t1:Number = nowMS();

        var arr:Array = (it && it.bullets) ? it.bullets : q["bullets"]; // 尝试读取 bullets（若可访问）
        var L:Number = (it && it.length != undefined) ? it.length : (arr ? arr.length : 0);

        // --- 正确性断言 ---
        // 非降序
        var okAsc:Boolean = true;
        for (var k:Number=1;k<L;k++){
            if (arr[k-1].aabbCollider.left > arr[k].aabbCollider.left) { okAsc=false; break; }
        }
        assertTrue(okAsc, dist+" n="+n+" 应为非降序");

        // 稳定性（相等键相对顺序不变）
        var stable:Boolean = true;
        for (var k2:Number=1;k2<L;k2++){
            var prev:Object = arr[k2-1], cur:Object = arr[k2];
            if (prev.aabbCollider.left == cur.aabbCollider.left) {
                if (prev.__id > cur.__id) { stable=false; break; }
            }
        }
        assertTrue(stable, dist+" n="+n+" 相等键保持原相对顺序（稳定排序）");

        msTotal += (t1 - t0);

        // 额外重复计时
        for (var r:Number=1;r<this.repeats;r++){
            var base2:Array = this.makeData(dist, n);
            var q2:BulletQueue = new BulletQueue();
            for (var j:Number=0;j<base2.length;j++) this.queueAdd(q2, base2[j]);

            var t2:Number = nowMS();
            this.queueIter(q2);
            var t3:Number = nowMS();

            msTotal += (t3 - t2);
        }

        var msAvg:Number = msTotal / this.repeats;
        return {
            dist: dist,
            n: n,
            ms: msAvg,
            msPer1k: msAvg / Math.max(1, n) * 1000
        };
    }

    // -------------------- 数据分布 --------------------
    private function makeData(dist:String, n:Number):Array {
        if (dist == "ascending")     return this.genAscending(n);
        if (dist == "descending")    return this.genDescending(n);
        if (dist == "random")        return this.genRandom(n);
        if (dist == "nearlySorted")  return this.genNearlySorted(n, 0.02);
        if (dist == "sawtooth")      return this.genSawtooth(n, Math.max(5, Math.floor(n/20)));
        if (dist == "endsHeavy")     return this.genEndsHeavy(n);
        if (dist == "fewUniques")    return this.genFewUniques(n, Math.max(3, Math.floor(Math.sqrt(n))));
        if (dist == "altHighLow")    return this.genAltHighLow(n);
        if (dist == "withInvalid")   return this.genWithInvalid(n);
        if (dist == "allSame")       return this.genAllSame(n);
        // fallback
        return this.genRandom(n);
    }

    private function makeBullet(left:Number, right:Number, id:Number):Object {
        return {
            aabbCollider: { left: left, right: right },
            __id: id,
            _name: "b"+id
        };
    }

    // 升序
    private function genAscending(n:Number):Array {
        var A:Array = [];
        for (var i:Number=0;i<n;i++) A.push(this.makeBullet(i, i+1, i));
        return A;
    }
    // 逆序
    private function genDescending(n:Number):Array {
        var A:Array = [];
        for (var i:Number=0;i<n;i++) A.push(this.makeBullet(n-1-i, n-i, i));
        return A;
    }
    // 随机
    private function genRandom(n:Number):Array {
        var A:Array = [];
        for (var i:Number=0;i<n;i++) {
            var x:Number = Math.floor(this.rndRange(0, n));
            A.push(this.makeBullet(x, x+1, i));
        }
        return A;
    }
    // 近乎有序（少量交换）
    private function genNearlySorted(n:Number, swapsRate:Number):Array {
        if (swapsRate == undefined) swapsRate = 0.02;
        var A:Array = this.genAscending(n);
        var swaps:Number = Math.max(1, Math.floor(n*swapsRate));
        for (var s:Number=0;s<swaps;s++){
            var i:Number = Math.floor(this.srand()*n);
            var j:Number = Math.floor(this.srand()*n);
            var t:Object = A[i]; A[i]=A[j]; A[j]=t;
        }
        return A;
    }
    // 锯齿波
    private function genSawtooth(n:Number, period:Number):Array {
        if (period == undefined) period = Math.max(5, Math.floor(n/20));
        var A:Array = [];
        for (var i:Number=0;i<n;i++){
            var x:Number = i % period;
            A.push(this.makeBullet(x, x+1, i));
        }
        return A;
    }
    // 两端密集
    private function genEndsHeavy(n:Number):Array {
        var A:Array = [];
        for (var i:Number=0;i<n;i++){
            var r:Number = this.srand();
            var x:Number = (r<0.5) ? Math.floor(this.rndRange(0, n*0.1)) : Math.floor(this.rndRange(n*0.9, n));
            A.push(this.makeBullet(x, x+1, i));
        }
        return A;
    }
    // 少量取值，大量重复
    private function genFewUniques(n:Number, k:Number):Array {
        if (k == undefined) k = Math.max(3, Math.floor(Math.sqrt(n)));
        var A:Array = [];
        for (var i:Number=0;i<n;i++){
            var x:Number = Math.floor(this.srand()*k);
            A.push(this.makeBullet(x, x+1, i));
        }
        return A;
    }
    // 交替高低
    private function genAltHighLow(n:Number):Array {
        var A:Array = [];
        for (var i:Number=0;i<n;i++){
            var x:Number = (i%2==0) ? (n - i) : i;
            A.push(this.makeBullet(x, x+1, i));
        }
        return A;
    }
    
    // 包含无效对象（null, undefined, NaN, 缺失collider）
    private function genWithInvalid(n:Number):Array {
        var A:Array = [];
        for (var i:Number=0;i<n;i++){
            if (i % 5 == 0 && i > 0) {
                // 每5个插入一个异常对象
                var r:Number = this.srand();
                if (r < 0.25) {
                    A.push(null);
                } else if (r < 0.5) {
                    A.push({__id: i, _name: "noCollider"}); // 缺失aabbCollider
                } else if (r < 0.75) {
                    A.push({aabbCollider: {left: NaN, right: NaN}, __id: i});
                } else {
                    A.push({aabbCollider: {left: i, right: NaN}, __id: i});
                }
            } else {
                A.push(this.makeBullet(Math.floor(this.rndRange(0, n)), Math.floor(this.rndRange(0, n))+1, i));
            }
        }
        return A;
    }
    
    // 所有元素相同
    private function genAllSame(n:Number):Array {
        var A:Array = [];
        var value:Number = 50;
        for (var i:Number=0;i<n;i++){
            A.push(this.makeBullet(value, value+1, i));
        }
        return A;
    }

    // -------------------- 方法名适配层 --------------------
    private function queueAdd(q:Object, item:Object):Void {
        var names:Array = ["add", "enqueue", "push", "addBullet", "offer"];
        for (var i:Number=0;i<names.length;i++){
            if (typeof q[names[i]] == "function"){ q[names[i]](item); return; }
        }
        // 兜底：若 bullets 可见
        if (q["bullets"] && q["bullets"].push) q["bullets"].push(item);
    }

    private function queueIter(q:Object):Object {
        var iterNames:Array = ["getSortedIterator", "iterator", "getIterator"];
        for (var i:Number=0;i<iterNames.length;i++){
            if (typeof q[iterNames[i]] == "function") return q[iterNames[i]]();
        }
        // 没有迭代器则尝试触发排序
        var sortNames:Array = ["sortByLeftBoundary", "sort", "resort"];
        for (var j:Number=0;j<sortNames.length;j++){
            if (typeof q[sortNames[j]] == "function"){ q[sortNames[j]](); break; }
        }
        // 构造一个简易迭代器
        var arr:Array = q["bullets"];
        var L:Number = (arr && arr.length != undefined) ? arr.length : 0;
        return { bullets: arr, indices: null, isIndexed:false, length: L };
    }

    // -------------------- 断言系统 --------------------
    private function assertTrue(cond:Boolean, note:String):Void {
        this.assertTotal++;
        if (!cond) {
            this.assertFailed++;
            log("[ASSERT FAIL] " + note);
        }
    }

    // -------------------- 日志/工具 --------------------
    private function log(msg:String):Void {
        if (_root.服务器 && _root.服务器.发布服务器消息) {
            _root.服务器.发布服务器消息(msg);
        } else {
            trace(msg);
        }
    }

    private function padRight(s:String, n:Number):String {
        var r:String = (s == null) ? "" : s;
        while (r.length < n) r += " ";
        return r;
    }

    private function nowMS():Number { return getTimer(); }

    // ========== 可复现 RNG（LCG）封装 ==========
    private function initRNG():Void {
        if (this.rng == null) {
            this.rng = LinearCongruentialEngine.getInstance();
            // 默认参数初始化（与其他测试保持一致的 m）
            this.rng.init(1664525, 1013904223, 4294967296, 12345);
        }
    }
    private function resetRNG(seed:Number):Void {
        if (this.rng == null) this.initRNG();
        this.rng.init(1664525, 1013904223, 4294967296, seed);
        this.rngSeed = seed; // 兼容旧字段（若有外部依赖调试）
    }

    // 简易可复现 RNG（LCG）
    private function srand():Number {
        if (this.rng == null) this.initRNG();
        return this.rng.nextFloat();
    }
    private function rndRange(a:Number, b:Number):Number {
        return a + (b - a) * this.srand();
    }
    
    // -------------------- 鲁棒性测试 --------------------
    private function runRobustnessTests():Void {
        log("");
        log("==================== 鲁棒性测试 ====================");
        
        var robustPass:Number = 0;
        var robustFail:Number = 0;
        
        // 测试1: 空队列
        if (this.testEmptyQueue()) {
            log("[PASS] 空队列测试");
            robustPass++;
        } else {
            log("[FAIL] 空队列测试");
            robustFail++;
        }
        
        // 测试2: 单元素
        if (this.testSingleElement()) {
            log("[PASS] 单元素测试");
            robustPass++;
        } else {
            log("[FAIL] 单元素测试");
            robustFail++;
        }
        
        // 测试3: 边界值(63/64/65)
        if (this.testBoundaryValues()) {
            log("[PASS] 边界值测试(63/64/65)");
            robustPass++;
        } else {
            log("[FAIL] 边界值测试");
            robustFail++;
        }
        
        // 测试4: clear()方法
        if (this.testClearMethod()) {
            log("[PASS] clear()方法测试");
            robustPass++;
        } else {
            log("[FAIL] clear()方法测试");
            robustFail++;
        }
        
        // 测试5: 缓冲区扩容
        if (this.testBufferResize()) {
            log("[PASS] 缓冲区扩容测试");
            robustPass++;
        } else {
            log("[FAIL] 缓冲区扩容测试");
            robustFail++;
        }
        
        // 测试6: API一致性
        if (this.testAPIConsistency()) {
            log("[PASS] API一致性测试");
            robustPass++;
        } else {
            log("[FAIL] API一致性测试");
            robustFail++;
        }
        
        // 测试7: keys对齐
        if (this.testKeysAlignment()) {
            log("[PASS] Keys对齐测试");
            robustPass++;
        } else {
            log("[FAIL] Keys对齐测试");
            robustFail++;
        }
        
        // 测试8: processAndClear方法
        if (this.testProcessAndClear()) {
            log("[PASS] processAndClear方法测试");
            robustPass++;
        } else {
            log("[FAIL] processAndClear方法测试");
            robustFail++;
        }
        
        // 测试9: addBatch方法
        if (this.testAddBatch()) {
            log("[PASS] addBatch方法测试");
            robustPass++;
        } else {
            log("[FAIL] addBatch方法测试");
            robustFail++;
        }
        
        log("鲁棒性测试: " + robustPass + " 通过, " + robustFail + " 失败");
        
        if (robustFail > 0) {
            this.assertFailed += robustFail;
        }
        this.assertTotal += (robustPass + robustFail);
        
        log("====================================================");
        log("");
    }
    
    private function testEmptyQueue():Boolean {
        var q:BulletQueue = new BulletQueue();
        var sorted:Array = q.getSortedBullets();
        
        if (!sorted || sorted.length != 0) return false;
        if (q.getCount() != 0) return false;
        
        var visitCount:Number = 0;
        q.forEachSorted(function(b:Object, i:Number):Void {
            visitCount++;
        });
        
        return visitCount == 0;
    }
    
    private function testSingleElement():Boolean {
        var q:BulletQueue = new BulletQueue();
        var bullet:Object = this.makeBullet(100, 110, 1);
        
        q.add(bullet);
        if (q.getCount() != 1) return false;
        
        var sorted:Array = q.getSortedBullets();
        if (sorted.length != 1) return false;
        if (sorted[0] != bullet) return false;
        
        return true;
    }
    
    private function testBoundaryValues():Boolean {
        // 测试63个元素（插入排序最大值）
        var q63:BulletQueue = new BulletQueue();
        for (var i:Number = 0; i < 63; i++) {
            q63.add(this.makeBullet(63 - i, 64 - i, i));
        }
        var sorted63:Array = q63.getSortedBullets();
        if (!this.isSorted(sorted63)) return false;
        
        // 测试64个元素（阈值边界）
        var q64:BulletQueue = new BulletQueue();
        for (var j:Number = 0; j < 64; j++) {
            q64.add(this.makeBullet(64 - j, 65 - j, j));
        }
        var sorted64:Array = q64.getSortedBullets();
        if (!this.isSorted(sorted64)) return false;
        
        // 测试65个元素（TimSort最小值）
        var q65:BulletQueue = new BulletQueue();
        for (var k:Number = 0; k < 65; k++) {
            q65.add(this.makeBullet(65 - k, 66 - k, k));
        }
        var sorted65:Array = q65.getSortedBullets();
        if (!this.isSorted(sorted65)) return false;
        
        return true;
    }
    
    private function testClearMethod():Boolean {
        var q:BulletQueue = new BulletQueue();
        
        // 添加元素
        for (var i:Number = 0; i < 10; i++) {
            q.add(this.makeBullet(i, i + 1, i));
        }
        
        var ref1:Array = q.getBulletsReference();
        q.clear();
        var ref2:Array = q.getBulletsReference();
        
        // 验证clear()保持引用
        if (ref1 != ref2) return false;
        if (ref1.length != 0) return false;
        if (q.getCount() != 0) return false;
        
        return true;
    }
    
    private function testBufferResize():Boolean {
        var q:BulletQueue = new BulletQueue();
        
        // 第一轮：少量元素
        for (var i:Number = 0; i < 10; i++) {
            q.add(this.makeBullet(i, i + 1, i));
        }
        q.sortByLeftBoundary();
        q.clear();
        
        // 第二轮：大量元素
        for (var j:Number = 0; j < 200; j++) {
            q.add(this.makeBullet(200 - j, 201 - j, j));
        }
        
        var sorted:Array = q.getSortedBullets();
        if (sorted.length != 200) return false;
        if (!this.isSorted(sorted)) return false;
        
        return true;
    }
    
    private function testAPIConsistency():Boolean {
        var q:BulletQueue = new BulletQueue();
        
        for (var i:Number = 0; i < 10; i++) {
            q.add(this.makeBullet(10 - i, 11 - i, i));
        }
        
        // 测试forEachSorted
        var count1:Number = 0;
        var lastLeft1:Number = -Infinity;
        var sorted1:Boolean = true;
        q.forEachSorted(function(bullet:Object, index:Number):Void {
            count1++;
            if (bullet.aabbCollider.left < lastLeft1) {
                sorted1 = false;
            }
            lastLeft1 = bullet.aabbCollider.left;
        });
        if (count1 != 10) return false;
        if (!sorted1) return false;
        
        // 测试forEachSortedWithKeys
        var count2:Number = 0;
        var keysMatch:Boolean = true;
        q.forEachSortedWithKeys(function(bullet:Object, left:Number, right:Number, index:Number):Void {
            count2++;
            if (left != bullet.aabbCollider.left) {
                keysMatch = false;
            }
            if (right != bullet.aabbCollider.right) {
                keysMatch = false;
            }
        });
        if (count2 != 10) return false;
        if (!keysMatch) return false;
        
        // 测试getSortedIterator
        var iter:Object = q.getSortedIterator();
        if (iter.indices != null) return false;  // 就地排序后应为null
        if (iter.isIndexed != false) return false;
        if (iter.length != 10) return false;
        
        return true;
    }
    
    private function testKeysAlignment():Boolean {
        var q:BulletQueue = new BulletQueue();
        
        // 添加随机顺序的子弹
        for (var i:Number = 0; i < 20; i++) {
            q.add(this.makeBullet(this.srand() * 100, this.srand() * 100 + 100, i));
        }
        
        q.sortByLeftBoundary();
        
        var bullets:Array = q.getBulletsReference();
        var leftKeys:Array = q.getLeftKeysRef();
        var rightKeys:Array = q.getRightKeysRef();
        
        if (bullets.length != leftKeys.length) return false;
        if (bullets.length != rightKeys.length) return false;
        
        // 验证对齐
        for (var j:Number = 0; j < bullets.length; j++) {
            if (bullets[j] && bullets[j].aabbCollider) {
                if (bullets[j].aabbCollider.left != leftKeys[j]) return false;
                if (bullets[j].aabbCollider.right != rightKeys[j]) return false;
            }
        }
        
        return true;
    }
    
    private function isSorted(arr:Array):Boolean {
        for (var i:Number = 1; i < arr.length; i++) {
            if (arr[i-1].aabbCollider.left > arr[i].aabbCollider.left) {
                return false;
            }
        }
        return true;
    }
    
    private function testProcessAndClear():Boolean {
        log("[DEBUG] 开始 testProcessAndClear 测试");
        
        // —— 测试1：空队列（约定：no-op）
        log("[TEST 1] 测试空队列");
        var q1:BulletQueue = new BulletQueue();
        var visitCount1:Number = 0;
        q1.processAndClear(function(b:Object, idx:Number):Void { visitCount1++; });
        log("  visitCount1=" + visitCount1 + " (期望:0)");
        log("  q1.getCount()=" + q1.getCount() + " (期望:0)");
        if (visitCount1 != 0) {
            log("  [FAIL] visitCount1 != 0");
            return false;
        }
        if (q1.getCount() != 0) {
            log("  [FAIL] q1.getCount() != 0");
            return false;
        }
        log("  [PASS] 测试1通过");

        // —— 测试2：小数组路径（插入排序）
        log("[TEST 2] 测试小数组路径(20个元素)");
        var q2:BulletQueue = new BulletQueue();
        for (var i:Number = 0; i < 20; i++) q2.add(this.makeBullet(20 - i, 21 - i, i));
        var visitCount2:Number = 0, lastLeft2:Number = -Infinity, sorted2:Boolean = true;
        var detailLog2:String = "";
        q2.processAndClear(function(b:Object, idx:Number):Void {
            visitCount2++;
            var curLeft:Number = b.aabbCollider.left;
            if (curLeft < lastLeft2) {
                sorted2 = false;
                detailLog2 += " [错误:idx=" + idx + ",left=" + curLeft + "<" + lastLeft2 + "]";
            }
            lastLeft2 = curLeft;
        });
        log("  visitCount2=" + visitCount2 + " (期望:20)");
        log("  sorted2=" + sorted2 + " (期望:true)");
        log("  q2.getCount()=" + q2.getCount() + " (期望:0)");
        if (detailLog2 != "") log("  排序错误详情:" + detailLog2);
        if (visitCount2 != 20 || !sorted2 || q2.getCount() != 0) {
            log("  [FAIL] 测试2失败");
            return false;
        }
        log("  [PASS] 测试2通过");

        // —— 测试3：大数组路径（TimSort/索引重排）
        log("[TEST 3] 测试大数组路径(100个元素)");
        // 为随机数据段重置 RNG，确保该段可重现
        this.resetRNG(987654321);
        var q3:BulletQueue = new BulletQueue();
        for (var j:Number = 0; j < 100; j++) q3.add(this.makeBullet(Math.floor(this.srand()*100), Math.floor(this.srand()*100)+100, j));
        var visitCount3:Number = 0, lastLeft3:Number = -Infinity, sorted3:Boolean = true;
        var detailLog3:String = "";
        var firstFewValues:String = "";
        q3.processAndClear(function(b:Object, idx:Number):Void {
            visitCount3++;
            var curLeft:Number = b.aabbCollider.left;
            if (visitCount3 <= 5) {
                firstFewValues += " [" + idx + "]=" + curLeft;
            }
            if (curLeft < lastLeft3) {
                sorted3 = false;
                if (detailLog3 == "") {  // 只记录第一个错误
                    detailLog3 = " [首个错误:idx=" + idx + ",left=" + curLeft + "<" + lastLeft3 + "]";
                }
            }
            lastLeft3 = curLeft;
        });
        log("  visitCount3=" + visitCount3 + " (期望:100)");
        log("  sorted3=" + sorted3 + " (期望:true)");
        log("  q3.getCount()=" + q3.getCount() + " (期望:0)");
        log("  前5个值:" + firstFewValues);
        if (detailLog3 != "") log("  排序错误详情:" + detailLog3);
        if (visitCount3 != 100 || !sorted3 || q3.getCount() != 0) {
            log("  [FAIL] 测试3失败");
            return false;
        }
        log("  [PASS] 测试3通过");

        // —— 测试4：连续调用（同一实例内验证 clear 行为）
        log("[TEST 4] 测试连续调用");
        var q4:BulletQueue = new BulletQueue();
        for (var k:Number = 0; k < 10; k++) q4.add(this.makeBullet(k, k+1, k));
        var firstCall:Number = 0; q4.processAndClear(function(b:Object, i:Number):Void { firstCall++; });
        var secondCall:Number = 0; q4.processAndClear(function(b:Object, i:Number):Void { secondCall++; });
        log("  firstCall=" + firstCall + " (期望:10)");
        log("  secondCall=" + secondCall + " (期望:0)");
        if (firstCall != 10 || secondCall != 0) {
            log("  [FAIL] 测试4失败");
            return false;
        }
        log("  [PASS] 测试4通过");

        // —— 测试5：稳定性（相同键保持插入顺序）
        log("[TEST 5] 测试稳定性");
        var q5:BulletQueue = new BulletQueue();
        for (var m:Number = 0; m < 10; m++) q5.add(this.makeBullet(5, 6, m));
        var stableIds:Array = [];
        q5.processAndClear(function(b:Object, i:Number):Void { stableIds.push(b.__id); });
        log("  stableIds长度=" + stableIds.length + " (期望:10)");
        var stableOk:Boolean = true;
        for (var n:Number = 0; n < stableIds.length; n++) {
            if (stableIds[n] != n) {
                log("  [错误] stableIds[" + n + "]=" + stableIds[n] + " (期望:" + n + ")");
                stableOk = false;
            }
        }
        if (!stableOk) {
            log("  [FAIL] 测试5失败");
            return false;
        }
        log("  [PASS] 测试5通过");

        log("[DEBUG] testProcessAndClear 全部测试通过");
        return true;
    }
    
    private function testAddBatch():Boolean {
        log("[DEBUG] 开始 testAddBatch 测试");
        
        // 测试1: 空数组批量添加
        log("[TEST 1] 测试空数组批量添加");
        var q1:BulletQueue = new BulletQueue();
        var emptyArray:Array = [];
        var added1:Number = q1.addBatch(emptyArray);
        log("  added1=" + added1 + " (期望:0)");
        log("  q1.getCount()=" + q1.getCount() + " (期望:0)");
        if (added1 != 0 || q1.getCount() != 0) {
            log("  [FAIL] 测试1失败");
            return false;
        }
        log("  [PASS] 测试1通过");
        
        // 测试2: null参数
        log("[TEST 2] 测试null参数");
        var q2:BulletQueue = new BulletQueue();
        var added2:Number = q2.addBatch(null);
        log("  added2=" + added2 + " (期望:0)");
        log("  q2.getCount()=" + q2.getCount() + " (期望:0)");
        if (added2 != 0 || q2.getCount() != 0) {
            log("  [FAIL] 测试2失败");
            return false;
        }
        log("  [PASS] 测试2通过");
        
        // 测试3: 正常批量添加
        log("[TEST 3] 测试正常批量添加");
        var q3:BulletQueue = new BulletQueue();
        var batch3:Array = [];
        for (var i:Number = 0; i < 50; i++) {
            batch3.push(this.makeBullet(50 - i, 51 - i, i));
        }
        var added3:Number = q3.addBatch(batch3);
        log("  added3=" + added3 + " (期望:50)");
        log("  q3.getCount()=" + q3.getCount() + " (期望:50)");
        
        // 验证排序正确性
        var sorted3:Array = q3.getSortedBullets();
        var isSorted3:Boolean = this.isSorted(sorted3);
        log("  排序正确性=" + isSorted3 + " (期望:true)");
        
        if (added3 != 50 || q3.getCount() != 50 || !isSorted3) {
            log("  [FAIL] 测试3失败");
            return false;
        }
        log("  [PASS] 测试3通过");
        
        // 测试4: 包含无效对象的批量添加
        log("[TEST 4] 测试包含无效对象的批量添加");
        var q4:BulletQueue = new BulletQueue();
        var batch4:Array = [
            this.makeBullet(1, 2, 1),
            null,
            this.makeBullet(3, 4, 2),
            {__id: 3, _name: "noCollider"},  // 缺失aabbCollider
            this.makeBullet(5, 6, 4),
            {aabbCollider: {left: NaN, right: NaN}, __id: 5},  // NaN值
            this.makeBullet(7, 8, 6),
            undefined,
            this.makeBullet(9, 10, 7),
            {aabbCollider: {left: Infinity, right: 10}, __id: 8}  // Infinity值
        ];
        var added4:Number = q4.addBatch(batch4);
        log("  added4=" + added4 + " (期望:5，只有有效子弹)");
        log("  q4.getCount()=" + q4.getCount() + " (期望:5)");
        
        // 验证只有有效子弹被添加
        var bullets4:Array = q4.getBulletsReference();
        var allValid:Boolean = true;
        for (var j:Number = 0; j < bullets4.length; j++) {
            var b:Object = bullets4[j];
            if (!b || !b.aabbCollider) {
                allValid = false;
                break;
            }
            var left:Number = b.aabbCollider.left;
            var right:Number = b.aabbCollider.right;
            if (((left - left) + (right - right)) != 0) {
                allValid = false;
                break;
            }
        }
        log("  所有子弹有效=" + allValid + " (期望:true)");
        
        if (added4 != 5 || q4.getCount() != 5 || !allValid) {
            log("  [FAIL] 测试4失败");
            return false;
        }
        log("  [PASS] 测试4通过");
        
        // 测试5: 大批量添加性能
        log("[TEST 5] 测试大批量添加(1000个元素)");
        var q5:BulletQueue = new BulletQueue();
        var batch5:Array = [];
        for (var k:Number = 0; k < 1000; k++) {
            batch5.push(this.makeBullet(Math.floor(this.srand() * 1000), Math.floor(this.srand() * 1000) + 1000, k));
        }
        
        var startTime:Number = getTimer();
        var added5:Number = q5.addBatch(batch5);
        var endTime:Number = getTimer();
        var timeTaken:Number = endTime - startTime;
        
        log("  added5=" + added5 + " (期望:1000)");
        log("  q5.getCount()=" + q5.getCount() + " (期望:1000)");
        log("  批量添加耗时=" + timeTaken + "ms");
        
        // 验证结果正确性
        var sorted5:Array = q5.getSortedBullets();
        var isSorted5:Boolean = this.isSorted(sorted5);
        log("  排序正确性=" + isSorted5 + " (期望:true)");
        
        if (added5 != 1000 || q5.getCount() != 1000 || !isSorted5) {
            log("  [FAIL] 测试5失败");
            return false;
        }
        log("  [PASS] 测试5通过");
        
        // 测试6: 混合使用add和addBatch
        log("[TEST 6] 测试混合使用add和addBatch");
        var q6:BulletQueue = new BulletQueue();
        
        // 先单个添加
        for (var m:Number = 0; m < 10; m++) {
            q6.add(this.makeBullet(m * 10, m * 10 + 1, m));
        }
        
        // 再批量添加
        var batch6:Array = [];
        for (var n:Number = 10; n < 20; n++) {
            batch6.push(this.makeBullet(n * 10, n * 10 + 1, n));
        }
        var added6:Number = q6.addBatch(batch6);
        
        // 再单个添加
        for (var p:Number = 20; p < 25; p++) {
            q6.add(this.makeBullet(p * 10, p * 10 + 1, p));
        }
        
        log("  批量添加返回值=" + added6 + " (期望:10)");
        log("  总数量=" + q6.getCount() + " (期望:25)");
        
        // 验证排序和数量
        var sorted6:Array = q6.getSortedBullets();
        var isSorted6:Boolean = this.isSorted(sorted6);
        log("  排序正确性=" + isSorted6 + " (期望:true)");
        
        if (added6 != 10 || q6.getCount() != 25 || !isSorted6) {
            log("  [FAIL] 测试6失败");
            return false;
        }
        log("  [PASS] 测试6通过");
        
        log("[DEBUG] testAddBatch 全部测试通过");
        return true;
    }

}
