/** 建角与整形共享身份控件；只编辑草稿，不发送请求或决定性别切换的业务规则。 */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.CharacterIdentityControls = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';
    function prefix(value) {
        if (!/^[a-z][a-z0-9-]*$/.test(value)) throw new Error('Invalid identity control prefix');
        return value;
    }
    function nameMarkup(id, helpButton) {
        id = prefix(id);
        return '<label class="cc-field cc-primary-name identity-field"><span>角色名 '
            + (helpButton ? '<button type="button" class="cc-help" id="' + id + '-help-character" aria-label="说明角色名">?</button>' : '')
            + '</span><input id="' + id + '-character-name" name="characterName" autocomplete="off" aria-describedby="'
            + id + '-character-help ' + id + '-error-characterName">'
            + '<small id="' + id + '-character-help">这是游戏内最主要的姓名，最多 15 个字符。</small>'
            + '<em id="' + id + '-error-characterName" class="cc-error identity-error"></em></label>';
    }
    function genderMarkup(id) {
        id = prefix(id);
        return '<fieldset class="cc-field cc-gender identity-gender"><legend>性别</legend>'
            + '<label><input type="radio" name="' + id + '-gender" value="male" checked><span>男性</span></label>'
            + '<label><input type="radio" name="' + id + '-gender" value="female"><span>女性</span></label></fieldset>';
    }
    function heightMarkup(id, hidden, stepLabel) {
        id = prefix(id);
        return '<label id="' + id + '-preview-height-control" class="cc-preview-height identity-height"'
            + (hidden ? ' hidden' : '') + '><span id="' + id + '-height-label">身高</span>'
            + '<span class="cc-height-range"><input id="' + id + '-height" type="range" min="150" max="200" step="1" aria-labelledby="'
            + (stepLabel ? prefix(stepLabel) + ' ' : '') + id + '-height-label" aria-describedby="' + id + '-height-value">'
            + '<output id="' + id + '-height-value" for="' + id + '-height">—</output></span></label>';
    }
    function bindNameInput(input, options) {
        var composing = false;
        function start() { composing = true; if (options.onComposition) options.onComposition(true); }
        function change() { if (options.onChange) options.onChange(input.value); }
        function end() { composing = false; if (options.onComposition) options.onComposition(false); change(); }
        function key(event) {
            if (event.key !== 'Enter') return;
            event.preventDefault();
            if (composing || event.isComposing || event.keyCode === 229) return;
            if (options.onEnter) options.onEnter();
        }
        input.addEventListener('compositionstart', start);
        input.addEventListener('compositionend', end);
        input.addEventListener('input', change);
        input.addEventListener('keydown', key);
        return function() {
            input.removeEventListener('compositionstart', start);
            input.removeEventListener('compositionend', end);
            input.removeEventListener('input', change);
            input.removeEventListener('keydown', key);
        };
    }
    function bindGender(inputs, onChange) {
        var listeners = Array.prototype.map.call(inputs, function(input) {
            function change() { if (input.checked) onChange(input.value); }
            input.addEventListener('change', change);
            return function() { input.removeEventListener('change', change); };
        });
        return function() { listeners.forEach(function(dispose) { dispose(); }); };
    }
    function bindHeight(input, onChange) {
        function change() { onChange(Number(input.value)); }
        input.addEventListener('input', change);
        return function() { input.removeEventListener('input', change); };
    }
    function characterNameError(value) {
        if (typeof value !== 'string' || value.length < 1 || value.length > 15 || !value.trim())
            return '角色名需为 1–15 个字符，且不能包含控制字符。';
        for (var i = 0; i < value.length; i++) {
            var n = value.charCodeAt(i);
            if (n < 32 || (n >= 127 && n <= 159)) return '角色名需为 1–15 个字符，且不能包含控制字符。';
        }
        return '';
    }
    function validateProfile(value) {
        var errors = {};
        value = value || {};
        var nameError = characterNameError(value.characterName);
        if (nameError) errors.characterName = nameError;
        if (value.gender !== 'male' && value.gender !== 'female') errors.gender = '请选择角色性别。';
        if (!Number.isInteger(value.height) || value.height < 150 || value.height > 200) errors.height = '身高必须在 150–200 厘米之间。';
        return errors;
    }
    function previewScale(height) { return 0.9 + (Number(height) - 150) / 250; }
    return {nameMarkup:nameMarkup, genderMarkup:genderMarkup, heightMarkup:heightMarkup,
        bindNameInput:bindNameInput, bindGender:bindGender, bindHeight:bindHeight,
        characterNameError:characterNameError, validateProfile:validateProfile, previewScale:previewScale};
});
