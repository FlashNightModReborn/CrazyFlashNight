/** Material-archive entry/return navigation for the host-owned NPCShop panel. */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.NpcShopMaterialNavigation = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function requireFunction(options, name) {
        if (!options || typeof options[name] !== 'function') {
            throw new Error('NPCShop material navigation requires ' + name);
        }
        return options[name];
    }

    function Controller(options) {
        options = options || {};
        this._runtime = options.runtime;
        this._bridge = options.bridge;
        this._panels = options.panels;
        this._workbench = options.workbench;
        this._itemFilter = options.itemFilter;
        this._getOwner = requireFunction(options, 'getOwner');
        this._getState = requireFunction(options, 'getState');
        this._getCatalogRenderer = requireFunction(options, 'getCatalogRenderer');
        this._isReturnBlocked = requireFunction(options, 'isReturnBlocked');
        this._refreshSnapshot = requireFunction(options, 'refreshSnapshot');
        this._refreshControls = requireFunction(options, 'refreshControls');
        this._target = null;
        this._banner = null;
        this._snapshotError = '';
        this._returnButton = null;
        this._returnStatus = null;
        this._returnIntent = null;
        this._returnTimer = null;
        this._returnGeneration = 0;
        this._returnSequence = 0;
        this._returnError = '';
        var self = this;
        this._bridge.on('panel_resp', function(data) { self._handleReturnFailure(data); });
    }

    Controller.prototype.configure = function(parsedInit, initData) {
        this.retireReturn();
        this.clearTarget(false);
        this._returnButton = null;
        this._returnStatus = null;
        this._banner = null;
        this._snapshotError = '';
        this._target = parsedInit && (parsedInit.kind === 'crafting_materials'
                || parsedInit.kind === 'crafting_recipe') ? {
            kind:parsedInit.kind,
            preferredCatalogIndex:Number(initData.preferredCatalogIndex),
            preferredItemName:String(initData.preferredItemName),
            highlightIndex:null,
            focusConsumed:false,
            notFoundFocusConsumed:false,
            manualCleared:false,
            notFound:false
        } : null;
    };

    Controller.prototype.hasTarget = function() { return !!this._target; };
    Controller.prototype.isReturning = function() { return !!this._returnIntent; };

    Controller.prototype.createReturnAction = function(shell) {
        this._returnButton = null;
        this._returnStatus = null;
        if (!this._target) return null;
        var group = document.createElement('span');
        group.className = 'npcshop-material-return-group';
        var button = document.createElement('button');
        button.type = 'button';
        button.className = 'workbench-mode-btn npcshop-material-return-btn';
        var recipeTarget = this._target.kind === 'crafting_recipe';
        button.textContent = recipeTarget ? '← 返回合成配方' : '← 返回材料档案';
        button.setAttribute('aria-label', recipeTarget ? '返回原合成配方' : '返回材料档案');
        button.setAttribute('data-audio-cue', 'back');
        var self = this;
        button.addEventListener('click', function(event) { self.requestReturn(event); });
        var status = document.createElement('small');
        status.className = 'npcshop-material-return-status';
        status.setAttribute('role', 'status');
        status.setAttribute('aria-live', 'polite');
        status.hidden = true;
        group.appendChild(button);
        group.appendChild(status);
        shell.addHeaderAction(group);
        this._returnButton = button;
        this._returnStatus = status;
        return group;
    };

    Controller.prototype.attachBanner = function(root) {
        var banner = document.createElement('div');
        banner.className = 'npcshop-navigation-banner';
        banner.setAttribute('role', 'status');
        banner.setAttribute('aria-live', 'polite');
        banner.hidden = true;
        root.appendChild(banner);
        this._banner = banner;
        return banner;
    };

    Controller.prototype._exactItem = function(catalog) {
        if (!this._target || this._target.manualCleared) return null;
        var target = this._target;
        var matches = (catalog || []).filter(function(item) {
            return item && Number(item.catalogIndex) === target.preferredCatalogIndex
                && String(item.itemName || '') === target.preferredItemName;
        });
        return matches.length === 1 ? matches[0] : null;
    };

    Controller.prototype._preferredCategory = function(item, state) {
        var catalog = state && state.catalog || [];
        var sections = state && state.layout && Array.isArray(state.layout.sections)
            ? state.layout.sections : [];
        for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
            var entries = sections[sectionIndex] && sections[sectionIndex].entries || [];
            if (entries.some(function(index) {
                    return Number(index) === Number(item.catalogIndex);
                })) {
                return {mode:'combined', path:['curated', String(sections[sectionIndex].id)]};
            }
        }
        var automaticPath = this._itemFilter.catalogPath(item).map(function(part) {
            return String(part.id);
        });
        var setTree = this._itemFilter.buildSetTree(catalog);
        return sections.length || setTree.children.length
            ? {mode:'combined', path:['category'].concat(automaticPath)}
            : {mode:'auto', path:automaticPath};
    };

    Controller.prototype.prepareState = function(state) {
        if (!this._target || this._target.manualCleared) return null;
        var item = this._exactItem(state && state.catalog || []);
        if (!item) {
            this._target.highlightIndex = null;
            if (!this._target.notFound) this._target.notFoundFocusConsumed = false;
            this._target.notFound = true;
            return null;
        }
        var category = null;
        if (this._target.highlightIndex === null || this._target.notFound) {
            category = this._preferredCategory(item, state);
        }
        this._target.highlightIndex = Number(item.catalogIndex);
        this._target.notFound = false;
        return category;
    };

    Controller.prototype._stripDescription = function(node) {
        if (!node) return;
        var id = node.getAttribute('data-navigation-description-id');
        if (id) {
            var described = String(node.getAttribute('aria-describedby') || '')
                .split(/\s+/).filter(function(token) { return token && token !== id; });
            if (described.length) node.setAttribute('aria-describedby', described.join(' '));
            else node.removeAttribute('aria-describedby');
            node.removeAttribute('data-navigation-description-id');
        }
        var hint = node.querySelector('.npcshop-navigation-focus-hint');
        if (hint && hint.parentNode) hint.parentNode.removeChild(hint);
        node.classList.remove('npcshop-navigation-focus');
        node.removeAttribute('data-navigation-focus');
    };

    Controller.prototype._clearBanner = function() {
        if (!this._banner) return;
        this._workbench.clearElement(this._banner);
        this._banner.hidden = true;
        this._banner.removeAttribute('tabindex');
        this._banner.removeAttribute('data-navigation-state');
    };

    Controller.prototype.clearTarget = function(manual) {
        var renderer = this._getCatalogRenderer();
        if (renderer && renderer.root) {
            var nodes = renderer.root.querySelectorAll('[data-navigation-focus]');
            for (var index = 0; index < nodes.length; index++) {
                this._stripDescription(nodes[index]);
            }
        }
        this._clearBanner();
        if (this._target && manual) {
            this._target.highlightIndex = null;
            this._target.notFound = false;
            this._target.manualCleared = true;
        }
    };

    Controller.prototype.beginSnapshot = function() {
        this._snapshotError = '';
        this._clearBanner();
    };

    Controller.prototype.acceptSnapshot = function() { this._snapshotError = ''; };

    Controller.prototype.rejectSnapshot = function() {
        if (!this._target) return false;
        this._snapshotError = '商店目录读取失败；请重新读取后再定位材料来源商品。';
        return this._renderSnapshotError();
    };

    Controller.prototype._renderSnapshotError = function() {
        if (!this._banner || !this._snapshotError) return false;
        this._clearBanner();
        this._banner.hidden = false;
        this._banner.setAttribute('data-navigation-state', 'snapshot-error');
        var text = document.createElement('p');
        text.textContent = this._snapshotError;
        var retry = document.createElement('button');
        retry.type = 'button';
        retry.className = 'workbench-mode-btn npcshop-navigation-retry';
        retry.textContent = '重新读取商店目录';
        retry.setAttribute('aria-label', '重新读取商店目录并定位材料来源商品');
        retry.addEventListener('click', this._refreshSnapshot);
        this._banner.appendChild(text);
        this._banner.appendChild(retry);
        if (typeof retry.focus === 'function') retry.focus();
        return true;
    };

    Controller.prototype._renderNotFound = function() {
        if (!this._banner || !this._target) return;
        this._clearBanner();
        this._banner.hidden = false;
        this._banner.setAttribute('tabindex', '-1');
        this._banner.setAttribute('data-navigation-state', 'not-found');
        this._banner.textContent = '未能定位“' + this._target.preferredItemName
            + '”：商店目录已变化或商品不可用。';
        if (!this._target.notFoundFocusConsumed) {
            this._target.notFoundFocusConsumed = true;
            if (typeof this._banner.focus === 'function') this._banner.focus();
        }
    };

    Controller.prototype.applyPresentation = function() {
        if (this._renderSnapshotError()) return;
        this._clearBanner();
        if (!this._target || this._target.manualCleared) return;
        var state = this._getState();
        var item = this._exactItem(state && state.catalog || []);
        if (!item || this._target.notFound) {
            this._renderNotFound();
            return;
        }
        var renderer = this._getCatalogRenderer();
        var nodes = renderer && renderer.root
            ? renderer.root.querySelectorAll('[data-workbench-key]') : [];
        var matches = [];
        for (var index = 0; index < nodes.length; index++) {
            var projected = nodes[index].__workbenchItem;
            if (String(nodes[index].getAttribute('data-workbench-key'))
                        === String(this._target.preferredCatalogIndex)
                    && projected
                    && Number(projected.catalogIndex) === this._target.preferredCatalogIndex
                    && String(projected.itemName || '') === this._target.preferredItemName) {
                matches.push(nodes[index]);
            }
        }
        if (matches.length !== 1) {
            this._renderNotFound();
            return;
        }
        var target = matches[0];
        this._stripDescription(target);
        target.classList.add('npcshop-navigation-focus');
        target.setAttribute('data-navigation-focus', 'true');
        var hint = document.createElement('span');
        var hintId = 'npcshop-navigation-focus-hint';
        hint.id = hintId;
        hint.className = 'npcshop-navigation-focus-hint';
        hint.textContent = this._target.kind === 'crafting_recipe'
            ? '从合成缺口定位' : '从材料档案定位';
        target.appendChild(hint);
        target.setAttribute('data-navigation-description-id', hintId);
        var described = String(target.getAttribute('aria-describedby') || '')
            .split(/\s+/).filter(Boolean);
        if (described.indexOf(hintId) < 0) described.push(hintId);
        target.setAttribute('aria-describedby', described.join(' '));
        if (!this._target.focusConsumed) {
            this._target.focusConsumed = true;
            if (typeof target.scrollIntoView === 'function') {
                target.scrollIntoView({block:'nearest', inline:'nearest'});
            }
            if (typeof target.focus === 'function') target.focus();
        }
    };

    Controller.prototype.consumeMutation = function(event) {
        if (!this._returnIntent) return false;
        if (event && event.type === 'keydown'
                && event.key !== 'Enter' && event.key !== ' ') return false;
        if (event && typeof event.preventDefault === 'function') event.preventDefault();
        if (event && typeof event.stopImmediatePropagation === 'function') {
            event.stopImmediatePropagation();
        }
        if (event && typeof event.stopPropagation === 'function') event.stopPropagation();
        return true;
    };

    Controller.prototype._setNodeDisabled = function(node, disabled) {
        if (!node) return;
        var marker = 'data-return-navigation-prior-aria-disabled';
        if (disabled) {
            if (!node.hasAttribute(marker)) {
                node.setAttribute(marker, node.hasAttribute('aria-disabled')
                    ? String(node.getAttribute('aria-disabled')) : '__absent__');
            }
            node.setAttribute('aria-disabled', 'true');
            node.inert = true;
            return;
        }
        if (node.hasAttribute(marker)) {
            var previous = node.getAttribute(marker);
            node.removeAttribute(marker);
            if (previous === '__absent__') node.removeAttribute('aria-disabled');
            else node.setAttribute('aria-disabled', previous);
        }
        node.inert = false;
    };

    Controller.prototype.syncControls = function(catalogRoot) {
        var returning = !!this._returnIntent;
        var nodes = catalogRoot ? catalogRoot.querySelectorAll('[data-workbench-key]') : [];
        for (var index = 0; index < nodes.length; index++) {
            nodes[index].disabled = returning;
            this._setNodeDisabled(nodes[index], returning);
        }
        if (this._returnButton) {
            this._returnButton.disabled = returning || this._isReturnBlocked();
            var recipeTarget = this._target && this._target.kind === 'crafting_recipe';
            this._returnButton.textContent = returning ? '返回中…'
                : this._returnError
                    ? (recipeTarget ? '重试返回合成配方' : '重试返回材料档案')
                    : (recipeTarget ? '← 返回合成配方' : '← 返回材料档案');
            this._returnButton.setAttribute('aria-busy', returning ? 'true' : 'false');
        }
        if (this._returnStatus) {
            var returnRecipe = this._target && this._target.kind === 'crafting_recipe';
            this._returnStatus.textContent = returning
                ? (returnRecipe ? '正在返回原合成配方…' : '正在返回材料档案…')
                : this._returnError;
            this._returnStatus.hidden = !returning && !this._returnError;
            this._returnStatus.setAttribute('data-navigation-state', returning
                ? 'pending' : this._returnError ? 'error' : 'idle');
        }
    };

    Controller.prototype._errorMessage = function(error) {
        var messages = {
            invalid_payload:'返回入口数据无效；请重新打开商店。',
            stale_source:'材料返回入口已经失效；请从材料档案重新进入。',
            navigation_unavailable:'材料档案导航暂不可用；请重试。',
            access_denied:'当前商店不能返回该材料档案。',
            source_not_settled:'商店状态仍在同步；请稍后重试。',
            admission_failed:'材料档案暂时无法打开；请重试。',
            timeout:'返回材料档案超时；请重试。',
            busy:'另一项面板导航正在进行；请稍后重试。',
            return_unavailable:'返回材料档案的入口已经失效。'
        };
        return messages[String(error || '')] || '暂时无法返回材料档案；请重试。';
    };

    Controller.prototype.requestReturn = function(event) {
        if (event && typeof event.preventDefault === 'function') event.preventDefault();
        if (this._returnIntent || !this._target || !this._returnButton
                || this._isReturnBlocked()) return false;
        var owner = this._getOwner();
        var restoreButtonFocus = document.activeElement === this._returnButton;
        var recipeTarget = this._target.kind === 'crafting_recipe';
        var callId = (recipeTarget ? 'npcshop-recipe-return-'
            : 'npcshop-material-return-') + (++this._returnSequence);
        var message = (recipeTarget
            ? this._runtime.createReturnCraftingRecipeMessage
            : this._runtime.createReturnCraftingMaterialsMessage)({
            callId:callId,
            recipeTarget:recipeTarget,
            panelInstanceId:owner.panelInstanceId
        });
        if (!message) {
            this._returnError = this._errorMessage('invalid_payload');
            this._refreshControls();
            return false;
        }
        var intent = {
            generation:++this._returnGeneration,
            ownerGeneration:owner.generation,
            panelInstanceId:owner.panelInstanceId,
            callId:callId,
            restoreButtonFocus:restoreButtonFocus,
            startedAt:Date.now()
        };
        this._returnError = '';
        this._returnIntent = intent;
        this._refreshControls();
        var sent = false;
        try { sent = this._bridge.send(message) !== false; }
        catch (_) { sent = false; }
        if (!sent) {
            this._failReturn(intent, 'navigation_unavailable');
            return false;
        }
        if (this._returnIntent === intent) {
            var self = this;
            var elapsed = Math.max(0, Date.now() - intent.startedAt);
            this._returnTimer = setTimeout(function() {
                if (self._returnIntent === intent) self._failReturn(intent, 'timeout');
            }, Math.max(0, this._runtime.NAVIGATION_WATCHDOG_MS - elapsed));
        }
        return true;
    };

    Controller.prototype._isCurrent = function(intent) {
        var owner = this._getOwner();
        return !!intent && this._returnIntent === intent
            && intent.generation === this._returnGeneration
            && intent.ownerGeneration === owner.generation
            && intent.panelInstanceId === owner.panelInstanceId
            && !!this._target
            && (!this._panels.getActive || this._panels.getActive() === 'npcshop');
    };

    Controller.prototype._handleReturnFailure = function(data) {
        var intent = this._returnIntent;
        var validate = intent && intent.recipeTarget
            ? this._runtime.validateReturnCraftingRecipeFailure
            : this._runtime.validateReturnCraftingMaterialsFailure;
        if (!this._isCurrent(intent)
                || !validate(data, {
                    callId:intent.callId,
                    panelInstanceId:intent.panelInstanceId
                })) return false;
        return this._failReturn(intent, data.error);
    };

    Controller.prototype._failReturn = function(intent, error) {
        if (!this._isCurrent(intent)) return false;
        var activeBeforeFailure = document.activeElement;
        if (this._returnTimer !== null) {
            clearTimeout(this._returnTimer);
            this._returnTimer = null;
        }
        this._returnIntent = null;
        this._returnError = this._errorMessage(error);
        this._refreshControls();
        if (intent.restoreButtonFocus && this._returnButton
                && this._returnButton.isConnected
                && (activeBeforeFailure === this._returnButton
                    || activeBeforeFailure === document.body
                    || activeBeforeFailure === document.documentElement)) {
            try { this._returnButton.focus({preventScroll:true}); }
            catch (_) { this._returnButton.focus(); }
        }
        return false;
    };

    Controller.prototype.retireReturn = function() {
        this._returnGeneration++;
        if (this._returnTimer !== null) {
            clearTimeout(this._returnTimer);
            this._returnTimer = null;
        }
        this._returnIntent = null;
        this._returnError = '';
    };

    Controller.prototype.cleanup = function() {
        this.retireReturn();
        this.clearTarget(false);
        this._target = null;
        this._banner = null;
        this._snapshotError = '';
        this._returnButton = null;
        this._returnStatus = null;
    };

    Controller.prototype.debugState = function() {
        var target = this._target;
        var intent = this._returnIntent;
        return {
            catalogNavigation:target ? {
                kind:target.kind,
                preferredCatalogIndex:target.preferredCatalogIndex,
                preferredItemName:target.preferredItemName,
                highlightIndex:target.highlightIndex,
                focusConsumed:target.focusConsumed,
                notFoundFocusConsumed:target.notFoundFocusConsumed,
                manualCleared:target.manualCleared,
                notFound:target.notFound
            } : null,
            returnNavigation:intent ? {
                generation:intent.generation,
                callId:intent.callId,
                panelInstanceId:intent.panelInstanceId
            } : null,
            returnNavigationError:this._returnError
        };
    };

    return {create:function(options) { return new Controller(options); }};
});
