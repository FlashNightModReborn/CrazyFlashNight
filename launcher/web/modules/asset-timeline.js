/**
 * Shared runtime helpers for baked Flash timeline assets.
 *
 * Both item icons and dressup skins use the same export contract:
 * - frames[] is the logical frame list.
 * - timelineFrames[] is an optional compressed playback list.
 * - durationFrames/holdFrames keeps repeated visual holds without copying PNGs.
 * - each nested layer advances on its own period; callers compose layers.
 */
var AssetTimeline = (function() {
    'use strict';

    var DEFAULT_FPS = 24;

    function numberOr(value, fallback) {
        return typeof value === 'number' && isFinite(value) ? value : fallback;
    }

    function arrayOrEmpty(value) {
        return value && value.length ? value : [];
    }

    function playbackFrames(entry) {
        if (!entry) return [];
        if (entry.timelineFrames && entry.timelineFrames.length) return entry.timelineFrames;
        if (entry.frames && entry.frames.length) return entry.frames;
        if (entry.export) {
            if (entry.export.timelineFrames && entry.export.timelineFrames.length) return entry.export.timelineFrames;
            if (entry.export.frames && entry.export.frames.length) return entry.export.frames;
        }
        return [];
    }

    function durationFrames(frame) {
        if (!frame) return 1;
        var duration = frame.durationFrames || frame.holdFrames;
        duration = Math.floor(Number(duration || 1));
        return duration > 0 ? duration : 1;
    }

    function totalDurationFrames(frames) {
        frames = arrayOrEmpty(frames);
        var total = 0;
        for (var i = 0; i < frames.length; i++) total += durationFrames(frames[i]);
        return total || frames.length;
    }

    function frameIdentity(frame, identity) {
        if (!frame) return '';
        if (typeof identity === 'function') return String(identity(frame));
        var keys = identity && identity.length ? identity : ['uri'];
        var parts = [];
        for (var i = 0; i < keys.length; i++) {
            parts.push(frame[keys[i]]);
        }
        return parts.join('|');
    }

    function distinctFrameCount(frames, identity) {
        frames = arrayOrEmpty(frames);
        var seen = {};
        var count = 0;
        for (var i = 0; i < frames.length; i++) {
            var key = frameIdentity(frames[i], identity);
            if (!key || seen[key]) continue;
            seen[key] = true;
            count++;
        }
        return count;
    }

    function frameRate(entry, fallbackFps, defaultFps) {
        var fps = entry && entry.fps;
        if (!(Number(fps) > 0) && entry && entry.export) fps = entry.export.fps;
        if (!(Number(fps) > 0)) fps = fallbackFps;
        if (!(Number(fps) > 0)) fps = defaultFps || DEFAULT_FPS;
        fps = Number(fps);
        return fps > 0 ? fps : (defaultFps || DEFAULT_FPS);
    }

    function selectedFrame(frames, nowMs, fps) {
        frames = arrayOrEmpty(frames);
        if (!frames.length) return null;
        if (frames.length === 1) return frames[0];
        var total = totalDurationFrames(frames);
        var tick = Math.floor((Number(nowMs || 0) / 1000) * frameRate({ fps: fps })) % total;
        for (var i = 0; i < frames.length; i++) {
            var duration = durationFrames(frames[i]);
            if (tick < duration) return frames[i];
            tick -= duration;
        }
        return frames[0];
    }

    function select(entry, nowMs, options) {
        options = options || {};
        var frames = options.frames || playbackFrames(entry);
        var fallbackFrame = typeof options.fallbackFrame === 'function'
            ? options.fallbackFrame(entry)
            : options.fallbackFrame;
        if (!frames.length) {
            return {
                frame: fallbackFrame || null,
                animated: false,
                totalFrames: 0,
                frames: frames
            };
        }
        var totalFrames = totalDurationFrames(frames);
        if (frames.length === 1 || totalFrames <= 1) {
            return {
                frame: frames[0],
                animated: false,
                totalFrames: totalFrames,
                frames: frames
            };
        }
        return {
            frame: selectedFrame(frames, nowMs, frameRate(entry, options.fallbackFps, options.defaultFps)),
            animated: distinctFrameCount(frames, options.identity) > 1,
            totalFrames: totalFrames,
            frames: frames
        };
    }

    return {
        DEFAULT_FPS: DEFAULT_FPS,
        numberOr: numberOr,
        playbackFrames: playbackFrames,
        durationFrames: durationFrames,
        totalDurationFrames: totalDurationFrames,
        distinctFrameCount: distinctFrameCount,
        frameRate: frameRate,
        selectedFrame: selectedFrame,
        select: select
    };
})();
