/** NPC 商店阵营主题 + 店主立绘底板。
 *  阵营配色来自 window.NpcShopThemes（tools/derive-npcshop-themes.js 生成，
 *  真源 data/shops/list.xml + data/rag/npc_state_db.json）；
 *  立绘真源是 flashswf/portraits/*.swf 的烘焙产物 assets/dialogue-portraits，
 *  缺失时回退 assets/shop-portraits 胸像，再退到占位字。
 *  立绘不作独立栏，而是压入商品目录槽（L slot）底部当底板：cover 放大裁切 +
 *  阵营深色滤镜，目录 UI 浮在其上形成材质感。 */
var NpcShopKeeper = (function() {
    'use strict';
    var _portraitManifestPromise = null;
    function assetBase() {
        return typeof window !== 'undefined' && window.CF7_NPCSHOP_ASSET_BASE || '';
    }
    function resolveTheme(shopId) {
        var themes = typeof window !== 'undefined' ? window.NpcShopThemes : null;
        var faction = '', theme = null;
        if (themes && themes.factions) {
            faction = themes.shops && themes.shops[shopId] ? themes.shops[shopId] : '';
            theme = themes.factions[faction] || themes.factions[themes.fallback || '_default'] || null;
        }
        return {
            faction:faction,
            accent:theme && theme.accent || '#c2c8cf',
            dark:theme && theme.dark || '#14161a',
            light:theme && theme.light || '#d6dade'
        };
    }
    function loadPortraitManifest() {
        if (!_portraitManifestPromise) {
            _portraitManifestPromise = fetch(assetBase() + 'assets/dialogue-portraits/manifest.json', {cache:'no-cache'})
                .then(function(res) {
                    if (!res.ok) throw new Error('portrait manifest HTTP ' + res.status);
                    return res.json();
                }).catch(function() { _portraitManifestPromise = null; return null; });
        }
        return _portraitManifestPromise;
    }
    function resolveDialoguePortrait(manifest, shopId) {
        if (!manifest || !manifest.entries) return null;
        var key = shopId;
        if (!manifest.entries[key]) {
            var aliases = manifest.aliases || {};
            key = aliases[shopId] || aliases[String(shopId).toLowerCase()] || null;
        }
        var entry = key && manifest.entries[key];
        if (!entry || !entry.expressions) return null;
        var name = entry.defaultExpression && entry.expressions[entry.defaultExpression]
            ? entry.defaultExpression : Object.keys(entry.expressions)[0];
        var asset = name && entry.expressions[name];
        if (!asset || !asset.uri || !asset.bounds || !asset.width || !asset.height) return null;
        return {url:assetBase() + 'assets/dialogue-portraits/' + asset.uri,
            width:asset.width, height:asset.height, bounds:asset.bounds};
    }
    // cover 适配再放大 12%（超出由 stage overflow 裁切）；纵向偏上锚定保留头部。
    // bust 回退用 contain，避免 256px 胸像被放大到糊。
    function fitPortrait(stage, img, asset, mode, retried) {
        var slotW = stage.clientWidth, slotH = stage.clientHeight;
        if (!slotW || !slotH) {
            if (!retried && typeof requestAnimationFrame === 'function') {
                requestAnimationFrame(function() { if (img.isConnected) fitPortrait(stage, img, asset, mode, true); });
            }
            return;
        }
        var bounds = asset.bounds;
        var scale = mode === 'bust'
            ? Math.min(slotW / bounds.width, slotH / bounds.height)
            : Math.max(slotW / bounds.width, slotH / bounds.height) * 1.12;
        img.style.width = (asset.width * scale).toFixed(2) + 'px';
        img.style.height = (asset.height * scale).toFixed(2) + 'px';
        img.style.left = ((slotW - bounds.width * scale) / 2 - bounds.x * scale).toFixed(2) + 'px';
        img.style.top = mode === 'bust'
            ? ((slotH - bounds.height * scale) / 2 - bounds.y * scale).toFixed(2) + 'px'
            : ((slotH - bounds.height * scale) * 0.1 - bounds.y * scale).toFixed(2) + 'px';
    }
    function mountBust(stage, shopId, isCurrent, placeholder) {
        if (typeof ShopPortraits === 'undefined' || !ShopPortraits.resolveAsync) return;
        ShopPortraits.resolveAsync(shopId).then(function(desc) {
            if (!isCurrent() || !desc) return;
            var img = new Image();
            img.className = 'npcshop-backdrop-portrait'; img.alt = ''; img.draggable = false;
            img.onload = function() {
                if (!isCurrent()) return;
                if (placeholder.parentNode) placeholder.parentNode.removeChild(placeholder);
                stage.appendChild(img);
                stage.setAttribute('data-portrait-source', 'bust');
                fitPortrait(stage, img, {width:desc.width, height:desc.height, bounds:desc.bounds}, 'bust');
            };
            img.src = desc.url;
        });
    }
    function mountPortrait(stage, shopId, isCurrent) {
        stage.setAttribute('data-portrait-source', 'none');
        var placeholder = document.createElement('div');
        placeholder.className = 'npcshop-backdrop-placeholder';
        placeholder.textContent = String(shopId || '店').charAt(0);
        stage.appendChild(placeholder);
        loadPortraitManifest().then(function(manifest) {
            if (!isCurrent()) return;
            var asset = resolveDialoguePortrait(manifest, shopId);
            if (!asset) { mountBust(stage, shopId, isCurrent, placeholder); return; }
            var img = new Image();
            img.className = 'npcshop-backdrop-portrait'; img.alt = ''; img.draggable = false;
            img.onload = function() {
                if (!isCurrent()) return;
                if (placeholder.parentNode) placeholder.parentNode.removeChild(placeholder);
                stage.appendChild(img);
                stage.setAttribute('data-portrait-source', 'dialogue');
                fitPortrait(stage, img, asset, 'dialogue');
            };
            img.onerror = function() { mountBust(stage, shopId, isCurrent, placeholder); };
            img.src = asset.url;
        });
    }
    function create(options) {
        options = options || {};
        var shopId = String(options.shopId || '');
        var theme = resolveTheme(shopId);
        var frame = document.createElement('div');
        frame.className = 'npcshop-frame';
        frame.style.setProperty('--npcshop-accent', theme.accent);
        frame.style.setProperty('--npcshop-dark', theme.dark);
        frame.style.setProperty('--npcshop-light', theme.light);
        var stage = document.createElement('div');
        stage.className = 'npcshop-backdrop';
        stage.setAttribute('aria-hidden', 'true');
        var slotFrame = options.shell && typeof options.shell.getSlotFrame === 'function'
            ? options.shell.getSlotFrame('L') : null;
        if (slotFrame) slotFrame.insertBefore(stage, slotFrame.firstChild);
        else frame.appendChild(stage);
        var alive = true;
        mountPortrait(stage, shopId, function() { return alive && stage.isConnected; });
        // 图标自愈：目录首次渲染若撞上 Icons manifest 异步未就绪（Icons.html 返回空占位），
        // manifest 到达后由调用方强制重渲；与 KShop CatalogPresenter 的 Icons.load 重渲同款。
        var iconsHealed = false;
        function warmIcons(callback) {
            if (iconsHealed) return;
            iconsHealed = true;
            if (typeof Icons === 'undefined' || !Icons || typeof Icons.load !== 'function') return;
            Icons.load(function() { if (alive && typeof callback === 'function') callback(); });
        }
        return {
            root:frame,
            faction:theme.faction,
            warmIcons:warmIcons,
            destroy:function() { alive = false; }
        };
    }
    return {create:create, resolveTheme:resolveTheme};
})();
