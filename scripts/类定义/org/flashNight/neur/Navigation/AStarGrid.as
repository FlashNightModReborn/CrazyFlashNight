// ===============================================================
// A* Pathfinding (Grid)
//
//  - 无递归，所有状态以数组保存，尽量减少对象创建。
//  - 开放表使用二叉堆（最小堆，按 f 值 + g 值打破平分）。
//  - 支持 4/8 邻接、禁止卡角、地形权重。
//  - 返回路径为 [{x:Number, y:Number}, ...]，从起点到终点。
// ===============================================================

class org.flashNight.neur.Navigation.AStarGrid
{
    // ---- 常量（采用整数权重，避免浮点） ----
    private static var COST_STRAIGHT:Number = 10; // 上下左右
    private static var COST_DIAGONAL:Number = 14; // 斜向近似 √2 * 10

    // ---- 网格属性 ----
    private var _w:Number;
    private var _h:Number;
    private var _size:Number;

    // walk: 1 可走 / 0 不可走；weight: 地形权重（>=1，默认1）
    private var _walk:Array;   // Array<Number>
    private var _weight:Array; // Array<Number>

    // ---- 搜索状态数组（按索引存储）----
    private var _g:Array;       // 消耗代价 g
    private var _f:Array;       // 评估代价 f = g + h
    private var _parent:Array;  // 父索引（-1 表示无）
    private var _closedMark:Array;   // 关闭标记（searchId）
    private var _openPos:Array;      // 在堆中的位置（0 表示不在堆，>0 表示堆下标+1）

    // ---- 开放表（二叉堆，存储的是“格子索引”）----
    private var _openHeap:Array; // 0-based 堆数组，存索引
    private var _openCount:Number;

    // ---- 搜索配置 ----
    private var _allowDiagonal:Boolean;
    private var _allowCornerCut:Boolean; // 斜向是否允许卡角（穿过对角）
    // 0=Manhattan, 1=Diagonal (Octile), 2=Euclidean（内部仍用整数近似）
    private var _heuristicType:Number;

    // ---- 运行态 ----
    private var _searchId:Number;

    // -----------------------------------------------------------
    // 构造与网格初始化
    // -----------------------------------------------------------
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

    // 重新分配网格（会清空 walk/weight，默认全可走、权重=1）
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
            _weight[i] = 0; // 默认无额外地形成本
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

    // -----------------------------------------------------------
    // 配置接口
    // -----------------------------------------------------------
    public function setHeuristic(type:Number):Void
    {
        // 0: Manhattan, 1: Diagonal(Octile), 2: Euclidean
        if (type < 0) type = 0;
        if (type > 2) type = 2;
        _heuristicType = type;
    }

    public function setAllowDiagonal(allow:Boolean):Void
    {
        _allowDiagonal = allow;
    }

    public function setAllowCornerCut(allow:Boolean):Void
    {
        _allowCornerCut = allow;
    }

    // 支持一维或二维矩阵设置可走性；非 0 视为可走
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

    // 设置地形权重（>=1），支持一维或二维
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

    public function setWalkable(x:Number, y:Number, walkable:Boolean):Void
    {
        if (!inBounds(x, y)) return;
        _walk[y * _w + x] = walkable ? 1 : 0;
    }

    public function setWeight(x:Number, y:Number, v:Number):Void
    {
        if (!inBounds(x, y)) return;
        if (v < 0) v = 0; // 权重不能为负
        _weight[y * _w + x] = v;
    }

    // -----------------------------------------------------------
    // 寻路接口
    // 返回：从起点到终点的 {x, y} 数组；找不到返回 null
    // 可选 maxExpand 防止极端情况下过久搜索（<=0 或 undefined 表示不限制）
    // -----------------------------------------------------------
    public function find(sx:Number, sy:Number, gx:Number, gy:Number, maxExpand:Number):Array
    {
        if (!inBounds(sx, sy) || !inBounds(gx, gy)) return null;

        var sIdx:Number = sy * _w + sx;
        var gIdx:Number = gy * _w + gx;

        if (_walk[sIdx] == 0) return null;
        if (_walk[gIdx] == 0) return null; // 如需允许终点不可走可在此调整策略

        // 清空开放堆状态（仅结构，不清空整个数组，使用 searchId 复用）
        _openHeap.splice(0, _openHeap.length);
        _openCount = 0;
        
        // 重要：清空开放表位置标记，避免上次搜索残留状态污染
        var i:Number = 0;
        while (i < _size) {
            _openPos[i] = 0;
            i++;
        }

        // 增加搜索轮次标记
        _searchId++;
        if (_searchId > 2000000000) _searchId = 1; // 防溢出简单处理

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
            
            // 保险阈值：防止实现bug导致卡死，理论上永远不会触发
            if (expanded > _size) {
                return null;
            }

            // 当前坐标
            cx = curIdx % _w;
            cy = (curIdx - cx) / _w;

            // 遍历邻居
            expandNeighbors(curIdx, cx, cy, gx, gy);
        }

        return null; // 无路
    }

    // -----------------------------------------------------------
    // 私有：邻居扩展（无递归）
    // -----------------------------------------------------------
    private function expandNeighbors(curIdx:Number, cx:Number, cy:Number, gx:Number, gy:Number):Void
    {
        // 4 或 8 邻接
        // dx 数组与 dy 数组同序
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

                if (_walk[nIdx] != 0 && _closedMark[nIdx] != _searchId)
                {
                    // 斜向卡角处理
                    var diag:Boolean = (dxs[i] != 0 && dys[i] != 0);
                    if (diag && !_allowCornerCut)
                    {
                        // 若斜向移动，则要求 (cx,ny) 和 (nx,cy) 都可走，避免穿过角
                        var side1Walk:Number = _walk[cy * _w + nx];
                        var side2Walk:Number = _walk[ny * _w + cx];
                        if (side1Walk == 0 || side2Walk == 0)
                        {
                            // 跳过此方向，循环末尾会自动递增i
                            continue;
                        }
                    }

                    // 计算移动代价（权重作为额外成本，而非倍率）
                    var stepCost:Number = diag ? COST_DIAGONAL : COST_STRAIGHT;
                    var tentativeG:Number = _g[curIdx] + stepCost + _weight[nIdx];

                    var pos:Number = _openPos[nIdx]; // 在堆中的位置（0=不在）
                    if (pos == 0)
                    {
                        // 节点不在开放表：加入
                        _parent[nIdx] = curIdx;
                        _g[nIdx] = tentativeG;
                        _f[nIdx] = tentativeG + heuristicCost(nx, ny, gx, gy);
                        heapPush(nIdx);
                    }
                    else
                    {
                        // 已在开放表：尝试松弛（优化）
                        if (tentativeG < _g[nIdx])
                        {
                            _parent[nIdx] = curIdx;
                            _g[nIdx] = tentativeG;
                            _f[nIdx] = tentativeG + heuristicCost(nx, ny, gx, gy);
                            // 位置在堆中，从该位置向上调整
                            heapUp(pos - 1);
                        }
                    }
                }
            }
        }
    }

    // -----------------------------------------------------------
    // 私有：构建路径（从终点回溯到起点，再反转）
    // -----------------------------------------------------------
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

    // -----------------------------------------------------------
    // 私有：启发式代价 h（整数）
    // 0: Manhattan    => (dx+dy)*10
    // 1: Diagonal/Oct => 10*(dx+dy) + (14-2*10)*min(dx,dy) = 10*(dx+dy) + 4*min
    // 2: Euclidean    => 10*sqrt(dx*dx+dy*dy) 近似用 14*min + 10*(max-min)
    // -----------------------------------------------------------
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
            // Euclidean（用无根号近似：14*min + 10*(max-min)）
            var mx:Number = (dx > dy) ? dx : dy;
            var mn2:Number = (dx < dy) ? dx : dy;
            return mn2 * 14 + (mx - mn2) * 10;
        }
    }

    // -----------------------------------------------------------
    // 私有：二叉堆（最小堆，按 f 值优先，g 值其次）
    // _openHeap 存储的是“格子索引”；_openPos[idx] 记录其在堆中的位置+1
    // -----------------------------------------------------------
    private function heapPush(idx:Number):Void
    {
        _openHeap[_openCount] = idx;
        _openPos[idx] = _openCount + 1; // 位置+1
        heapUp(_openCount);
        _openCount++;
    }

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

    private function heapUp(i:Number):Void
    {
        // 自底向上调整
        var heap:Array = _openHeap;
        var node:Number = heap[i];

        while (i > 0)
        {
            var p:Number = (i - 1) >> 1; // 父
            var parentIdx:Number = heap[p];

            if (less(node, parentIdx))
            {
                // 交换
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

    // 比较函数：f 小优先；f 相等时 g 小优先（更接近起点，通常更平滑）
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

    // -----------------------------------------------------------
    // 私有：工具
    // -----------------------------------------------------------
    private function inBounds(x:Number, y:Number):Boolean
    {
        return (x >= 0 && y >= 0 && x < _w && y < _h);
    }

    // 可选：获取网格尺寸
    public function getWidth():Number { return _w; }
    public function getHeight():Number { return _h; }
}
