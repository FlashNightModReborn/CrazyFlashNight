(function(root, factory) {
    if (typeof module === "object" && module.exports) {
        module.exports = factory();
    } else {
        root.BlackMarketItemSurface = factory();
    }
})(typeof globalThis !== "undefined" ? globalThis : this, function() {
    "use strict";

    var VERSION = "object-sdf-nanobot-sludge.v2";
    var MATERIAL_PROFILE = "dormant-military-nanobots.v1";
    var NANO_CELL_SCALE = 0.068;
    var DEFAULT_ALPHA_THRESHOLD = 12;
    var INF = 1e15;

    function clamp(value, low, high) {
        return value < low ? low : value > high ? high : value;
    }

    function round(value, digits) {
        var scale = Math.pow(10, digits === undefined ? 4 : digits);
        return Math.round(value * scale) / scale;
    }

    function hash32(text) {
        var hash = 2166136261 >>> 0;
        var source = String(text || "");
        var i;
        for (i = 0; i < source.length; i += 1) {
            hash ^= source.charCodeAt(i);
            hash = Math.imul(hash, 16777619) >>> 0;
        }
        return hash >>> 0;
    }

    function hashCoord(x, y, seed) {
        var value = (seed ^ Math.imul((x | 0) + 0x7f4a7c15, 0x45d9f3b)
            ^ Math.imul((y | 0) + 0x165667b1, 0x27d4eb2d)) >>> 0;
        value ^= value >>> 16;
        value = Math.imul(value, 0x7feb352d) >>> 0;
        value ^= value >>> 15;
        value = Math.imul(value, 0x846ca68b) >>> 0;
        value ^= value >>> 16;
        return (value >>> 0) / 4294967296;
    }

    function smooth(value) {
        return value * value * (3 - 2 * value);
    }

    function valueNoise(x, y, seed) {
        var x0 = Math.floor(x);
        var y0 = Math.floor(y);
        var tx = smooth(x - x0);
        var ty = smooth(y - y0);
        var a = hashCoord(x0, y0, seed);
        var b = hashCoord(x0 + 1, y0, seed);
        var c = hashCoord(x0, y0 + 1, seed);
        var d = hashCoord(x0 + 1, y0 + 1, seed);
        var top = a + (b - a) * tx;
        var bottom = c + (d - c) * tx;
        return top + (bottom - top) * ty;
    }

    function fbm(x, y, seed) {
        var total = 0;
        var amplitude = 0.58;
        var frequency = 0.055;
        var norm = 0;
        var octave;
        for (octave = 0; octave < 4; octave += 1) {
            total += valueNoise(x * frequency, y * frequency, seed + octave * 1013) * amplitude;
            norm += amplitude;
            amplitude *= 0.52;
            frequency *= 2.03;
        }
        return total / norm;
    }

    function sampleWorley(x, y, seed, out) {
        var px = x * NANO_CELL_SCALE;
        var py = y * NANO_CELL_SCALE;
        var cx = Math.floor(px);
        var cy = Math.floor(py);
        var best = 4;
        var second = 4;
        var nearestX = cx;
        var nearestY = cy;
        var ox;
        var oy;
        for (oy = -1; oy <= 1; oy += 1) {
            for (ox = -1; ox <= 1; ox += 1) {
                var gx = cx + ox;
                var gy = cy + oy;
                var fx = gx + hashCoord(gx, gy, seed ^ 0x51ed270b);
                var fy = gy + hashCoord(gx, gy, seed ^ 0x2c1b3c6d);
                var dx = fx - px;
                var dy = fy - py;
                var distance = dx * dx + dy * dy;
                if (distance < best) {
                    second = best;
                    best = distance;
                    nearestX = gx;
                    nearestY = gy;
                } else if (distance < second) {
                    second = distance;
                }
            }
        }
        out[0] = clamp(Math.sqrt(best) / 1.25, 0, 1);
        out[1] = clamp(Math.sqrt(second) / 1.25, 0, 1);
        out[2] = nearestX;
        out[3] = nearestY;
        return out;
    }

    function median(values) {
        if (!values.length) return 0;
        var copy = values.slice().sort(function(a, b) { return a - b; });
        var middle = copy.length >> 1;
        return copy.length % 2 ? copy[middle] : (copy[middle - 1] + copy[middle]) * 0.5;
    }

    function colorDistance(data, offset, color) {
        var dr = data[offset] - color[0];
        var dg = data[offset + 1] - color[1];
        var db = data[offset + 2] - color[2];
        return Math.sqrt(dr * dr * 0.30 + dg * dg * 0.59 + db * db * 0.11);
    }

    function localColorDistance(data, first, second) {
        var dr = data[first] - data[second];
        var dg = data[first + 1] - data[second + 1];
        var db = data[first + 2] - data[second + 2];
        return Math.sqrt(dr * dr * 0.30 + dg * dg * 0.59 + db * db * 0.11);
    }

    function alphaMask(imageData, threshold) {
        var count = imageData.width * imageData.height;
        var mask = new Uint8Array(count);
        var opaque = 0;
        var i;
        for (i = 0; i < count; i += 1) {
            if (imageData.data[i * 4 + 3] >= threshold) {
                mask[i] = 1;
                opaque += 1;
            }
        }
        return { mask: mask, count: opaque };
    }

    function maskBounds(mask, width, height) {
        var minX = width;
        var minY = height;
        var maxX = -1;
        var maxY = -1;
        var count = 0;
        var x;
        var y;
        for (y = 0; y < height; y += 1) {
            for (x = 0; x < width; x += 1) {
                if (!mask[y * width + x]) continue;
                if (x < minX) minX = x;
                if (x > maxX) maxX = x;
                if (y < minY) minY = y;
                if (y > maxY) maxY = y;
                count += 1;
            }
        }
        if (!count) return { x: 0, y: 0, width: 0, height: 0, count: 0 };
        return { x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1, count: count };
    }

    function dilate(mask, width, height, radius) {
        if (radius <= 0) return new Uint8Array(mask);
        var out = new Uint8Array(mask.length);
        var x;
        var y;
        var ox;
        var oy;
        for (y = 0; y < height; y += 1) {
            for (x = 0; x < width; x += 1) {
                if (!mask[y * width + x]) continue;
                for (oy = -radius; oy <= radius; oy += 1) {
                    var yy = y + oy;
                    if (yy < 0 || yy >= height) continue;
                    var span = Math.floor(Math.sqrt(radius * radius - oy * oy));
                    for (ox = -span; ox <= span; ox += 1) {
                        var xx = x + ox;
                        if (xx >= 0 && xx < width) out[yy * width + xx] = 1;
                    }
                }
            }
        }
        return out;
    }

    function erode(mask, width, height, radius) {
        if (radius <= 0) return new Uint8Array(mask);
        var out = new Uint8Array(mask.length);
        var x;
        var y;
        var ox;
        var oy;
        for (y = 0; y < height; y += 1) {
            for (x = 0; x < width; x += 1) {
                var keep = 1;
                for (oy = -radius; oy <= radius && keep; oy += 1) {
                    var yy = y + oy;
                    var span = Math.floor(Math.sqrt(radius * radius - oy * oy));
                    for (ox = -span; ox <= span; ox += 1) {
                        var xx = x + ox;
                        if (xx < 0 || xx >= width || yy < 0 || yy >= height || !mask[yy * width + xx]) {
                            keep = 0;
                            break;
                        }
                    }
                }
                if (keep) out[y * width + x] = 1;
            }
        }
        return out;
    }

    function closeMask(mask, width, height, radius) {
        return erode(dilate(mask, width, height, radius), width, height, radius);
    }

    function fillSmallHoles(mask, width, height, maxHoleArea) {
        var visited = new Uint8Array(mask.length);
        var queue = new Int32Array(mask.length);
        var x;
        var y;
        var head;
        var tail;
        var index;

        function flood(start, collect) {
            head = 0;
            tail = 0;
            queue[tail++] = start;
            visited[start] = 1;
            var cells = collect ? [] : null;
            while (head < tail) {
                var current = queue[head++];
                if (cells) cells.push(current);
                var cx = current % width;
                var cy = Math.floor(current / width);
                var next;
                if (cx > 0) {
                    next = current - 1;
                    if (!mask[next] && !visited[next]) { visited[next] = 1; queue[tail++] = next; }
                }
                if (cx + 1 < width) {
                    next = current + 1;
                    if (!mask[next] && !visited[next]) { visited[next] = 1; queue[tail++] = next; }
                }
                if (cy > 0) {
                    next = current - width;
                    if (!mask[next] && !visited[next]) { visited[next] = 1; queue[tail++] = next; }
                }
                if (cy + 1 < height) {
                    next = current + width;
                    if (!mask[next] && !visited[next]) { visited[next] = 1; queue[tail++] = next; }
                }
            }
            return cells;
        }

        for (x = 0; x < width; x += 1) {
            index = x;
            if (!mask[index] && !visited[index]) flood(index, false);
            index = (height - 1) * width + x;
            if (!mask[index] && !visited[index]) flood(index, false);
        }
        for (y = 1; y + 1 < height; y += 1) {
            index = y * width;
            if (!mask[index] && !visited[index]) flood(index, false);
            index = y * width + width - 1;
            if (!mask[index] && !visited[index]) flood(index, false);
        }

        var out = new Uint8Array(mask);
        for (index = 0; index < mask.length; index += 1) {
            if (mask[index] || visited[index]) continue;
            var cells = flood(index, true);
            if (cells.length <= maxHoleArea) {
                for (var i = 0; i < cells.length; i += 1) out[cells[i]] = 1;
            }
        }
        return out;
    }

    function retainComponents(mask, width, height) {
        var labels = new Int32Array(mask.length);
        var queue = new Int32Array(mask.length);
        var components = [];
        var label = 0;
        var index;
        for (index = 0; index < mask.length; index += 1) {
            if (!mask[index] || labels[index]) continue;
            label += 1;
            var head = 0;
            var tail = 0;
            var minX = width;
            var minY = height;
            var maxX = 0;
            var maxY = 0;
            var sumX = 0;
            var sumY = 0;
            queue[tail++] = index;
            labels[index] = label;
            while (head < tail) {
                var current = queue[head++];
                var x = current % width;
                var y = Math.floor(current / width);
                if (x < minX) minX = x;
                if (x > maxX) maxX = x;
                if (y < minY) minY = y;
                if (y > maxY) maxY = y;
                sumX += x;
                sumY += y;
                var next;
                if (x > 0) {
                    next = current - 1;
                    if (mask[next] && !labels[next]) { labels[next] = label; queue[tail++] = next; }
                }
                if (x + 1 < width) {
                    next = current + 1;
                    if (mask[next] && !labels[next]) { labels[next] = label; queue[tail++] = next; }
                }
                if (y > 0) {
                    next = current - width;
                    if (mask[next] && !labels[next]) { labels[next] = label; queue[tail++] = next; }
                }
                if (y + 1 < height) {
                    next = current + width;
                    if (mask[next] && !labels[next]) { labels[next] = label; queue[tail++] = next; }
                }
            }
            components.push({
                label: label,
                area: tail,
                minX: minX,
                minY: minY,
                maxX: maxX,
                maxY: maxY,
                cx: sumX / tail,
                cy: sumY / tail
            });
        }
        if (!components.length) return new Uint8Array(mask.length);
        components.sort(function(a, b) {
            var ac = 1 - Math.min(1, Math.hypot(a.cx - width * 0.5, a.cy - height * 0.5) / Math.max(width, height));
            var bc = 1 - Math.min(1, Math.hypot(b.cx - width * 0.5, b.cy - height * 0.5) / Math.max(width, height));
            return b.area * (0.72 + bc * 0.28) - a.area * (0.72 + ac * 0.28);
        });
        var main = components[0];
        var keep = {};
        keep[main.label] = true;
        var maxGap = Math.max(width, height) * 0.12;
        for (var c = 1; c < components.length; c += 1) {
            var part = components[c];
            var gapX = Math.max(0, main.minX - part.maxX, part.minX - main.maxX);
            var gapY = Math.max(0, main.minY - part.maxY, part.minY - main.maxY);
            var gap = Math.hypot(gapX, gapY);
            if (part.area >= Math.max(3, main.area * 0.006) && gap <= maxGap) keep[part.label] = true;
        }
        var out = new Uint8Array(mask.length);
        for (index = 0; index < labels.length; index += 1) {
            if (keep[labels[index]]) out[index] = 1;
        }
        return out;
    }

    function sampleEdgeColor(imageData) {
        var width = imageData.width;
        var height = imageData.height;
        var data = imageData.data;
        var channels = [[], [], []];
        var rings = [0, 0.025, 0.065];
        var step = Math.max(1, Math.floor(Math.min(width, height) / 32));
        var r;
        var x;
        var y;

        function push(px, py) {
            px = clamp(Math.round(px), 0, width - 1);
            py = clamp(Math.round(py), 0, height - 1);
            var offset = (py * width + px) * 4;
            if (data[offset + 3] < DEFAULT_ALPHA_THRESHOLD) return;
            channels[0].push(data[offset]);
            channels[1].push(data[offset + 1]);
            channels[2].push(data[offset + 2]);
        }

        for (r = 0; r < rings.length; r += 1) {
            var insetX = rings[r] * (width - 1);
            var insetY = rings[r] * (height - 1);
            for (x = 0; x < width; x += step) {
                push(x, insetY);
                push(x, height - 1 - insetY);
            }
            for (y = 0; y < height; y += step) {
                push(insetX, y);
                push(width - 1 - insetX, y);
            }
        }
        var color = [median(channels[0]), median(channels[1]), median(channels[2])];
        var distances = [];
        for (var i = 0; i < channels[0].length; i += 1) {
            var dr = channels[0][i] - color[0];
            var dg = channels[1][i] - color[1];
            var db = channels[2][i] - color[2];
            distances.push(Math.sqrt(dr * dr * 0.30 + dg * dg * 0.59 + db * db * 0.11));
        }
        var center = median(distances);
        var deviations = distances.map(function(value) { return Math.abs(value - center); });
        return {
            color: color,
            threshold: clamp(center + median(deviations) * 3.2 + 12, 22, 78),
            spread: median(deviations)
        };
    }

    function segmentOpaqueBackground(imageData, alpha) {
        var width = imageData.width;
        var height = imageData.height;
        var data = imageData.data;
        var sample = sampleEdgeColor(imageData);
        var background = new Uint8Array(alpha.mask.length);
        var queue = new Int32Array(alpha.mask.length);
        var head = 0;
        var tail = 0;
        var x;
        var y;

        function seed(index) {
            if (!background[index]) {
                background[index] = 1;
                queue[tail++] = index;
            }
        }

        for (x = 0; x < width; x += 1) {
            seed(x);
            seed((height - 1) * width + x);
        }
        for (y = 1; y + 1 < height; y += 1) {
            seed(y * width);
            seed(y * width + width - 1);
        }

        while (head < tail) {
            var current = queue[head++];
            var cx = current % width;
            var cy = Math.floor(current / width);
            var currentOffset = current * 4;

            function visit(next) {
                if (background[next]) return;
                var offset = next * 4;
                var globalDistance = colorDistance(data, offset, sample.color);
                var localDistance = localColorDistance(data, offset, currentOffset);
                if (!alpha.mask[next] || globalDistance <= sample.threshold
                        || (globalDistance <= sample.threshold * 1.55 && localDistance <= 18 + sample.spread)) {
                    background[next] = 1;
                    queue[tail++] = next;
                }
            }

            if (cx > 0) visit(current - 1);
            if (cx + 1 < width) visit(current + 1);
            if (cy > 0) visit(current - width);
            if (cy + 1 < height) visit(current + width);
        }

        var candidate = new Uint8Array(alpha.mask.length);
        var margin = Math.max(1, Math.floor(Math.min(width, height) * 0.012));
        var count = 0;
        for (y = margin; y < height - margin; y += 1) {
            for (x = margin; x < width - margin; x += 1) {
                var index = y * width + x;
                if (alpha.mask[index] && !background[index]) {
                    candidate[index] = 1;
                    count += 1;
                }
            }
        }
        candidate = closeMask(candidate, width, height, 1);
        candidate = fillSmallHoles(candidate, width, height, Math.max(24, Math.round(count * 0.12)));
        candidate = retainComponents(candidate, width, height);
        var bounds = maskBounds(candidate, width, height);

        if (bounds.count < width * height * 0.006 || bounds.count > width * height * 0.72) {
            candidate.fill(0);
            for (y = margin; y < height - margin; y += 1) {
                for (x = margin; x < width - margin; x += 1) {
                    var fallbackIndex = y * width + x;
                    if (alpha.mask[fallbackIndex]
                            && colorDistance(data, fallbackIndex * 4, sample.color) > sample.threshold * 0.72) {
                        candidate[fallbackIndex] = 1;
                    }
                }
            }
            candidate = fillSmallHoles(closeMask(candidate, width, height, 1), width, height,
                Math.max(24, Math.round(width * height * 0.05)));
            candidate = retainComponents(candidate, width, height);
            bounds = maskBounds(candidate, width, height);
        }
        return { mask: candidate, bounds: bounds, edgeColor: sample.color, threshold: sample.threshold };
    }

    function extractObjectMask(imageData, options) {
        options = options || {};
        var threshold = options.alphaThreshold === undefined ? DEFAULT_ALPHA_THRESHOLD : options.alphaThreshold;
        var alpha = alphaMask(imageData, threshold);
        var total = imageData.width * imageData.height;
        if (!alpha.count) {
            return {
                mask: alpha.mask,
                bounds: maskBounds(alpha.mask, imageData.width, imageData.height),
                source: "empty-alpha",
                confidence: 0
            };
        }
        var alphaCoverage = alpha.count / total;
        if (alphaCoverage < 0.86) {
            var direct = retainComponents(alpha.mask, imageData.width, imageData.height);
            return {
                mask: direct,
                bounds: maskBounds(direct, imageData.width, imageData.height),
                source: "alpha",
                confidence: round(clamp(1 - alphaCoverage * 0.25, 0.72, 0.99))
            };
        }
        var segmented = segmentOpaqueBackground(imageData, alpha);
        var segmentedCoverage = segmented.bounds.count / total;
        if (segmented.bounds.count < Math.max(12, Math.round(total * 0.006))) {
            return {
                mask: alpha.mask,
                bounds: maskBounds(alpha.mask, imageData.width, imageData.height),
                source: "opaque-alpha-fallback",
                confidence: 0.12,
                backgroundColor: segmented.edgeColor,
                backgroundThreshold: round(segmented.threshold, 2)
            };
        }
        return {
            mask: segmented.mask,
            bounds: segmented.bounds,
            source: "edge-segmented-alpha",
            confidence: round(clamp(1 - Math.abs(segmentedCoverage - 0.28), 0.38, 0.9)),
            backgroundColor: segmented.edgeColor,
            backgroundThreshold: round(segmented.threshold, 2)
        };
    }

    function edt1d(source, length, output, vertices, boundaries) {
        var k = 0;
        var q;
        vertices[0] = 0;
        boundaries[0] = -INF;
        boundaries[1] = INF;
        for (q = 1; q < length; q += 1) {
            var vertex = vertices[k];
            var intersection = ((source[q] + q * q) - (source[vertex] + vertex * vertex))
                / (2 * q - 2 * vertex);
            while (intersection <= boundaries[k] && k > 0) {
                k -= 1;
                vertex = vertices[k];
                intersection = ((source[q] + q * q) - (source[vertex] + vertex * vertex))
                    / (2 * q - 2 * vertex);
            }
            k += 1;
            vertices[k] = q;
            boundaries[k] = intersection;
            boundaries[k + 1] = INF;
        }
        k = 0;
        for (q = 0; q < length; q += 1) {
            while (boundaries[k + 1] < q) k += 1;
            var delta = q - vertices[k];
            output[q] = delta * delta + source[vertices[k]];
        }
    }

    function distanceToFeature(featureMask, width, height) {
        var size = width * height;
        var interim = new Float64Array(size);
        var output = new Float64Array(size);
        var maxLength = Math.max(width, height);
        var source = new Float64Array(maxLength);
        var result = new Float64Array(maxLength);
        var vertices = new Int32Array(maxLength);
        var boundaries = new Float64Array(maxLength + 1);
        var x;
        var y;

        for (x = 0; x < width; x += 1) {
            for (y = 0; y < height; y += 1) source[y] = featureMask[y * width + x] ? 0 : INF;
            edt1d(source, height, result, vertices, boundaries);
            for (y = 0; y < height; y += 1) interim[y * width + x] = result[y];
        }
        for (y = 0; y < height; y += 1) {
            for (x = 0; x < width; x += 1) source[x] = interim[y * width + x];
            edt1d(source, width, result, vertices, boundaries);
            for (x = 0; x < width; x += 1) output[y * width + x] = result[x];
        }
        return output;
    }

    function signedDistance(mask, width, height) {
        var background = new Uint8Array(mask.length);
        var hasForeground = false;
        var hasBackground = false;
        var i;
        for (i = 0; i < mask.length; i += 1) {
            if (mask[i]) hasForeground = true;
            else { background[i] = 1; hasBackground = true; }
        }
        var result = new Float64Array(mask.length);
        if (!hasForeground) {
            result.fill(-Math.max(width, height));
            return result;
        }
        if (!hasBackground) {
            result.fill(Math.max(width, height));
            return result;
        }
        var toForeground = distanceToFeature(mask, width, height);
        var toBackground = distanceToFeature(background, width, height);
        for (i = 0; i < mask.length; i += 1) {
            result[i] = mask[i] ? Math.sqrt(toBackground[i]) : -Math.sqrt(toForeground[i]);
        }
        return result;
    }

    function downsampleMask(mask, width, height, bounds, maxDimension) {
        if (!bounds || !bounds.count) {
            return { mask: new Uint8Array(1), width: 1, height: 1, bounds: bounds || maskBounds(mask, width, height) };
        }
        var longest = Math.max(bounds.width, bounds.height);
        var scale = Math.min(1, maxDimension / longest);
        var gridWidth = Math.max(3, Math.round(bounds.width * scale));
        var gridHeight = Math.max(3, Math.round(bounds.height * scale));
        var grid = new Uint8Array(gridWidth * gridHeight);
        var gx;
        var gy;
        for (gy = 0; gy < gridHeight; gy += 1) {
            var y0 = bounds.y + Math.floor(gy * bounds.height / gridHeight);
            var y1 = bounds.y + Math.max(1, Math.ceil((gy + 1) * bounds.height / gridHeight));
            for (gx = 0; gx < gridWidth; gx += 1) {
                var x0 = bounds.x + Math.floor(gx * bounds.width / gridWidth);
                var x1 = bounds.x + Math.max(1, Math.ceil((gx + 1) * bounds.width / gridWidth));
                var occupied = 0;
                var sampled = 0;
                for (var y = y0; y < Math.min(y1, height); y += 1) {
                    for (var x = x0; x < Math.min(x1, width); x += 1) {
                        sampled += 1;
                        occupied += mask[y * width + x] ? 1 : 0;
                    }
                }
                if (sampled && occupied / sampled >= 0.2) grid[gy * gridWidth + gx] = 1;
            }
        }
        grid = fillSmallHoles(closeMask(grid, gridWidth, gridHeight, 1), gridWidth, gridHeight,
            Math.max(6, Math.round(grid.length * 0.07)));
        return {
            mask: grid,
            width: gridWidth,
            height: gridHeight,
            bounds: bounds,
            sourceWidth: width,
            sourceHeight: height
        };
    }

    function thinMask(source, width, height) {
        var mask = new Uint8Array(source);
        var remove = new Uint8Array(mask.length);
        var changed = true;
        var iteration = 0;
        var x;
        var y;

        function transitions(p) {
            var count = 0;
            var i;
            for (i = 0; i < 8; i += 1) {
                if (!p[i] && p[(i + 1) % 8]) count += 1;
            }
            return count;
        }

        while (changed && iteration < 96) {
            changed = false;
            iteration += 1;
            for (var phase = 0; phase < 2; phase += 1) {
                remove.fill(0);
                for (y = 1; y + 1 < height; y += 1) {
                    for (x = 1; x + 1 < width; x += 1) {
                        var index = y * width + x;
                        if (!mask[index]) continue;
                        var p = [
                            mask[index - width], mask[index - width + 1], mask[index + 1],
                            mask[index + width + 1], mask[index + width], mask[index + width - 1],
                            mask[index - 1], mask[index - width - 1]
                        ];
                        var neighbors = 0;
                        for (var n = 0; n < 8; n += 1) neighbors += p[n] ? 1 : 0;
                        if (neighbors < 2 || neighbors > 6 || transitions(p) !== 1) continue;
                        if (phase === 0) {
                            if (p[0] && p[2] && p[4]) continue;
                            if (p[2] && p[4] && p[6]) continue;
                        } else {
                            if (p[0] && p[2] && p[6]) continue;
                            if (p[0] && p[4] && p[6]) continue;
                        }
                        remove[index] = 1;
                    }
                }
                for (var i = 0; i < mask.length; i += 1) {
                    if (remove[i]) { mask[i] = 0; changed = true; }
                }
            }
        }
        return mask;
    }

    function maskMoments(mask, width, height) {
        var count = 0;
        var sumX = 0;
        var sumY = 0;
        var x;
        var y;
        for (y = 0; y < height; y += 1) {
            for (x = 0; x < width; x += 1) {
                if (!mask[y * width + x]) continue;
                count += 1;
                sumX += x;
                sumY += y;
            }
        }
        if (!count) return { count: 0, cx: width * 0.5, cy: height * 0.5, majorX: 1, majorY: 0, ratio: 1 };
        var cx = sumX / count;
        var cy = sumY / count;
        var xx = 0;
        var yy = 0;
        var xy = 0;
        for (y = 0; y < height; y += 1) {
            for (x = 0; x < width; x += 1) {
                if (!mask[y * width + x]) continue;
                var dx = x - cx;
                var dy = y - cy;
                xx += dx * dx;
                yy += dy * dy;
                xy += dx * dy;
            }
        }
        xx /= count;
        yy /= count;
        xy /= count;
        var trace = xx + yy;
        var delta = Math.sqrt(Math.max(0, (xx - yy) * (xx - yy) + 4 * xy * xy));
        var lambda1 = (trace + delta) * 0.5;
        var lambda2 = Math.max(1e-6, (trace - delta) * 0.5);
        var majorX;
        var majorY;
        if (Math.abs(xy) > 1e-8) {
            majorX = lambda1 - yy;
            majorY = xy;
        } else if (xx >= yy) {
            majorX = 1;
            majorY = 0;
        } else {
            majorX = 0;
            majorY = 1;
        }
        var norm = Math.hypot(majorX, majorY) || 1;
        return {
            count: count,
            cx: cx,
            cy: cy,
            majorX: majorX / norm,
            majorY: majorY / norm,
            lambda1: lambda1,
            lambda2: lambda2,
            ratio: Math.sqrt(lambda1 / lambda2)
        };
    }

    function gridToSource(grid, x, y) {
        return {
            x: grid.bounds.x + (x + 0.5) * grid.bounds.width / grid.width,
            y: grid.bounds.y + (y + 0.5) * grid.bounds.height / grid.height
        };
    }

    function findAutomaticAnchor(mask, width, height, seed) {
        var bounds = maskBounds(mask, width, height);
        if (!bounds.count) {
            return { x: width * 0.5, y: height * 0.5, normalizedX: 0.5, normalizedY: 0.5,
                confidence: 0, method: "empty-fallback", shapeClass: "empty" };
        }
        var grid = downsampleMask(mask, width, height, bounds, 112);
        var moments = maskMoments(grid.mask, grid.width, grid.height);
        var skeleton = thinMask(grid.mask, grid.width, grid.height);
        var background = new Uint8Array(grid.mask.length);
        for (var i = 0; i < background.length; i += 1) background[i] = grid.mask[i] ? 0 : 1;
        var widthSquared = distanceToFeature(background, grid.width, grid.height);
        var maxWidth = 1;
        var candidates = [];
        var minProjection = INF;
        var maxProjection = -INF;
        var minIndex = -1;
        var maxIndex = -1;
        var skeletonMinProjection = INF;
        var skeletonMaxProjection = -INF;
        var skeletonMinIndex = -1;
        var skeletonMaxIndex = -1;
        var x;
        var y;
        for (y = 0; y < grid.height; y += 1) {
            for (x = 0; x < grid.width; x += 1) {
                var index = y * grid.width + x;
                if (!grid.mask[index]) continue;
                var localWidth = Math.sqrt(widthSquared[index]);
                if (localWidth > maxWidth) maxWidth = localWidth;
                var projection = (x - moments.cx) * moments.majorX + (y - moments.cy) * moments.majorY;
                if (projection < minProjection) { minProjection = projection; minIndex = index; }
                if (projection > maxProjection) { maxProjection = projection; maxIndex = index; }
                if (!skeleton[index]) continue;
                if (projection < skeletonMinProjection) { skeletonMinProjection = projection; skeletonMinIndex = index; }
                if (projection > skeletonMaxProjection) { skeletonMaxProjection = projection; skeletonMaxIndex = index; }
                var neighbors = 0;
                for (var oy = -1; oy <= 1; oy += 1) {
                    for (var ox = -1; ox <= 1; ox += 1) {
                        if (!ox && !oy) continue;
                        var xx = x + ox;
                        var yy = y + oy;
                        if (xx >= 0 && xx < grid.width && yy >= 0 && yy < grid.height
                                && skeleton[yy * grid.width + xx]) neighbors += 1;
                    }
                }
                if (neighbors <= 1 || neighbors >= 3) candidates.push(index);
            }
        }
        if (skeletonMinIndex >= 0) candidates.push(skeletonMinIndex);
        if (skeletonMaxIndex >= 0) candidates.push(skeletonMaxIndex);
        if (minIndex >= 0) candidates.push(minIndex);
        if (maxIndex >= 0) candidates.push(maxIndex);
        var unique = {};
        candidates = candidates.filter(function(index) {
            if (unique[index]) return false;
            unique[index] = true;
            return true;
        });
        if (!candidates.length) candidates.push(minIndex >= 0 ? minIndex : 0);

        var maxProjectionMagnitude = Math.max(1, Math.abs(minProjection), Math.abs(maxProjection));
        var maxPerpendicular = Math.max(1, Math.min(grid.width, grid.height) * 0.5);
        var projectionRange = Math.max(1, maxProjection - minProjection);
        var negativeLimit = minProjection + projectionRange * 0.30;
        var positiveLimit = maxProjection - projectionRange * 0.30;
        var negativeMass = 0;
        var positiveMass = 0;
        var negativeWidth = 0;
        var positiveWidth = 0;
        for (var terminalIndex = 0; terminalIndex < grid.mask.length; terminalIndex += 1) {
            if (!grid.mask[terminalIndex]) continue;
            var terminalX = terminalIndex % grid.width;
            var terminalY = Math.floor(terminalIndex / grid.width);
            var terminalProjection = (terminalX - moments.cx) * moments.majorX
                + (terminalY - moments.cy) * moments.majorY;
            if (terminalProjection <= negativeLimit) {
                negativeMass += 1;
                negativeWidth += Math.sqrt(widthSquared[terminalIndex]);
            }
            if (terminalProjection >= positiveLimit) {
                positiveMass += 1;
                positiveWidth += Math.sqrt(widthSquared[terminalIndex]);
            }
        }
        var negativeStrength = negativeMass * (0.35 + negativeWidth / Math.max(1, negativeMass * maxWidth));
        var positiveStrength = positiveMass * (0.35 + positiveWidth / Math.max(1, positiveMass * maxWidth));
        var endStrengthMax = Math.max(1, negativeStrength, positiveStrength);
        var scored = candidates.map(function(index) {
            var px = index % grid.width;
            var py = Math.floor(index / grid.width);
            var projection = (px - moments.cx) * moments.majorX + (py - moments.cy) * moments.majorY;
            var perpendicular = Math.abs((px - moments.cx) * -moments.majorY + (py - moments.cy) * moments.majorX);
            var extreme = Math.abs(projection) / maxProjectionMagnitude;
            var axisAlignment = 1 - clamp(perpendicular / maxPerpendicular, 0, 1);
            var localWidth = Math.sqrt(widthSquared[index]) / maxWidth;
            var mass = 0;
            var branch = 0;
            for (var oy = -5; oy <= 5; oy += 1) {
                for (var ox = -5; ox <= 5; ox += 1) {
                    if (ox * ox + oy * oy > 25) continue;
                    var xx = px + ox;
                    var yy = py + oy;
                    if (xx < 0 || xx >= grid.width || yy < 0 || yy >= grid.height) continue;
                    if (grid.mask[yy * grid.width + xx]) mass += 1;
                    if (skeleton[yy * grid.width + xx]) branch += 1;
                }
            }
            mass = mass / 81;
            branch = clamp(branch / 18, 0, 1);
            var thinPenalty = localWidth < 0.14 ? (0.14 - localWidth) * 1.8 : 0;
            var terminalStrength = (projection < 0 ? negativeStrength : positiveStrength) / endStrengthMax;
            var tie = hashCoord(px, py, hash32(seed)) * 0.005;
            return {
                index: index,
                x: px,
                y: py,
                score: extreme * 0.32 + axisAlignment * 0.10 + localWidth * 0.20 + mass * 0.13
                    + branch * 0.05 + terminalStrength * 0.20 - thinPenalty + tie,
                extreme: extreme,
                width: localWidth,
                mass: mass
            };
        }).sort(function(a, b) { return b.score - a.score; });

        var best = scored[0];
        var second = scored.length > 1 ? scored[1] : { score: best.score - 0.25 };
        var sourcePoint = gridToSource(grid, best.x, best.y);
        var shapeClass = moments.ratio >= 2.15 ? "elongated"
            : moments.ratio >= 1.38 ? "asymmetric-compact" : "compact";
        return {
            x: sourcePoint.x,
            y: sourcePoint.y,
            normalizedX: round(sourcePoint.x / width),
            normalizedY: round(sourcePoint.y / height),
            confidence: round(clamp(0.42 + (best.score - second.score) * 1.45
                + (moments.ratio >= 2.15 ? 0.13 : 0), 0.18, 0.98)),
            method: "pca-pruned-skeleton",
            shapeClass: shapeClass,
            elongation: round(moments.ratio, 3),
            score: round(best.score, 4),
            centroid: gridToSource(grid, moments.cx, moments.cy)
        };
    }

    function planOrientation(imageData, targetWidth, targetHeight, options) {
        options = options || {};
        var extraction = extractObjectMask(imageData, options);
        var bounds = extraction.bounds;
        if (!bounds.count) {
            return {
                degrees: 0,
                scale: 1,
                bounds: bounds,
                sourceAnalysis: extraction,
                anchor: findAutomaticAnchor(extraction.mask, imageData.width, imageData.height, options.seed || "empty"),
                outputAnchor: { x: targetWidth * 0.5, y: targetHeight * 0.5 }
            };
        }
        var anchor = findAutomaticAnchor(extraction.mask, imageData.width, imageData.height, options.seed || "anchor");
        var padding = clamp(options.paddingRatio === undefined ? 0.075 : options.paddingRatio, 0.02, 0.2);
        var availableWidth = targetWidth * (1 - padding * 2);
        var availableHeight = targetHeight * (1 - padding * 2);
        var scale0 = Math.min(availableWidth / bounds.width, availableHeight / bounds.height);
        var scale90 = Math.min(availableWidth / bounds.height, availableHeight / bounds.width);
        var horizontal = bounds.width / Math.max(1, bounds.height) >= 1.18;
        var rotate = options.autoRotate !== false && horizontal && scale90 > scale0 * 1.07;
        var degrees = 0;
        if (rotate) {
            var centroidX = anchor.centroid ? anchor.centroid.x : bounds.x + bounds.width * 0.5;
            degrees = anchor.x <= centroidX ? 90 : -90;
        }
        var scale = rotate ? scale90 : scale0;
        var centerX = bounds.x + bounds.width * 0.5;
        var centerY = bounds.y + bounds.height * 0.5;
        var dx = anchor.x - centerX;
        var dy = anchor.y - centerY;
        var radians = degrees * Math.PI / 180;
        var outputAnchor = {
            x: targetWidth * 0.5 + (Math.cos(radians) * dx - Math.sin(radians) * dy) * scale,
            y: targetHeight * 0.5 + (Math.sin(radians) * dx + Math.cos(radians) * dy) * scale
        };
        if (rotate && outputAnchor.y > targetHeight * 0.5) {
            degrees = -degrees;
            radians = degrees * Math.PI / 180;
            outputAnchor.x = targetWidth * 0.5 + (Math.cos(radians) * dx - Math.sin(radians) * dy) * scale;
            outputAnchor.y = targetHeight * 0.5 + (Math.sin(radians) * dx + Math.cos(radians) * dy) * scale;
        }
        return {
            degrees: degrees,
            scale: scale,
            bounds: bounds,
            sourceAnalysis: extraction,
            anchor: anchor,
            outputAnchor: outputAnchor,
            fitGain: round((rotate ? scale90 : scale0) / Math.max(1e-6, scale0), 3)
        };
    }

    function MinHeap(capacity) {
        this.nodes = new Int32Array(Math.max(8, capacity));
        this.values = new Float64Array(Math.max(8, capacity));
        this.length = 0;
    }

    MinHeap.prototype._grow = function() {
        var nodes = new Int32Array(this.nodes.length * 2);
        var values = new Float64Array(this.values.length * 2);
        nodes.set(this.nodes);
        values.set(this.values);
        this.nodes = nodes;
        this.values = values;
    };

    MinHeap.prototype.push = function(node, value) {
        if (this.length >= this.nodes.length) this._grow();
        var index = this.length++;
        while (index > 0) {
            var parent = (index - 1) >> 1;
            if (this.values[parent] <= value) break;
            this.nodes[index] = this.nodes[parent];
            this.values[index] = this.values[parent];
            index = parent;
        }
        this.nodes[index] = node;
        this.values[index] = value;
    };

    MinHeap.prototype.pop = function() {
        if (!this.length) return null;
        var node = this.nodes[0];
        var value = this.values[0];
        this.length -= 1;
        if (this.length) {
            var lastNode = this.nodes[this.length];
            var lastValue = this.values[this.length];
            var index = 0;
            while (true) {
                var left = index * 2 + 1;
                if (left >= this.length) break;
                var right = left + 1;
                var child = right < this.length && this.values[right] < this.values[left] ? right : left;
                if (this.values[child] >= lastValue) break;
                this.nodes[index] = this.nodes[child];
                this.values[index] = this.values[child];
                index = child;
            }
            this.nodes[index] = lastNode;
            this.values[index] = lastValue;
        }
        return { node: node, value: value };
    };

    function nearestGridCell(grid, sourceX, sourceY) {
        var guessX = Math.floor((sourceX - grid.bounds.x) * grid.width / Math.max(1, grid.bounds.width));
        var guessY = Math.floor((sourceY - grid.bounds.y) * grid.height / Math.max(1, grid.bounds.height));
        guessX = clamp(guessX, 0, grid.width - 1);
        guessY = clamp(guessY, 0, grid.height - 1);
        var guessed = guessY * grid.width + guessX;
        if (grid.mask[guessed]) return guessed;
        var best = -1;
        var bestDistance = INF;
        for (var index = 0; index < grid.mask.length; index += 1) {
            if (!grid.mask[index]) continue;
            var x = index % grid.width;
            var y = Math.floor(index / grid.width);
            var distance = (x - guessX) * (x - guessX) + (y - guessY) * (y - guessY);
            if (distance < bestDistance) { bestDistance = distance; best = index; }
        }
        return best;
    }

    function geodesicArrival(grid, anchor, seed) {
        var arrival = new Float64Array(grid.mask.length);
        arrival.fill(INF);
        var start = nearestGridCell(grid, anchor.x, anchor.y);
        if (start < 0) return arrival;
        var background = new Uint8Array(grid.mask.length);
        for (var i = 0; i < background.length; i += 1) background[i] = grid.mask[i] ? 0 : 1;
        var widthSquared = distanceToFeature(background, grid.width, grid.height);
        var maxWidth = 1;
        for (i = 0; i < widthSquared.length; i += 1) {
            if (grid.mask[i] && widthSquared[i] > maxWidth) maxWidth = widthSquared[i];
        }
        maxWidth = Math.sqrt(maxWidth);
        var heap = new MinHeap(Math.max(16, Math.floor(grid.mask.length * 0.4)));
        arrival[start] = 0;
        heap.push(start, 0);
        var directions = [
            [-1, 0, 1], [1, 0, 1], [0, -1, 1], [0, 1, 1],
            [-1, -1, Math.SQRT2], [1, -1, Math.SQRT2], [-1, 1, Math.SQRT2], [1, 1, Math.SQRT2]
        ];
        while (heap.length) {
            var current = heap.pop();
            if (current.value !== arrival[current.node]) continue;
            var cx = current.node % grid.width;
            var cy = Math.floor(current.node / grid.width);
            for (var d = 0; d < directions.length; d += 1) {
                var nx = cx + directions[d][0];
                var ny = cy + directions[d][1];
                if (nx < 0 || nx >= grid.width || ny < 0 || ny >= grid.height) continue;
                var next = ny * grid.width + nx;
                if (!grid.mask[next]) continue;
                var widthBias = 1 - clamp(Math.sqrt(widthSquared[next]) / maxWidth, 0, 1);
                var texture = valueNoise(nx * 0.19, ny * 0.19, seed ^ 0x6d2b79f5);
                var step = directions[d][2] * (0.76 + widthBias * 0.18 + texture * 0.34);
                var nextValue = current.value + step;
                if (nextValue < arrival[next]) {
                    arrival[next] = nextValue;
                    heap.push(next, nextValue);
                }
            }
        }
        return arrival;
    }

    function nthValue(values, target) {
        var left = 0;
        var right = values.length - 1;
        while (left < right) {
            var pivot = values[(left + right) >> 1];
            var i = left;
            var j = right;
            while (i <= j) {
                while (values[i] < pivot) i += 1;
                while (values[j] > pivot) j -= 1;
                if (i <= j) {
                    var tmp = values[i];
                    values[i] = values[j];
                    values[j] = tmp;
                    i += 1;
                    j -= 1;
                }
            }
            if (target <= j) right = j;
            else if (target >= i) left = i;
            else return values[target];
        }
        return values[left];
    }

    function buildCoverageMasks(objectMask, width, height, anchor, targetCoverage, seedText) {
        var bounds = maskBounds(objectMask, width, height);
        var grid = downsampleMask(objectMask, width, height, bounds, 128);
        var seed = hash32(seedText || "blackmarket-surface");
        var arrival = geodesicArrival(grid, anchor, seed);
        var objectPixels = bounds.count;
        var targetCovered = clamp(Math.round(objectPixels * targetCoverage), 0, objectPixels);
        var revealCount = objectPixels - targetCovered;
        var reveal = new Uint8Array(objectMask.length);
        var mudInside = new Uint8Array(objectMask.length);
        if (!objectPixels) {
            return { reveal: reveal, mudInside: mudInside, objectPixels: 0, coveredPixels: 0,
                actualCoverage: 0, targetCoverage: targetCoverage, grid: grid };
        }
        if (revealCount <= 0) {
            mudInside.set(objectMask);
            return { reveal: reveal, mudInside: mudInside, objectPixels: objectPixels, coveredPixels: objectPixels,
                actualCoverage: 1, targetCoverage: targetCoverage, grid: grid };
        }
        if (revealCount >= objectPixels) {
            reveal.set(objectMask);
            return { reveal: reveal, mudInside: mudInside, objectPixels: objectPixels, coveredPixels: 0,
                actualCoverage: 0, targetCoverage: targetCoverage, grid: grid };
        }

        var scores = new Float64Array(objectPixels);
        var scoreByPixel = new Float64Array(objectMask.length);
        scoreByPixel.fill(INF);
        var position = 0;
        for (var y = 0; y < height; y += 1) {
            for (var x = 0; x < width; x += 1) {
                var index = y * width + x;
                if (!objectMask[index]) continue;
                var gx = clamp(Math.floor((x - bounds.x) * grid.width / Math.max(1, bounds.width)), 0, grid.width - 1);
                var gy = clamp(Math.floor((y - bounds.y) * grid.height / Math.max(1, bounds.height)), 0, grid.height - 1);
                var base = arrival[gy * grid.width + gx];
                var micro = hashCoord(x, y, seed ^ 0xa5a5a5a5) * 0.21;
                var score = base + micro;
                scoreByPixel[index] = score;
                scores[position++] = score;
            }
        }
        var threshold = nthValue(scores, revealCount - 1);
        var revealed = 0;
        var ties = [];
        for (var i = 0; i < objectMask.length; i += 1) {
            if (!objectMask[i]) continue;
            if (scoreByPixel[i] < threshold) {
                reveal[i] = 1;
                revealed += 1;
            } else if (scoreByPixel[i] === threshold) {
                ties.push(i);
            }
        }
        ties.sort(function(a, b) {
            var ah = hashCoord(a % width, Math.floor(a / width), seed ^ 0x31415926);
            var bh = hashCoord(b % width, Math.floor(b / width), seed ^ 0x31415926);
            return ah - bh;
        });
        for (i = 0; i < ties.length && revealed < revealCount; i += 1) {
            reveal[ties[i]] = 1;
            revealed += 1;
        }
        var covered = 0;
        for (i = 0; i < objectMask.length; i += 1) {
            if (objectMask[i] && !reveal[i]) { mudInside[i] = 1; covered += 1; }
        }
        return {
            reveal: reveal,
            mudInside: mudInside,
            objectPixels: objectPixels,
            coveredPixels: covered,
            actualCoverage: covered / objectPixels,
            targetCoverage: targetCoverage,
            threshold: threshold,
            grid: grid
        };
    }

    function addAttachedEnvelope(coverage, objectMask, width, height, seedText) {
        var radius = clamp(Math.round(Math.min(width, height) * (0.008 + coverage.targetCoverage * 0.008)), 2, 7);
        var expandedMud = dilate(coverage.mudInside, width, height, radius);
        var expandedObject = dilate(objectMask, width, height, radius + 1);
        var protectedReveal = dilate(coverage.reveal, width, height, Math.max(1, radius - 1));
        var finalMud = new Uint8Array(objectMask.length);
        var i;
        for (i = 0; i < finalMud.length; i += 1) {
            if (expandedMud[i] && expandedObject[i] && !protectedReveal[i]) finalMud[i] = 1;
        }

        var seed = hash32(seedText || "blackmarket-surface");
        var bounds = maskBounds(coverage.mudInside, width, height);
        if (bounds.count) {
            var step = Math.max(3, Math.round(bounds.width / 28));
            for (var x = bounds.x; x < bounds.x + bounds.width; x += step) {
                var bottom = -1;
                for (var y = bounds.y + bounds.height - 1; y >= bounds.y; y -= 1) {
                    if (coverage.mudInside[y * width + x]) { bottom = y; break; }
                }
                if (bottom < 0 || hashCoord(x, bottom, seed ^ 0xf00dcafe) > 0.16) continue;
                var length = 3 + Math.floor(hashCoord(x, bottom, seed ^ 0x91e10da5) * (4 + radius * 2.4));
                var dripWidth = 1 + Math.floor(hashCoord(x, bottom, seed ^ 0xc2b2ae35) * Math.max(1, radius * 0.55));
                for (var dy = 1; dy <= length; dy += 1) {
                    var yy = bottom + dy;
                    if (yy >= height) break;
                    var taper = Math.max(0, Math.round(dripWidth * (1 - dy / (length + 2))));
                    for (var dx = -taper; dx <= taper; dx += 1) {
                        var xx = x + dx;
                        if (xx < 0 || xx >= width) continue;
                        var index = yy * width + xx;
                        if (!protectedReveal[index]) finalMud[index] = 1;
                    }
                }
            }
        }
        return { mask: finalMud, radius: radius };
    }

    function copyImageDataLike(imageData) {
        return { width: imageData.width, height: imageData.height, data: new Uint8ClampedArray(imageData.data) };
    }

    function sharpenSourceImageData(imageData, strength) {
        strength = clamp(Number(strength) || 0.18, 0, 0.35);
        if (!imageData || !imageData.data || strength <= 0) return copyImageDataLike(imageData);
        var width = imageData.width;
        var height = imageData.height;
        var source = imageData.data;
        var output = copyImageDataLike(imageData);
        var target = output.data;
        function channelAt(index, channel, fallback) {
            return source[index + 3] > 0 ? source[index + channel] : fallback;
        }
        for (var y = 1; y < height - 1; y += 1) {
            for (var x = 1; x < width - 1; x += 1) {
                var index = (y * width + x) * 4;
                if (source[index + 3] === 0) continue;
                var left = index - 4;
                var right = index + 4;
                var up = index - width * 4;
                var down = index + width * 4;
                for (var channel = 0; channel < 3; channel += 1) {
                    var center = source[index + channel];
                    var neighbors = channelAt(left, channel, center) + channelAt(right, channel, center)
                        + channelAt(up, channel, center) + channelAt(down, channel, center);
                    target[index + channel] = clamp(Math.round(center + (center * 4 - neighbors) * strength), 0, 255);
                }
            }
        }
        return output;
    }

    function applyHiddenColorMode(output, objectMask, mode) {
        if (mode === "source") return;
        var data = output.data;
        for (var i = 0; i < objectMask.length; i += 1) {
            if (!objectMask[i]) continue;
            var offset = i * 4;
            var luminance = data[offset] * 0.2126 + data[offset + 1] * 0.7152 + data[offset + 2] * 0.0722;
            var value = clamp(48 + luminance * 0.48, 32, 154);
            data[offset] = value * 0.82;
            data[offset + 1] = value * 0.88;
            data[offset + 2] = value * 0.87;
        }
    }

    function blendPixel(data, offset, red, green, blue, alpha) {
        var inverse = 1 - alpha;
        data[offset] = clamp(Math.round(data[offset] * inverse + red * alpha), 0, 255);
        data[offset + 1] = clamp(Math.round(data[offset + 1] * inverse + green * alpha), 0, 255);
        data[offset + 2] = clamp(Math.round(data[offset + 2] * inverse + blue * alpha), 0, 255);
        data[offset + 3] = clamp(Math.round(data[offset + 3] + (255 - data[offset + 3]) * alpha), 0, 255);
    }

    function drawDebugOverlay(output, objectMask, sdf, anchor, coverage) {
        var width = output.width;
        var height = output.height;
        var data = output.data;
        var x;
        var y;
        for (y = 1; y + 1 < height; y += 1) {
            for (x = 1; x + 1 < width; x += 1) {
                var index = y * width + x;
                if (objectMask[index] && (!objectMask[index - 1] || !objectMask[index + 1]
                        || !objectMask[index - width] || !objectMask[index + width])) {
                    blendPixel(data, index * 4, 78, 232, 217, 0.72);
                } else if (objectMask[index] && Math.abs((sdf[index] % 8) - 4) < 0.34) {
                    blendPixel(data, index * 4, 94, 126, 230, 0.36);
                }
            }
        }
        var ax = Math.round(anchor.x);
        var ay = Math.round(anchor.y);
        for (var delta = -7; delta <= 7; delta += 1) {
            var px = ax + delta;
            var py = ay + delta;
            if (px >= 0 && px < width && ay >= 0 && ay < height) blendPixel(data, (ay * width + px) * 4, 255, 75, 81, 0.94);
            if (ax >= 0 && ax < width && py >= 0 && py < height) blendPixel(data, (py * width + ax) * 4, 255, 75, 81, 0.94);
        }
        if (coverage && coverage.reveal) {
            for (y = 1; y + 1 < height; y += 1) {
                for (x = 1; x + 1 < width; x += 1) {
                    var revealIndex = y * width + x;
                    if (coverage.reveal[revealIndex]
                            && (!coverage.reveal[revealIndex - 1] || !coverage.reveal[revealIndex + 1]
                                || !coverage.reveal[revealIndex - width] || !coverage.reveal[revealIndex + width])) {
                        blendPixel(data, revealIndex * 4, 249, 187, 72, 0.62);
                    }
                }
            }
        }
    }

    function renderSurfaceImageData(imageData, options) {
        options = options || {};
        var started = typeof performance !== "undefined" && performance.now ? performance.now() : Date.now();
        var extraction = extractObjectMask(imageData, options);
        var objectMask = extraction.mask;
        var width = imageData.width;
        var height = imageData.height;
        var structural = fillSmallHoles(closeMask(objectMask, width, height, 1), width, height,
            Math.max(24, Math.round(extraction.bounds.count * 0.08)));
        var sdf = signedDistance(structural, width, height);
        var anchor = options.anchor && Number.isFinite(options.anchor.x) && Number.isFinite(options.anchor.y)
            ? {
                x: clamp(options.anchor.x, 0, width - 1),
                y: clamp(options.anchor.y, 0, height - 1),
                normalizedX: round(clamp(options.anchor.x / width, 0, 1)),
                normalizedY: round(clamp(options.anchor.y / height, 0, 1)),
                confidence: options.anchor.confidence === undefined ? 0.72 : options.anchor.confidence,
                method: options.anchor.method || "transformed-auto-anchor",
                shapeClass: options.anchor.shapeClass || "unknown",
                elongation: options.anchor.elongation || null
            }
            : findAutomaticAnchor(structural, width, height, options.seed || "surface-anchor");
        var targetCoverage = clamp(options.coverage === undefined ? 0.84 : Number(options.coverage), 0, 1);
        var mudEnabled = options.mud !== false && extraction.bounds.count > 0;
        var coverage = mudEnabled
            ? buildCoverageMasks(objectMask, width, height, anchor, targetCoverage, options.seed || "surface")
            : {
                reveal: new Uint8Array(objectMask),
                mudInside: new Uint8Array(objectMask.length),
                objectPixels: extraction.bounds.count,
                coveredPixels: 0,
                actualCoverage: 0,
                targetCoverage: targetCoverage
            };
        var envelope = mudEnabled ? addAttachedEnvelope(coverage, structural, width, height, options.seed || "surface")
            : { mask: new Uint8Array(objectMask.length), radius: 0 };
        var output = copyImageDataLike(imageData);
        applyHiddenColorMode(output, objectMask, options.hiddenColorMode || "source");
        var seed = hash32(options.seed || "surface");
        // The canvas backing store follows devicePixelRatio. Normalize the material coordinates to the
        // short axis so the swarm cells keep the same apparent scale instead of shrinking on high-DPI wells.
        var materialScale = clamp(Math.min(width, height) / 180, 0.5, 2.2);
        var heightField = new Float32Array(objectMask.length);
        var seamField = new Uint8Array(objectMask.length);
        var dormantNodeField = new Uint8Array(objectMask.length);
        var cellular = [0, 0, 0, 0];
        var i;
        if (mudEnabled) {
            for (var y = 0; y < height; y += 1) {
                for (var x = 0; x < width; x += 1) {
                    i = y * width + x;
                    if (!envelope.mask[i]) continue;
                    var materialX = x / materialScale;
                    var materialY = y / materialScale;
                    var cloud = fbm(materialX, materialY, seed);
                    sampleWorley(materialX, materialY, seed ^ 0xb5297a4d, cellular);
                    var cells = 1 - cellular[0];
                    var seam = smooth(clamp(1 - (cellular[1] - cellular[0]) * 7.2, 0, 1));
                    var dormantNode = hashCoord(cellular[2], cellular[3], seed ^ 0x73a4f1c9) > 0.79
                        ? smooth(clamp(1 - cellular[0] / 0.19, 0, 1)) : 0;
                    var body = clamp(sdf[i] / Math.max(3, envelope.radius * 2.4), -0.2, 1);
                    var wrapBand = 0.5 + Math.sin(sdf[i] / materialScale * 0.58
                        + cloud * 6.4 + materialY * 0.021) * 0.5;
                    heightField[i] = clamp(0.22 + cloud * 0.36 + cells * 0.18 + body * 0.16
                        + dormantNode * 0.10 - seam * 0.06 + (wrapBand - 0.5) * 0.06, 0.10, 1);
                    seamField[i] = Math.round(seam * 255);
                    dormantNodeField[i] = Math.round(dormantNode * 255);
                }
            }
            var swarmSeamPixels = 0;
            var dormantNodePixels = 0;
            var metallicFleckPixels = 0;
            for (y = 0; y < height; y += 1) {
                for (x = 0; x < width; x += 1) {
                    i = y * width + x;
                    if (!envelope.mask[i]) continue;
                    var left = heightField[i - (x > 0 ? 1 : 0)];
                    var right = heightField[i + (x + 1 < width ? 1 : 0)];
                    var top = heightField[i - (y > 0 ? width : 0)];
                    var bottom = heightField[i + (y + 1 < height ? width : 0)];
                    var nx = (left - right) * 1.45;
                    var ny = (top - bottom) * 1.45;
                    var nz = 1;
                    var normalLength = Math.hypot(nx, ny, nz) || 1;
                    var light = clamp((nx * -0.46 + ny * -0.62 + nz * 0.64) / normalLength, -1, 1);
                    var seamStrength = seamField[i] / 255;
                    var nodeStrength = dormantNodeField[i] / 255;
                    var edge = x === 0 || y === 0 || x + 1 === width || y + 1 === height
                        || !envelope.mask[i - 1] || !envelope.mask[i + 1]
                        || !envelope.mask[i - width] || !envelope.mask[i + width];
                    var wet = heightField[i] > 0.77 && light > 0.38 ? (heightField[i] - 0.77) * 72 : 0;
                    var ridgeSpecular = Math.pow(Math.max(0, light), 6)
                        * clamp((heightField[i] - 0.54) * 2.4, 0, 1) * 46;
                    var fleckNoise = hashCoord(x >> 1, y, seed ^ 0xc13fa9a9);
                    var metallicFleck = !edge && light > 0.05 && fleckNoise > 0.992
                        ? (fleckNoise - 0.992) / 0.008 : 0;
                    var tone = 24 + heightField[i] * 38 + light * 15 + wet + ridgeSpecular
                        + nodeStrength * Math.max(0, light) * 11 - seamStrength * 12;
                    if (edge) tone -= 18;
                    var red = clamp(tone * 0.82 + metallicFleck * 18, 13, 126);
                    var green = clamp(tone * 0.90 + metallicFleck * 23, 15, 136);
                    var blue = clamp(tone * 0.93 + metallicFleck * 30, 17, 148);
                    var outsideDistance = sdf[i] < 0 ? -sdf[i] : 0;
                    var edgeFilm = clamp(1 - outsideDistance / Math.max(1, envelope.radius + 1), 0, 1);
                    var alpha = coverage.mudInside[i]
                        ? 0.965 + heightField[i] * 0.03
                        : clamp(0.34 + edgeFilm * 0.48 + heightField[i] * 0.08, 0.32, 0.89);
                    blendPixel(output.data, i * 4, red, green, blue, alpha);
                    if (seamStrength > 0.62) swarmSeamPixels += 1;
                    if (nodeStrength > 0.34) dormantNodePixels += 1;
                    if (metallicFleck > 0) metallicFleckPixels += 1;
                }
            }
        } else {
            swarmSeamPixels = 0;
            dormantNodePixels = 0;
            metallicFleckPixels = 0;
        }
        if (options.debug) drawDebugOverlay(output, objectMask, sdf, anchor, coverage);
        var maxInside = 0;
        for (i = 0; i < sdf.length; i += 1) if (sdf[i] > maxInside) maxInside = sdf[i];
        var ended = typeof performance !== "undefined" && performance.now ? performance.now() : Date.now();
        return {
            imageData: output,
            metrics: {
                version: VERSION,
                maskSource: extraction.source,
                segmentationConfidence: extraction.confidence,
                objectPixels: extraction.bounds.count,
                objectBounds: extraction.bounds,
                targetCoverage: round(targetCoverage),
                actualCoverage: round(coverage.actualCoverage),
                coverageDelta: round(coverage.actualCoverage - targetCoverage),
                coveredObjectPixels: coverage.coveredPixels,
                revealedObjectPixels: Math.max(0, coverage.objectPixels - coverage.coveredPixels),
                envelopeRadiusPx: envelope.radius,
                materialProfile: MATERIAL_PROFILE,
                materialMotion: "static-dormant",
                materialScale: round(materialScale, 3),
                nanoCellPitchPx: round(materialScale / NANO_CELL_SCALE, 2),
                swarmSeamPixels: swarmSeamPixels,
                dormantNodePixels: dormantNodePixels,
                metallicFleckPixels: metallicFleckPixels,
                sdfMaxInsidePx: round(maxInside, 2),
                anchor: {
                    x: round(anchor.x, 2),
                    y: round(anchor.y, 2),
                    normalizedX: round(anchor.x / width),
                    normalizedY: round(anchor.y / height),
                    confidence: round(anchor.confidence || 0),
                    method: anchor.method,
                    shapeClass: anchor.shapeClass,
                    elongation: anchor.elongation
                },
                elapsedMs: round(ended - started, 2)
            }
        };
    }

    function makeCanvas(width, height) {
        if (typeof OffscreenCanvas !== "undefined") return new OffscreenCanvas(width, height);
        if (typeof document !== "undefined" && document.createElement) {
            var canvas = document.createElement("canvas");
            canvas.width = width;
            canvas.height = height;
            return canvas;
        }
        throw new Error("Canvas API unavailable");
    }

    function createImageDataOn(context, width, height, data) {
        var imageData = context.createImageData(width, height);
        imageData.data.set(data);
        return imageData;
    }

    function processBitmap(bitmap, targetWidth, targetHeight, options) {
        options = options || {};
        targetWidth = clamp(Math.round(targetWidth), 32, 1024);
        targetHeight = clamp(Math.round(targetHeight), 32, 1280);
        var sourceWidth = Math.max(1, bitmap.width || bitmap.naturalWidth || 1);
        var sourceHeight = Math.max(1, bitmap.height || bitmap.naturalHeight || 1);
        var sourceCanvas = makeCanvas(sourceWidth, sourceHeight);
        var sourceContext = sourceCanvas.getContext("2d", { willReadFrequently: true });
        sourceContext.clearRect(0, 0, sourceWidth, sourceHeight);
        sourceContext.drawImage(bitmap, 0, 0, sourceWidth, sourceHeight);
        var sourceData = sourceContext.getImageData(0, 0, sourceWidth, sourceHeight);
        var plan = planOrientation(sourceData, targetWidth, targetHeight, options);
        // preserveSourceAlpha（揭晓后的干净展示）跳过遮罩量化：遮罩仍驱动几何（bounds/anchor/
        // SDF/污泥），但绘图层保留原始半透边缘，不再二值化出锯齿
        var preserveAlpha = options.preserveSourceAlpha === true;
        if (!preserveAlpha) {
            var maskedData = new Uint8ClampedArray(sourceData.data);
            for (var i = 0; i < plan.sourceAnalysis.mask.length; i += 1) {
                if (!plan.sourceAnalysis.mask[i]) maskedData[i * 4 + 3] = 0;
            }
            sourceContext.clearRect(0, 0, sourceWidth, sourceHeight);
            sourceContext.putImageData(createImageDataOn(sourceContext, sourceWidth, sourceHeight, maskedData), 0, 0);
        }

        var targetCanvas = makeCanvas(targetWidth, targetHeight);
        var targetContext = targetCanvas.getContext("2d", { willReadFrequently: true });
        targetContext.clearRect(0, 0, targetWidth, targetHeight);
        targetContext.save();
        targetContext.translate(targetWidth * 0.5, targetHeight * 0.5);
        targetContext.rotate(plan.degrees * Math.PI / 180);
        targetContext.imageSmoothingEnabled = true;
        targetContext.imageSmoothingQuality = "high";
        targetContext.drawImage(sourceCanvas,
            plan.bounds.x, plan.bounds.y, plan.bounds.width, plan.bounds.height,
            -plan.bounds.width * plan.scale * 0.5, -plan.bounds.height * plan.scale * 0.5,
            plan.bounds.width * plan.scale, plan.bounds.height * plan.scale);
        targetContext.restore();
        var orientedData = targetContext.getImageData(0, 0, targetWidth, targetHeight);
        var sharpeningStrength = options.sharpenSource === true
            ? clamp(Number(options.sharpenStrength) || 0.18, 0, 0.35) : 0;
        if (sharpeningStrength > 0) {
            orientedData = sharpenSourceImageData(orientedData, sharpeningStrength);
        }
        var renderOptions = {};
        var key;
        for (key in options) renderOptions[key] = options[key];
        renderOptions.anchor = {
            x: plan.outputAnchor.x,
            y: plan.outputAnchor.y,
            confidence: plan.anchor.confidence,
            method: "transformed-" + plan.anchor.method,
            shapeClass: plan.anchor.shapeClass,
            elongation: plan.anchor.elongation
        };
        var rendered = renderSurfaceImageData(orientedData, renderOptions);
        targetContext.putImageData(createImageDataOn(targetContext, targetWidth, targetHeight, rendered.imageData.data), 0, 0);
        rendered.metrics.orientationDeg = plan.degrees;
        // 污泥只在正交旋转完成后的目标 Alpha/SDF 上生成；两项角度必须同源，
        // 避免原始图层与旋转后污泥落在不同坐标系。
        rendered.metrics.mudOrientationDeg = plan.degrees;
        rendered.metrics.surfaceSpace = "post-orientation-object-alpha";
        rendered.metrics.orientationFitGain = plan.fitGain;
        rendered.metrics.sourceMask = plan.sourceAnalysis.source;
        rendered.metrics.sourceSegmentationConfidence = plan.sourceAnalysis.confidence;
        rendered.metrics.sourceAnchor = {
            normalizedX: plan.anchor.normalizedX,
            normalizedY: plan.anchor.normalizedY,
            confidence: plan.anchor.confidence,
            method: plan.anchor.method,
            shapeClass: plan.anchor.shapeClass,
            elongation: plan.anchor.elongation
        };
        rendered.metrics.sourceAlpha = preserveAlpha ? "preserved" : "segmented";
        rendered.metrics.sourceSharpening = sharpeningStrength > 0 ? "alpha-safe-unsharp" : "none";
        rendered.metrics.sourceSharpeningStrength = round(sharpeningStrength, 2);
        return { canvas: targetCanvas, metrics: rendered.metrics };
    }

    function createRenderer(options) {
        options = options || {};
        var worker = null;
        var workerFailed = false;
        var pending = {};
        var sequence = 0;
        var blobPromises = {};
        var surfaceCache = {};
        var cacheOrder = [];
        var metricsByKey = {};
        var destroyed = false;
        var cacheLimit = clamp(Number(options.cacheLimit) || 36, 6, 96);

        function safeWorker() {
            if (worker || workerFailed || destroyed || typeof Worker === "undefined" || !options.workerUrl) return worker;
            try {
                worker = new Worker(options.workerUrl);
                worker.onmessage = handleWorkerMessage;
                worker.onerror = function() {
                    workerFailed = true;
                    if (worker) worker.terminate();
                    worker = null;
                    var ids = Object.keys(pending);
                    ids.forEach(function(id) {
                        var request = pending[id];
                        delete pending[id];
                        runMainThread(request);
                    });
                };
            } catch (error) {
                workerFailed = true;
                worker = null;
            }
            return worker;
        }

        function loadBlob(url) {
            if (!blobPromises[url]) {
                blobPromises[url] = fetch(url, { cache: "force-cache" }).then(function(response) {
                    if (!response.ok) throw new Error("surface asset HTTP " + response.status);
                    return response.blob();
                }).catch(function(error) {
                    delete blobPromises[url];
                    throw error;
                });
            }
            return blobPromises[url];
        }

        function decodeBlobAsImage(blob) {
            if (typeof Image === "undefined" || typeof URL === "undefined") {
                return Promise.reject(new Error("image decode API unavailable"));
            }
            return new Promise(function(resolve, reject) {
                var objectUrl = URL.createObjectURL(blob);
                var image = new Image();
                image.onload = function() { URL.revokeObjectURL(objectUrl); resolve(image); };
                image.onerror = function() { URL.revokeObjectURL(objectUrl); reject(new Error("surface image decode failed")); };
                image.src = objectUrl;
            });
        }

        function rasterizeImageToBitmap(image) {
            var width = Math.max(1, image.naturalWidth || image.width || 1);
            var height = Math.max(1, image.naturalHeight || image.height || 1);
            if (typeof OffscreenCanvas === "undefined") {
                return Promise.reject(new Error("image decode API unavailable"));
            }
            var canvas = new OffscreenCanvas(width, height);
            canvas.getContext("2d").drawImage(image, 0, 0);
            return Promise.resolve(canvas.transferToImageBitmap());
        }

        function imageToBitmap(image) {
            if (typeof createImageBitmap === "function") {
                return createImageBitmap(image).catch(function() { return rasterizeImageToBitmap(image); });
            }
            return rasterizeImageToBitmap(image);
        }

        // Chromium/WebView2 的 createImageBitmap 没有 SVG blob 解码器；拒绝时退回
        // HTMLImageElement 解码，再统一转成 ImageBitmap，保证 worker 转移路径可用。
        function blobToDrawable(blob) {
            if (typeof createImageBitmap === "function") {
                return createImageBitmap(blob).catch(function() {
                    return decodeBlobAsImage(blob).then(imageToBitmap);
                });
            }
            return decodeBlobAsImage(blob);
        }

        function canvasSize(canvas, spec) {
            spec = spec || {};
            if (Number.isFinite(Number(spec.renderWidth)) && Number.isFinite(Number(spec.renderHeight))) {
                return {
                    width: clamp(Math.round(Number(spec.renderWidth)), 128, 1024),
                    height: clamp(Math.round(Number(spec.renderHeight)), 180, 1280)
                };
            }
            var rect = canvas.getBoundingClientRect ? canvas.getBoundingClientRect() : { width: 180, height: 300 };
            var ratio = typeof devicePixelRatio === "number" ? clamp(devicePixelRatio, 1, 1.5) : 1;
            var width = clamp(Math.round(Math.max(96, rect.width) * ratio), 128, 384);
            var height = clamp(Math.round(Math.max(144, rect.height) * ratio), 180, 640);
            return { width: width, height: height };
        }

        function makeCacheKey(spec, size) {
            return [VERSION, spec.sourceKey || spec.assetUrl, size.width, size.height, spec.seed, round(spec.coverage || 0),
                spec.mud === false ? 0 : 1, spec.hiddenColorMode || "source", spec.debug ? 1 : 0,
                spec.autoRotate === false ? 0 : 1, round(spec.paddingRatio === undefined ? 0.075 : spec.paddingRatio),
                spec.sharpenSource === true ? 1 : 0,
                round(spec.sharpenStrength === undefined ? 0.18 : spec.sharpenStrength),
                spec.preserveSourceAlpha === true ? 1 : 0].join("|");
        }

        function drawBitmap(canvas, bitmap) {
            canvas.width = bitmap.width;
            canvas.height = bitmap.height;
            var context = canvas.getContext("2d");
            context.clearRect(0, 0, canvas.width, canvas.height);
            context.drawImage(bitmap, 0, 0);
        }

        function rememberSurface(key, bitmap, metrics) {
            if (surfaceCache[key] && surfaceCache[key].bitmap && surfaceCache[key].bitmap !== bitmap
                    && surfaceCache[key].bitmap.close) surfaceCache[key].bitmap.close();
            surfaceCache[key] = { bitmap: bitmap, metrics: metrics };
            cacheOrder = cacheOrder.filter(function(item) { return item !== key; });
            cacheOrder.push(key);
            while (cacheOrder.length > cacheLimit) {
                var evicted = cacheOrder.shift();
                var entry = surfaceCache[evicted];
                if (entry && entry.bitmap && entry.bitmap.close) entry.bitmap.close();
                delete surfaceCache[evicted];
            }
        }

        function finish(request, bitmap, metrics, backend) {
            if (destroyed) {
                if (bitmap && bitmap.close) bitmap.close();
                return;
            }
            metrics.backend = backend;
            metrics.offerId = request.spec.offerId || null;
            metrics.sourceKind = request.spec.sourceKind || "icon";
            metrics.sourceComposition = request.spec.sourceComposition || null;
            metrics.focusFitFieldCount = Number(request.spec.focusFitFieldCount || 0);
            metrics.focusDrawFieldCount = Number(request.spec.focusDrawFieldCount || 0);
            metrics.previewGender = request.spec.previewGender || null;
            rememberSurface(request.cacheKey, bitmap, metrics);
            metricsByKey[request.spec.offerId || request.cacheKey] = JSON.parse(JSON.stringify(metrics));
            drawBitmap(request.canvas, bitmap);
            request.canvas.setAttribute("data-surface-state", "ready");
            if (typeof request.spec.onComplete === "function") request.spec.onComplete(metrics, request.canvas);
            request.resolve(metrics);
        }

        function fail(request, error) {
            request.canvas.setAttribute("data-surface-state", "error");
            if (typeof request.spec.onError === "function") request.spec.onError(error, request.canvas);
            request.reject(error);
        }

        function runMainThread(request) {
            loadBlob(request.spec.assetUrl).then(function(blob) {
                return blobToDrawable(blob);
            }).then(function(bitmap) {
                var result = processBitmap(bitmap, request.size.width, request.size.height, request.spec);
                if (bitmap.close) bitmap.close();
                var outputBitmap = result.canvas.transferToImageBitmap
                    ? result.canvas.transferToImageBitmap() : null;
                if (outputBitmap) {
                    finish(request, outputBitmap, result.metrics, "main-thread-fallback");
                    return;
                }
                request.canvas.width = result.canvas.width;
                request.canvas.height = result.canvas.height;
                request.canvas.getContext("2d").drawImage(result.canvas, 0, 0);
                result.metrics.backend = "main-thread-fallback";
                result.metrics.offerId = request.spec.offerId || null;
                result.metrics.sourceKind = request.spec.sourceKind || "icon";
                result.metrics.sourceComposition = request.spec.sourceComposition || null;
                result.metrics.focusFitFieldCount = Number(request.spec.focusFitFieldCount || 0);
                result.metrics.focusDrawFieldCount = Number(request.spec.focusDrawFieldCount || 0);
                result.metrics.previewGender = request.spec.previewGender || null;
                metricsByKey[request.spec.offerId || request.cacheKey] = JSON.parse(JSON.stringify(result.metrics));
                request.canvas.setAttribute("data-surface-state", "ready");
                if (typeof request.spec.onComplete === "function") request.spec.onComplete(result.metrics, request.canvas);
                request.resolve(result.metrics);
            }).catch(function(error) { fail(request, error); });
        }

        function handleWorkerMessage(event) {
            var message = event.data || {};
            var request = pending[message.id];
            if (!request) {
                if (message.bitmap && message.bitmap.close) message.bitmap.close();
                return;
            }
            delete pending[message.id];
            if (message.error) {
                runMainThread(request);
                return;
            }
            finish(request, message.bitmap, message.metrics, "offscreen-worker");
        }

        function render(canvas, spec) {
            if (destroyed) return Promise.reject(new Error("surface renderer destroyed"));
            spec = spec || {};
            if (!canvas || !spec.assetUrl) return Promise.reject(new Error("surface canvas/asset missing"));
            var size = canvasSize(canvas, spec);
            var cacheKey = makeCacheKey(spec, size);
            canvas.setAttribute("data-surface-state", "loading");
            if (surfaceCache[cacheKey]) {
                drawBitmap(canvas, surfaceCache[cacheKey].bitmap);
                canvas.setAttribute("data-surface-state", "ready");
                var cachedMetrics = JSON.parse(JSON.stringify(surfaceCache[cacheKey].metrics));
                metricsByKey[spec.offerId || cacheKey] = cachedMetrics;
                if (typeof spec.onComplete === "function") {
                    Promise.resolve().then(function() { spec.onComplete(cachedMetrics, canvas); });
                }
                return Promise.resolve(cachedMetrics);
            }
            return new Promise(function(resolve, reject) {
                var request = {
                    id: ++sequence,
                    canvas: canvas,
                    spec: spec,
                    size: size,
                    cacheKey: cacheKey,
                    resolve: resolve,
                    reject: reject
                };
                var activeWorker = safeWorker();
                if (!activeWorker || typeof createImageBitmap === "undefined") {
                    runMainThread(request);
                    return;
                }
                loadBlob(spec.assetUrl).then(function(blob) { return blobToDrawable(blob); }).then(function(bitmap) {
                    if (destroyed) { if (bitmap.close) bitmap.close(); return; }
                    pending[request.id] = request;
                    activeWorker.postMessage({
                        id: request.id,
                        bitmap: bitmap,
                        width: size.width,
                        height: size.height,
                        options: {
                            seed: spec.seed,
                            coverage: spec.coverage,
                            mud: spec.mud,
                            hiddenColorMode: spec.hiddenColorMode,
                            debug: spec.debug,
                            autoRotate: spec.autoRotate,
                            paddingRatio: spec.paddingRatio,
                            sharpenSource: spec.sharpenSource,
                            sharpenStrength: spec.sharpenStrength
                        }
                    }, [bitmap]);
                }).catch(function(error) { fail(request, error); });
            });
        }

        function destroy() {
            destroyed = true;
            if (worker) worker.terminate();
            worker = null;
            Object.keys(surfaceCache).forEach(function(key) {
                var bitmap = surfaceCache[key].bitmap;
                if (bitmap && bitmap.close) bitmap.close();
            });
            surfaceCache = {};
            cacheOrder = [];
            pending = {};
            metricsByKey = {};
        }

        return {
            render: render,
            metrics: function() { return JSON.parse(JSON.stringify(metricsByKey)); },
            clearMetrics: function() { metricsByKey = {}; },
            destroy: destroy,
            version: VERSION
        };
    }

    return {
        VERSION: VERSION,
        MATERIAL_PROFILE: MATERIAL_PROFILE,
        hash32: hash32,
        extractObjectMask: extractObjectMask,
        sharpenSourceImageData: sharpenSourceImageData,
        signedDistance: signedDistance,
        findAutomaticAnchor: findAutomaticAnchor,
        planOrientation: planOrientation,
        buildCoverageMasks: buildCoverageMasks,
        renderSurfaceImageData: renderSurfaceImageData,
        processBitmap: processBitmap,
        createRenderer: createRenderer,
        _internals: {
            closeMask: closeMask,
            fillSmallHoles: fillSmallHoles,
            thinMask: thinMask,
            downsampleMask: downsampleMask,
            nthValue: nthValue
        }
    };
});
