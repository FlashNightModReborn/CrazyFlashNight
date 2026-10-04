/** One active decoder; bounded page cache. Closing or turning pages retires all callbacks. */
(function(root) {
    'use strict';
    function Media() { this.cache = new Map(); this.cancel = null; this.generation = 0; }
    Media.prototype.stop = function() {
        this.generation++;
        if (this.cancel) this.cancel();
        this.cancel = null;
    };
    Media.prototype.load = function(key, url, page) {
        this.stop();
        var self = this, generation = this.generation;
        if (this.cache.has(key)) {
            var cached = this.cache.get(key); this.cache.delete(key); this.cache.set(key, cached);
            return Promise.resolve(cached);
        }
        return new Promise(function(resolve, reject) {
            var video = page && page.storage === 'video-frame';
            var node = document.createElement(video ? 'video' : 'img'), done = false;
            var timer = setTimeout(function() { finish(new Error('media_timeout')); }, 15000);
            function release(error) {
                clearTimeout(timer); node.onload = node.onerror = node.onloadeddata = node.onseeked = null;
                if (video) {
                    node.pause(); node.removeAttribute('src'); node.load();
                } else if (error) node.removeAttribute('src');
            }
            function finish(error, result) {
                if (done) return; done = true; release(error || generation !== self.generation);
                if (generation === self.generation) self.cancel = null;
                if (error || generation !== self.generation) { reject(error || new Error('cancelled')); return; }
                self.cache.set(key, result);
                while (self.cache.size > 3) self.cache.delete(self.cache.keys().next().value);
                resolve(result);
            }
            self.cancel = function() { finish(new Error('cancelled')); };
            node.onerror = function() { finish(new Error('media_unavailable')); };
            if (video) {
                node.muted = true; node.playsInline = true; node.preload = 'auto';
                var painted = false;
                function draw() {
                    if (done || painted || node.seeking || node.readyState < 2) return;
                    painted = true;
                    var crop = page.crop;
                    if (crop[0] + crop[2] > node.videoWidth || crop[1] + crop[3] > node.videoHeight) {
                        finish(new Error('invalid_crop')); return;
                    }
                    var canvas = document.createElement('canvas'); canvas.width = crop[2]; canvas.height = crop[3];
                    canvas.getContext('2d').drawImage(node, crop[0], crop[1], crop[2], crop[3], 0, 0, crop[2], crop[3]);
                    canvas.dataset.frame = String(page.frame); finish(null, canvas);
                }
                node.onloadeddata = function() {
                    node.onloadeddata = null;
                    // Seek inside the requested one-second frame, including frame zero.
                    // seeked is emitted after the paused decoder has produced the target frame.
                    // A frame callback queued before seeking can instead report the old frame.
                    node.onseeked = draw;
                    node.currentTime = page.time_seconds + 0.05;
                };
            } else {
                node.decoding = 'async'; node.draggable = false;
                node.onload = function() { finish(null, node); };
            }
            node.src = url;
        });
    };
    Media.prototype.destroy = function() { this.stop(); this.cache.clear(); };
    root.BookshelfMedia = Media;
})(window);
