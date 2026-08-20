"use strict";

importScripts("./item-surface.js");

self.onmessage = function(event) {
    var message = event.data || {};
    var bitmap = message.bitmap;
    try {
        if (!bitmap) throw new Error("surface worker bitmap missing");
        var started = typeof performance !== "undefined" && performance.now ? performance.now() : Date.now();
        var result = BlackMarketItemSurface.processBitmap(bitmap, message.width, message.height, message.options || {});
        if (bitmap.close) bitmap.close();
        if (!result.canvas.transferToImageBitmap) throw new Error("surface worker cannot transfer canvas");
        var output = result.canvas.transferToImageBitmap();
        var ended = typeof performance !== "undefined" && performance.now ? performance.now() : Date.now();
        result.metrics.workerElapsedMs = Math.round((ended - started) * 100) / 100;
        self.postMessage({ id: message.id, bitmap: output, metrics: result.metrics }, [output]);
    } catch (error) {
        if (bitmap && bitmap.close) bitmap.close();
        self.postMessage({
            id: message.id,
            error: error && error.stack ? error.stack : String(error)
        });
    }
};
