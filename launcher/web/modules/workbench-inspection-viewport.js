/**
 * Shared inspection camera for workbench previews.
 *
 * The camera owns transient pointer/wheel/keyboard presentation state only.
 * It never creates a renderer, duplicates a Canvas, or persists domain state.
 * Consumers with intentionally off-centre evidence may provide panBounds(state, camera)
 * to enlarge the default scaled-viewport pan envelope without changing existing users.
 */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.WorkbenchInspectionViewport = api;
        root.WorkbenchInspectionViewport = api;
    }
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function number(value, fallback) {
        value = Number(value);
        return isFinite(value) ? value : fallback;
    }

    function clamp(value, minimum, maximum) {
        return Math.max(minimum, Math.min(maximum, value));
    }

    function addClasses(node, names) {
        String(names || '').split(/\s+/).forEach(function(name) {
            if (name) node.classList.add(name);
        });
    }

    function removeNode(node) {
        if (node && node.parentNode) node.parentNode.removeChild(node);
    }

    function listen(records, target, type, handler, options) {
        target.addEventListener(type, handler, options);
        records.push(function() {
            target.removeEventListener(type, handler, options);
        });
    }

    function Camera(options) {
        options = options || {};
        this._document = options.document
            || options.viewport && options.viewport.ownerDocument
            || options.target && options.target.ownerDocument;
        this.viewport = options.viewport;
        this.target = options.target;
        if (!this._document || !this.viewport || !this.target) {
            throw new Error('WorkbenchInspectionViewport requires document, viewport, and target');
        }
        this._minimum = Math.max(0.1, number(options.minZoom, 1));
        this._maximum = Math.max(this._minimum, number(options.maxZoom, 4));
        this._fitZoom = clamp(number(options.fitZoom, 1), this._minimum, this._maximum);
        this._defaultZoom = clamp(
            number(options.defaultZoom, this._fitZoom), this._minimum, this._maximum);
        this._zoomStep = Math.max(0.01, number(options.zoomStep, 0.2));
        this._panStep = Math.max(1, number(options.panStep, 34));
        this._onChange = typeof options.onChange === 'function'
            ? options.onChange : function() {};
        this._resetOffset = typeof options.resetOffset === 'function'
            ? options.resetOffset : null;
        this._panBounds = typeof options.panBounds === 'function'
            ? options.panBounds : null;
        this._state = {
            zoom:this._defaultZoom,
            panX:0,
            panY:0,
            dragging:false,
            pointerId:null,
            x:0,
            y:0
        };
        this._enabled = false;
        this._destroyed = false;
        this._listeners = [];
        this._ownsControls = !options.controlsRoot;
        this.controls = options.controlsRoot || this._document.createElement('div');
        addClasses(this.controls,
            'workbench-inspection-controls ' + (options.controlsClass || ''));
        this.controls.setAttribute('role', 'toolbar');
        this.controls.setAttribute('aria-label',
            options.controlsAriaLabel || '预览视角控制');
        this._panControls = this._document.createElement('div');
        addClasses(this._panControls,
            'workbench-inspection-pan-controls ' + (options.panControlsClass || ''));
        this._panControls.setAttribute('role', 'group');
        this._panControls.setAttribute('aria-label', '移动预览');
        this._zoomControls = this._document.createElement('div');
        addClasses(this._zoomControls,
            'workbench-inspection-zoom-controls ' + (options.zoomControlsClass || ''));
        this._zoomControls.setAttribute('role', 'group');
        this._zoomControls.setAttribute('aria-label', '缩放预览');
        this._status = this._document.createElement('output');
        addClasses(this._status,
            'workbench-inspection-status ' + (options.statusClass || ''));
        this._status.setAttribute('aria-live', 'polite');
        this._status.setAttribute('aria-label', '当前预览缩放');
        this._controlClass = options.controlClass || '';
        this._buildControls(options);
        this.controls.appendChild(this._panControls);
        this.controls.appendChild(this._zoomControls);
        if (options.controlsHost) options.controlsHost.appendChild(this.controls);

        addClasses(this.viewport,
            'workbench-inspection-viewport ' + (options.viewportClass || ''));
        addClasses(this.target,
            'workbench-inspection-target ' + (options.targetClass || ''));
        if (!this.viewport.hasAttribute('tabindex')) {
            this.viewport.setAttribute('tabindex', '0');
            this._ownsTabIndex = true;
        }
        if (!this.viewport.hasAttribute('role')) this.viewport.setAttribute('role', 'region');
        if (options.ariaLabel) this.viewport.setAttribute('aria-label', options.ariaLabel);
        if (options.describedBy) this.viewport.setAttribute('aria-describedby', options.describedBy);
        this._bind();
        this._syncControls();
        if (options.active === true) this.activate({reset:true});
    }

    Camera.prototype._button = function(label, ariaLabel, action, handler) {
        var node = this._document.createElement('button');
        node.type = 'button';
        node.textContent = label;
        addClasses(node,
            'workbench-inspection-control ' + this._controlClass);
        node.setAttribute('data-inspection-action', action);
        node.setAttribute('aria-label', ariaLabel);
        var self = this;
        listen(this._listeners, node, 'click', function(event) {
            if (node.disabled || self._destroyed) return;
            if (event && event.preventDefault) event.preventDefault();
            handler.call(self, event);
        });
        return node;
    };

    Camera.prototype._buildControls = function(options) {
        var self = this;
        [
            ['←', '向左移动预览', 'left', function() { self.shift(-self._panStep, 0); }],
            ['↑', '向上移动预览', 'up', function() { self.shift(0, -self._panStep); }],
            ['↓', '向下移动预览', 'down', function() { self.shift(0, self._panStep); }],
            ['→', '向右移动预览', 'right', function() { self.shift(self._panStep, 0); }]
        ].forEach(function(spec) {
            self._panControls.appendChild(
                self._button(spec[0], spec[1], spec[2], spec[3]));
        });
        this._zoomControls.appendChild(this._button(
            '−', '缩小预览', 'zoom-out',
            function() { this.setZoom(this._state.zoom - this._zoomStep); }));
        this._zoomControls.appendChild(this._status);
        this._zoomControls.appendChild(this._button(
            '+', '放大预览', 'zoom-in',
            function() { this.setZoom(this._state.zoom + this._zoomStep); }));
        if (options.fitLabel !== false) {
            this._zoomControls.appendChild(this._button(
                options.fitLabel || '全貌',
                options.fitAriaLabel || '显示完整预览',
                'fit',
                function() { this.reset(this._fitZoom); }));
        }
        if (options.resetLabel) {
            this._zoomControls.appendChild(this._button(
                options.resetLabel,
                options.resetAriaLabel || '恢复默认预览',
                'reset',
                function() { this.reset(this._defaultZoom); }));
        }
    };

    Camera.prototype._limits = function() {
        var width = this.viewport.clientWidth || 1;
        var height = this.viewport.clientHeight || 1;
        var limits = {
            x:Math.max(0, width * (this._state.zoom - 1) / 2),
            y:Math.max(0, height * (this._state.zoom - 1) / 2)
        };
        if (this._panBounds) {
            var expanded = this._panBounds(this.debugState(), this) || {};
            limits.x = Math.max(limits.x, Math.max(0, number(expanded.x, 0)));
            limits.y = Math.max(limits.y, Math.max(0, number(expanded.y, 0)));
        }
        return limits;
    };

    Camera.prototype._syncControls = function() {
        this._status.textContent = Math.round(this._state.zoom * 100) + '%';
        var buttons = this.controls.querySelectorAll('[data-inspection-action]');
        for (var i = 0; i < buttons.length; i++) buttons[i].disabled = !this._enabled;
    };

    Camera.prototype._apply = function(reason) {
        var limits = this._limits();
        this._state.panX = clamp(this._state.panX, -limits.x, limits.x);
        this._state.panY = clamp(this._state.panY, -limits.y, limits.y);
        if (this._enabled) {
            this.target.style.transform = 'translate3d('
                + Math.round(this._state.panX) + 'px,'
                + Math.round(this._state.panY) + 'px,0) scale('
                + this._state.zoom + ')';
        }
        this._syncControls();
        this._onChange(this.debugState(), reason || 'apply', this);
        return true;
    };

    Camera.prototype.setZoom = function(nextZoom, anchorX, anchorY) {
        if (this._destroyed || !this._enabled) return false;
        var previous = this._state.zoom;
        var next = clamp(
            Math.round(number(nextZoom, previous) * 100) / 100,
            this._minimum,
            this._maximum
        );
        if (next === previous) return false;
        if (typeof anchorX === 'number' && typeof anchorY === 'number') {
            var rect = this.viewport.getBoundingClientRect();
            var scaleX = (this.viewport.clientWidth || rect.width || 1)
                / Math.max(1, rect.width);
            var scaleY = (this.viewport.clientHeight || rect.height || 1)
                / Math.max(1, rect.height);
            var localX = (anchorX - rect.left - rect.width / 2) * scaleX;
            var localY = (anchorY - rect.top - rect.height / 2) * scaleY;
            var ratio = next / previous;
            this._state.panX = localX - (localX - this._state.panX) * ratio;
            this._state.panY = localY - (localY - this._state.panY) * ratio;
        }
        this._state.zoom = next;
        return this._apply('zoom');
    };

    Camera.prototype.shift = function(deltaX, deltaY) {
        if (this._destroyed || !this._enabled) return false;
        this._state.panX += number(deltaX, 0);
        this._state.panY += number(deltaY, 0);
        return this._apply('pan');
    };

    Camera.prototype.reset = function(zoom, offset) {
        if (this._destroyed) return false;
        if ((!offset || offset.panX == null && offset.panY == null) && this._resetOffset) {
            offset = this._resetOffset(zoom, this.debugState(), this);
        }
        offset = offset || {};
        this._state.zoom = clamp(
            number(zoom, this._defaultZoom), this._minimum, this._maximum);
        this._state.panX = number(offset.panX, 0);
        this._state.panY = number(offset.panY, 0);
        if (this._enabled) return this._apply('reset');
        this._syncControls();
        return true;
    };

    Camera.prototype._stopDragging = function(pointerId) {
        if (!this._state.dragging) return false;
        if (pointerId != null && this._state.pointerId !== pointerId) return false;
        var captured = this._state.pointerId;
        this._state.dragging = false;
        this.viewport.classList.remove('is-dragging');
        if (captured != null && this.viewport.hasPointerCapture
                && this.viewport.hasPointerCapture(captured)) {
            try { this.viewport.releasePointerCapture(captured); } catch (_) {}
        }
        this._state.pointerId = null;
        return true;
    };

    Camera.prototype._bind = function() {
        var self = this;
        listen(this._listeners, this.viewport, 'pointerdown', function(event) {
            if (!self._enabled || event.button !== 0) return;
            self._state.dragging = true;
            self._state.pointerId = event.pointerId;
            self._state.x = event.clientX;
            self._state.y = event.clientY;
            self.viewport.classList.add('is-dragging');
            if (self.viewport.setPointerCapture) {
                try { self.viewport.setPointerCapture(event.pointerId); } catch (_) {}
            }
            event.preventDefault();
        });
        listen(this._listeners, this.viewport, 'pointermove', function(event) {
            if (!self._enabled || !self._state.dragging
                    || event.pointerId !== self._state.pointerId) return;
            var rect = self.viewport.getBoundingClientRect();
            var deltaX = (event.clientX - self._state.x)
                * (self.viewport.clientWidth || rect.width || 1) / Math.max(1, rect.width);
            var deltaY = (event.clientY - self._state.y)
                * (self.viewport.clientHeight || rect.height || 1) / Math.max(1, rect.height);
            self._state.x = event.clientX;
            self._state.y = event.clientY;
            self.shift(deltaX, deltaY);
        });
        ['pointerup', 'pointercancel', 'lostpointercapture'].forEach(function(type) {
            listen(self._listeners, self.viewport, type, function(event) {
                self._stopDragging(event.pointerId);
            });
        });
        listen(this._listeners, this.viewport, 'wheel', function(event) {
            if (!self._enabled) return;
            event.preventDefault();
            self.setZoom(
                self._state.zoom + (event.deltaY < 0 ? self._zoomStep : -self._zoomStep),
                event.clientX,
                event.clientY
            );
        }, {passive:false});
        listen(this._listeners, this.viewport, 'keydown', function(event) {
            if (!self._enabled) return;
            var handled = true;
            if (event.key === 'ArrowLeft') self.shift(-self._panStep, 0);
            else if (event.key === 'ArrowRight') self.shift(self._panStep, 0);
            else if (event.key === 'ArrowUp') self.shift(0, -self._panStep);
            else if (event.key === 'ArrowDown') self.shift(0, self._panStep);
            else if (event.key === '+' || event.key === '=') {
                self.setZoom(self._state.zoom + self._zoomStep);
            } else if (event.key === '-' || event.key === '_') {
                self.setZoom(self._state.zoom - self._zoomStep);
            } else if (event.key === 'Home') self.reset(self._fitZoom);
            else if (event.key === '0') self.reset(self._defaultZoom);
            else handled = false;
            if (handled) event.preventDefault();
        });
    };

    Camera.prototype.activate = function(options) {
        if (this._destroyed) return false;
        options = options || {};
        this._enabled = true;
        this.viewport.setAttribute('data-inspection-active', 'true');
        this.controls.setAttribute('aria-disabled', 'false');
        if (options.reset !== false) this.reset(this._defaultZoom, options);
        else this._apply('activate');
        return true;
    };

    Camera.prototype.deactivate = function() {
        if (this._destroyed) return false;
        var changed = this._enabled || this._state.dragging;
        this._stopDragging();
        this._enabled = false;
        this._state.zoom = this._defaultZoom;
        this._state.panX = 0;
        this._state.panY = 0;
        this.target.style.removeProperty('transform');
        this.viewport.removeAttribute('data-inspection-active');
        this.controls.setAttribute('aria-disabled', 'true');
        this._syncControls();
        return changed;
    };

    Camera.prototype.resize = function() {
        if (this._destroyed || !this._enabled) return false;
        return this._apply('resize');
    };

    Camera.prototype.getZoomControls = function() {
        return this._zoomControls;
    };

    Camera.prototype.debugState = function() {
        return {
            enabled:this._enabled,
            zoom:this._state.zoom,
            panX:this._state.panX,
            panY:this._state.panY,
            dragging:this._state.dragging,
            minimum:this._minimum,
            maximum:this._maximum
        };
    };

    Camera.prototype.destroy = function() {
        if (this._destroyed) return false;
        this.deactivate();
        this._destroyed = true;
        for (var i = this._listeners.length - 1; i >= 0; i--) this._listeners[i]();
        this._listeners = [];
        if (this._ownsControls) removeNode(this.controls);
        if (this._ownsTabIndex) this.viewport.removeAttribute('tabindex');
        this.viewport.classList.remove('workbench-inspection-viewport', 'is-dragging');
        this.target.classList.remove('workbench-inspection-target');
        return true;
    };

    return {
        Camera:Camera,
        create:function(options) { return new Camera(options); }
    };
});
