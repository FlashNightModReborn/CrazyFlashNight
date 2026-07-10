/**
 * Suppresses browser-native gestures that visually break the game UI.
 * Text editors and explicit [data-browser-native] islands remain untouched.
 */
(function(root, factory) {
    'use strict';
    var api = factory(root && root.document ? root.document : null);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.GameUiBehavior = api;
})(typeof window !== 'undefined' ? window : globalThis, function(documentRef) {
    'use strict';

    var installed = false;
    var blocked = { selectstart: 0, dragstart: 0, contextmenu: 0 };

    function closestElement(target) {
        if (!target) return null;
        if (target.nodeType === 1) return target;
        return target.parentElement || null;
    }

    function allowsNativeBehavior(target) {
        var element = closestElement(target);
        if (!element || !element.closest) return false;
        return !!element.closest('input,textarea,[contenteditable="true"],[data-browser-native]');
    }

    function blockUnlessAllowed(event) {
        if (allowsNativeBehavior(event.target)) return;
        if (Object.prototype.hasOwnProperty.call(blocked, event.type)) blocked[event.type]++;
        event.preventDefault();
    }

    function install(doc) {
        doc = doc || documentRef;
        if (!doc || installed) return false;
        doc.addEventListener('selectstart', blockUnlessAllowed, true);
        doc.addEventListener('dragstart', blockUnlessAllowed, true);
        doc.addEventListener('contextmenu', blockUnlessAllowed, true);
        installed = true;
        return true;
    }

    function debugState() {
        return {
            installed: installed,
            blocked: {
                selectstart: blocked.selectstart,
                dragstart: blocked.dragstart,
                contextmenu: blocked.contextmenu
            }
        };
    }

    install(documentRef);

    return {
        install: install,
        allowsNativeBehavior: allowsNativeBehavior,
        debugState: debugState
    };
});

