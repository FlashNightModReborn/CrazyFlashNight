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
 * - 缩放策略：首个图标自动校准，后续统一使用固定 Matrix
 * - 像素提取按 as2-performance.md 热路径规范优化
 */
class org.flashNight.arki.render.BitmapExporter {

    // 导出尺寸
    private static var SIZE:Number = 256;
    private static var ROWS_PER_CHUNK:Number = 32;

    // 校准状态：首个图标确定缩放比后锁定
    private static var _calibrated:Boolean = false;
    private static var _scale:Number;
    private static var _offsetX:Number;
    private static var _offsetY:Number;

    // base64 查表（预构建，避免 charAt 的 GetMember 开销）
    private static var _b64Chars:Array;

    // 复用缓冲区
    private static var _bmp:BitmapData;
    private static var _mtx:Matrix;
    private static var _clearRect:Rectangle;

    /**
     * 重置校准状态。下次 render 时重新从首个图标确定缩放比。
     */
    public static function resetCalibration():Void {
        _calibrated = false;
        if (_bmp != undefined) {
            _bmp.dispose();
            _bmp = undefined;
        }
        _mtx = undefined;
    }

    /**
     * 光栅化 MovieClip 并返回 base64 分块数组。
     *
     * @param mc 要光栅化的 MovieClip（已 gotoAndStop 到目标帧）
     * @return 分块数组 [{b64: "...", startRow: N}, ...]，失败返回 null
     */
    public static function render(mc:MovieClip):Array {
        if (mc == undefined) return null;

        // 惰性初始化
        if (_b64Chars == undefined) _initB64Table();
        if (_bmp == undefined) {
            _bmp = new BitmapData(SIZE, SIZE, true, 0x00000000);
            _clearRect = new Rectangle(0, 0, SIZE, SIZE);
        }

        // 校准：用首个图标的边界确定统一 Matrix
        if (!_calibrated) {
            _calibrate(mc);
        }

        // 清空复用 BitmapData [S03: 复用预分配对象]
        _bmp.fillRect(_clearRect, 0x00000000);

        // 光栅化
        _bmp.draw(mc, _mtx);

        // 提取像素 + base64 分块编码
        return _extractChunks();
    }

    /**
     * 从首个图标确定统一缩放 Matrix。
     * 所有图标使用相同制作规范，边界应一致。
     */
    private static function _calibrate(mc:MovieClip):Void {
        var bb:Object = mc.getBounds(mc);
        var bw:Number = bb.xMax - bb.xMin;
        var bh:Number = bb.yMax - bb.yMin;

        if (bw <= 0 || bh <= 0) {
            // 退回默认 1:1 映射
            _scale = 1;
            _offsetX = 0;
            _offsetY = 0;
        } else {
            // [H15] Math.min 内联为三元
            _scale = SIZE / ((bw > bh) ? bw : bh);
            var drawW:Number = bw * _scale;
            var drawH:Number = bh * _scale;
            _offsetX = (SIZE - drawW) / 2 - bb.xMin * _scale;
            _offsetY = (SIZE - drawH) / 2 - bb.yMin * _scale;
        }

        _mtx = new Matrix(_scale, 0, 0, _scale, _offsetX, _offsetY);
        _calibrated = true;

        _root.服务器.发布服务器消息("[BitmapExporter] 校准: scale=" + _scale
            + " offset=(" + ((_offsetX * 100 | 0) / 100) + "," + ((_offsetY * 100 | 0) / 100) + ")"
            + " bounds=(" + (bw | 0) + "x" + (bh | 0) + ")");
    }

    /**
     * 从 _bmp 提取像素，base64 编码并分块返回。
     *
     * 热路径优化（参照 as2-performance.md）：
     * - [H01] 全部外部变量缓存到局部
     * - [H04] 不使用 s.length（此处为 Number 计算，不涉及）
     * - [H15] Math.min 内联为三元
     * - [S01] base64 编码内联，避免方法调用(1340ns/call)
     * - [S03] 字节数组预分配长度
     * - 字符串拼接用裸 +（优于 Array.join [anti-hallucination §2]）
     * - getPixel32 结果直接位运算拆分
     * - base64 查表用数组索引(35ns) 替代 charAt(580ns)
     */
    private static function _extractChunks():Array {
        var chunks:Array = [];
        // [H01] 局部化外部变量
        var bmp:BitmapData = _bmp;
        var size:Number = SIZE;
        var rowsPerChunk:Number = ROWS_PER_CHUNK;
        var b64:Array = _b64Chars;

        var startRow:Number = 0;
        while (startRow < size) {
            var endRow:Number = startRow + rowsPerChunk;
            if (endRow > size) endRow = size;

            // 像素提取 → 字节数组
            // 预计算大小 [S03]：rowsPerChunk * SIZE * 4 = 32768
            var bytes:Array = new Array((endRow - startRow) * size * 4);
            var bi:Number = 0;
            var y:Number = startRow;
            while (y < endRow) {
                var x:Number = 0;
                while (x < size) {
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
            var blen:Number = bi; // 实际写入长度
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
            // 尾部 padding（32行×256×4=32768, 32768%3=1, 有1字节余）
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

            chunks.push({b64: out, startRow: startRow});
            startRow += rowsPerChunk;
        }

        return chunks;
    }

    /**
     * 初始化 base64 字符查表。
     * 数组索引查找(35ns) 远优于 String.charAt(580ns) [H04/成本阶梯]。
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
