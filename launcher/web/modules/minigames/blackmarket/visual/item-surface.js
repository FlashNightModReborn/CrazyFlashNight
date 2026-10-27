(function(root, factory) {
    if (typeof module === "object" && module.exports) {
        module.exports = factory();
    } else {
        root.BlackMarketItemSurface = factory();
    }
})(typeof globalThis !== "undefined" ? globalThis : this, function() {
    "use strict";

    var VERSION = "object-sdf-nanobot-sludge.v3";
    var MATERIAL_PROFILE = "dormant-military-nanobots.v1";
    var NANO_CELL_SCALE = 0.068;
    var DEFAULT_ALPHA_THRESHOLD = 12;
    var INF = 1e15;
    // Six visible offers plus a small amount of navigation overlap. Entries verify the
    // complete mask after hashing; a hash collision must never reuse another shape.
    var revealFieldCache = [];
    var REVEAL_FIELD_CACHE_LIMIT = 8;

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
        var sample = sampleEdgeColor(imageData);
        var threshold = 18;
        var background = new Uint8Array(alpha.mask.length);
        var queue = new Int32Array(alpha.mask.length);
        var head = 0;
        var tail = 0;
        function visit(index) {
            if (background[index] || (alpha.mask[index]
                    && colorDistance(imageData.data, index * 4, sample.color) > threshold)) return;
            background[index] = 1;
            queue[tail++] = index;
        }
        for (var x = 0; x < width; x += 1) { visit(x); visit((height - 1) * width + x); }
        for (var y = 1; y + 1 < height; y += 1) { visit(y * width); visit(y * width + width - 1); }
        while (head < tail) {
            var current = queue[head++];
            x = current % width;
            y = Math.floor(current / width);
            if (x) visit(current - 1);
            if (x + 1 < width) visit(current + 1);
            if (y) visit(current - width);
            if (y + 1 < height) visit(current + width);
        }
        var candidate = new Uint8Array(alpha.mask.length);
        for (var i = 0; i < candidate.length; i += 1) candidate[i] = alpha.mask[i] && !background[i] ? 1 : 0;
        return { mask: candidate, bounds: maskBounds(candidate, width, height), edgeColor: sample.color, threshold: threshold };
    }

    function extractObjectMask(imageData, options) {
        options = options || {};
        var threshold = options.alphaThreshold === undefined ? DEFAULT_ALPHA_THRESHOLD : options.alphaThreshold;
        var alpha = alphaMask(imageData, threshold);
        var total = imageData.width * imageData.height;
        var width = imageData.width;
        var height = imageData.height;
        var data = imageData.data;
        if (!alpha.count) {
            return {
                mask: alpha.mask,
                bounds: maskBounds(alpha.mask, width, height),
                source: "empty-alpha",
                confidence: 0,
                quality: { status: "empty", warnings: ["empty-source"] }
            };
        }
        var transparent = 0;
        var core = new Uint8Array(total);
        var coreCount = 0;
        for (var index = 0; index < total; index += 1) {
            if (data[index * 4 + 3] < threshold) transparent += 1;
            if (data[index * 4 + 3] >= 240) { core[index] = 1; coreCount += 1; }
        }
        // Occupied area is not evidence of an opaque background. Inventory
        // shadows can cover almost the whole tile while its body has valid alpha.
        if (transparent > 0 || options.preparedAlpha === true) {
            var direct = alpha.mask;
            var shadowRemoved = 0;
            var maskMode = options.sourceMaskMode || options.hiddenColorMode;
            var proxy = maskMode === "proxy" || maskMode === "monochrome";
            if (proxy && !options.preparedAlpha && coreCount >= Math.max(4, alpha.count * 0.08)
                    && alpha.count - coreCount > total * 0.015) {
                var coreDistance = distanceToFeature(core, width, height);
                direct = new Uint8Array(total);
                for (index = 0; index < total; index += 1) {
                    // Keep the opaque body and its local antialiasing fringe;
                    // never join, fill or discard disconnected real parts.
                    direct[index] = core[index] || (data[index * 4 + 3] >= 96 && coreDistance[index] <= 2.25) ? 1 : 0;
                    if (alpha.mask[index] && !direct[index]) shadowRemoved += 1;
                }
            }
            var bounds = maskBounds(direct, width, height);
            var cropped = maskMode === "proxy" || bounds.x <= 1 || bounds.y <= 1
                || bounds.x + bounds.width >= width - 1 || bounds.y + bounds.height >= height - 1;
            return {
                mask: direct,
                bounds: bounds,
                source: shadowRemoved ? "alpha-core-with-fringe" : "alpha",
                confidence: cropped ? 0.72 : 0.98,
                quality: { status: cropped ? "usable-crop" : "usable-alpha", cropped: cropped,
                    shadowPixelsRemoved: shadowRemoved, warnings: cropped ? ["source-touches-frame"] : [] }
            };
        }
        // Color segmentation is reserved for genuinely opaque, uniform borders.
        // An uncertain crop is retained as a crop; it is never scored as a good
        // silhouette merely because a few contrasting internal pixels survived.
        var edge = sampleEdgeColor(imageData);
        var agrees = 0;
        var samples = 0;
        for (index = 0; index < total; index += 1) {
            var x = index % width;
            var y = Math.floor(index / width);
            if (x && y && x !== width - 1 && y !== height - 1) continue;
            samples += 1;
            if (colorDistance(data, index * 4, edge.color) <= 18) agrees += 1;
        }
        if (agrees / samples < 0.85 || edge.spread > 8) {
            return { mask: alpha.mask, bounds: maskBounds(alpha.mask, width, height),
                source: "ambiguous-opaque", confidence: 0.12,
                quality: { status: "ambiguous", cropped: true, warnings: ["nonuniform-opaque-border"] } };
        }
        var segmented = segmentOpaqueBackground(imageData, alpha);
        if (segmented.bounds.count < Math.max(12, Math.round(total * 0.006))) {
            return {
                mask: alpha.mask,
                bounds: maskBounds(alpha.mask, width, height),
                source: "ambiguous-opaque",
                confidence: 0.12,
                quality: { status: "ambiguous", cropped: true, warnings: ["foreground-not-separable"] },
                backgroundColor: segmented.edgeColor,
                backgroundThreshold: round(segmented.threshold, 2)
            };
        }
        return {
            mask: segmented.mask,
            bounds: segmented.bounds,
            source: "edge-segmented-alpha",
            confidence: 0.68,
            quality: { status: "estimated-opaque", warnings: ["color-segmentation-estimate"] },
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

    function geodesicArrival(mask, width, height, bounds, anchor, seed) {
        // Work on the actual foreground graph. A coarse occupancy grid loses thin
        // connections and leaves source pixels pointing into background cells.
        var arrival = new Float64Array(mask.length);
        arrival.fill(INF);
        var labels = new Int32Array(mask.length);
        var queue = new Int32Array(bounds.count);
        var components = [];
        var directions = [
            [-1, 0, 1], [1, 0, 1], [0, -1, 1], [0, 1, 1],
            [-1, -1, Math.SQRT2], [1, -1, Math.SQRT2], [-1, 1, Math.SQRT2], [1, 1, Math.SQRT2]
        ];
        var i;
        for (i = 0; i < mask.length; i += 1) {
            if (!mask[i] || labels[i]) continue;
            var label = components.length + 1;
            var head = 0;
            var tail = 1;
            var nearest = i;
            var nearestDistance = INF;
            queue[0] = i;
            labels[i] = label;
            while (head < tail) {
                var node = queue[head++];
                var x = node % width;
                var y = Math.floor(node / width);
                var dx = x + 0.5 - anchor.x;
                var dy = y + 0.5 - anchor.y;
                var distance = dx * dx + dy * dy;
                if (distance < nearestDistance || (distance === nearestDistance && node < nearest)) {
                    nearest = node;
                    nearestDistance = distance;
                }
                for (var d = 0; d < directions.length; d += 1) {
                    var nx = x + directions[d][0];
                    var ny = y + directions[d][1];
                    if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
                    var next = ny * width + nx;
                    if (!mask[next] || labels[next]) continue;
                    labels[next] = label;
                    queue[tail++] = next;
                }
            }
            components.push({ root: nearest, distance: nearestDistance, area: tail });
        }
        components.sort(function(a, b) { return a.distance - b.distance || a.root - b.root; });
        var background = new Uint8Array(mask.length);
        for (i = 0; i < background.length; i += 1) background[i] = mask[i] ? 0 : 1;
        var widthSquared = distanceToFeature(background, width, height);
        var maxWidth = 1;
        for (i = 0; i < widthSquared.length; i += 1) {
            if (mask[i] && widthSquared[i] > maxWidth) maxWidth = widthSquared[i];
        }
        maxWidth = Math.sqrt(maxWidth);
        var cost = new Float32Array(mask.length);
        var textureScale = 128 / Math.max(1, bounds.width, bounds.height) * 0.19;
        for (i = 0; i < mask.length; i += 1) {
            if (!mask[i]) continue;
            var widthBias = 1 - clamp(Math.sqrt(widthSquared[i]) / maxWidth, 0, 1);
            var texture = valueNoise((i % width) * textureScale, Math.floor(i / width) * textureScale, seed ^ 0x6d2b79f5);
            cost[i] = 0.76 + widthBias * 0.18 + texture * 0.34;
        }
        var heap = new MinHeap(Math.max(16, Math.floor(Math.sqrt(bounds.count) * 4)));
        var maximum = -1;
        var visited = 0;
        for (var c = 0; c < components.length; c += 1) {
            // A disconnected real part gets a new continuous front only after the
            // previous part is complete. No INF values or random reveal speckles.
            var start = components[c].root;
            arrival[start] = maximum + 1;
            heap.push(start, arrival[start]);
            while (heap.length) {
                var current = heap.pop();
                if (current.value !== arrival[current.node]) continue;
                visited += 1;
                maximum = Math.max(maximum, current.value);
                var cx = current.node % width;
                var cy = Math.floor(current.node / width);
                for (d = 0; d < directions.length; d += 1) {
                    nx = cx + directions[d][0];
                    ny = cy + directions[d][1];
                    if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
                    next = ny * width + nx;
                    if (!mask[next]) continue;
                    var nextValue = current.value + directions[d][2] * cost[next];
                    if (nextValue < arrival[next]) {
                        arrival[next] = nextValue;
                        heap.push(next, nextValue);
                    }
                }
            }
        }
        if (visited !== bounds.count) throw new Error("surface reveal graph is incomplete");
        return { arrival: arrival, componentCount: components.length, reachablePixels: visited };
    }

    function revealFieldFor(mask, width, height, bounds, anchor, seedText) {
        var hash = 2166136261 >>> 0;
        var i;
        for (i = 0; i < mask.length; i += 1) hash = Math.imul(hash ^ mask[i], 16777619) >>> 0;
        var key = [width, height, hash, anchor.x, anchor.y, seedText].join("|");
        for (var c = 0; c < revealFieldCache.length; c += 1) {
            var entry = revealFieldCache[c];
            if (entry.key !== key || entry.mask.length !== mask.length) continue;
            for (i = 0; i < mask.length && entry.mask[i] === mask[i]; i += 1) { /* exact identity */ }
            if (i !== mask.length) continue;
            revealFieldCache.splice(c, 1);
            revealFieldCache.push(entry);
            return entry.field;
        }
        var field = geodesicArrival(mask, width, height, bounds, anchor, hash32(seedText));
        revealFieldCache.push({ key: key, mask: new Uint8Array(mask), field: field });
        if (revealFieldCache.length > REVEAL_FIELD_CACHE_LIMIT) revealFieldCache.shift();
        return field;
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
        if (!Number.isFinite(targetCoverage)) throw new Error("surface coverage must be finite");
        seedText = seedText || "blackmarket-surface";
        var seed = hash32(seedText);
        var objectPixels = bounds.count;
        var targetCovered = clamp(Math.round(objectPixels * targetCoverage), 0, objectPixels);
        var revealCount = objectPixels - targetCovered;
        var reveal = new Uint8Array(objectMask.length);
        var mudInside = new Uint8Array(objectMask.length);
        if (!objectPixels) {
            return { reveal: reveal, mudInside: mudInside, objectPixels: 0, coveredPixels: 0,
                actualCoverage: 0, targetCoverage: targetCoverage, componentCount: 0, reachablePixels: 0 };
        }
        if (revealCount <= 0) {
            mudInside.set(objectMask);
            return { reveal: reveal, mudInside: mudInside, objectPixels: objectPixels, coveredPixels: objectPixels,
                actualCoverage: 1, targetCoverage: targetCoverage, reachablePixels: objectPixels };
        }
        if (revealCount >= objectPixels) {
            reveal.set(objectMask);
            return { reveal: reveal, mudInside: mudInside, objectPixels: objectPixels, coveredPixels: 0,
                actualCoverage: 0, targetCoverage: targetCoverage, reachablePixels: objectPixels };
        }

        var field = revealFieldFor(objectMask, width, height, bounds, anchor, seedText);
        var arrival = field.arrival;
        var scores = new Float64Array(objectPixels);
        var scoreByPixel = new Float64Array(objectMask.length);
        scoreByPixel.fill(INF);
        var position = 0;
        for (var y = 0; y < height; y += 1) {
            for (var x = 0; x < width; x += 1) {
                var index = y * width + x;
                if (!objectMask[index]) continue;
                var base = arrival[index];
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
            componentCount: field.componentCount,
            reachablePixels: field.reachablePixels,
            revealMethod: "full-resolution-component-geodesic"
        };
    }

    function addAttachedEnvelope(coverage, objectMask, width, height, seedText) {
        var radius = clamp(Math.round(Math.min(width, height) * (0.008 + coverage.targetCoverage * 0.008)), 2, 7);
        // Interior coverage is authoritative. Material skirts can only add pixels
        // outside the object, never erase budgeted mud or cover a revealed pixel.
        var finalMud = new Uint8Array(coverage.mudInside);
        if (!coverage.coveredPixels) return { mask: finalMud, radius: radius };
        var toMud = distanceToFeature(coverage.mudInside, width, height);
        var toReveal = distanceToFeature(coverage.reveal, width, height);
        var protectionSquared = Math.pow(Math.max(1, radius - 1), 2);
        var protectedReveal = new Uint8Array(objectMask.length);
        var i;
        for (i = 0; i < finalMud.length; i += 1) {
            protectedReveal[i] = toReveal[i] <= protectionSquared ? 1 : 0;
            if (!objectMask[i] && toMud[i] <= radius * radius && !protectedReveal[i]) finalMud[i] = 1;
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
                    var center = yy * width + x;
                    if (protectedReveal[center] || (objectMask[center] && !coverage.mudInside[center])) break;
                    var taper = Math.max(0, Math.round(dripWidth * (1 - dy / (length + 2))));
                    for (var dx = -taper; dx <= taper; dx += 1) {
                        var xx = x + dx;
                        if (xx < 0 || xx >= width) continue;
                        var index = yy * width + xx;
                        if (!objectMask[index] && !protectedReveal[index]) finalMud[index] = 1;
                    }
                }
            }
        }
        // Remove exterior fragments disconnected by the protected reveal margin.
        var attached = new Uint8Array(finalMud.length);
        var queue = new Int32Array(finalMud.length);
        var head = 0;
        var tail = 0;
        for (i = 0; i < finalMud.length; i += 1) {
            if (coverage.mudInside[i]) { attached[i] = 1; queue[tail++] = i; }
        }
        while (head < tail) {
            var current = queue[head++];
            var cx = current % width;
            var cy = Math.floor(current / width);
            for (var oy = -1; oy <= 1; oy += 1) {
                for (var ox = -1; ox <= 1; ox += 1) {
                    var nx = cx + ox;
                    var ny = cy + oy;
                    if ((!ox && !oy) || nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
                    var next = ny * width + nx;
                    if (finalMud[next] && !attached[next]) { attached[next] = 1; queue[tail++] = next; }
                }
            }
        }
        return { mask: attached, radius: radius };
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
            var offset = i * 4;
            // Alpha fringes and translucent glow may lie outside the coverage
            // mask. They remain visible and must obey the same hidden color
            // policy; recoloring them must not change the geometric budget.
            if (!data[offset + 3]) continue;
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
        var envelope = mudEnabled ? addAttachedEnvelope(coverage, objectMask, width, height, options.seed || "surface")
            : { mask: new Uint8Array(objectMask.length), radius: 0 };
        var finalCoveredPixels = 0;
        for (var coveredIndex = 0; coveredIndex < objectMask.length; coveredIndex += 1) {
            if (objectMask[coveredIndex] && envelope.mask[coveredIndex]) finalCoveredPixels += 1;
        }
        var finalCoverage = coverage.objectPixels ? finalCoveredPixels / coverage.objectPixels : 0;
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
            diagnostics: options.diagnostics === true ? {
                objectMask: objectMask,
                revealMask: coverage.reveal,
                mudMask: envelope.mask,
                budgetMask: coverage.mudInside
            } : undefined,
            metrics: {
                version: VERSION,
                maskSource: extraction.source,
                segmentationConfidence: extraction.confidence,
                objectPixels: extraction.bounds.count,
                objectBounds: extraction.bounds,
                targetCoverage: round(targetCoverage),
                actualCoverage: round(finalCoverage, 7),
                coverageDelta: round(finalCoverage - targetCoverage, 7),
                budgetCoverage: round(coverage.actualCoverage, 7),
                coveredObjectPixels: finalCoveredPixels,
                revealedObjectPixels: Math.max(0, coverage.objectPixels - finalCoveredPixels),
                coverageMetric: "final-mud-object-intersection",
                coverageInvariant: finalCoveredPixels === coverage.coveredPixels,
                revealMethod: coverage.revealMethod || "all-or-none",
                componentCount: coverage.componentCount || 0,
                unreachableObjectPixels: mudEnabled ? coverage.objectPixels - coverage.reachablePixels : 0,
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
        if (!plan.sourceAnalysis.bounds.count) {
            var emptyError = new Error("surface source contains no visible pixels");
            emptyError.code = "empty-source";
            throw emptyError;
        }
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
        renderOptions.preparedAlpha = true;
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
        rendered.metrics.sourceQuality = plan.sourceAnalysis.quality;
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
        return { canvas: targetCanvas, metrics: rendered.metrics, diagnostics: rendered.diagnostics };
    }

    function createRenderer(options) {
        options = options || {};
        var worker = null;
        var workerFailed = false;
        var pending = {};
        var inFlight = {};
        var canvasRequests = new WeakMap();
        var mainQueue = [];
        var mainTimer = null;
        var sequence = 0;
        var blobPromises = {};
        var surfaceCache = {};
        var cacheOrder = [];
        var metricsByKey = {};
        var destroyed = false;
        var cacheLimit = clamp(Number(options.cacheLimit) || 36, 6, 96);
        var timeoutMs = clamp(Number(options.timeoutMs) || 30000, 25, 60000);

        function abortError(message) {
            var error = new Error(message);
            error.name = "AbortError";
            return error;
        }

        function retire(request) {
            request.settled = true;
            if (request.timer) clearTimeout(request.timer);
            if (request.bitmap && request.bitmap.close) request.bitmap.close();
            request.bitmap = null;
            if (request.originalResult && request.originalResult.bitmap.close) request.originalResult.bitmap.close();
            request.originalResult = null;
            delete pending[request.id];
            if (inFlight[request.cacheKey] === request) delete inFlight[request.cacheKey];
        }

        function armTimeout(request) {
            if (request.timer) clearTimeout(request.timer);
            request.timer = setTimeout(function() {
                if (request.settled) return;
                if (request.state === "worker" && !workerFailed) workerFailure();
                else fail(request, new Error("surface render timed out"));
            }, timeoutMs);
        }

        function workerFailure() {
            if (destroyed) return;
            workerFailed = true;
            if (worker) worker.terminate();
            worker = null;
            Object.keys(pending).forEach(function(id) {
                var request = pending[id];
                // Decode jobs are already registered. They choose the *current*
                // backend when decode completes, never a captured dead Worker.
                if (request && !request.settled && request.state === "worker") {
                    armTimeout(request);
                    runMainThread(request);
                }
            });
        }

        function safeWorker() {
            if (worker || workerFailed || destroyed || typeof Worker === "undefined" || !options.workerUrl) return worker;
            try {
                worker = new Worker(options.workerUrl);
                worker.onmessage = handleWorkerMessage;
                worker.onerror = workerFailure;
                worker.onmessageerror = workerFailure;
            } catch (error) {
                workerFailed = true;
                worker = null;
            }
            return worker;
        }

        function loadBlob(url) {
            if (!blobPromises[url]) {
                blobPromises[url] = new Promise(function(resolve, reject) {
                    var controller = typeof AbortController !== "undefined" ? new AbortController() : null;
                    var timer = setTimeout(function() {
                        if (controller) controller.abort();
                        reject(new Error("surface asset timed out"));
                    }, timeoutMs);
                    var init = { cache: "force-cache" };
                    if (controller) init.signal = controller.signal;
                    Promise.resolve().then(function() { return fetch(url, init); }).then(function(response) {
                        if (!response.ok) throw new Error("surface asset HTTP " + response.status);
                        return response.blob();
                    }).then(function(blob) { clearTimeout(timer); resolve(blob); }, function(error) {
                        clearTimeout(timer);
                        reject(error);
                    });
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
                spec.preserveSourceAlpha === true ? 1 : 0, spec.assetUrl,
                spec.fallbackAssetUrl || "", spec.fallbackHiddenColorMode || "monochrome", spec.sourceMaskMode || "",
                spec.fallbackSourceMaskMode || "monochrome"].join("|");
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

        function deliver(waiter, bitmap, sourceMetrics, cacheKey) {
            if (waiter.settled) return;
            if (destroyed || canvasRequests.get(waiter.canvas) !== waiter) {
                rejectWaiter(waiter, abortError("surface render superseded"));
                return;
            }
            var metrics = JSON.parse(JSON.stringify(sourceMetrics));
            metrics.offerId = waiter.spec.offerId || null;
            metrics.sourceKind = waiter.spec.sourceKind || "icon";
            metrics.sourceComposition = waiter.spec.sourceComposition || null;
            metrics.focusFitFieldCount = Number(waiter.spec.focusFitFieldCount || 0);
            metrics.focusDrawFieldCount = Number(waiter.spec.focusDrawFieldCount || 0);
            metrics.previewGender = waiter.spec.previewGender || null;
            try {
                drawBitmap(waiter.canvas, bitmap);
                waiter.canvas.setAttribute("data-surface-state", "ready");
                metricsByKey[waiter.spec.offerId || cacheKey] = JSON.parse(JSON.stringify(metrics));
                waiter.settled = true;
                canvasRequests.delete(waiter.canvas);
                waiter.resolve(metrics);
                if (typeof waiter.spec.onComplete === "function") {
                    try { waiter.spec.onComplete(metrics, waiter.canvas); } catch (ignored) { /* result is already delivered */ }
                }
            } catch (error) {
                rejectWaiter(waiter, error);
            }
        }

        function rejectWaiter(waiter, error) {
            if (waiter.settled) return;
            waiter.settled = true;
            if (canvasRequests.get(waiter.canvas) === waiter) {
                canvasRequests.delete(waiter.canvas);
                if (error.name !== "AbortError") {
                    waiter.canvas.setAttribute("data-surface-state", "error");
                    if (typeof waiter.spec.onError === "function") {
                        try { waiter.spec.onError(error, waiter.canvas); } catch (ignored) { /* settle original error */ }
                    }
                }
            }
            waiter.reject(error);
        }

        function finish(request, bitmap, metrics, backend) {
            if (request.settled || destroyed) {
                if (bitmap && bitmap.close) bitmap.close();
                return;
            }
            if (!bitmap || !bitmap.width || !bitmap.height || !metrics) {
                if (bitmap && bitmap.close) bitmap.close();
                fail(request, new Error("surface worker returned an invalid result"));
                return;
            }
            if (!request.sourceFallback && request.spec.fallbackAssetUrl && metrics.sourceQuality
                    && metrics.sourceQuality.status === "ambiguous") {
                // Keep the already rendered original until its same-item
                // alternative proves usable. No guess can erase the last image.
                request.originalResult = { bitmap: bitmap, metrics: metrics, backend: backend };
                useFallback(request, "ambiguous-primary-to-same-item-transparent-frame");
                return;
            }
            if (request.originalResult && metrics.sourceMask !== "alpha" && metrics.sourceMask !== "alpha-core-with-fringe") {
                if (bitmap.close) bitmap.close();
                restoreOriginal(request);
                return;
            }
            retire(request);
            metrics.backend = backend;
            metrics.sourceFallback = request.sourceFallback || null;
            rememberSurface(request.cacheKey, bitmap, metrics);
            request.waiters.forEach(function(waiter) { deliver(waiter, bitmap, metrics, request.cacheKey); });
        }

        function fail(request, error) {
            if (!request || request.settled) return;
            if (!destroyed && error.name !== "AbortError" && request.originalResult) {
                restoreOriginal(request);
                return;
            }
            retire(request);
            request.waiters.forEach(function(waiter) { rejectWaiter(waiter, error); });
        }

        function pumpMainQueue() {
            mainTimer = null;
            if (destroyed) return;
            var request;
            while (mainQueue.length) {
                request = mainQueue.shift();
                if (!request.settled) break;
                request = null;
            }
            if (!request) return;
            var bitmap = request.bitmap;
            request.bitmap = null;
            request.state = "main-running";
            try {
                var result = processBitmap(bitmap, request.size.width, request.size.height, request.spec);
                var output = result.canvas.transferToImageBitmap ? result.canvas.transferToImageBitmap() : result.canvas;
                finish(request, output, result.metrics, "main-thread-fallback");
            } catch (error) {
                if (!recoverEmptySource(request, error.code)) fail(request, error);
            } finally {
                if (bitmap && bitmap.close) bitmap.close();
                // A macrotask boundary between items lets input and paint run.
                if (mainQueue.length && !destroyed) mainTimer = setTimeout(pumpMainQueue, 0);
            }
        }

        function queueMain(request, bitmap) {
            if (destroyed || request.settled) { if (bitmap.close) bitmap.close(); return; }
            request.bitmap = bitmap;
            request.state = "main-queued";
            mainQueue.push(request);
            if (mainTimer === null) mainTimer = setTimeout(pumpMainQueue, 0);
        }

        function runMainThread(request) {
            if (request.settled || destroyed) return;
            request.state = "decoding-main";
            loadBlob(request.spec.assetUrl).then(blobToDrawable).then(function(bitmap) {
                queueMain(request, bitmap);
            }).catch(function(error) { fail(request, error); });
        }

        function recoverEmptySource(request, code) {
            return code === "empty-source" && useFallback(request, "empty-primary-to-same-item-inventory-frame");
        }

        function restoreOriginal(request) {
            var original = request.originalResult;
            request.originalResult = null;
            request.sourceFallback = "ambiguous-alternate-unusable-primary-retained";
            finish(request, original.bitmap, original.metrics, original.backend);
        }

        function useFallback(request, reason) {
            if (request.sourceFallback || !request.spec.fallbackAssetUrl) return false;
            request.sourceFallback = reason;
            request.spec = Object.assign({}, request.spec, {
                assetUrl: request.spec.fallbackAssetUrl,
                // An uncoated withdrawn/sealed offer is still hidden. Restore source color
                // only when the caller explicitly requests a clean source view.
                hiddenColorMode: request.spec.mud === false && (request.spec.hiddenColorMode || "source") === "source"
                    ? "source" : (request.spec.fallbackHiddenColorMode || "monochrome"),
                sourceMaskMode: request.spec.fallbackSourceMaskMode || "monochrome"
            });
            armTimeout(request);
            start(request);
            return true;
        }

        function workerOptions(spec) {
            return {
                seed: spec.seed, coverage: spec.coverage, mud: spec.mud,
                hiddenColorMode: spec.hiddenColorMode, debug: spec.debug,
                sourceMaskMode: spec.sourceMaskMode,
                autoRotate: spec.autoRotate, paddingRatio: spec.paddingRatio,
                sharpenSource: spec.sharpenSource, sharpenStrength: spec.sharpenStrength,
                preserveSourceAlpha: spec.preserveSourceAlpha
            };
        }

        function start(request) {
            request.state = "decoding";
            safeWorker();
            loadBlob(request.spec.assetUrl).then(blobToDrawable).then(function(bitmap) {
                if (destroyed || request.settled) { if (bitmap.close) bitmap.close(); return; }
                var activeWorker = safeWorker();
                if (!activeWorker || typeof createImageBitmap === "undefined") { queueMain(request, bitmap); return; }
                request.state = "worker";
                try {
                    activeWorker.postMessage({ id: request.id, bitmap: bitmap,
                        width: request.size.width, height: request.size.height,
                        options: workerOptions(request.spec) }, [bitmap]);
                } catch (error) {
                    if (bitmap.close) bitmap.close();
                    workerFailure();
                }
            }).catch(function(error) { fail(request, error); });
        }

        function handleWorkerMessage(event) {
            var message = event.data || {};
            var request = pending[message.id];
            if (!request || request.settled || request.state !== "worker") {
                if (message.bitmap && message.bitmap.close) message.bitmap.close();
                return;
            }
            if (message.error) {
                if (message.bitmap && message.bitmap.close) message.bitmap.close();
                if (recoverEmptySource(request, message.code)) return;
                armTimeout(request);
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
            var previous = canvasRequests.get(canvas);
            if (previous && !previous.settled) {
                rejectWaiter(previous, abortError("surface render superseded"));
                var priorJob = previous.request;
                if (priorJob && !priorJob.settled && !priorJob.waiters.some(function(w) { return !w.settled; })) retire(priorJob);
            }
            canvas.setAttribute("data-surface-state", "loading");
            return new Promise(function(resolve, reject) {
                var waiter = { canvas: canvas, spec: spec, resolve: resolve, reject: reject, settled: false };
                canvasRequests.set(canvas, waiter);
                if (surfaceCache[cacheKey]) {
                    var cached = surfaceCache[cacheKey];
                    deliver(waiter, cached.bitmap, cached.metrics, cacheKey);
                    return;
                }
                var request = inFlight[cacheKey];
                if (request) {
                    request.waiters.push(waiter);
                    waiter.request = request;
                    return;
                }
                request = { id: ++sequence, spec: spec, size: size, cacheKey: cacheKey,
                    waiters: [waiter], state: "created", settled: false, timer: null, bitmap: null };
                waiter.request = request;
                // Registration precedes both Worker startup and asynchronous decode.
                inFlight[cacheKey] = request;
                pending[request.id] = request;
                armTimeout(request);
                start(request);
            });
        }

        function destroy() {
            if (destroyed) return;
            destroyed = true;
            if (worker) worker.terminate();
            worker = null;
            if (mainTimer !== null) clearTimeout(mainTimer);
            mainTimer = null;
            Object.keys(pending).forEach(function(id) { fail(pending[id], abortError("surface renderer destroyed")); });
            Object.keys(surfaceCache).forEach(function(key) {
                var bitmap = surfaceCache[key].bitmap;
                if (bitmap && bitmap.close) bitmap.close();
            });
            mainQueue = [];
            inFlight = {};
            surfaceCache = {};
            cacheOrder = [];
            pending = {};
            blobPromises = {};
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
