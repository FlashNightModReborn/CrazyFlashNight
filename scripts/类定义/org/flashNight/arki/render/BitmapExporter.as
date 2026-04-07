import flash.display.BitmapData;
import flash.geom.Matrix;
import flash.geom.Rectangle;

/**
 * BitmapExporter - 通用 MovieClip → 像素数据导出器
 *
 * 将指定 MovieClip 光栅化为固定尺寸位图，
 * 提取 ARGB 像素并以 base64 分块输出。
 *
 * 设计原则：
 * - 渲染逻辑与传输/状态机分离，IconBaker 调用本类完成光栅化
 * - 校准策略由调用方控制：profileKey 非 null 缓存复用，null 每次独立校准
 * - 像素提取按 as2-performance.md 热路径规范优化
 */
class org.flashNight.arki.render.BitmapExporter {

    // 导出尺寸
    private static var SIZE:Number = 256;
    private static var ROWS_PER_CHUNK:Number = 32;

    // 校准缓存：profileKey → Matrix（非 null 时缓存复用）
    private static var _profiles:Object;

    // base64 查表（预构建，避免 charAt 的 GetMember 开销）
    private static var _b64Chars:Array;

    // 复用缓冲区
    private static var _bmp:BitmapData;
    private static var _clearRect:Rectangle;

    /**
     * 重置校准缓存与内部缓冲区。
     */
    public static function resetCalibration():Void {
        _profiles = {};
        if (_bmp != undefined) {
            _bmp.dispose();
            _bmp = undefined;
        }
    }

    /**
     * 光栅化 MovieClip 并返回带裁剪信息的结果对象。
     *
     * @param mc          要光栅化的 MovieClip（已 gotoAndStop 到目标帧）
     * @param profileKey  校准缓存键。非 null 时首次校准后缓存复用（适用于
     *                    模板统一的帧，如 f1 图标帧——遮罩导致 getBounds 不可靠，
     *                    但所有图标共享同一模板边界）。null 时每次独立校准
     *                    （适用于尺寸各异的帧，如 f2 掉落物帧）。
     * @return {chunks, contentX, contentY, contentW, contentH}，失败返回 null
     *         chunks: [{b64: "..."}, ...]
     *         contentX/Y/W/H: 实际内容区域（像素坐标），C# 端据此在 256×256 画布定位
     */
    public static function render(mc:MovieClip, profileKey:String):Object {
        if (mc == undefined) return null;

        // 惰性初始化
        if (_b64Chars == undefined) _initB64Table();
        if (_profiles == undefined) _profiles = {};
        if (_bmp == undefined) {
            _bmp = new BitmapData(SIZE, SIZE, true, 0x00000000);
            _clearRect = new Rectangle(0, 0, SIZE, SIZE);
        }

        // 校准：profileKey 非 null 时缓存复用，null 时每次独立计算
        var mtx:Matrix;
        if (profileKey != null && _profiles[profileKey] != undefined) {
            mtx = _profiles[profileKey];
        } else {
            mtx = _buildMatrix(mc);
            if (profileKey != null) {
                _profiles[profileKey] = mtx;
            }
        }

        // 清空复用 BitmapData [S03: 复用预分配对象]
        _bmp.fillRect(_clearRect, 0x00000000);

        // 光栅化
        _bmp.draw(mc, mtx);

        // 用 getColorBoundsRect 获取非透明像素的边界矩形
        // mask=0xFF000000 color=0x00000000 findColor=false → 找 alpha != 0 的区域
        var cr:Rectangle = _bmp.getColorBoundsRect(0xFF000000, 0x00000000, false);

        var cx:Number;
        var cy:Number;
        var cw:Number;
        var ch:Number;

        if (cr.width <= 0 || cr.height <= 0) {
            // 全透明，仍返回满幅（防御性）
            cx = 0;
            cy = 0;
            cw = SIZE;
            ch = SIZE;
        } else {
            cx = cr.x;
            cy = cr.y;
            cw = cr.width;
            ch = cr.height;
        }

        // 提取 contentRect 区域的像素 + base64 分块编码
        var chunks:Array = _extractChunks(cx, cy, cw, ch);

        return {chunks: chunks, contentX: cx, contentY: cy, contentW: cw, contentH: ch};
    }

    /**
     * 根据 MC 边界计算等比缩放居中 Matrix。
     */
    private static function _buildMatrix(mc:MovieClip):Matrix {
        var bb:Object = mc.getBounds(mc);
        var bw:Number = bb.xMax - bb.xMin;
        var bh:Number = bb.yMax - bb.yMin;

        var scale:Number;
        var offsetX:Number;
        var offsetY:Number;

        if (bw <= 0 || bh <= 0) {
            scale = 1;
            offsetX = 0;
            offsetY = 0;
        } else {
            // [H15] Math.min/max 内联为三元
            scale = SIZE / ((bw > bh) ? bw : bh);
            var drawW:Number = bw * scale;
            var drawH:Number = bh * scale;
            offsetX = (SIZE - drawW) / 2 - bb.xMin * scale;
            offsetY = (SIZE - drawH) / 2 - bb.yMin * scale;
        }

        return new Matrix(scale, 0, 0, scale, offsetX, offsetY);
    }

    /**
     * 从 _bmp 的指定区域提取像素，base64 编码并分块返回。
     *
     * 热路径优化（参照 as2-performance.md）：
     * - [H01] 全部外部变量缓存到局部
     * - [H15] Math.min 内联为三元
     * - [S01] base64 编码内联，避免方法调用(1340ns/call)
     * - [S03] 字节数组预分配长度
     * - 字符串拼接用裸 +（优于 Array.join [anti-hallucination §2]）
     * - base64 查表用数组索引(35ns) 替代 charAt(580ns)
     */
    private static function _extractChunks(cx:Number, cy:Number, cw:Number, ch:Number):Array {
        var chunks:Array = [];
        // [H01] 局部化外部变量
        var bmp:BitmapData = _bmp;
        var rowsPerChunk:Number = ROWS_PER_CHUNK;
        var b64:Array = _b64Chars;

        // 内容区域边界
        var xEnd:Number = cx + cw;
        var yEnd:Number = cy + ch;

        var startRow:Number = cy;
        while (startRow < yEnd) {
            var endRow:Number = startRow + rowsPerChunk;
            if (endRow > yEnd) endRow = yEnd;

            // 像素提取 → 字节数组，预分配 [S03]
            var byteCount:Number = (endRow - startRow) * cw * 4;
            var bytes:Array = new Array(byteCount);
            var bi:Number = 0;
            var y:Number = startRow;
            while (y < endRow) {
                var x:Number = cx;
                while (x < xEnd) {
                    var p:Number = bmp.getPixel32(x, y);
                    // ARGB 拆分 — 直接索引赋值 [H20: 避免 push]
                    bytes[bi] = (p >>> 24) & 0xFF;
                    bytes[bi + 1] = (p >>> 16) & 0xFF;
                    bytes[bi + 2] = (p >>> 8) & 0xFF;
                    bytes[bi + 3] = p & 0xFF;
                    bi += 4;
                    x++;
                }
                y++;
            }

            // base64 编码（内联 [S01]，数组查表替代 charAt）
            var out:String = "";
            var ei:Number = 0;
            var blen:Number = bi;
            // 主循环：仅处理完整三元组
            var fullEnd:Number = blen - (blen % 3);
            while (ei < fullEnd) {
                var c1:Number = bytes[ei];
                var c2:Number = bytes[ei + 1];
                var c3:Number = bytes[ei + 2];
                out += b64[c1 >> 2]
                    + b64[((c1 & 3) << 4) | (c2 >> 4)]
                    + b64[((c2 & 15) << 2) | (c3 >> 6)]
                    + b64[c3 & 63];
                ei += 3;
            }
            // 尾部 padding
            var rem:Number = blen - fullEnd;
            if (rem === 1) {
                var r1:Number = bytes[ei];
                out += b64[r1 >> 2] + b64[(r1 & 3) << 4] + "==";
            } else if (rem === 2) {
                var r1b:Number = bytes[ei];
                var r2:Number = bytes[ei + 1];
                out += b64[r1b >> 2]
                    + b64[((r1b & 3) << 4) | (r2 >> 4)]
                    + b64[(r2 & 15) << 2]
                    + "=";
            }

            chunks.push({b64: out});
            startRow += rowsPerChunk;
        }

        return chunks;
    }

    /**
     * 初始化 base64 字符查表。
     * 数组索引查找(35ns) 远优于 String.charAt(580ns)。
     */
    private static function _initB64Table():Void {
        var str:String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        _b64Chars = [];
        var i:Number = 0;
        while (i < 64) {
            _b64Chars[i] = str.charAt(i);
            i++;
        }
    }
}
