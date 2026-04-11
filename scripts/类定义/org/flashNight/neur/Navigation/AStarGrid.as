// ===============================================================
//  A* Pathfinding (Grid) —— 栅格 A* 寻路（ActionScript 2 · AVM1 极限优化版）
// ---------------------------------------------------------------
//  设计目标：
//    1) 高性能：全热路径内联（零方法调用开销）、静态方向表、脏列表增量清空、
//       局部变量缓存（H01）、严格等号（H08）、整型代价。
//    2) 易集成：支持 4/8 邻接、禁止卡角（防穿角）、地形权重（加法成本）。
//    3) 稳定鲁棒：下标/边界检查完备；搜索轮次 searchId 复用标记避免全表清空。
//    4) 易调优：Manhattan / Octile 两种启发式；maxExpand 限流。
//    5) 帧预算：findInit/findStep/getResult 分步搜索接口，可跨帧分摊。
//  复杂度：
//    - 典型 A* 时间 O(E log V)，二叉堆 push/pop O(log V)，空间 O(V)。
//  AVM1 性能优化要点：
//    - 方法调用 ~1340ns、函数调用 ~485ns → 热路径全部内联到 findStep()
//    - new Array() ~550ns + GC → 静态方向表 _DX4/_DY4/_DX8/_DY8 类级复用
//    - splice ~4231ns → heap 清空用 length=0 (H20/H21)
//    - O(size) _openPos 重置 → 脏列表仅清上次搜索触及的索引
//    - 实例变量 ~144ns/次 → 热循环入口全部缓存到局部寄存器变量 (H01)
//    - == ~21ns vs === ~19ns → 热路径一律 === (H08)
//    - Math.abs ~249ns → 三元 (H14)；Math.min ~264ns → 三元 (H15)
//  坐标与单位：
//    - 格坐标，非像素；线性索引 = y * _w + x（行主序）。
//    - 代价基于 COST_STRAIGHT=10 的整数刻度，权重为加法"额外成本"。
//  返回路径：
//    - [{x:Number, y:Number}, ...]，从起点到终点；无路返回 null。
//  启发式：
//    - 0 = Manhattan（4 邻接）；1 = Octile（8 邻接，默认）。
//    - 注：原 type 2 "Euclidean近似" 与 Octile 数学等价，已合并。
//  确定性：
//    - 堆比较：先 f 小，再 g 小 → 同输入→同输出，测试可复现。
//  分步搜索 API（帧预算模式）：
//    - findInit(sx,sy,gx,gy) → 返回 1(平凡路径)/0(搜索已启动)/-1(无效输入)
//    - findStep(budget)      → 返回 1(找到)/0(预算耗尽)/-1(无路)
//    - getResult()           → 返回路径 Array 或 null
//    - find() 是 findInit+findStep 的便捷封装
// ===============================================================

class org.flashNight.neur.Navigation.AStarGrid
{
    // -----------------------------------------------------------
    // 常量：整型代价
    // -----------------------------------------------------------
    private static var COST_STRAIGHT:Number = 10;
    private static var COST_DIAGONAL:Number = 14;

    // -----------------------------------------------------------
    // 静态方向表（类级分配一次，避免热路径 new Array S03）
    // 索引 0-3: 正交（右/左/下/上）
    // 索引 4-7: 斜向（右下/右上/左下/左上）
    // -----------------------------------------------------------
    private static var _DX4:Array = [1, -1, 0, 0];
    private static var _DY4:Array = [0, 0, 1, -1];
    private static var _DX8:Array = [1, -1, 0, 0, 1, 1, -1, -1];
    private static var _DY8:Array = [0, 0, 1, -1, 1, -1, 1, -1];

    // -----------------------------------------------------------
    // 网格属性
    // -----------------------------------------------------------
    private var _w:Number;
    private var _h:Number;
    private var _size:Number;

    // -----------------------------------------------------------
    // 地图数据
    // -----------------------------------------------------------
    private var _walk:Array;
    private var _weight:Array;

    // -----------------------------------------------------------
    // 搜索状态（按格索引存储）
    // -----------------------------------------------------------
    private var _g:Array;
    private var _f:Array;
    private var _parent:Array;
    private var _closedMark:Array;
    private var _openPos:Array;

    // -----------------------------------------------------------
    // 脏列表：追踪 _openPos 被修改过的索引
    // 避免每次 find() 前 O(size) 全量清零
    // -----------------------------------------------------------
    private var _dirtyList:Array;
    private var _dirtyCount:Number;

    // -----------------------------------------------------------
    // 开放表（二叉最小堆，根在 0）
    // -----------------------------------------------------------
    private var _openHeap:Array;
    private var _openCount:Number;

    // -----------------------------------------------------------
    // 配置
    // -----------------------------------------------------------
    private var _allowDiagonal:Boolean;
    private var _allowCornerCut:Boolean;
    private var _heuristicType:Number;

    // -----------------------------------------------------------
    // 运行态
    // -----------------------------------------------------------
    private var _searchId:Number;
    private var _lastExpanded:Number;

    // -----------------------------------------------------------
    // 分步搜索持久状态
    // -----------------------------------------------------------
    private var _stepActive:Boolean;
    private var _stepGx:Number;
    private var _stepGy:Number;
    private var _stepGIdx:Number;
    private var _stepResult:Array;

    // ===========================================================
    // 构造与初始化
    // ===========================================================

    /**
     * 构造函数
     * @param w 网格宽度（格数，缺省 1）
     * @param h 网格高度（格数，缺省 1）
     * @param allowDiagonal 是否允许斜向（缺省 true）
     * @param allowCornerCut 是否允许卡角（缺省 false）
     */
    public function AStarGrid(w:Number, h:Number, allowDiagonal:Boolean, allowCornerCut:Boolean)
    {
        if (w == undefined) w = 1;
        if (h == undefined) h = 1;
        _allowDiagonal  = (allowDiagonal == undefined) ? true : allowDiagonal;
        _allowCornerCut = (allowCornerCut == undefined) ? false : allowCornerCut;
        _heuristicType  = 1;
        _searchId       = 1;
        _lastExpanded   = 0;
        _stepActive     = false;
        resize(w, h);
    }

    /**
     * 重新分配网格（清空地图数据和搜索状态）
     */
    public function resize(w:Number, h:Number):Void
    {
        _w = w;
        _h = h;
        var sz:Number = w * h;
        _size = sz;

        _walk       = new Array(sz);
        _weight     = new Array(sz);
        _g          = new Array(sz);
        _f          = new Array(sz);
        _parent     = new Array(sz);
        _closedMark = new Array(sz);
        _openPos    = new Array(sz);

        var i:Number = sz;
        while (--i >= 0)
        {
            _walk[i]       = 1;
            _weight[i]     = 0;
            _g[i]          = 0;
            _f[i]          = 0;
            _parent[i]     = -1;
            _closedMark[i] = 0;
            _openPos[i]    = 0;
        }

        _openHeap   = [];
        _openCount  = 0;
        _dirtyList  = [];
        _dirtyCount = 0;
        _stepActive = false;
    }

    // ===========================================================
    // 配置接口
    // ===========================================================

    /**
     * 设置启发式类型
     * @param type 0=Manhattan（4邻接推荐），1=Octile（8邻接推荐，默认）
     *   注：传入 2 等价于 1（原 "Euclidean近似" 与 Octile 数学相同，已合并）
     */
    public function setHeuristic(type:Number):Void
    {
        _heuristicType = (type === 0) ? 0 : 1;
    }

    /** 设置是否允许斜向移动（8邻接） */
    public function setAllowDiagonal(allow:Boolean):Void
    {
        _allowDiagonal = allow;
    }

    /** 设置是否允许卡角（仅斜向时有意义） */
    public function setAllowCornerCut(allow:Boolean):Void
    {
        _allowCornerCut = allow;
    }

    // ===========================================================
    // 地图数据接口
    // ===========================================================

    /**
     * 批量设置可走性（支持二维/一维）
     * 二维：[y][x]，长度 = _h；一维：线性索引，长度 >= _size
     */
    public function setWalkableMatrix(matrix:Array):Void
    {
        var i:Number, x:Number, y:Number, idx:Number;
        var mw:Number = _w;
        var mh:Number = _h;
        var msz:Number = _size;
        var wk:Array = _walk;

        if (matrix != null && matrix.length === mh && (matrix[0] instanceof Array))
        {
            y = 0;
            while (y < mh)
            {
                var row:Array = matrix[y];
                x = 0;
                idx = y * mw;
                while (x < mw)
                {
                    wk[idx] = (row[x]) ? 1 : 0;
                    x++;
                    idx++;
                }
                y++;
            }
        }
        else
        {
            i = 0;
            while (i < msz)
            {
                wk[i] = (matrix[i]) ? 1 : 0;
                i++;
            }
        }
    }

    /**
     * 批量设置地形权重（支持二维/一维）
     * 值含义：进入该格的额外成本（>=0），负值钳为 0
     */
    public function setWeightMatrix(matrix:Array):Void
    {
        var i:Number, x:Number, y:Number, idx:Number, wv:Number;
        var mw:Number = _w;
        var mh:Number = _h;
        var msz:Number = _size;
        var wt:Array = _weight;

        if (matrix != null && matrix.length === mh && (matrix[0] instanceof Array))
        {
            y = 0;
            while (y < mh)
            {
                var row:Array = matrix[y];
                x = 0;
                idx = y * mw;
                while (x < mw)
                {
                    wv = row[x];
                    wt[idx] = (wv >= 0) ? wv : 0;
                    x++;
                    idx++;
                }
                y++;
            }
        }
        else
        {
            i = 0;
            while (i < msz)
            {
                wv = matrix[i];
                wt[i] = (wv >= 0) ? wv : 0;
                i++;
            }
        }
    }

    /** 设置单格可走性 */
    public function setWalkable(x:Number, y:Number, walkable:Boolean):Void
    {
        if (x >= 0 && y >= 0 && x < _w && y < _h)
            _walk[y * _w + x] = walkable ? 1 : 0;
    }

    /** 设置单格权重（>=0，负值钳为 0） */
    public function setWeight(x:Number, y:Number, v:Number):Void
    {
        if (x >= 0 && y >= 0 && x < _w && y < _h)
            _weight[y * _w + x] = (v >= 0) ? v : 0;
    }

    // ===========================================================
    // 寻路接口：一次性（便捷封装）
    // ===========================================================

    /**
     * 一次性寻路：从 (sx,sy) 到 (gx,gy)
     * @param maxExpand 最大展开节点数（可选，防极端卡死）
     * @return 路径数组（起点→终点），无路返回 null
     */
    public function find(sx:Number, sy:Number, gx:Number, gy:Number, maxExpand:Number):Array
    {
        var status:Number = findInit(sx, sy, gx, gy);
        if (status === 1) return _stepResult;
        if (status < 0) return null;

        var budget:Number = (maxExpand != undefined && maxExpand > 0) ? maxExpand : _size;
        status = findStep(budget);
        if (status === 1) return _stepResult;
        return null;
    }

    // ===========================================================
    // 寻路接口：分步搜索（帧预算模式）
    // ===========================================================

    /**
     * 初始化一次分步搜索
     * @return 1=平凡路径（起点=终点，结果已存入 getResult()），
     *         0=搜索已启动（后续调用 findStep），
     *        -1=无效输入（越界/不可走）
     */
    public function findInit(sx:Number, sy:Number, gx:Number, gy:Number):Number
    {
        var w:Number  = _w;
        var h:Number  = _h;

        // 内联边界检查
        if (sx < 0 || sy < 0 || sx >= w || sy >= h) return -1;
        if (gx < 0 || gy < 0 || gx >= w || gy >= h) return -1;

        var sI:Number = sy * w + sx;
        var gI:Number = gy * w + gx;
        var wk:Array  = _walk;

        if (wk[sI] === 0 || wk[gI] === 0) return -1;

        // 起点=终点：平凡路径
        if (sI === gI)
        {
            _stepResult   = [{x:sx, y:sy}];
            _lastExpanded = 0;
            _stepActive   = false;
            return 1;
        }

        // --- 清空开放堆 (H21: length=0 代替 splice) ---
        var hp:Array = _openHeap;
        hp.length = 0;

        // --- 脏列表增量清空 _openPos ---
        var op:Array = _openPos;
        var dl:Array = _dirtyList;
        var dc:Number = _dirtyCount;
        var i:Number = 0;
        while (i < dc)
        {
            op[dl[i]] = 0;
            i++;
        }

        // --- searchId 自增（逻辑清空 closed 表） ---
        var sid:Number = _searchId + 1;
        if (sid > 2000000000) sid = 1;
        _searchId = sid;

        // --- 起点启发式（内联） ---
        var hT:Number = _heuristicType;
        var dx:Number = sx - gx;
        if (dx < 0) dx = -dx;
        var dy:Number = sy - gy;
        if (dy < 0) dy = -dy;
        var hV:Number;
        if (hT === 0)
        {
            hV = (dx + dy) * 10;
        }
        else
        {
            var mn:Number = (dx < dy) ? dx : dy;
            var mx:Number = (dx > dy) ? dx : dy;
            hV = mx * 10 + mn * 4;
        }

        // --- 初始化起点 ---
        _g[sI]      = 0;
        _f[sI]      = hV;
        _parent[sI] = -1;

        // heapPush 起点
        hp[0]   = sI;
        op[sI]  = 1;
        dl[0]   = sI;

        // --- 写回实例状态 ---
        _openCount    = 1;
        _dirtyCount   = 1;
        _lastExpanded = 0;
        _stepGx       = gx;
        _stepGy       = gy;
        _stepGIdx     = gI;
        _stepResult   = null;
        _stepActive   = true;

        return 0;
    }

    /**
     * 继续分步搜索（核心热路径，全内联优化）
     * @param budget 本次允许展开的最大节点数
     * @return 1=找到路径（调用 getResult() 获取），
     *         0=预算耗尽（下次继续 findStep），
     *        -1=确认无路
     *
     * AVM1 优化清单：
     *  - 所有实例数组/变量在入口缓存到局部寄存器 (H01)
     *  - inBounds/heuristicCost/less/heapUp/heapDown 全部内联（省 ~1340ns/call）
     *  - 方向表从静态 _DX8/_DY8 读取（省 new Array ~550ns/call）
     *  - === 代替 ==（H08）、三元 abs（H14）、三元 min/max（H15）
     */
    public function findStep(budget:Number):Number
    {
        if (!_stepActive) return -1;

        // =======================================================
        // 局部寄存器缓存（H01: 所有热路径变量一次性局部化）
        // =======================================================
        var w:Number    = _w;
        var h:Number    = _h;
        var sz:Number   = _size;
        var gx:Number   = _stepGx;
        var gy:Number   = _stepGy;
        var gI:Number   = _stepGIdx;
        var wk:Array    = _walk;
        var wt:Array    = _weight;
        var ga:Array    = _g;
        var fa:Array    = _f;
        var pr:Array    = _parent;
        var cm:Array    = _closedMark;
        var op:Array    = _openPos;
        var hp:Array    = _openHeap;
        var oc:Number   = _openCount;
        var dl:Array    = _dirtyList;
        var dc:Number   = _dirtyCount;
        var sid:Number  = _searchId;
        var diag:Boolean    = _allowDiagonal;
        var cut:Boolean     = _allowCornerCut;
        var hT:Number       = _heuristicType;
        var dxA:Array   = diag ? _DX8 : _DX4;
        var dyA:Array   = diag ? _DY8 : _DY4;
        var nLen:Number = diag ? 8 : 4;
        var wm1:Number  = w - 1;
        var hm1:Number  = h - 1;
        var exp:Number  = _lastExpanded;

        // =======================================================
        // 变量声明集中到入口（AVM1 最佳实践）
        // =======================================================
        var curI:Number, cx:Number, cy:Number, curG:Number;
        var k:Number, ddx:Number, ddy:Number;
        var nx:Number, ny:Number, nI:Number;
        var sc:Number, tG:Number, pos:Number;
        var dx:Number, dy:Number, mn:Number, mx:Number, hV:Number;
        var hi:Number, nd:Number, pi:Number, pn:Number;
        var lc:Number, rc:Number, bt:Number, bn:Number;
        var tf1:Number, tf2:Number;

        // =======================================================
        // 主搜索循环
        // =======================================================
        while (oc > 0 && budget > 0)
        {
            budget--;

            // ===================================================
            // heapPop 内联：弹出 f 最小节点
            // ===================================================
            curI = hp[0];
            oc--;
            if (oc > 0)
            {
                nd = hp[oc];
                hp[0] = nd;
                op[nd] = 1;
                hp.length = oc;
                op[curI] = 0;

                // --- heapDown(0) 内联 ---
                hi = 0;
                while (true)
                {
                    lc = (hi << 1) + 1;
                    rc = lc + 1;
                    if (lc >= oc) break;
                    bt = lc;
                    if (rc < oc)
                    {
                        // inline less(hp[rc], hp[lc])
                        tf1 = fa[hp[rc]];
                        tf2 = fa[hp[lc]];
                        if (tf1 < tf2 || (tf1 === tf2 && ga[hp[rc]] < ga[hp[lc]])) bt = rc;
                    }
                    bn = hp[bt];
                    tf1 = fa[bn];
                    tf2 = fa[nd];
                    if (tf1 < tf2 || (tf1 === tf2 && ga[bn] < ga[nd]))
                    {
                        hp[hi] = bn;
                        op[bn] = hi + 1;
                        hi = bt;
                    }
                    else
                    {
                        break;
                    }
                }
                hp[hi] = nd;
                op[nd] = hi + 1;
            }
            else
            {
                hp.length = 0;
                op[curI] = 0;
            }

            // ===================================================
            // 目标检测
            // ===================================================
            if (curI === gI)
            {
                _openCount = oc;
                _dirtyCount = dc;
                _lastExpanded = exp;
                _stepResult = buildPath(curI);
                _stepActive = false;
                return 1;
            }

            // 标记关闭
            cm[curI] = sid;
            exp++;

            // 保险阈值
            if (exp > sz)
            {
                _openCount = oc;
                _dirtyCount = dc;
                _lastExpanded = exp;
                _stepActive = false;
                return -1;
            }

            // 当前坐标
            cx = curI % w;
            cy = (curI - cx) / w;
            curG = ga[curI];

            // ===================================================
            // 邻居扩展（静态方向表 + 全内联）
            // ===================================================
            k = 0;
            while (k < nLen)
            {
                ddx = dxA[k];
                ddy = dyA[k];
                nx = cx + ddx;
                ny = cy + ddy;

                // 内联边界检查
                if (nx >= 0 && nx <= wm1 && ny >= 0 && ny <= hm1)
                {
                    nI = ny * w + nx;

                    // 可走性 + 关闭表检查
                    if (wk[nI] !== 0 && cm[nI] !== sid)
                    {
                        // --- 卡角检查（仅斜向方向 k >= 4） ---
                        // 从 (cx,cy) 到 (nx,ny) 的斜向移动
                        // 需要 (nx,cy) 和 (cx,ny) 都可走，否则视为穿角
                        if (k >= 4 && !cut)
                        {
                            if (wk[cy * w + nx] === 0 || wk[ny * w + cx] === 0)
                            {
                                k++;
                                continue;
                            }
                        }

                        // 移动代价 = 基础步长 + 目标格权重
                        sc = (k >= 4) ? 14 : 10;
                        tG = curG + sc + wt[nI];
                        pos = op[nI];

                        if (pos === 0)
                        {
                            // ---- 新节点：设值 + heapPush + heapUp ----
                            pr[nI] = curI;
                            ga[nI] = tG;

                            // 内联启发式
                            dx = nx - gx;
                            if (dx < 0) dx = -dx;
                            dy = ny - gy;
                            if (dy < 0) dy = -dy;
                            if (hT === 0)
                            {
                                hV = (dx + dy) * 10;
                            }
                            else
                            {
                                mn = (dx < dy) ? dx : dy;
                                mx = (dx > dy) ? dx : dy;
                                hV = mx * 10 + mn * 4;
                            }
                            fa[nI] = tG + hV;

                            // heapPush 内联
                            hp[oc] = nI;
                            op[nI] = oc + 1;
                            dl[dc] = nI;
                            dc++;

                            // heapUp(oc) 内联
                            hi = oc;
                            nd = nI;
                            while (hi > 0)
                            {
                                pi = (hi - 1) >> 1;
                                pn = hp[pi];
                                tf1 = fa[nd];
                                tf2 = fa[pn];
                                if (tf1 < tf2 || (tf1 === tf2 && ga[nd] < ga[pn]))
                                {
                                    hp[hi] = pn;
                                    op[pn] = hi + 1;
                                    hi = pi;
                                }
                                else
                                {
                                    break;
                                }
                            }
                            hp[hi] = nd;
                            op[nd] = hi + 1;
                            oc++;
                        }
                        else if (tG < ga[nI])
                        {
                            // ---- 松弛：更新路径 + heapUp ----
                            pr[nI] = curI;
                            ga[nI] = tG;

                            // 内联启发式
                            dx = nx - gx;
                            if (dx < 0) dx = -dx;
                            dy = ny - gy;
                            if (dy < 0) dy = -dy;
                            if (hT === 0)
                            {
                                hV = (dx + dy) * 10;
                            }
                            else
                            {
                                mn = (dx < dy) ? dx : dy;
                                mx = (dx > dy) ? dx : dy;
                                hV = mx * 10 + mn * 4;
                            }
                            fa[nI] = tG + hV;

                            // heapUp(pos - 1) 内联
                            hi = pos - 1;
                            nd = nI;
                            while (hi > 0)
                            {
                                pi = (hi - 1) >> 1;
                                pn = hp[pi];
                                tf1 = fa[nd];
                                tf2 = fa[pn];
                                if (tf1 < tf2 || (tf1 === tf2 && ga[nd] < ga[pn]))
                                {
                                    hp[hi] = pn;
                                    op[pn] = hi + 1;
                                    hi = pi;
                                }
                                else
                                {
                                    break;
                                }
                            }
                            hp[hi] = nd;
                            op[nd] = hi + 1;
                        }
                    }
                }
                k++;
            }
        }

        // 循环结束：堆空 → 无路；预算耗尽 → 搜索未完成
        _openCount = oc;
        _dirtyCount = dc;
        _lastExpanded = exp;

        if (oc === 0)
        {
            _stepActive = false;
            return -1;
        }
        return 0;
    }

    /**
     * 获取分步搜索结果（findStep 返回 1 后调用）
     * @return 路径数组或 null
     */
    public function getResult():Array
    {
        return _stepResult;
    }

    /**
     * 分步搜索是否仍在进行中
     */
    public function isSearchActive():Boolean
    {
        return _stepActive;
    }

    // ===========================================================
    // 路径回溯（私有，仅在找到目标时调用一次）
    // ===========================================================

    private function buildPath(endIdx:Number):Array
    {
        var path:Array = [];
        var idx:Number = endIdx;
        var w:Number = _w;
        var pa:Array = _parent;
        var x:Number, y:Number;

        while (idx !== -1)
        {
            x = idx % w;
            y = (idx - x) / w;
            path.push({x:x, y:y});
            idx = pa[idx];
        }

        path.reverse();
        return path;
    }

    // ===========================================================
    // 查询接口
    // ===========================================================

    /** 网格宽（格数） */
    public function getWidth():Number { return _w; }

    /** 网格高（格数） */
    public function getHeight():Number { return _h; }

    /** 查询单格可走性（越界返回 false） */
    public function isWalkable(x:Number, y:Number):Boolean
    {
        if (x < 0 || y < 0 || x >= _w || y >= _h) return false;
        return _walk[y * _w + x] !== 0;
    }

    /** 查询单格权重（越界返回 0） */
    public function getWeight(x:Number, y:Number):Number
    {
        if (x < 0 || y < 0 || x >= _w || y >= _h) return 0;
        return _weight[y * _w + x];
    }

    /** 上次搜索（find/findStep）展开的节点数 */
    public function getLastExpanded():Number { return _lastExpanded; }
}
