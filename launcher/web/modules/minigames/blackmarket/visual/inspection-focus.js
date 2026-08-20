(function(root, factory) {
    "use strict";
    var api = factory();
    if (typeof module !== "undefined" && module.exports) module.exports = api;
    if (root) root.BlackMarketInspectionFocus = api;
})(typeof window !== "undefined" ? window : globalThis, function() {
    "use strict";

    function number(value, fallback) {
        value = Number(value);
        return isFinite(value) ? value : fallback;
    }

    function clamp(value, minimum, maximum) {
        return Math.max(minimum, Math.min(maximum, value));
    }

    function rotationQuarter(value) {
        value = ((Math.round(number(value, 0) / 90) * 90) % 360 + 360) % 360;
        return value;
    }

    function normalizedBounds(bounds, width, height, padding) {
        bounds = bounds || {};
        var x = number(bounds.x, 0);
        var y = number(bounds.y, 0);
        var right = x + Math.max(0, number(bounds.width, 0));
        var bottom = y + Math.max(0, number(bounds.height, 0));
        if (!(right > x && bottom > y) || bounds.count === 0) {
            return { x:0, y:0, width:width, height:height, count:width * height };
        }
        padding = Math.max(0, number(padding, 0));
        x = clamp(x - padding, 0, width);
        y = clamp(y - padding, 0, height);
        right = clamp(right + padding, x, width);
        bottom = clamp(bottom + padding, y, height);
        return {
            x:x,
            y:y,
            width:Math.max(1, right - x),
            height:Math.max(1, bottom - y),
            count:Math.max(1, number(bounds.count, 1))
        };
    }

    function rotateBounds(bounds, sourceWidth, sourceHeight, rotation) {
        rotation = rotationQuarter(rotation);
        if (rotation === 90) {
            return {
                x:sourceHeight - bounds.y - bounds.height,
                y:bounds.x,
                width:bounds.height,
                height:bounds.width,
                count:bounds.count
            };
        }
        if (rotation === 180) {
            return {
                x:sourceWidth - bounds.x - bounds.width,
                y:sourceHeight - bounds.y - bounds.height,
                width:bounds.width,
                height:bounds.height,
                count:bounds.count
            };
        }
        if (rotation === 270) {
            return {
                x:bounds.y,
                y:sourceWidth - bounds.x - bounds.width,
                width:bounds.height,
                height:bounds.width,
                count:bounds.count
            };
        }
        return {
            x:bounds.x,
            y:bounds.y,
            width:bounds.width,
            height:bounds.height,
            count:bounds.count
        };
    }

    function plan(options) {
        options = options || {};
        var sourceWidth = Math.max(1, number(options.sourceWidth, 1));
        var sourceHeight = Math.max(1, number(options.sourceHeight, 1));
        var viewportWidth = Math.max(1, number(options.viewportWidth, 1));
        var viewportHeight = Math.max(1, number(options.viewportHeight, 1));
        var rotation = rotationQuarter(options.rotation);
        var padding = Math.max(0, number(options.paddingPx, 10))
            + Math.max(0, number(options.envelopeRadiusPx, 0));
        var sourceBounds = normalizedBounds(
            options.objectBounds, sourceWidth, sourceHeight, padding);
        var bounds = rotateBounds(sourceBounds, sourceWidth, sourceHeight, rotation);
        var canvasWidth = rotation === 90 || rotation === 270 ? sourceHeight : sourceWidth;
        var canvasHeight = rotation === 90 || rotation === 270 ? sourceWidth : sourceHeight;
        var canvasRatio = clamp(number(options.canvasRatio, 0.92), 0.5, 1);
        var canvasScale = Math.min(
            1,
            viewportWidth * canvasRatio / canvasWidth,
            viewportHeight * canvasRatio / canvasHeight
        );
        var renderedBoundsWidth = Math.max(1, bounds.width * canvasScale);
        var renderedBoundsHeight = Math.max(1, bounds.height * canvasScale);
        var fillRatio = clamp(number(options.fillRatio, 0.72), 0.4, 0.9);
        var maximum = Math.max(1, number(options.maxZoom, 4));
        var zoom = clamp(Math.min(
            viewportWidth * fillRatio / renderedBoundsWidth,
            viewportHeight * fillRatio / renderedBoundsHeight
        ), 1, maximum);
        zoom = Math.round(zoom * 100) / 100;
        var offsetX = -(bounds.x + bounds.width * 0.5 - canvasWidth * 0.5) * canvasScale;
        var offsetY = -(bounds.y + bounds.height * 0.5 - canvasHeight * 0.5) * canvasScale;
        if (Math.abs(offsetX) < 0.000001) offsetX = 0;
        if (Math.abs(offsetY) < 0.000001) offsetY = 0;

        return {
            version:"blackmarket-inspection-focus.v1",
            rotation:rotation,
            zoom:zoom,
            fitZoom:1,
            offsetX:offsetX,
            offsetY:offsetY,
            panX:offsetX * zoom,
            panY:offsetY * zoom,
            canvasWidth:canvasWidth,
            canvasHeight:canvasHeight,
            renderedCanvasWidth:canvasWidth * canvasScale,
            renderedCanvasHeight:canvasHeight * canvasScale,
            bounds:bounds,
            fillRatio:fillRatio
        };
    }

    return {
        version:"blackmarket-inspection-focus.v1",
        plan:plan,
        rotateBounds:rotateBounds
    };
});
