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
        
        // 边界条件测试
        test_boundary_coordinates();
        test_single_cell_grid();
        test_narrow_corridors();
        test_maze_like_paths();
        test_out_of_bounds_requests();
        test_invalid_start_or_goal();
        
        // 权重和可达性测试
        test_extreme_weights();
        test_mixed_terrain_weights();
        test_partial_blocked_grid();
        test_spiral_obstacle_pattern();
        
        // 启发式函数测试
        test_different_heuristics();
        test_heuristic_consistency();
        
        // 对角线和卡角测试
        test_diagonal_vs_straight_cost();
        test_complex_corner_cutting();
        test_tight_diagonal_passages();
        
        // 搜索限制测试
        test_max_expand_limit();
        test_very_long_paths();
        
        // 极端尺寸测试
        test_large_grid_pathfinding();
        test_grid_edge_cases();

        // 性能和压力测试（不以耗时判定成败，只记录）
        if (doPerf) {
            perf_smoke(seed);
            perf_stress_diagonal_heavy(seed);
            perf_worst_case_scenarios(seed);
            perf_memory_intensive(seed);
        }

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

    // ========== 边界条件测试 ==========
    private static function test_boundary_coordinates():Void
    {
        var name:String = "边界坐标寻路测试";
        begin(name);
        
        var nav:AStarGrid = new AStarGrid(5, 5, true, false);
        
        // 测试四个角落之间的路径
        var path1:Array = nav.find(0, 0, 4, 4);
        assertNotNull(path1, "左上到右下应有路径");
        assertPoint(path1[0], 0, 0, "起点应为(0,0)");
        assertPoint(path1[path1.length-1], 4, 4, "终点应为(4,4)");
        
        var path2:Array = nav.find(4, 0, 0, 4);
        assertNotNull(path2, "右上到左下应有路径");
        
        var path3:Array = nav.find(0, 4, 4, 0);
        assertNotNull(path3, "左下到右上应有路径");
        
        end();
    }

    private static function test_single_cell_grid():Void
    {
        var name:String = "单格网格测试";
        begin(name);
        
        var nav:AStarGrid = new AStarGrid(1, 1, true, false);
        var path:Array = nav.find(0, 0, 0, 0);
        assertNotNull(path, "单格网格应返回路径");
        assertEqual(path.length, 1, "单格路径长度应为1");
        assertPoint(path[0], 0, 0, "单格路径应为起点");
        
        end();
    }

    private static function test_narrow_corridors():Void
    {
        var name:String = "狭窄通道测试";
        begin(name);
        
        var nav:AStarGrid = new AStarGrid(7, 3, false, false);
        var walk:Array = [[1,0,1,0,1,0,1],
                          [1,1,1,1,1,1,1],
                          [1,0,1,0,1,0,1]];
        nav.setWalkableMatrix(walk);
        
        var path:Array = nav.find(0, 1, 6, 1);
        assertNotNull(path, "应能通过狭窄通道");
        assertEqual(path.length, 7, "通道路径长度应为7");
        
        // 测试所有路径点都在y=1这一行
        var allInCorridor:Boolean = true;
        var i:Number = 0;
        while (i < path.length) {
            if (path[i].y != 1) { allInCorridor = false; break; }
            i++;
        }
        assertTrue(allInCorridor, "路径应完全在通道内");
        
        end();
    }

    private static function test_maze_like_paths():Void
    {
        var name:String = "迷宫式路径测试";
        begin(name);
        
        var nav:AStarGrid = new AStarGrid(5, 5, false, false);
        var walk:Array = [[1,1,0,1,1],
                          [0,1,0,1,0],
                          [1,1,1,1,1],
                          [0,1,0,1,0],
                          [1,1,0,1,1]];
        nav.setWalkableMatrix(walk);
        
        var path:Array = nav.find(0, 0, 4, 4);
        assertNotNull(path, "迷宫应有解");
        assertTrue(path.length > 5, "迷宫路径应较长");
        
        end();
    }

    private static function test_out_of_bounds_requests():Void
    {
        var name:String = "越界请求测试";
        begin(name);
        
        var nav:AStarGrid = new AStarGrid(3, 3, true, false);
        
        var path1:Array = nav.find(-1, 0, 2, 2);
        assertNull(path1, "起点越界应返回null");
        
        var path2:Array = nav.find(0, 0, 5, 2);
        assertNull(path2, "终点越界应返回null");
        
        var path3:Array = nav.find(-1, -1, 5, 5);
        assertNull(path3, "起终点都越界应返回null");
        
        end();
    }

    private static function test_invalid_start_or_goal():Void
    {
        var name:String = "起终点不可达测试";
        begin(name);
        
        var nav:AStarGrid = new AStarGrid(3, 3, false, false);
        var walk:Array = [[0,1,1],
                          [1,1,1],
                          [1,1,0]];
        nav.setWalkableMatrix(walk);
        
        var path1:Array = nav.find(0, 0, 2, 2);
        assertNull(path1, "起点不可走应返回null");
        
        var path2:Array = nav.find(1, 1, 2, 2);
        assertNull(path2, "终点不可走应返回null");
        
        end();
    }

    // ========== 权重和可达性测试 ==========
    private static function test_extreme_weights():Void
    {
        var name:String = "极端权重测试";
        begin(name);
        
        var nav:AStarGrid = new AStarGrid(3, 3, false, false);
        var weight:Array = [[0,1000,0],
                            [0,1000,0],
                            [0,0,0]];
        nav.setWeightMatrix(weight);
        
        var path:Array = nav.find(0, 0, 2, 0);
        assertNotNull(path, "应能绕开极高权重");
        
        // 检查路径是否绕开了高权重格子(1,0)和(1,1)
        var avoidsHighWeight:Boolean = true;
        var i:Number = 0;
        while (i < path.length) {
            var px:Number = path[i].x;
            var py:Number = path[i].y;
            // 只检查实际高权重的格子：(1,0)和(1,1)
            if ((px == 1 && py == 0) || (px == 1 && py == 1)) { 
                avoidsHighWeight = false; 
                break; 
            }
            i++;
        }
        assertTrue(avoidsHighWeight, "应绕开高权重区域");
        
        end();
    }

    private static function test_mixed_terrain_weights():Void
    {
        var name:String = "混合地形权重测试";
        begin(name);
        
        var nav:AStarGrid = new AStarGrid(4, 4, true, false);
        var weight:Array = [[0,1,2,3],
                            [1,2,3,4],
                            [2,3,4,5],
                            [3,4,5,6]];
        nav.setWeightMatrix(weight);
        
        var path:Array = nav.find(0, 0, 3, 3);
        assertNotNull(path, "混合权重应找到路径");
        
        // 计算路径总权重，应该选择较优路径
        var totalWeight:Number = 0;
        var i:Number = 0;
        while (i < path.length) {
            var px:Number = path[i].x;
            var py:Number = path[i].y;
            totalWeight += weight[py][px];
            i++;
        }
        assertTrue(totalWeight > 0, "路径权重应为正值");
        
        end();
    }

    private static function test_partial_blocked_grid():Void
    {
        var name:String = "部分阻塞网格测试";
        begin(name);
        
        var nav:AStarGrid = new AStarGrid(6, 6, true, false);
        var walk:Array = [];
        var y:Number = 0;
        while (y < 6) {
            var row:Array = [1,1,1,1,1,1];
            walk.push(row);
            y++;
        }
        
        // 创建一个"L"型障碍
        walk[2][2] = 0; walk[2][3] = 0; walk[2][4] = 0;
        walk[3][2] = 0; walk[4][2] = 0;
        nav.setWalkableMatrix(walk);
        
        var path:Array = nav.find(1, 1, 5, 5);
        assertNotNull(path, "应能绕过L型障碍");
        
        end();
    }

    private static function test_spiral_obstacle_pattern():Void
    {
        var name:String = "螺旋障碍模式测试";
        begin(name);
        
        var nav:AStarGrid = new AStarGrid(7, 7, false, false);
        var walk:Array = [[1,1,1,1,1,1,1],
                          [1,0,0,0,0,0,1],
                          [1,0,1,1,1,0,1],
                          [1,0,1,1,1,0,1], // 把(3,3)改为可走
                          [1,0,1,1,1,0,1],
                          [1,0,0,0,0,0,1],
                          [1,1,1,1,1,1,1]];
        nav.setWalkableMatrix(walk);
        
        var path:Array = nav.find(0, 0, 3, 3);
        assertNotNull(path, "应能通过螺旋障碍");
        
        end();
    }

    // ========== 启发式函数测试 ==========
    private static function test_different_heuristics():Void
    {
        var name:String = "不同启发式函数测试";
        begin(name);
        
        var nav:AStarGrid = new AStarGrid(5, 5, true, false);
        
        // 测试Manhattan距离
        nav.setHeuristic(0);
        var pathManhattan:Array = nav.find(0, 0, 4, 4);
        assertNotNull(pathManhattan, "Manhattan启发式应找到路径");
        
        // 测试Diagonal距离
        nav.setHeuristic(1);
        var pathDiagonal:Array = nav.find(0, 0, 4, 4);
        assertNotNull(pathDiagonal, "Diagonal启发式应找到路径");
        
        // 测试Euclidean距离
        nav.setHeuristic(2);
        var pathEuclidean:Array = nav.find(0, 0, 4, 4);
        assertNotNull(pathEuclidean, "Euclidean启发式应找到路径");
        
        end();
    }

    private static function test_heuristic_consistency():Void
    {
        var name:String = "启发式一致性测试";
        begin(name);
        
        var nav:AStarGrid = new AStarGrid(8, 8, true, false);
        
        // 为每种启发式测试多次，结果应一致
        var h:Number = 0;
        while (h <= 2) {
            nav.setHeuristic(h);
            var path1:Array = nav.find(1, 1, 6, 6);
            var path2:Array = nav.find(1, 1, 6, 6);
            assertTrue(pathEqual(path1, path2), "启发式" + h + "应保持一致");
            h++;
        }
        
        end();
    }

    // ========== 对角线和卡角测试 ==========
    private static function test_diagonal_vs_straight_cost():Void
    {
        var name:String = "对角线vs直线成本测试";
        begin(name);
        
        // 对角线允许但不允许卡角
        var nav:AStarGrid = new AStarGrid(3, 3, true, false);
        var path:Array = nav.find(0, 0, 2, 2);
        assertNotNull(path, "应找到对角线路径");
        assertEqual(path.length, 3, "对角线路径应为3步");
        
        // 对角线不允许
        nav.setAllowDiagonal(false);
        path = nav.find(0, 0, 2, 2);
        assertNotNull(path, "4向应找到路径");
        assertTrue(path.length > 3, "4向路径应长于对角线");
        
        end();
    }

    private static function test_complex_corner_cutting():Void
    {
        var name:String = "复杂卡角测试";
        begin(name);
        
        var nav:AStarGrid = new AStarGrid(4, 4, true, true);
        var walk:Array = [[1,0,0,1],
                          [0,1,1,0],
                          [0,1,1,0],
                          [1,0,0,1]];
        nav.setWalkableMatrix(walk);
        
        // 允许卡角时应能找到路径
        var pathWithCut:Array = nav.find(0, 0, 3, 3);
        assertNotNull(pathWithCut, "允许卡角应找到路径");
        
        // 禁止卡角时应无路径
        nav.setAllowCornerCut(false);
        var pathNoCut:Array = nav.find(0, 0, 3, 3);
        assertNull(pathNoCut, "禁止卡角应无路径");
        
        end();
    }

    private static function test_tight_diagonal_passages():Void
    {
        var name:String = "紧密对角通道测试";
        begin(name);
        
        var nav:AStarGrid = new AStarGrid(5, 5, true, true);
        var walk:Array = [[1,0,1,0,1],
                          [0,1,0,1,0],
                          [1,0,1,0,1],
                          [0,1,0,1,0],
                          [1,0,1,0,1]];
        nav.setWalkableMatrix(walk);
        
        var path:Array = nav.find(0, 0, 4, 4);
        assertNotNull(path, "紧密对角通道应可通过");
        
        end();
    }

    // ========== 搜索限制测试 ==========
    private static function test_max_expand_limit():Void
    {
        var name:String = "最大扩展限制测试";
        begin(name);
        
        var nav:AStarGrid = new AStarGrid(10, 10, true, false); // 改为允许对角线
        
        // 设置一个需要较多搜索的复杂路径
        var walk:Array = [];
        var y:Number = 0;
        while (y < 10) {
            var row:Array = [];
            var x:Number = 0;
            while (x < 10) {
                // 棋盘模式，但确保起点邻居可达
                if ((x + y) % 2 == 0 || y == 9) {
                    row.push(1);
                } else {
                    row.push(0);
                }
                x++;
            }
            walk.push(row);
            y++;
        }
        // 确保起点(0,0)的邻居至少有一个可达
        walk[0][1] = 1; // 确保(0,1)可走
        walk[1][0] = 1; // 确保(1,0)可走
        nav.setWalkableMatrix(walk);
        
        // 限制很小的扩展次数
        var pathLimited:Array = nav.find(0, 0, 9, 9, 5);
        assertNull(pathLimited, "扩展限制应阻止找到路径");
        
        // 不限制扩展次数
        var pathUnlimited:Array = nav.find(0, 0, 9, 9);
        assertNotNull(pathUnlimited, "无限制应找到路径");
        
        end();
    }

    private static function test_very_long_paths():Void
    {
        var name:String = "超长路径测试";
        begin(name);
        
        // 创建一个蛇形通道强制绕行的场景 
        var nav:AStarGrid = new AStarGrid(11, 5, false, false);
        
        // 蛇形障碍模式：必须绕很多弯
        var walk:Array = [[1,1,1,1,1,1,1,1,1,1,0],  // 第0行：横向通道，最后封死
                          [0,0,0,0,0,0,0,0,0,1,1],  // 第1行：右端开口向下
                          [1,1,1,1,1,1,1,1,1,1,0],  // 第2行：横向通道，左端封死
                          [1,0,0,0,0,0,0,0,0,0,0],  // 第3行：左端开口向下
                          [1,1,1,1,1,1,1,1,1,1,1]]; // 第4行：到达终点
        nav.setWalkableMatrix(walk);
        
        var path:Array = nav.find(0, 0, 10, 4);
        assertNotNull(path, "应找到超长路径");
        // 理论路径：右→右...→右→下→左→左...→左→下→右→右...→右，应该远超21步
        assertTrue(path.length > 30, "蛇形路径应很长");
        
        end();
    }

    // ========== 极端尺寸测试 ==========
    private static function test_large_grid_pathfinding():Void
    {
        var name:String = "大网格寻路测试";
        begin(name);
        
        var nav:AStarGrid = new AStarGrid(50, 50, true, false);
        
        // 大部分可走，少量随机障碍
        var walk:Array = [];
        var y:Number = 0;
        while (y < 50) {
            var row:Array = [];
            var x:Number = 0;
            while (x < 50) {
                // 95%可走
                row.push(((x * 7 + y * 11) % 100) < 95 ? 1 : 0);
                x++;
            }
            walk.push(row);
            y++;
        }
        // 确保起终点可达
        walk[0][0] = 1;
        walk[49][49] = 1;
        nav.setWalkableMatrix(walk);
        
        var path:Array = nav.find(0, 0, 49, 49);
        assertNotNull(path, "大网格应找到路径");
        
        end();
    }

    private static function test_grid_edge_cases():Void
    {
        var name:String = "网格边缘情况测试";
        begin(name);
        
        // 测试resize到更小尺寸
        var nav:AStarGrid = new AStarGrid(5, 5, false, false);
        nav.resize(2, 2);
        var path1:Array = nav.find(0, 0, 1, 1);
        assertNotNull(path1, "缩小后应能寻路");
        
        // 测试resize到更大尺寸
        nav.resize(10, 10);
        var path2:Array = nav.find(0, 0, 9, 9);
        assertNotNull(path2, "扩大后应能寻路");
        
        // 测试权重设置边界值
        nav.setWeight(0, 0, 0.5); // 应被调整为1
        nav.setWeight(1, 1, -5);  // 应被调整为1
        var path3:Array = nav.find(0, 0, 1, 1);
        assertNotNull(path3, "设置无效权重后仍应能寻路");
        
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

    private static function perf_stress_diagonal_heavy(seed:Number):Void
    {
        var name:String = "对角线密集性能测试（60x60）";
        begin(name);
        
        var nav:AStarGrid = new AStarGrid(60, 60, true, true);
        
        // 创建需要大量对角线移动的复杂地形
        var rnd:Number = seed + 1000;
        function rand01():Number {
            rnd = (rnd * 1103515245 + 12345) & 0x7fffffff;
            return (rnd % 10000) / 10000;
        }
        
        var walk:Array = [];
        var y:Number = 0;
        while (y < 60) {
            var row:Array = [];
            var x:Number = 0;
            while (x < 60) {
                // 30% 障碍，形成复杂对角线需求
                row.push(rand01() < 0.70 ? 1 : 0);
                x++;
            }
            walk.push(row);
            y++;
        }
        // 确保起终点和路径连通性
        walk[0][0] = 1; walk[59][59] = 1;
        walk[1][1] = 1; walk[58][58] = 1;
        nav.setWalkableMatrix(walk);
        
        var t0:Number = getTimer();
        var path:Array = nav.find(0, 0, 59, 59, 20000);
        var t1:Number = getTimer();
        var ms:Number = t1 - t0;
        
        if (path == null) {
            log(" [对角线性能] 未找到路径，耗时：" + ms + " ms");
        } else {
            log(" [对角线性能] 找到路径，节点数：" + path.length + "，耗时：" + ms + " ms");
        }
        
        end(true);
    }

    private static function perf_worst_case_scenarios(seed:Number):Void
    {
        var name:String = "最坏情况性能测试";
        begin(name);
        
        // 测试1: 长距离无解搜索
        var nav1:AStarGrid = new AStarGrid(40, 40, false, false);
        var walk1:Array = [];
        var y:Number = 0;
        while (y < 40) {
            var row:Array = [];
            var x:Number = 0;
            while (x < 40) {
                // 创建两个隔离区域
                if (x < 19) {
                    row.push(1);
                } else if (x == 19) {
                    row.push(0); // 中间墙
                } else {
                    row.push(1);
                }
                x++;
            }
            walk1.push(row);
            y++;
        }
        nav1.setWalkableMatrix(walk1);
        
        var t0:Number = getTimer();
        var path1:Array = nav1.find(0, 0, 39, 39, 5000);
        var t1:Number = getTimer();
        log(" [最坏情况1] 隔离搜索耗时：" + (t1 - t0) + " ms，结果：" + (path1 ? "有路" : "无路"));
        
        // 测试2: 复杂权重梯度
        var nav2:AStarGrid = new AStarGrid(30, 30, true, false);
        var weight:Array = [];
        y = 0;
        while (y < 30) {
            var rowW:Array = [];
            x = 0;
            while (x < 30) {
                // 权重随距离中心递增
                var dx:Number = x - 15;
                var dy:Number = y - 15;
                var dist:Number = Math.sqrt(dx*dx + dy*dy);
                rowW.push(Math.floor(dist) + 1);
                x++;
            }
            weight.push(rowW);
            y++;
        }
        nav2.setWeightMatrix(weight);
        
        t0 = getTimer();
        var path2:Array = nav2.find(0, 0, 29, 29);
        t1 = getTimer();
        log(" [最坏情况2] 权重梯度耗时：" + (t1 - t0) + " ms，路径长度：" + (path2 ? path2.length : "无路"));
        
        end(true);
    }

    private static function perf_memory_intensive(seed:Number):Void
    {
        var name:String = "内存密集型测试（100x100）";
        begin(name);
        
        var nav:AStarGrid = new AStarGrid(100, 100, true, false);
        
        // 设置复杂地形但保证有解
        var rnd:Number = seed + 2000;
        function rand01():Number {
            rnd = (rnd * 1103515245 + 12345) & 0x7fffffff;
            return (rnd % 10000) / 10000;
        }
        
        var walk:Array = [];
        var y:Number = 0;
        while (y < 100) {
            var row:Array = [];
            var x:Number = 0;
            while (x < 100) {
                // 15% 障碍，保持大部分可达
                row.push(rand01() < 0.85 ? 1 : 0);
                x++;
            }
            walk.push(row);
            y++;
        }
        
        // 确保有明确路径
        y = 0;
        while (y < 100) {
            walk[y][0] = 1; // 左边界路径
            walk[0][y] = 1; // 上边界路径
            walk[y][99] = 1; // 右边界路径
            walk[99][y] = 1; // 下边界路径
            y++;
        }
        nav.setWalkableMatrix(walk);
        
        var t0:Number = getTimer();
        var path:Array = nav.find(0, 0, 99, 99, 30000);
        var t1:Number = getTimer();
        var ms:Number = t1 - t0;
        
        if (path == null) {
            log(" [内存密集型] 搜索超时或无解，耗时：" + ms + " ms");
        } else {
            log(" [内存密集型] 完成搜索，路径长度：" + path.length + "，耗时：" + ms + " ms");
        }
        
        // 内存压力测试：连续多次搜索
        var runs:Number = 5;
        var totalTime:Number = 0;
        var i:Number = 0;
        while (i < runs) {
            var sx:Number = Math.floor(rand01() * 80);
            var sy:Number = Math.floor(rand01() * 80);
            var gx:Number = sx + Math.floor(rand01() * 19) + 1;
            var gy:Number = sy + Math.floor(rand01() * 19) + 1;
            if (gx >= 100) gx = 99;
            if (gy >= 100) gy = 99;
            
            t0 = getTimer();
            nav.find(sx, sy, gx, gy, 5000);
            t1 = getTimer();
            totalTime += (t1 - t0);
            i++;
        }
        log(" [内存密集型] " + runs + "次连续搜索平均耗时：" + (totalTime/runs) + " ms");
        
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
