import org.flashNight.neur.Navigation.AStarGrid;

/**
 * A*（AStarGrid）测试套件
 * 一句话启动：org.flashNight.neur.Navigation.AStarGridTest.run();
 * 可选参数：run({ visualize:false, seed:12345, perf:true })
 */
class org.flashNight.neur.Navigation.AStarGridTest
{
    // ==== 配置 ====
    private static var DEF_SEED:Number = 20250815;

    // 统计
    private static var total:Number;
    private static var passed:Number;
    private static var failed:Number;

    // ========== 对外入口 ==========
    static function run(cfg:Object):Void
    {
        if (cfg == undefined) cfg = {};
        var seed:Number = (cfg.seed != undefined) ? cfg.seed : DEF_SEED;
        var doPerf:Boolean = (cfg.perf != undefined) ? cfg.perf : true;

        total = 0; passed = 0; failed = 0;
        log("==== [A* 测试开始] ====");

        // 基本正确性
        test_straight_4dir();
        test_diagonal_short();
        test_corner_cut_forbidden();
        test_corner_cut_allowed();
        test_weight_avoid();
        test_start_equals_goal();
        test_no_path();
        test_resize_then_find();
        test_determinism();

        // 性能烟雾（不以耗时判定成败，只记录）
        if (doPerf) perf_smoke(seed);

        log("==== [A* 测试结束] 通过: " + passed + "/" + total + "  失败: " + failed + " ====");
    }

    // ========== 用例 ==========
    private static function test_straight_4dir():Void
    {
        var name:String = "直线 4向 寻路";
        begin(name);

        var nav:AStarGrid = new AStarGrid(5, 1, false, false);
        var path:Array = nav.find(0, 0, 4, 0);
        // 期望节点数=5，按 (0,0)->(1,0)->...->(4,0)
        assertNotNull(path, "应当找到路径");
        assertEqual(path.length, 5, "路径长度应为5");
        assertPoint(path[0], 0, 0, "起点应为(0,0)");
        assertPoint(path[4], 4, 0, "终点应为(4,0)");
        // 中间检查
        var ok:Boolean = true;
        var i:Number=0;
        while (i<path.length)
        {
            if (path[i].y != 0 || path[i].x != i) { ok=false; break; }
            i++;
        }
        assertTrue(ok, "应逐格前进到 x=4");

        end();
    }

    private static function test_diagonal_short():Void
    {
        var name:String = "空旷 允许斜向 路径更短";
        begin(name);

        var nav:AStarGrid = new AStarGrid(3, 3, true, true);
        var path:Array = nav.find(0, 0, 2, 2);
        assertNotNull(path, "应当找到路径");
        // 期望最短：(0,0)->(1,1)->(2,2) 共3点
        assertEqual(path.length, 3, "对角应只需3步节点");
        end();
    }

    private static function test_corner_cut_forbidden():Void
    {
        var name:String = "禁止卡角 时 斜穿被阻";
        begin(name);

        var nav:AStarGrid = new AStarGrid(3, 3, true, false);
        var walk:Array = [[1,0,1],[0,1,1],[1,1,1]];
        nav.setWalkableMatrix(walk);
        // (1,0)与(0,1)封住起点的直邻，禁止卡角下从(0,0)到(2,2)无路
        var path:Array = nav.find(0, 0, 2, 2);
        assertNull(path, "禁止卡角时不应穿过对角");
        end();
    }

    private static function test_corner_cut_allowed():Void
    {
        var name:String = "允许卡角 时 可对角穿过";
        begin(name);

        var nav:AStarGrid = new AStarGrid(3, 3, true, true);
        var walk:Array = [[1,0,1],[0,1,1],[1,1,1]];
        nav.setWalkableMatrix(walk);
        var path:Array = nav.find(0, 0, 2, 2);
        assertNotNull(path, "允许卡角应找到路");
        assertEqual(path.length, 3, "允许卡角应为3节点对角");
        end();
    }

    private static function test_weight_avoid():Void
    {
        var name:String = "权重高区域应被绕开";
        begin(name);

        var nav:AStarGrid = new AStarGrid(5, 3, true, false);

        // 全可走
        var walk:Array = [];
        var y:Number=0;
        while (y<3){ var row:Array=[1,1,1,1,1]; walk.push(row); y++; }
        nav.setWalkableMatrix(walk);

        // 中线(1,1)(2,1)(3,1)权重很高
        var weight:Array = [];
        y=0;
        while (y<3){
            var roww:Array=[1,1,1,1,1];
            weight.push(roww);
            y++;
        }
        weight[1][1]=9; weight[1][2]=9; weight[1][3]=9;
        nav.setWeightMatrix(weight);

        var path:Array = nav.find(0, 1, 4, 1);
        assertNotNull(path, "应当找到路径");
        // 断言：除了起终点，尽量不走 y=1 的重权格
        var avoid:Boolean = true;
        var i:Number=1;
        while (i<path.length-1){
            if (path[i].y==1 && (path[i].x>=1 && path[i].x<=3)) { avoid=false; break; }
            i++;
        }
        assertTrue(avoid, "应绕开高权重带");
        end();
    }

    private static function test_start_equals_goal():Void
    {
        var name:String = "起点即终点";
        begin(name);

        var nav:AStarGrid = new AStarGrid(10, 10, true, false);
        var path:Array = nav.find(3, 7, 3, 7);
        assertNotNull(path, "应返回非空路径");
        assertEqual(path.length, 1, "长度应为1");
        assertPoint(path[0], 3, 7, "唯一节点应为起点");
        end();
    }

    private static function test_no_path():Void
    {
        var name:String = "无路情形";
        begin(name);

        var nav:AStarGrid = new AStarGrid(5, 3, false, false);
        var walk:Array = [[1,0,1,1,1],
                          [1,0,1,1,1],
                          [1,0,1,1,1]]; // 竖墙
        nav.setWalkableMatrix(walk);
        var path:Array = nav.find(0, 1, 4, 1);
        assertNull(path, "应无路径");
        end();
    }

    private static function test_resize_then_find():Void
    {
        var name:String = "resize 后继续可用";
        begin(name);

        var nav:AStarGrid = new AStarGrid(2, 2, false, false);
        var p1:Array = nav.find(0,0,1,1); // 有可能走不通（斜向禁止），只要不报错即可
        // 扩容
        nav.resize(3,3);
        var walk:Array = [[1,1,1],[1,1,1],[1,1,1]];
        nav.setWalkableMatrix(walk);
        var p2:Array = nav.find(0,0,2,2);
        assertNotNull(p2, "resize 后应可正常寻路");
        end();
    }

    private static function test_determinism():Void
    {
        var name:String = "确定性（同输入同输出）";
        begin(name);

        var nav:AStarGrid = new AStarGrid(8, 8, true, false);
        var walk:Array = [];
        var y:Number=0;
        while (y<8){ var r:Array=[1,1,1,1,1,1,1,1]; walk.push(r); y++; }
        // 放障碍
        walk[3][3]=0; walk[3][4]=0; walk[4][3]=0;
        nav.setWalkableMatrix(walk);

        var a:Array = nav.find(0,0,7,7);
        var b:Array = nav.find(0,0,7,7);
        assertTrue( pathEqual(a,b), "两次结果应一致" );
        end();
    }

    private static function perf_smoke(seed:Number):Void
    {
        var name:String = "性能烟雾测试（80x80 随机障碍 20%）";
        begin(name);

        var nav:AStarGrid = new AStarGrid(80, 80, true, false);

        // 随机可走矩阵
        var rnd:Number = seed;
        function rand01():Number {
            // 线性同余简易随机
            rnd = (rnd * 1103515245 + 12345) & 0x7fffffff;
            return (rnd % 10000) / 10000; // [0,1)
        }

        var walk:Array = [];
        var y:Number=0;
        while (y<80){
            var row:Array=[];
            var x:Number=0;
            while (x<80){
                // 20% 障碍
                var allow:Number = (rand01()<0.20) ? 0 : 1;
                row.push(allow);
                x++;
            }
            walk.push(row);
            y++;
        }
        // 保证起终点可走
        walk[0][0]=1; walk[79][79]=1;
        nav.setWalkableMatrix(walk);

        var t0:Number = getTimer();
        var path:Array = nav.find(0,0,79,79, 15000); // 给个较大的 expand 限额防止极端卡住
        var t1:Number = getTimer();
        var ms:Number = t1 - t0;

        if (path==null) {
            log(" [性能] 未找到路径，耗时："+ms+" ms（随机地图可能无路，属正常）");
        } else {
            log(" [性能] 找到路径，节点数："+path.length+"，耗时："+ms+" ms");
        }
        // 性能用例不判定通过与否
        end(true);
    }

    // ========== 断言 & 工具 ==========
    private static function begin(name:String):Void
    {
        total++;
        log("— 用例开始：「"+name+"」");
        _currentName = name;
        _currentFailed = false;
    }
    private static var _currentName:String;
    private static var _currentFailed:Boolean;

    private static function end(skipCount:Boolean):Void
    {
        if (skipCount) {
            log("  用例完成（性能/记录型，不计入通过/失败）。");
            return;
        }
        if (_currentFailed) {
            failed++;
            log("  ⇒ 结果：失败");
        } else {
            passed++;
            log("  ⇒ 结果：通过");
        }
    }

    private static function fail(msg:String):Void
    {
        _currentFailed = true;
        log("  [断言失败] " + msg);
    }

    private static function assertTrue(cond:Boolean, msg:String):Void
    {
        if (!cond) fail(msg);
    }

    private static function assertEqual(a:Number, b:Number, msg:String):Void
    {
        if (a != b) fail(msg + "（实际=" + a + " 期望=" + b + "）");
    }

    private static function assertNotNull(o:Object, msg:String):Void
    {
        if (o == null) fail(msg + "（实际为 null）");
    }

    private static function assertNull(o:Object, msg:String):Void
    {
        if (o != null) fail(msg + "（实际非 null）");
    }

    private static function assertPoint(p:Object, x:Number, y:Number, msg:String):Void
    {
        if (p == null || p.x != x || p.y != y) {
            var s:String = p==null ? "null" : "("+p.x+","+p.y+")";
            fail(msg + "（实际="+s+" 期望=(" + x + "," + y + ")）");
        }
    }

    private static function pathEqual(a:Array, b:Array):Boolean
    {
        if (a==null && b==null) return true;
        if (a==null || b==null) return false;
        if (a.length != b.length) return false;
        var i:Number=0;
        while (i<a.length){
            var pa:Object=a[i], pb:Object=b[i];
            if (pa.x!=pb.x || pa.y!=pb.y) return false;
            i++;
        }
        return true;
    }

    private static function log(s:String):Void
    {
        if (_root["服务器"] && _root["服务器"]["发布服务器消息"] instanceof Function) {
            _root["服务器"]["发布服务器消息"](s);
        } else {
            trace(s);
        }
    }
}
