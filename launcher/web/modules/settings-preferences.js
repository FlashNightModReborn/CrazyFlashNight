/** 现役 Web Panel 本机偏好的集中目录；读写仍使用各消费者既有 localStorage key。 */
(function(root, factory) {
    'use strict';
    var api = factory(root && root.localStorage);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.SettingsPreferences = api;
})(typeof window !== 'undefined' ? window : globalThis, function(defaultStorage) {
    'use strict';

    var DEFINITIONS = [
        {key:'cf7.skills.loadoutConfirmationMode', group:'交互确认', label:'技能装配确认', values:['safe','fast'], fallback:'safe'},
        {key:'cf7.equipmentTuning.modConfirmationMode', group:'交互确认', label:'配件调制确认', values:['safe','fast'], fallback:'safe'},
        {key:'cf7.dialogueMode', group:'呈现', label:'任务对话呈现', values:['rich','brief'], fallback:'rich'},
        {key:'cf7-jukebox-theme', group:'呈现', label:'点歌器主题', values:['green','amber'], fallback:'green'},
        {key:'cf7.itemgrid.mode.workbench', group:'物品密度', label:'背包/战备箱', values:['full','compact'], fallback:'compact'},
        {key:'cf7.itemgrid.mode.crafting-materials', group:'物品密度', label:'合成材料', values:['full','compact'], fallback:'compact'},
        {key:'cf7.itemgrid.mode.crafting-recipes', group:'物品密度', label:'合成配方', values:['full','compact'], fallback:'full'},
        {key:'cf7.itemgrid.mode.arena', group:'物品密度', label:'竞技场目录', values:['full','compact'], fallback:'compact'},
        {key:'cf7.itemgrid.mode.kshop', group:'物品密度', label:'K 商店', values:['full','compact'], fallback:'compact'},
        {key:'cf7.itemgrid.mode.npcshop', group:'物品密度', label:'NPC 商店', values:['full','compact'], fallback:'compact'},
        {key:'cf7.itemgrid.mode.skills', group:'物品密度', label:'技能', values:['full','compact'], fallback:'compact'},
        {key:'cf7.itemgrid.mode.team-merc', group:'物品密度', label:'佣兵队伍', values:['full','compact'], fallback:'compact'},
        {key:'cf7.itemgrid.mode.team-pet', group:'物品密度', label:'战宠队伍', values:['full','compact'], fallback:'compact'},
        {key:'cf7.gobang.audio.muted', group:'小游戏', label:'五子棋音轨', values:['0','1'], fallback:'0'}
    ];

    function cloneDefinition(row) {
        return {key:row.key, group:row.group, label:row.label,
            values:row.values.slice(), fallback:row.fallback};
    }

    function find(key) {
        for (var i = 0; i < DEFINITIONS.length; i++) {
            if (DEFINITIONS[i].key === key) return DEFINITIONS[i];
        }
        return null;
    }

    function read(key, storage) {
        var definition = find(key);
        if (!definition) return null;
        var value = null;
        try { value = (storage || defaultStorage).getItem(key); } catch (_) {}
        return definition.values.indexOf(value) >= 0 ? value : definition.fallback;
    }

    function write(key, value, storage) {
        var definition = find(key);
        if (!definition || definition.values.indexOf(value) < 0) return false;
        try {
            (storage || defaultStorage).setItem(key, value);
            return true;
        } catch (_) { return false; }
    }

    function list(storage) {
        var rows = [];
        for (var i = 0; i < DEFINITIONS.length; i++) {
            var row = cloneDefinition(DEFINITIONS[i]);
            row.value = read(row.key, storage);
            rows.push(row);
        }
        return rows;
    }

    function reset(key, storage) {
        var definition = find(key);
        if (!definition) return false;
        try {
            (storage || defaultStorage).removeItem(key);
            return true;
        } catch (_) { return false; }
    }

    return {definitions:function() { return DEFINITIONS.map(cloneDefinition); },
        read:read, write:write, list:list, reset:reset};
});
