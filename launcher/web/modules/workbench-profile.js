/** Closed DualPaneShell profile validation and atomic profile projection. */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.WorkbenchShellProfile = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    var VALID_PROFILES = {
        'catalog-decision': true,
        'archive-reference': true,
        'transfer-pair': true,
        'library-action-strip': true,
        'library-decision': true,
        'character-build': true,
        'canvas-editor': true,
        'canvas-editor-focus': true,
        'stage-focus': true
    };
    var VALID_PROFILE_NAMES = Object.freeze(Object.keys(VALID_PROFILES));

    function requireProfile(profile) {
        if (typeof profile !== 'string' || !VALID_PROFILES[profile]) {
            throw new TypeError('DualPaneShell requires a valid profile');
        }
        return profile;
    }

    function setProfile(profile) {
        var next = requireProfile(profile);
        if (this._destroyed || this._destroying) return false;
        this._root.setAttribute('data-profile', next);
        this._profile = next;
        return true;
    }

    function setSlotLabel(slotId, label) {
        var frame = this._slotFrames[slotId];
        if (!frame) return false;
        var text = String(label || '');
        var marker = frame.querySelector('.workbench-slot-marker span');
        if (marker) marker.textContent = text;
        frame.setAttribute('aria-label', '工作台栏位 ' + slotId + ' ' + text);
        return true;
    }

    function setTitle(title, subtitle) {
        this._title.textContent = title || '';
        this._subtitle.textContent = subtitle || '';
    }

    return {
        validProfiles: VALID_PROFILE_NAMES,
        requireProfile: requireProfile,
        setProfile: setProfile,
        setSlotLabel: setSlotLabel,
        setTitle: setTitle
    };
});
