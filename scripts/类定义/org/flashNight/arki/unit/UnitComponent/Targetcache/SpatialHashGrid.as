/**
 * SpatialHashGrid - 2D spatial hash grid for 2.5D games
 * Flat array index: grid[col * rows + row]
 * Rebuild each frame: clear + rebuildFromUnits
 * Query result array reuse, zero high-frequency allocation
 * Out-of-bounds coordinates auto-clamped
 *
 * @version 1.0
 */
class org.flashNight.arki.unit.UnitComponent.Targetcache.SpatialHashGrid {

    private var _originX:Number;
    private var _originY:Number;
    private var _cellW:Number;
    private var _cellH:Number;
    private var _invCellW:Number;
    private var _invCellH:Number;
    private var _cols:Number;
    private var _rows:Number;
    private var _cellCount:Number;
    private var _grid:Array;
    private var _unitCount:Number;
    private var _units:Array;
    private var _xs:Array;
    private var _ys:Array;
    private var _pool:Array;
    private var _result:Array;

    /**
     * @param originX  Grid left X (typically Xmin)
     * @param originY  Grid top Y (typically Ymin)
     * @param width    Grid width (Xmax - Xmin)
     * @param height   Grid height (Ymax - Ymin)
     * @param cellW    Cell width (recommend 150~300)
     * @param cellH    Cell height
     */
    public function SpatialHashGrid(originX:Number, originY:Number,
                                     width:Number, height:Number,
                                     cellW:Number, cellH:Number) {
        _originX = originX;
        _originY = originY;
        _cellW = cellW;
        _cellH = cellH;
        _invCellW = 1.0 / cellW;
        _invCellH = 1.0 / cellH;

        _cols = Math.ceil(width / cellW);
        _rows = Math.ceil(height / cellH);
        if (_cols < 1) _cols = 1;
        if (_rows < 1) _rows = 1;
        _cellCount = _cols * _rows;

        _grid = new Array(_cellCount);
        _units = [];
        _xs = [];
        _ys = [];
        _pool = [];
        _unitCount = 0;
        _result = [];

        var i:Number = _cellCount;
        while (--i >= 0) {
            _grid[i] = [];
        }
    }

    /**
     * Clear all cells. O(cellCount)
     */
    public function clear():Void {
        var grid:Array = _grid;
        var n:Number = _cellCount;
        var i:Number = 0;
        while (i < n) {
            grid[i].length = 0;
            i++;
        }
        _units.length = 0;
        _xs.length = 0;
        _ys.length = 0;
        _unitCount = 0;
    }

    /**
     * Insert a unit at (x, y).
     */
    public function insert(unit:Object, x:Number, y:Number):Void {
        var col:Number = ((x - _originX) * _invCellW) | 0;
        var row:Number = ((y - _originY) * _invCellH) | 0;
        if (col < 0) col = 0;
        else if (col >= _cols) col = _cols - 1;
        if (row < 0) row = 0;
        else if (row >= _rows) row = _rows - 1;

        var index:Number = _unitCount;
        _units[index] = unit;
        _xs[index] = x;
        _ys[index] = y;

        var cell:Array = _grid[col * _rows + row];
        cell[cell.length] = index;
        _unitCount = index + 1;
    }

    /**
     * Rebuild grid from unit array.
     * X = AABB center, Y = Z轴坐标
     */
    public function rebuildFromUnits(units:Array):Void {
        var grid:Array = _grid;
        var n:Number = _cellCount;
        var i:Number = 0;
        while (i < n) {
            grid[i].length = 0;
            i++;
        }
        _unitCount = 0;

        var len:Number = units.length;
        var snapUnits:Array = _units;
        var snapXs:Array = _xs;
        var snapYs:Array = _ys;
        snapUnits.length = len;
        snapXs.length = len;
        snapYs.length = len;
        var invW:Number = _invCellW;
        var invH:Number = _invCellH;
        var ox:Number = _originX;
        var oy:Number = _originY;
        var cols:Number = _cols;
        var rows:Number = _rows;
        var maxCol:Number = cols - 1;
        var maxRow:Number = rows - 1;

        var j:Number = 0;
        var unit:Object;
        var aabb:Object;
        var x:Number;
        var y:Number;
        var col:Number;
        var row:Number;
        var cell:Array;

        while (j < len) {
            unit = units[j];
            aabb = unit.aabbCollider;
            x = (aabb.left + aabb.right) * 0.5;
            y = unit.Z轴坐标;

            snapUnits[j] = unit;
            snapXs[j] = x;
            snapYs[j] = y;

            col = ((x - ox) * invW) | 0;
            row = ((y - oy) * invH) | 0;
            if (col < 0) col = 0;
            else if (col > maxCol) col = maxCol;
            if (row < 0) row = 0;
            else if (row > maxRow) row = maxRow;

            cell = grid[col * rows + row];
            cell[cell.length] = j;
            j++;
        }
        _unitCount = len;
    }

    /**
     * Rebuild grid from pre-fetched parallel arrays.
     * Faster than rebuildFromUnits: skips unit.aabbCollider chain access.
     * X = (leftValues[i] + rightValues[i]) * 0.5, Y = units[i].Z轴坐标
     *
     * @param units       Sorted unit array (same as SortedUnitCache.data)
     * @param leftValues  Pre-fetched aabbCollider.left values
     * @param rightValues Pre-fetched aabbCollider.right values
     */
    public function rebuildFromParallelArrays(units:Array, leftValues:Array, rightValues:Array):Void {
        var grid:Array = _grid;
        var n:Number = _cellCount;
        var i:Number = 0;
        while (i < n) {
            grid[i].length = 0;
            i++;
        }
        _unitCount = 0;

        var len:Number = units.length;
        var snapUnits:Array = _units;
        var snapXs:Array = _xs;
        var snapYs:Array = _ys;
        snapUnits.length = len;
        snapXs.length = len;
        snapYs.length = len;
        var invW:Number = _invCellW;
        var invH:Number = _invCellH;
        var ox:Number = _originX;
        var oy:Number = _originY;
        var rows:Number = _rows;
        var maxCol:Number = _cols - 1;
        var maxRow:Number = rows - 1;

        var j:Number = 0;
        var x:Number;
        var y:Number;
        var col:Number;
        var row:Number;
        var cell:Array;

        while (j < len) {
            x = (leftValues[j] + rightValues[j]) * 0.5;
            y = units[j].Z轴坐标;

            snapUnits[j] = units[j];
            snapXs[j] = x;
            snapYs[j] = y;

            col = ((x - ox) * invW) | 0;
            row = ((y - oy) * invH) | 0;
            if (col < 0) col = 0;
            else if (col > maxCol) col = maxCol;
            if (row < 0) row = 0;
            else if (row > maxRow) row = maxRow;

            cell = grid[col * rows + row];
            cell[cell.length] = j;
            j++;
        }
        _unitCount = len;
    }

    /**
     * Rectangle query. Returns units whose center is in [x1,x2] x [y1,y2].
     * Result array is reused - consume before next query call.
     */
    public function queryRect(x1:Number, y1:Number, x2:Number, y2:Number,
                               filterFn:Function):Array {
        var result:Array = _result;
        result.length = 0;

        var ox:Number = _originX;
        var oy:Number = _originY;
        var invW:Number = _invCellW;
        var invH:Number = _invCellH;
        var rows:Number = _rows;
        var maxCol:Number = _cols - 1;
        var maxRow:Number = rows - 1;

        var c0:Number = ((x1 - ox) * invW) | 0;
        var c1:Number = ((x2 - ox) * invW) | 0;
        var r0:Number = ((y1 - oy) * invH) | 0;
        var r1:Number = ((y2 - oy) * invH) | 0;

        if (c0 < 0) c0 = 0;
        if (c1 > maxCol) c1 = maxCol;
        if (r0 < 0) r0 = 0;
        if (r1 > maxRow) r1 = maxRow;

        var grid:Array = _grid;
        var hasFilter:Boolean = (filterFn != undefined && filterFn != null);
        var c:Number;
        var r:Number;
        var cell:Array;
        var cellLen:Number;
        var k:Number;
        var idx:Number;
        var unit:Object;
        var ux:Number;
        var uy:Number;
        var snapUnits:Array = _units;
        var snapXs:Array = _xs;
        var snapYs:Array = _ys;

        c = c0;
        while (c <= c1) {
            r = r0;
            while (r <= r1) {
                cell = grid[c * rows + r];
                cellLen = cell.length;
                k = 0;
                while (k < cellLen) {
                    idx = cell[k];
                    ux = snapXs[idx];
                    uy = snapYs[idx];
                    if (ux >= x1 && ux <= x2 && uy >= y1 && uy <= y2) {
                        unit = snapUnits[idx];
                        if (!hasFilter || filterFn(unit)) {
                            result[result.length] = unit;
                        }
                    }
                    k++;
                }
                r++;
            }
            c++;
        }

        return result;
    }

    /**
     * Circle query. Returns units within radius of (cx, cy).
     */
    public function queryCircle(cx:Number, cy:Number, radius:Number,
                                 filterFn:Function):Array {
        var result:Array = _result;
        result.length = 0;

        if (radius <= 0) return result;

        var r2:Number = radius * radius;
        var ox:Number = _originX;
        var oy:Number = _originY;
        var invW:Number = _invCellW;
        var invH:Number = _invCellH;
        var rows:Number = _rows;
        var maxCol:Number = _cols - 1;
        var maxRow:Number = rows - 1;

        var c0:Number = ((cx - radius - ox) * invW) | 0;
        var c1:Number = ((cx + radius - ox) * invW) | 0;
        var r0:Number = ((cy - radius - oy) * invH) | 0;
        var r1:Number = ((cy + radius - oy) * invH) | 0;

        if (c0 < 0) c0 = 0;
        if (c1 > maxCol) c1 = maxCol;
        if (r0 < 0) r0 = 0;
        if (r1 > maxRow) r1 = maxRow;

        var grid:Array = _grid;
        var hasFilter:Boolean = (filterFn != undefined && filterFn != null);
        var c:Number;
        var r:Number;
        var cell:Array;
        var cellLen:Number;
        var k:Number;
        var idx:Number;
        var unit:Object;
        var dx:Number;
        var dy:Number;
        var snapUnits:Array = _units;
        var snapXs:Array = _xs;
        var snapYs:Array = _ys;

        c = c0;
        while (c <= c1) {
            r = r0;
            while (r <= r1) {
                cell = grid[c * rows + r];
                cellLen = cell.length;
                k = 0;
                while (k < cellLen) {
                    idx = cell[k];
                    dx = snapXs[idx] - cx;
                    dy = snapYs[idx] - cy;
                    if (dx * dx + dy * dy <= r2) {
                        unit = snapUnits[idx];
                        if (!hasFilter || filterFn(unit)) {
                            result[result.length] = unit;
                        }
                    }
                    k++;
                }
                r++;
            }
            c++;
        }

        return result;
    }

    /**
     * Nearest neighbor query. Returns closest unit within maxDist.
     */
    public function queryNearest(cx:Number, cy:Number, maxDist:Number,
                                  excludeUnit:Object, filterFn:Function):Object {
        if (maxDist <= 0) return null;

        var bestDist2:Number = maxDist * maxDist;
        var bestUnit:Object = null;

        var ox:Number = _originX;
        var oy:Number = _originY;
        var invW:Number = _invCellW;
        var invH:Number = _invCellH;
        var rows:Number = _rows;
        var maxCol:Number = _cols - 1;
        var maxRow:Number = rows - 1;

        var c0:Number = ((cx - maxDist - ox) * invW) | 0;
        var c1:Number = ((cx + maxDist - ox) * invW) | 0;
        var r0:Number = ((cy - maxDist - oy) * invH) | 0;
        var r1:Number = ((cy + maxDist - oy) * invH) | 0;

        if (c0 < 0) c0 = 0;
        if (c1 > maxCol) c1 = maxCol;
        if (r0 < 0) r0 = 0;
        if (r1 > maxRow) r1 = maxRow;

        var grid:Array = _grid;
        var hasFilter:Boolean = (filterFn != undefined && filterFn != null);
        var hasExclude:Boolean = (excludeUnit != null && excludeUnit != undefined);
        var c:Number;
        var r:Number;
        var cell:Array;
        var cellLen:Number;
        var k:Number;
        var idx:Number;
        var unit:Object;
        var dx:Number;
        var dy:Number;
        var d2:Number;
        var snapUnits:Array = _units;
        var snapXs:Array = _xs;
        var snapYs:Array = _ys;

        c = c0;
        while (c <= c1) {
            r = r0;
            while (r <= r1) {
                cell = grid[c * rows + r];
                cellLen = cell.length;
                k = 0;
                while (k < cellLen) {
                    idx = cell[k];
                    unit = snapUnits[idx];
                    k++;
                    if ((!hasExclude || unit != excludeUnit)) {
                        dx = snapXs[idx] - cx;
                        dy = snapYs[idx] - cy;
                        d2 = dx * dx + dy * dy;
                        if (d2 <= bestDist2) {
                            if (!hasFilter || filterFn(unit)) {
                                if (bestUnit == null || d2 < bestDist2) {
                                    bestDist2 = d2;
                                    bestUnit = unit;
                                }
                            }
                        }
                    }
                }
                r++;
            }
            c++;
        }

        return bestUnit;
    }

    /**
     * Count units in circle. Faster than queryCircle().length.
     */
    public function countInCircle(cx:Number, cy:Number, radius:Number):Number {
        if (radius <= 0) return 0;

        var count:Number = 0;
        var r2:Number = radius * radius;
        var ox:Number = _originX;
        var oy:Number = _originY;
        var invW:Number = _invCellW;
        var invH:Number = _invCellH;
        var rows:Number = _rows;
        var maxCol:Number = _cols - 1;
        var maxRow:Number = rows - 1;

        var c0:Number = ((cx - radius - ox) * invW) | 0;
        var c1:Number = ((cx + radius - ox) * invW) | 0;
        var r0:Number = ((cy - radius - oy) * invH) | 0;
        var r1:Number = ((cy + radius - oy) * invH) | 0;

        if (c0 < 0) c0 = 0;
        if (c1 > maxCol) c1 = maxCol;
        if (r0 < 0) r0 = 0;
        if (r1 > maxRow) r1 = maxRow;

        var grid:Array = _grid;
        var c:Number;
        var r:Number;
        var cell:Array;
        var cellLen:Number;
        var k:Number;
        var idx:Number;
        var dx:Number;
        var dy:Number;
        var snapXs:Array = _xs;
        var snapYs:Array = _ys;

        c = c0;
        while (c <= c1) {
            r = r0;
            while (r <= r1) {
                cell = grid[c * rows + r];
                cellLen = cell.length;
                k = 0;
                while (k < cellLen) {
                    idx = cell[k];
                    dx = snapXs[idx] - cx;
                    dy = snapYs[idx] - cy;
                    if (dx * dx + dy * dy <= r2) {
                        count++;
                    }
                    k++;
                }
                r++;
            }
            c++;
        }

        return count;
    }

    /**
     * Get grid diagnostics.
     */
    public function getStats():Object {
        var maxCellSize:Number = 0;
        var nonEmpty:Number = 0;
        var grid:Array = _grid;
        var n:Number = _cellCount;
        var i:Number = 0;
        var len:Number;

        while (i < n) {
            len = grid[i].length;
            if (len > 0) {
                nonEmpty++;
                if (len > maxCellSize) maxCellSize = len;
            }
            i++;
        }

        return {
            cols: _cols,
            rows: _rows,
            cellCount: _cellCount,
            cellW: _cellW,
            cellH: _cellH,
            unitCount: _unitCount,
            nonEmptyCells: nonEmpty,
            maxCellSize: maxCellSize,
            poolSize: _pool.length
        };
    }
}
