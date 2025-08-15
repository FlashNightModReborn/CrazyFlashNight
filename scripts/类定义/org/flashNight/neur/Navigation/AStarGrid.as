// ===============================================================
//  A* Pathfinding (Grid) —— 栅格 A* 寻路（ActionScript 2 实现）
// ---------------------------------------------------------------
//  设计目标：
//    1) 高性能：无递归、以数组承载状态、减少对象创建；开放表用二叉堆；整型代价。
//    2) 易集成：支持 4/8 邻接、禁止卡角（防穿角）、地形权重（加法成本）。
//    3) 稳定鲁棒：下标/边界检查完备；搜索轮次 searchId 复用标记避免全表清空。
//    4) 易调优：可选择启发式（Manhattan / Octile / 近似 Euclidean）；可加 maxExpand 限流。
//  复杂度（理论）：
//    - 若无权重、均匀代价，典型 A* 时间复杂度 O(E log V)，E≈分支因子×展开节点数；
//      使用二叉堆使 push/pop 为 O(log V)。空间复杂度 O(V)。
//  约定与术语：
//    - "卡角"：指斜向穿过两个相邻的障碍角落；禁止卡角可避免"擦角穿越"。
//    - "权重"：对某格的**额外代价**（加法），非倍率；默认 0 表示无额外成本。
//    - "可走性"：1=可走、0=不可走。
//
//  坐标与单位说明：
//    - **格坐标 vs 像素坐标**：本类所有 API 使用"格"为单位；若世界坐标是像素，需由调用方完成 px→cell/cell→px 映射。
//    - **索引计算公式**：内部线性索引 = y * _w + x（行主序存储）。
//    - **代价单位**：基于 COST_STRAIGHT=10 的整数刻度（相当于把每步×10），权重是加法的"额外成本"。
//  返回路径：
//    - 形式为数组 [{x:Number, y:Number}, ...]，**从起点到终点**（已反转），若无路返回 null。
//
//  特殊情形的明确约定：
//    - **起点 = 终点**：返回 [{x:sx,y:sy}]（长度 1），属于命中而非 null。
//    - **终点不可走**：当前直接返回 null。设计意图：避免"擦边占位"的歧义行为。
//    - **maxExpand 限制**：触发上限返回 null 并不代表"地图无路"，而是"被限流"；真实无路需提高限制重试验证。
//
//  启发式与邻接匹配的可采纳性：
//    - **4 邻接→Manhattan** 可采纳；**8 邻接→Octile** 可采纳；
//    - **"Euclidean(近似)"** 与 Octile 数值等价，选择它不会提升质量，仅影响命名一致性；
//    - **启发式选错**会导致扩张变多或最优性受影响（切勿随意切换）。
//
//  确定性与 tie-breaking：
//    - **堆比较规则**：先比 f，再比 g；若 f,g 都相等，按插入顺序（堆结构）稳定；
//    - 因此 **同输入→同输出**，确保测试可复现。
//  注意：
//    - 本类为**纯栅格** A*，未内建导航网格/可视直线(LOS)/漏斗压路径；可在外层做路径后处理。
//    - 若需真正欧氏距离并仍保持可采纳性，请自行替换启发式实现（需注意整型代价与单调性）。
//
//  使用示例：
//    ```actionscript
//    // 1. 创建 5x3 网格，允许斜向但禁止卡角
//    var nav:AStarGrid = new AStarGrid(5, 3, true, false);
//    
//    // 2. 设置地图（二维数组，1=可走，0=不可走）
//    var walkMatrix:Array = [
//        [1,1,1,0,1],
//        [1,0,1,0,1],
//        [1,1,1,1,1]
//    ];
//    nav.setWalkableMatrix(walkMatrix);
//    
//    // 3. 可选：设置地形权重（额外成本）
//    var weightMatrix:Array = [
//        [0,0,5,0,0],  // 泥地成本高
//        [0,0,2,0,0],
//        [0,0,0,0,0]
//    ];
//    nav.setWeightMatrix(weightMatrix);
//    
//    // 4. 寻路：从(0,0)到(4,2)
//    var path:Array = nav.find(0, 0, 4, 2);
//    if (path != null) {
//        for (var i:Number = 0; i < path.length; i++) {
//            trace("步骤" + i + ": (" + path[i].x + "," + path[i].y + ")");
//        }
//    }
//    ```
//
//  最佳实践：
//    - 对于大地图（>100x100），建议启用 maxExpand 限制，避免极端情况下性能问题
//    - 4向寻路推荐 Manhattan 启发式，8向寻路推荐 Octile 启发式
//    - 权重值通常在 0-10 范围内，过大会影响路径自然度
//    - 频繁寻路时，复用同一个 AStarGrid 实例而非重复创建
//    - 动态障碍变化时，只需调用 setWalkable(x,y,false) 无需重新创建网格
// ===============================================================

class org.flashNight.neur.Navigation.AStarGrid
{
    // -----------------------------------------------------------
    // 常量：整型代价（避免浮点运算）
    // -----------------------------------------------------------
    /** 上下左右移动成本（单位步长 × 10 的等比例整数） */
    private static var COST_STRAIGHT:Number = 10;
    /** 斜向移动成本的整数近似（≈ √2 × 10） */
    private static var COST_DIAGONAL:Number = 14;

    // -----------------------------------------------------------
    // 网格属性（宽、高、总格数）
    // -----------------------------------------------------------
    /** 网格宽度（格数） */
    private var _w:Number;
    /** 网格高度（格数） */
    private var _h:Number;
    /** 网格总格数（_w * _h） */
    private var _size:Number;

    // -----------------------------------------------------------
    // 地图数据（可走性、地形权重）
    // -----------------------------------------------------------
    /**
     * 可走性数组（长度 = _size）
     * - 1：可走；0：不可走
     * - 可用 setWalkableMatrix / setWalkable 定义与修改
     */
    private var _walk:Array;   // Array<Number>

    /**
     * 地形权重数组（长度 = _size）
     * - 语义：对进入该格的“额外成本”（加法），默认 0 表示无额外成本
     * - 允许 >=0 的整数；负值将被钳位为 0
     */
    private var _weight:Array; // Array<Number>

    // -----------------------------------------------------------
    // 搜索状态（按格索引存储）
    // -----------------------------------------------------------
    /** g：从起点到当前格的实际累计成本 */
    private var _g:Array;       // Array<Number>
    /** f：评估代价 = g + h（h 为启发式估计） */
    private var _f:Array;       // Array<Number>
    /**
     * 父节点索引：回溯路径用
     * - -1 表示无父（通常用于起点）
     */
    private var _parent:Array;  // Array<Number>

    /**
     * 关闭标记（长度 = _size）
     * - 存储 _searchId：若等于本轮 searchId，即认为该格在“关闭表”
     * - 通过递增 searchId 达到“逻辑清空”效果，避免每次全量重置
     */
    private var _closedMark:Array;   // Array<Number>

    /**
     * 开放表位置（长度 = _size）
     * - 0：不在堆
     * - >0：在堆中位置下标 + 1
     * - 用于 O(1) 知道节点是否在开放堆，以及其位置，便于堆内上浮
     */
    private var _openPos:Array;      // Array<Number>

    // -----------------------------------------------------------
    // 开放表（二叉堆）
    // -----------------------------------------------------------
    /**
     * 二叉最小堆（存放“格子索引”）
     * - 根在 0 下标
     * - 比较优先级：先 f 小者优先，若 f 相等则 g 小者优先（倾向于“更近起点”，路径更平滑）
     */
    private var _openHeap:Array; // Array<Number>
    /** 当前堆内元素个数 */
    private var _openCount:Number;

    // -----------------------------------------------------------
    // 搜索配置
    // -----------------------------------------------------------
    /** 是否允许斜向移动（8 邻接）；false 则仅 4 邻接 */
    private var _allowDiagonal:Boolean;
    /**
     * 是否允许卡角（仅当允许斜向时有意义）
     * - false：若斜向移动，则要求相邻的两个直角侧格均可走（防穿角）
     * - true ：允许从障碍角落处“擦角”过去
     */
    private var _allowCornerCut:Boolean;

    /**
     * 启发式类型：
     *   0 = Manhattan（4 邻接常用）
     *   1 = Diagonal / Octile（8 邻接常用，默认）
     *   2 = Euclidean（内部使用整数近似：14*min + 10*(max-min)）
     */
    private var _heuristicType:Number;

    // -----------------------------------------------------------
    // 运行态
    // -----------------------------------------------------------
    /**
     * 搜索轮次标识
     * - 每次 find() 自增一次
     * - 与 _closedMark 协同用于"逻辑清空"关闭表
     * - 溢出时回绕到 1，只影响标记不影响正确性
     */
    private var _searchId:Number;

    // ===========================================================
    // 构造 与 初始化
    // ===========================================================

    /**
     * 构造函数
     * @param w 网格宽度（格数，缺省 1）
     * @param h 网格高度（格数，缺省 1）
     * @param allowDiagonal 是否允许斜向（缺省 true）
     * @param allowCornerCut 是否允许卡角（缺省 false）
     *
     * 行为：
     * - 调用 resize(w,h) 分配与初始化内部数组；
     * - 缺省启发式为 Octile（_heuristicType=1）。
     */
    public function AStarGrid(w:Number, h:Number, allowDiagonal:Boolean, allowCornerCut:Boolean)
    {
        if (w == undefined) w = 1;
        if (h == undefined) h = 1;
        _allowDiagonal    = (allowDiagonal == undefined) ? true  : allowDiagonal;
        _allowCornerCut   = (allowCornerCut == undefined) ? false : allowCornerCut;
        _heuristicType    = 1; // 缺省使用 Octile/Diagonal 启发
        _searchId         = 1;
        resize(w, h);
    }

    /**
     * 重新分配网格与搜索状态（会清空地图数据）
     * @param w 新的网格宽（格数）
     * @param h 新的网格高（格数）
     *
     * 初始化：
     * - _walk 全部设为 1（可走）
     * - _weight 全部设为 0（无额外成本）
     * - g/f/parent/closedMark/openPos 清零/默认值
     * - 清空开放堆
     *
     * 注意：
     * - 调用后，若需要障碍或权重，请再调用 setWalkableMatrix / setWeightMatrix。
     */
    public function resize(w:Number, h:Number):Void
    {
        _w = w;
        _h = h;
        _size = _w * _h;

        _walk   = new Array(_size);
        _weight = new Array(_size);
        _g      = new Array(_size);
        _f      = new Array(_size);
        _parent = new Array(_size);
        _closedMark = new Array(_size);
        _openPos    = new Array(_size);

        var i:Number = 0;
        while (i < _size)
        {
            _walk[i] = 1;
            _weight[i] = 0; // 默认无额外地形成本（与注释“>=1”不同，这里采用“额外成本=0”为默认）
            _g[i] = 0;
            _f[i] = 0;
            _parent[i] = -1;
            _closedMark[i] = 0;
            _openPos[i] = 0;
            i++;
        }

        _openHeap = [];
        _openCount = 0;
    }

    // ===========================================================
    // 配置接口
    // ===========================================================

    /**
     * 设置启发式类型
     * @param type 0=Manhattan, 1=Octile, 2=Euclidean(近似)
     * - 推荐：4 邻接→Manhattan；8 邻接→Octile（默认）
     * - Euclidean 为整数近似，通常与 Octile 行为接近
     */
    public function setHeuristic(type:Number):Void
    {
        if (type < 0) type = 0;
        if (type > 2) type = 2;
        _heuristicType = type;
    }

    /**
     * 是否允许斜向移动（8 邻接）
     * @param allow true 允许 / false 不允许（4 邻接）
     */
    public function setAllowDiagonal(allow:Boolean):Void
    {
        _allowDiagonal = allow;
    }

    /**
     * 是否允许卡角（仅在允许斜向时生效）
     * @param allow true 允许擦角 / false 禁止（要求两侧直角格均可走）
     */
    public function setAllowCornerCut(allow:Boolean):Void
    {
        _allowCornerCut = allow;
    }

    /**
     * 批量设置可走性（支持二维/一维）
     * @param matrix
     *  - 若为二维：长度等于 _h，且每行是 Array，按 [y][x] 读取
     *  - 若为一维：长度至少 _size，按线性索引写入；多余元素被忽略
     *  - 非 0 视为可走，0/假值视为不可走
     *
     * 拷贝语义：
     *  - 数据为**值写入**而不保留引用，调用后可安全修改原 matrix
     *  - 频繁整表 setWalkableMatrix 有成本，动态障碍建议只调用 setWalkable(x,y,false) 改增量
     */
    public function setWalkableMatrix(matrix:Array):Void
    {
        var i:Number, x:Number, y:Number, idx:Number;

        // 猜测二维：matrix.length == _h && matrix[0] is Array
        if (matrix != null && matrix.length == _h && (matrix[0] instanceof Array))
        {
            y = 0;
            while (y < _h)
            {
                var row:Array = matrix[y];
                x = 0;
                while (x < _w)
                {
                    idx = y * _w + x;
                    _walk[idx] = (row[x]) ? 1 : 0;
                    x++;
                }
                y++;
            }
        }
        else
        {
            // 一维：长度至少 _size
            i = 0;
            while (i < _size)
            {
                _walk[i] = (matrix[i]) ? 1 : 0;
                i++;
            }
        }
    }

    /**
     * 批量设置地形权重（支持二维/一维）
     * @param matrix
     *  - 二维：长度等于 _h，按 [y][x]；一维：长度至少 _size，多余元素被忽略
     *  - 值含义：进入该格的**额外成本**（>=0），负值将被钳为 0
     *  - 注意：权重是"加法"，不是"乘法倍率"
     *
     * 拷贝语义：
     *  - 数据为**值写入**而不保留引用，调用后可安全修改原 matrix
     *  - 频繁整表 setWeightMatrix 有成本，动态权重建议只调用 setWeight(x,y,v) 改增量
     */
    public function setWeightMatrix(matrix:Array):Void
    {
        var i:Number, x:Number, y:Number, idx:Number;

        if (matrix != null && matrix.length == _h && (matrix[0] instanceof Array))
        {
            y = 0;
            while (y < _h)
            {
                var row:Array = matrix[y];
                x = 0;
                while (x < _w)
                {
                    idx = y * _w + x;
                    var wv:Number = row[x];
                    _weight[idx] = (wv >= 0) ? wv : 0;
                    x++;
                }
                y++;
            }
        }
        else
        {
            i = 0;
            while (i < _size)
            {
                var v:Number = matrix[i];
                _weight[i] = (v >= 0) ? v : 0;
                i++;
            }
        }
    }

    /**
     * 设置单格可走性
     * @param x 列坐标（0.._w-1）
     * @param y 行坐标（0.._h-1）
     * @param walkable true=可走 / false=不可走
     */
    public function setWalkable(x:Number, y:Number, walkable:Boolean):Void
    {
        if (!inBounds(x, y)) return;
        _walk[y * _w + x] = walkable ? 1 : 0;
    }

    /**
     * 设置单格权重
     * @param x 列坐标（0.._w-1）
     * @param y 行坐标（0.._h-1）
     * @param v 进入该格的额外成本（>=0；负值将被钳为 0）
     */
    public function setWeight(x:Number, y:Number, v:Number):Void
    {
        if (!inBounds(x, y)) return;
        if (v < 0) v = 0; // 权重不能为负
        _weight[y * _w + x] = v;
    }

    // ===========================================================
    // 寻路接口
    // ===========================================================

    /**
     * 计算从起点到终点的路径（A*）
     * @param sx 起点 x
     * @param sy 起点 y
     * @param gx 终点 x
     * @param gy 终点 y
     * @param maxExpand 可选：最大展开节点数上限（>0 有效；用于防止极端卡死）
     *   - 达到上限返回 null，但**不代表地图无路**，而是**被限流**
     *   - 建议值：小地图(<50x50)可不设；若需限流，可设为 0.25×_size ~ 1.0×_size，或改用**按帧预算**的分步搜索接口在外层限时
     * @return Array<{x:Number,y:Number}>：从起点到终点；若无路或超限返回 null
     *
     * 过程要点：
     *  - 使用 _searchId 实现“关闭表逻辑清空”，避免每次重新分配；
     *  - 每次搜索会将 _openPos 全表置 0（确保开放堆状态不被上次污染）；
     *  - 按 f 优先、f 相等时 g 小优先的最小堆。
     *
     * 注意：
     *  - 起点/终点若不可走，直接返回 null（如需允许终点不可走，可在此修改策略）；
     *  - expanded > _size 的防御阈值仅为保险（理论不应触发）。
     */
    public function find(sx:Number, sy:Number, gx:Number, gy:Number, maxExpand:Number):Array
    {
        if (!inBounds(sx, sy) || !inBounds(gx, gy)) return null;

        var sIdx:Number = sy * _w + sx;
        var gIdx:Number = gy * _w + gx;

        if (_walk[sIdx] == 0) return null;
        if (_walk[gIdx] == 0) return null; // 如需允许终点不可走可在此调整策略

        // 清空开放堆结构
        _openHeap.splice(0, _openHeap.length);
        _openCount = 0;

        // 重要：清空开放表位置标记，避免上次搜索残留状态污染
        var i:Number = 0;
        while (i < _size) {
            _openPos[i] = 0;
            i++;
        }

        // 搜索轮次自增（避免整表清空 closed 标记）
        _searchId++;
        if (_searchId > 2000000000) _searchId = 1; // 简单防溢出

        // 初始化起点
        _g[sIdx] = 0;
        _f[sIdx] = heuristicCost(sx, sy, gx, gy);
        _parent[sIdx] = -1;
        heapPush(sIdx);

        var expanded:Number = 0;
        var curIdx:Number, cx:Number, cy:Number;

        while (_openCount > 0)
        {
            if (maxExpand != undefined && maxExpand > 0 && expanded >= maxExpand) {
                // 达到扩展上限，宣告失败
                return null;
            }

            curIdx = heapPop();
            if (curIdx == gIdx)
            {
                return buildPath(gIdx); // 命中，回溯路径
            }

            _closedMark[curIdx] = _searchId;
            expanded++;

            // 保险阈值：防止实现 bug 导致卡死（理论不触发）
            if (expanded > _size) {
                return null;
            }

            // 当前坐标
            cx = curIdx % _w;
            cy = (curIdx - cx) / _w;

            // 扩展邻居
            expandNeighbors(curIdx, cx, cy, gx, gy);
        }

        return null; // 无路
    }

    // ===========================================================
    // 私有：邻居扩展
    // ===========================================================

    /**
     * 扩展当前节点的邻居（根据 4/8 邻接）
     * - 实现无递归、尽量减少临时对象创建
     * - 斜向且禁止卡角时，会校验两侧直角格是否可走
     * - 采用“额外成本”为加法（stepCost + weight[nIdx]）
     *
     * @param curIdx 当前节点线性索引
     * @param cx 当前节点 x
     * @param cy 当前节点 y
     * @param gx 目标 x（用于启发式）
     * @param gy 目标 y（用于启发式）
     */
    private function expandNeighbors(curIdx:Number, cx:Number, cy:Number, gx:Number, gy:Number):Void
    {
        // 4 或 8 邻接的偏移表（注：此处每次创建数组，若需极致性能可改为静态常量缓存）
        var dxs:Array, dys:Array;
        if (_allowDiagonal)
        {
            dxs = [ 1,-1, 0, 0,  1, 1,-1,-1 ];
            dys = [ 0, 0, 1,-1,  1,-1, 1,-1 ];
        }
        else
        {
            dxs = [ 1,-1, 0, 0 ];
            dys = [ 0, 0, 1,-1 ];
        }

        var len:Number = dxs.length;

        for (var i:Number = 0; i < len; i++)
        {
            var nx:Number = cx + dxs[i];
            var ny:Number = cy + dys[i];

            if (inBounds(nx, ny))
            {
                var nIdx:Number = ny * _w + nx;

                // 不可走或已关闭则跳过
                if (_walk[nIdx] != 0 && _closedMark[nIdx] != _searchId)
                {
                    // 斜向卡角处理（防穿角逻辑）
                    var diag:Boolean = (dxs[i] != 0 && dys[i] != 0);
                    if (diag && !_allowCornerCut)
                    {
                        // 斜向移动时检查两个直角邻格：从 (cx,cy) 到 (nx,ny)
                        // 需要 (cx,ny) 和 (nx,cy) 都可走，否则视为"卡角穿越"
                        // 示例：从(0,0)到(1,1)，需要(0,1)和(1,0)都可走
                        var side1Walk:Number = _walk[cy * _w + nx]; // (cx,ny)
                        var side2Walk:Number = _walk[ny * _w + cx]; // (nx,cy)
                        if (side1Walk == 0 || side2Walk == 0)
                        {
                            continue; // 跳过此斜向方向
                        }
                    }

                    // 计算移动代价（基础步长 + 目标格权重）
                    var stepCost:Number = diag ? COST_DIAGONAL : COST_STRAIGHT;
                    var tentativeG:Number = _g[curIdx] + stepCost + _weight[nIdx];

                    var pos:Number = _openPos[nIdx]; // 在堆中的位置（0=不在）
                    if (pos == 0)
                    {
                        // 节点首次发现：加入开放表
                        _parent[nIdx] = curIdx;
                        _g[nIdx] = tentativeG;
                        _f[nIdx] = tentativeG + heuristicCost(nx, ny, gx, gy);
                        heapPush(nIdx);
                    }
                    else
                    {
                        // 节点已在开放表：尝试路径松弛（Relaxation）
                        // 若通过当前节点到达邻居的成本更低，则更新其路径
                        if (tentativeG < _g[nIdx])
                        {
                            _parent[nIdx] = curIdx;  // 更新父节点
                            _g[nIdx] = tentativeG;   // 更新实际成本
                            _f[nIdx] = tentativeG + heuristicCost(nx, ny, gx, gy); // 更新总估值
                            // 因为 f 值变小，需要向上调整堆位置（pos-1 因为内部存储是位置+1）
                            heapUp(pos - 1);
                        }
                    }
                }
            }
        }
    }

    // ===========================================================
    // 私有：路径回溯
    // ===========================================================

    /**
     * 从终点索引回溯到起点，构建路径并反转为“起点→终点”
     * @param endIdx 终点索引
     * @return Array<{x:Number,y:Number}>
     */
    private function buildPath(endIdx:Number):Array
    {
        var path:Array = [];
        var idx:Number = endIdx;

        while (idx != -1)
        {
            var x:Number = idx % _w;
            var y:Number = (idx - x) / _w;
            path.push({x:x, y:y});
            idx = _parent[idx];
        }

        path.reverse(); // 起点 -> 终点
        return path;
    }

    // ===========================================================
    // 私有：启发式代价 h（整数）
    // ===========================================================

    /**
     * 计算启发式代价 h（整数）
     *  - 0: Manhattan    => (dx + dy) * 10
     *  - 1: Diagonal/Oct => 10 * max(dx,dy) + 4 * min(dx,dy)    // 等价于 14*min + 10*(max-min)
     *  - 2: Euclidean    => 采用无根号近似：14*min + 10*(max-min)
     *
     * 可采纳性：
     *  - 对均匀步长与相应邻接模型，上述近似通常不超过真实最短路径代价（保持 A* 最优性）。
     *
     * @param x 当前 x
     * @param y 当前 y
     * @param gx 目标 x
     * @param gy 目标 y
     */
    private function heuristicCost(x:Number, y:Number, gx:Number, gy:Number):Number
    {
        var dx:Number = (x > gx) ? (x - gx) : (gx - x);
        var dy:Number = (y > gy) ? (y - gy) : (gy - y);

        if (_heuristicType == 0)
        {
            // Manhattan
            return (dx + dy) * 10;
        }
        else if (_heuristicType == 1)
        {
            // Diagonal / Octile: 14*min + 10*(max-min) = 10*max + 4*min
            var mn:Number = (dx < dy) ? dx : dy;
            var mx:Number = (dx > dy) ? dx : dy;
            return mx * 10 + mn * 4;
        }
        else
        {
            // Euclidean（整数近似）
            var mx:Number = (dx > dy) ? dx : dy;
            var mn2:Number = (dx < dy) ? dx : dy;
            return mn2 * 14 + (mx - mn2) * 10;
        }
    }

    // ===========================================================
    // 私有：二叉堆（开放表）
    // ===========================================================

    /**
     * 入堆（最小堆：f 小优先，f 相等时 g 小优先）
     * @param idx 节点索引
     */
    private function heapPush(idx:Number):Void
    {
        _openHeap[_openCount] = idx;
        _openPos[idx] = _openCount + 1; // 位置+1
        heapUp(_openCount);
        _openCount++;
    }

    /**
     * 出堆（弹出最优节点）
     * @return 最优节点索引
     */
    private function heapPop():Number
    {
        var ret:Number = _openHeap[0];
        _openCount--;
        if (_openCount > 0)
        {
            var lastIdx:Number = _openHeap[_openCount];
            _openHeap[0] = lastIdx;
            _openPos[lastIdx] = 1;
            _openHeap.length = _openCount;
            _openPos[ret] = 0;
            heapDown(0);
        }
        else
        {
            _openHeap.length = 0;
            _openPos[ret] = 0;
        }
        return ret;
    }

    /**
     * 自底向上堆调整（上浮）
     * @param i 起始位置
     */
    private function heapUp(i:Number):Void
    {
        var heap:Array = _openHeap;
        var node:Number = heap[i];

        while (i > 0)
        {
            var p:Number = (i - 1) >> 1; // 父
            var parentIdx:Number = heap[p];

            if (less(node, parentIdx))
            {
                // 交换并更新位置表
                heap[i] = parentIdx;
                _openPos[parentIdx] = i + 1;
                i = p;
            }
            else
            {
                break;
            }
        }

        heap[i] = node;
        _openPos[node] = i + 1;
    }

    /**
     * 自顶向下堆调整（下沉）
     * @param i 起始位置
     */
    private function heapDown(i:Number):Void
    {
        var heap:Array = _openHeap;
        var size:Number = _openCount;
        var node:Number = heap[i];

        while (true)
        {
            var li:Number = (i << 1) + 1; // 左子
            var ri:Number = li + 1;       // 右子

            if (li >= size) break;

            var best:Number = li;
            var liIdx:Number = heap[li];
            var riIdx:Number;

            if (ri < size)
            {
                riIdx = heap[ri];
                if (less(riIdx, liIdx)) best = ri;
            }

            var bestIdx:Number = heap[best];
            if (less(bestIdx, node))
            {
                heap[i] = bestIdx;
                _openPos[bestIdx] = i + 1;
                i = best;
            }
            else
            {
                break;
            }
        }

        heap[i] = node;
        _openPos[node] = i + 1;
    }

    /**
     * 比较函数（用于堆）
     * @param aIdx 节点 A
     * @param bIdx 节点 B
     * @return true 若 A 的优先级高于 B（f 更小；f 相等则 g 更小）
     */
    private function less(aIdx:Number, bIdx:Number):Boolean
    {
        var fa:Number = _f[aIdx];
        var fb:Number = _f[bIdx];
        if (fa < fb) return true;
        if (fa > fb) return false;
        var ga:Number = _g[aIdx];
        var gb:Number = _g[bIdx];
        return (ga < gb);
    }

    // ===========================================================
    // 私有：工具
    // ===========================================================

    /**
     * 边界检查
     * @param x 列（0.._w-1）
     * @param y 行（0.._h-1）
     * @return true 若在边界内
     */
    private function inBounds(x:Number, y:Number):Boolean
    {
        return (x >= 0 && y >= 0 && x < _w && y < _h);
    }

    // ===========================================================
    // 只读信息
    // ===========================================================

    /** 获取网格宽（格数） */
    public function getWidth():Number { return _w; }
    /** 获取网格高（格数） */
    public function getHeight():Number { return _h; }
    
    // ===========================================================
    // 查询接口（可选扩展）
    // ===========================================================
    
    /**
     * 查询指定坐标的可走性
     * @param x 列坐标（0.._w-1）
     * @param y 行坐标（0.._h-1）
     * @return true=可走 / false=不可走（越界也返回 false）
     */
    public function isWalkable(x:Number, y:Number):Boolean
    {
        if (!inBounds(x, y)) return false;
        return _walk[y * _w + x] != 0;
    }
    
    /**
     * 查询指定坐标的权重
     * @param x 列坐标（0.._w-1）
     * @param y 行坐标（0.._h-1）
     * @return 权重值（>=0）；越界返回 0
     */
    public function getWeight(x:Number, y:Number):Number
    {
        if (!inBounds(x, y)) return 0;
        return _weight[y * _w + x];
    }
}
