(function(root, factory) {
    'use strict';
    var components = typeof module !== 'undefined' && module.exports
        ? require('../workbench-components.js')
        : root && (root.WorkbenchComponents || root.CF7 && root.CF7.WorkbenchComponents);
    var inspection = typeof module !== 'undefined' && module.exports
        ? require('../workbench-inspection-viewport.js')
        : root && (root.WorkbenchInspectionViewport
            || root.CF7 && root.CF7.WorkbenchInspectionViewport);
    var api = factory(components, inspection);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.CharacterBuildDollPreview = api;
        root.CharacterBuildDollPreview = api;
    }
})(typeof window !== 'undefined' ? window : globalThis,
function(WorkbenchComponents, InspectionViewport) {
    'use strict';
    if (!WorkbenchComponents || typeof WorkbenchComponents.SecondaryPage !== 'function') {
        throw new Error('CharacterBuildDollPreview requires WorkbenchComponents.SecondaryPage');
    }
    if (!InspectionViewport || typeof InspectionViewport.create !== 'function') {
        throw new Error('CharacterBuildDollPreview requires WorkbenchInspectionViewport');
    }
    var previewSequence = 0;

    function requireElement(value, name) {
        if (!value || typeof value.appendChild !== 'function') {
            throw new Error('CharacterBuildDollPreview requires ' + name);
        }
        return value;
    }

    function createElement(document, tagName, className, text) {
        var element = document.createElement(tagName);
        if (className) element.className = className;
        if (text != null) element.textContent = text;
        return element;
    }

    function DollPreview(options) {
        options = options || {};
        this._document = options.document
            || options.root && options.root.ownerDocument || null;
        if (!this._document || typeof this._document.createElement !== 'function') {
            throw new Error('CharacterBuildDollPreview requires a document');
        }

        this._root = requireElement(options.root, 'root');
        this._stage = requireElement(options.stage, 'stage');
        this._canvas = requireElement(options.canvas, 'canvas');
        this._home = requireElement(options.home, 'home');
        if (this._stage.parentNode !== this._home) {
            throw new Error('CharacterBuildDollPreview stage must initially be a direct child of home');
        }
        if (!this._stage.contains(this._canvas)) {
            throw new Error('CharacterBuildDollPreview canvas must belong to stage');
        }
        if (this._stage === this._root || this._stage.contains && this._stage.contains(this._root)) {
            throw new Error('CharacterBuildDollPreview root cannot be inside stage');
        }

        this._buttonHost = requireElement(options.buttonHost || this._home, 'buttonHost');
        this._underlays = options.underlays != null ? options.underlays : options.underlay;
        this._onViewportChange = typeof options.onViewportChange === 'function'
            ? options.onViewportChange : null;
        this._homeAnchor = this._stage.nextSibling;
        this._stageExpanded = false;
        this._destroyed = false;
        this._destroying = false;

        this._openButton = createElement(
            this._document,
            'button',
            'character-build-doll-preview-open',
            options.openLabel || '放大预览'
        );
        this._openButton.type = 'button';
        this._openButton.setAttribute('data-doll-preview-open', '');
        this._openButton.setAttribute('aria-haspopup', 'dialog');
        this._openButton.setAttribute('aria-expanded', 'false');
        this._openButton.setAttribute('aria-label', options.openAriaLabel || '放大查看角色纸娃娃预览');

        this._pageRoot = createElement(
            this._document,
            'section',
            'character-build-doll-preview-page'
        );
        this._pageRoot.setAttribute('data-doll-preview-page', '');
        this._pageRoot.id = options.pageId
            || 'character-build-doll-preview-' + (++previewSequence);
        this._openButton.setAttribute('aria-controls', this._pageRoot.id);

        var heading = createElement(
            this._document,
            'header',
            'character-build-doll-preview-heading'
        );
        var headingCopy = createElement(
            this._document,
            'div',
            'character-build-doll-preview-heading-copy'
        );
        var eyebrow = createElement(
            this._document,
            'span',
            'character-build-doll-preview-eyebrow',
            options.eyebrow || 'CURRENT BUILD'
        );
        this._title = createElement(
            this._document,
            'h2',
            'character-build-doll-preview-title',
            options.title || '纸娃娃预览'
        );
        headingCopy.appendChild(eyebrow);
        headingCopy.appendChild(this._title);

        this._closeButton = createElement(
            this._document,
            'button',
            'character-build-doll-preview-close',
            options.closeLabel || '返回构筑'
        );
        this._closeButton.type = 'button';
        this._closeButton.setAttribute('data-doll-preview-close', '');
        this._closeButton.setAttribute('aria-label', options.closeAriaLabel || '关闭纸娃娃预览并返回构筑');
        heading.appendChild(headingCopy);
        heading.appendChild(this._closeButton);

        this._mount = createElement(
            this._document,
            'div',
            'character-build-doll-preview-mount'
        );
        this._mount.setAttribute('data-doll-preview-mount', '');

        this._footer = createElement(
            this._document, 'footer', 'character-build-doll-preview-footer');
        this._footer.setAttribute('data-body-copy', '');
        this._footer.appendChild(createElement(
            this._document,
            'span',
            'character-build-doll-preview-help',
            options.footer || '拖拽移动 · 滚轮缩放 · 方向键平移 · Esc 返回构筑'
        ));
        this._pageRoot.appendChild(heading);
        this._pageRoot.appendChild(this._mount);
        this._pageRoot.appendChild(this._footer);

        var self = this;
        this._page = new WorkbenchComponents.SecondaryPage({
            root:this._pageRoot,
            document:this._document,
            role:'dialog',
            ariaLabel:options.ariaLabel || '角色纸娃娃放大预览',
            className:'character-build-doll-preview-secondary',
            initialFocus:this._mount,
            removeOnDestroy:true,
            onOpen:function() { self._moveToPreview(); },
            onClose:function(reason) { self._restoreStage(reason); }
        });
        this._page.mount(this._root);
        this._page.bindClose(this._closeButton);
        this._inspection = InspectionViewport.create({
            document:this._document,
            viewport:this._mount,
            target:this._canvas,
            controlsHost:this._footer,
            ariaLabel:'角色纸娃娃预览，可拖拽或使用方向键移动',
            defaultZoom:1,
            fitZoom:1,
            minZoom:1,
            maxZoom:3,
            zoomStep:0.2,
            panStep:34,
            fitLabel:'全貌',
            onChange:function(_, reason) {
                self._notifyViewportChange('expanded', reason || 'camera');
            }
        });

        this._handleOpenClick = function(event) {
            if (event && event.preventDefault) event.preventDefault();
            self.open(self._openButton);
        };
        this._openButton.addEventListener('click', this._handleOpenClick);
        this._buttonHost.appendChild(this._openButton);
    }

    DollPreview.prototype._resolveUnderlays = function() {
        var value = this._underlays;
        if (typeof value === 'function') value = value(this);
        if (value != null) return value;
        return this._root.querySelector
            ? this._root.querySelector('[data-build-underlay]')
            : null;
    };

    DollPreview.prototype._notifyViewportChange = function(mode, reason) {
        if (this._onViewportChange) {
            this._onViewportChange(mode, this._stage, this, reason || null);
        }
    };

    DollPreview.prototype._moveToPreview = function() {
        if (this._destroyed || this._destroying || this._stageExpanded) return false;
        this._mount.appendChild(this._stage);
        this._stageExpanded = true;
        this._openButton.setAttribute('aria-expanded', 'true');
        try {
            this._inspection.activate({reset:true});
            this._notifyViewportChange('expanded', 'open');
        } catch (error) {
            this._inspection.deactivate();
            this._restoreStageNode();
            this._stageExpanded = false;
            this._openButton.setAttribute('aria-expanded', 'false');
            throw error;
        }
        return true;
    };

    DollPreview.prototype._restoreStageNode = function() {
        if (this._stage.parentNode === this._home) return false;
        if (this._homeAnchor && this._homeAnchor.parentNode === this._home) {
            this._home.insertBefore(this._stage, this._homeAnchor);
        } else if (this._openButton.parentNode === this._home) {
            this._home.insertBefore(this._stage, this._openButton);
        } else {
            this._home.appendChild(this._stage);
        }
        return true;
    };

    DollPreview.prototype._restoreStage = function(reason) {
        var changed = this._stageExpanded || this._stage.parentNode !== this._home;
        this._inspection.deactivate();
        this._restoreStageNode();
        this._stageExpanded = false;
        this._openButton.setAttribute('aria-expanded', 'false');
        if (changed) this._notifyViewportChange('embedded', reason || 'close');
        return changed;
    };

    DollPreview.prototype.open = function(opener) {
        if (this._destroyed || this._destroying) return false;
        if (this._page.isActive()) return true;
        if (this._stage.parentNode !== this._home) this._restoreStage('pre-open');
        var context = {
            opener:opener || this._openButton,
            initialFocus:this._mount
        };
        var underlays = this._resolveUnderlays();
        if (underlays != null) context.underlay = underlays;
        try {
            var opened = this._page.open(context);
            if (!opened) this._restoreStage('open-cancelled');
            return opened;
        } catch (error) {
            this._restoreStage('open-error');
            throw error;
        }
    };

    DollPreview.prototype.close = function(reason) {
        if (this._destroyed || this._destroying) return false;
        if (this._page.isActive()) return this._page.close(reason || 'close');
        return this._restoreStage(reason || 'close');
    };

    DollPreview.prototype.isOpen = function() {
        return !this._destroyed && this._page.isActive();
    };

    DollPreview.prototype.getCameraState = function() {
        return this._inspection.debugState();
    };

    DollPreview.prototype.resize = function() {
        return this._inspection.resize();
    };

    DollPreview.prototype.debugState = function() {
        var parent = this._stage.parentNode === this._mount
            ? 'preview'
            : this._stage.parentNode === this._home ? 'home' : 'external';
        return {
            destroyed:this._destroyed,
            open:this.isOpen(),
            stageExpanded:this._stageExpanded,
            stageParent:parent,
            openButtonMounted:!!this._openButton.parentNode,
            canvasCount:this._stage.querySelectorAll
                ? this._stage.querySelectorAll('canvas').length : 0,
            camera:this._inspection.debugState()
        };
    };

    DollPreview.prototype.destroy = function() {
        if (this._destroyed || this._destroying) return false;
        this._destroying = true;
        var firstError = null;
        try {
            this._page.destroy();
        } catch (pageError) {
            firstError = pageError;
        }
        try {
            this._restoreStage('destroy');
        } catch (restoreError) {
            if (!firstError) firstError = restoreError;
        }
        try {
            this._openButton.removeEventListener('click', this._handleOpenClick);
            if (this._openButton.parentNode) this._openButton.parentNode.removeChild(this._openButton);
        } catch (buttonError) {
            if (!firstError) firstError = buttonError;
        }
        try { this._inspection.destroy(); }
        catch (inspectionError) { if (!firstError) firstError = inspectionError; }
        this._destroyed = true;
        this._destroying = false;
        this._handleOpenClick = null;
        this._onViewportChange = null;
        if (firstError) throw firstError;
        return true;
    };

    function create(options) {
        return new DollPreview(options);
    }

    return {
        DollPreview:DollPreview,
        create:create
    };
});
