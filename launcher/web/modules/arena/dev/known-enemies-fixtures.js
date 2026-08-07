/**
 * Arena QA — knownEnemies fixture 工厂（P1b）
 *
 * 背景：snapshot.knownEnemies = AS2 killStats.byType 的 spritename 列表，
 * 经 arena-panel.js setKnownEnemies → _knownEnemies/_knownEnemyCount，
 * 决定堕落/爬升 tab 是否渲染（modeAvailable 要求 _knownEnemyCount > 0 且
 * buildFallenCards().length > 0），并按势力过滤可出卡单位（filterKnownUnits）。
 *
 * 本文件只提供「注入哪些 spritename」的可复用变体，不复制任何单位数据——
 * 唯一数据源始终是 window.ArenaMetaRosters（arena-meta-rosters.js 派生 JSON），
 * fixture 在调用时现取，数据重派生后自动跟随。
 *
 * 变体：
 *   all()              全量已知：全部势力 roster 的去重 spritename（当前 173 个）
 *                      → 堕落/爬升各出 18 张卡（联合大学/斯巴达总单位数 < FALLEN_MIN_UNITS=4 被滤）。
 *   partial()          部分已知：波斯军 roster 的 6 个 spritename。
 *                      注意跨势力 sprite 污染（2026-08 数据现状，登记为债）：
 *                      这 6 个 spritename 同时散落其他势力 roster，实际出卡 6 张——
 *                      波斯军(6/6)、不死军团(5/5)、方舟(4/66)、亡灵/僵尸(1/185)、天网(2/125)、忍者(3/37)。
 *   none()             全未知：[] → _knownEnemyCount=0 → 堕落/爬升 tab 结构性缺席，
 *                      标准模式回退全 merc（隐藏警报卡进「混编情报不足」失败态）。
 *   forFactions(names) 自定义：按势力名收集 spritename（用于定向覆盖）。
 */
window.ArenaQaKnownFixtures = (function() {
    'use strict';

    function factionRosters() {
        return (typeof window !== 'undefined' && window.ArenaMetaRosters && window.ArenaMetaRosters.factions) || {};
    }

    function forFactions(names) {
        var rosters = factionRosters();
        var seen = {};
        var out = [];
        (names || []).forEach(function(name) {
            var faction = rosters[name];
            var units = faction && faction.units || [];
            for (var i = 0; i < units.length; i++) {
                var sprite = units[i] && units[i].spritename;
                if (!sprite || seen[sprite]) continue;
                seen[sprite] = true;
                out.push(sprite);
            }
        });
        return out;
    }

    function all() {
        var names = [];
        for (var key in factionRosters()) names.push(key);
        return forFactions(names);
    }

    function partial() {
        return forFactions(['波斯军']);
    }

    function none() {
        return [];
    }

    return {
        all: all,
        partial: partial,
        none: none,
        forFactions: forFactions
    };
})();
