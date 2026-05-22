'use strict';

// Scene-node PNG unsharp mask worker.
//
// 设计契约 (与 map-canvas-stage-renderer.js getSharpenedUrl 配套, 与 tools/tune-map-filter-fit.js
// COMPOSITE_VISUAL_SCALE_CAP 抬高到 1.75 的策略配套):
//   - 仅对 RGB 通道做 3x3 unsharp, alpha 原样透传, 防止半透明边缘黑色光晕
//   - 单消息 = 单图: 主线程负责 dedup (assetUrl 缓存 Promise), worker 不维护状态
//   - 输入 bitmap 通过 transferable 传入, 处理完即 close()
//   - 任何异常都回 { key, error }, 主线程降级回 raw URL (无声失败, 不破坏渲染)
//
// 输入 message: { key:String, bitmap:ImageBitmap, amount:Number }
// 输出 message: { key:String, blob:Blob }  // 成功
//            或 { key:String, error:String } // 失败

function applyUnsharp(imageData, amount) {
    // Kernel: [0,-a,0; -a,1+4a,-a; 0,-a,0]
    // 边缘像素 (1 px 框) 不卷积, 原样复制, 避免越界判定开销 + 边缘伪影。
    var src = imageData.data;
    var w = imageData.width;
    var h = imageData.height;
    var dst = new Uint8ClampedArray(src.length);
    var center = 1 + 4 * amount;
    var neg = -amount;
    var x, y, idx, nIdx;
    var sumR, sumG, sumB;
    var stride = w * 4;

    for (y = 0; y < h; y++) {
        for (x = 0; x < w; x++) {
            idx = (y * w + x) * 4;
            if (x === 0 || y === 0 || x === w - 1 || y === h - 1) {
                dst[idx]     = src[idx];
                dst[idx + 1] = src[idx + 1];
                dst[idx + 2] = src[idx + 2];
                dst[idx + 3] = src[idx + 3];
                continue;
            }
            sumR = src[idx]     * center;
            sumG = src[idx + 1] * center;
            sumB = src[idx + 2] * center;

            nIdx = idx - stride;            // up
            sumR += src[nIdx]     * neg;
            sumG += src[nIdx + 1] * neg;
            sumB += src[nIdx + 2] * neg;

            nIdx = idx + stride;            // down
            sumR += src[nIdx]     * neg;
            sumG += src[nIdx + 1] * neg;
            sumB += src[nIdx + 2] * neg;

            nIdx = idx - 4;                 // left
            sumR += src[nIdx]     * neg;
            sumG += src[nIdx + 1] * neg;
            sumB += src[nIdx + 2] * neg;

            nIdx = idx + 4;                 // right
            sumR += src[nIdx]     * neg;
            sumG += src[nIdx + 1] * neg;
            sumB += src[nIdx + 2] * neg;

            // Uint8ClampedArray 自动 clamp [0,255]
            dst[idx]     = sumR;
            dst[idx + 1] = sumG;
            dst[idx + 2] = sumB;
            dst[idx + 3] = src[idx + 3];
        }
    }

    return new ImageData(dst, w, h);
}

self.onmessage = function(e) {
    var msg = e.data || {};
    var key = msg.key || '';
    var bitmap = msg.bitmap;
    var amount = typeof msg.amount === 'number' ? msg.amount : 0.45;

    if (!key || !bitmap) {
        self.postMessage({ key: key, error: 'invalid-payload' });
        return;
    }

    try {
        var w = bitmap.width;
        var h = bitmap.height;
        var canvas = new OffscreenCanvas(w, h);
        var ctx = canvas.getContext('2d');
        ctx.drawImage(bitmap, 0, 0);
        bitmap.close();

        var imageData = ctx.getImageData(0, 0, w, h);
        var sharpened = applyUnsharp(imageData, amount);
        ctx.putImageData(sharpened, 0, 0);

        canvas.convertToBlob({ type: 'image/png' }).then(function(blob) {
            self.postMessage({ key: key, blob: blob });
        }, function(err) {
            self.postMessage({ key: key, error: String(err && err.message || err) });
        });
    } catch (err) {
        try { if (bitmap && bitmap.close) bitmap.close(); } catch (e2) {}
        self.postMessage({ key: key, error: String(err && err.message || err) });
    }
};
