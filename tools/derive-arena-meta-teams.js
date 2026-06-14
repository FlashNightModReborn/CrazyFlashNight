#!/usr/bin/env node
'use strict';

// ════════════════════════════════════════════════════════════════════════════
// derive-arena-meta-teams.js  —  竞技场「元战队」目录派生器（Phase 1 / Reading A）
//
// 从真实关卡 XML（data/stages/**）抽取每个 SubStage 的敌人组合 = 一支「元战队」，
// 经 data/units/units.json 解析 兵种N → {名字, spritename, 等级, is_hostile}，
// 按敌人 spritename 家族打势力标签，算战力评分，输出 data/arena/meta_teams.json。
//
// 用途：
//   - Phase 1：混入标准模式抽取（按 powerRating + 等级带匹配卡片）提升新鲜感
//   - Phase 2：按 faction 过滤即得堕落城等势力 roster（同一份数据，零返工）
//
// 设计要点：
//   - 元战队单元 = 一个 SubStage 合并后的敌方阵容（一间「房」的真实组合，1~N 体）。
//     丢弃关卡专属的 x/y/SpawnIndex 站位（竞技场自行布阵）。
//   - 只收 is_hostile 的 兵种（NPC/友军 is_hostile=false 排除）。
//   - 所有关卡 兵种 走廉价 EnemyBehavior（非「使用人形怪AI」玩家模板）→ 天然是性能友好的非人形。
//   - faction 主信号 = 敌人 spritename 家族（敌人-盗贼* → 堕落城）；命不中规则 → unknown，
//     summary 列出所有未识别家族供人工补 FACTION_RULES。
//
// 运行：node tools/derive-arena-meta-teams.js [--check] [--granularity=subwave|substage]
//   --check：只校验+打摘要，不写文件（CI/复核用）
//   --granularity：元战队切分粒度。subwave(默认)=按 SubWave(设计师的一波同时刷怪，规模小、组合真实)；
//                  substage=按 SubStage 合并(整间房，规模大，更适合当 roster 采样源)
// ════════════════════════════════════════════════════════════════════════════

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const STAGES_DIR = path.join(ROOT, 'data', 'stages');
const UNITS_PATH = path.join(ROOT, 'data', 'units', 'units.json');
const OUT_PATH = path.join(ROOT, 'data', 'arena', 'meta_teams.json');
const WEB_MODULE_PATH = path.join(ROOT, 'launcher', 'web', 'modules', 'arena-meta-rosters.js');
const CHECK_ONLY = process.argv.indexOf('--check') !== -1;
const GRAN_ARG = (process.argv.find(a => a.indexOf('--granularity=') === 0) || '').split('=')[1];
const GRANULARITY = GRAN_ARG === 'substage' ? 'substage' : 'subwave';

// 跳过非关卡 XML
const SKIP_FILES = new Set(['list.xml', 'loading_data.xml']);
function isSkipped(name) {
    return SKIP_FILES.has(name) || name === '__list__.xml' || !name.toLowerCase().endsWith('.xml');
}

// 势力规则：按 spritename 子串投票（命中即归属，权重 = 该兵种在队伍里的 count）。
// 顺序敏感：先具体后宽泛。命不中 → unknown（summary 会列家族供补全）。
// ⚠ 自动初版，faction 命名待人工核 lore。规则按 spritename 子串投票，顺序敏感(先具体后宽泛)。
const FACTION_RULES = [
    { re: /盗贼/, faction: '堕落城' },
    { re: /贝斯|主唱|鼓手|吉他|键盘|摇滚/, faction: '摇滚公园' },
    { re: /军阀|游寇|革命军/, faction: '军阀势力' },
    { re: /黑铁/, faction: '黑铁会' },
    { re: /终结者|天网|机器人|机械|无人机|炮台|EXUSIAI|克隆/, faction: '天网' },
    { re: /凤凰眷属/, faction: '凤凰眷属' },
    { re: /方舟/, faction: '方舟' },
    { re: /异形|奇美拉|徘徊者|吐酸者|美洲狮|渗透者|原体融合/, faction: '异形' },
    { re: /日本/, faction: '日本军' },
    { re: /波斯/, faction: '波斯军' },
    { re: /斯巴达|罗马军团/, faction: '斯巴达' },
    { re: /不死/, faction: '不死军团' },
    { re: /忍者/, faction: '忍者' },
    { re: /僵尸|尸|亡灵|骷髅/, faction: '亡灵/僵尸' },
    { re: /基因虫|虫|寄生|孢子|母巢/, faction: '虫群' },
    { re: /狂野玫瑰|玫瑰|少女|萝莉|姑娘|女仆|护士/, faction: '狂野玫瑰' },
    { re: /雪女|霜精|冰/, faction: '雪山' },
    { re: /魔神|恶魔|魔女/, faction: '魔神' },
    { re: /大学|学生|教师|老师/, faction: '联合大学' },
    { re: /铁血/, faction: '铁血' }
];

// 玩家模板 sprite（主角-男/女）= 可能走「使用人形怪AI」的昂贵人形单位，
// 也违背「打非人形怪」主题 → 标记并从 roster 采样池剔除（仍保留在 teams[] 供溯源）。
function isHumanoidTemplate(spritename) {
    return /主角/.test(String(spritename || ''));
}

// 显示名兜底：部分单位 name 是占位「???」/空/null（多为 boss/未命名），回退用 spritename 家族，
// 避免预览里出现「???」。不是 faction 命名（那块待人工核 lore），只是展示名净化。
function cleanName(u) {
    var n = String(u.name || '');
    if (n === '' || n === '???' || n === 'null') return String(u.spritename || '').replace(/^敌人-/, '');
    return n;
}

function factionFor(spritename) {
    if (!spritename) return null;
    for (let i = 0; i < FACTION_RULES.length; i++) {
        if (FACTION_RULES[i].re.test(spritename)) return FACTION_RULES[i].faction;
    }
    return null;
}

// ── unit 注册表：兵种N → {id,name,spritename,level,is_hostile} ──
const units = JSON.parse(fs.readFileSync(UNITS_PATH, 'utf8'));
const byType = {};
for (let i = 0; i < units.length; i++) byType['兵种' + units[i].id] = units[i];

// ── 递归收集关卡文件 ──
function walk(dir, out) {
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    for (const e of entries) {
        const full = path.join(dir, e.name);
        if (e.isDirectory()) walk(full, out);
        else if (!isSkipped(e.name)) out.push(full);
    }
    return out;
}

// ── 极简关卡 XML 抽取（机器生成、结构规整，正则足够；只取 SubStage 分组 + Enemy 叶子）──
function tag1(xml, tag) {
    const m = xml.match(new RegExp('<' + tag + '>\\s*([\\s\\S]*?)\\s*</' + tag + '>'));
    return m ? m[1].trim() : null;
}
function splitSubStages(xml) {
    const re = /<SubStage\b[^>]*?(?:id=['"]?(\d+)['"]?)?[^>]*>/g;
    const marks = [];
    let m;
    while ((m = re.exec(xml))) marks.push({ id: m[1], start: m.index });
    const out = [];
    for (let i = 0; i < marks.length; i++) {
        const end = i + 1 < marks.length ? marks[i + 1].start : xml.length;
        out.push({ id: marks[i].id != null ? marks[i].id : String(i), body: xml.slice(marks[i].start, end) });
    }
    // 无 SubStage 包裹（极少数旧格式）→ 整文件当一个组
    if (out.length === 0) out.push({ id: '0', body: xml });
    return out;
}
function splitSubWaves(body) {
    const re = /<SubWave\b[^>]*?(?:id=['"]?(\d+)['"]?)?[^>]*>/g;
    const marks = [];
    let m;
    while ((m = re.exec(body))) marks.push({ id: m[1], start: m.index });
    const out = [];
    for (let i = 0; i < marks.length; i++) {
        const end = i + 1 < marks.length ? marks[i + 1].start : body.length;
        out.push({ id: marks[i].id != null ? marks[i].id : String(i), body: body.slice(marks[i].start, end) });
    }
    if (out.length === 0) out.push({ id: '0', body: body });
    return out;
}
function extractEnemies(body) {
    const re = /<Enemy\b[^>]*>([\s\S]*?)<\/Enemy>/g;
    const list = [];
    let m;
    while ((m = re.exec(body))) {
        const inner = m[1];
        const typeRaw = tag1(inner, 'Type');
        if (!typeRaw) continue;
        // Type 可能是 <CaseSwitch> 随机型：抽出所有 Case 候选 兵种N
        let types;
        if (/<CaseSwitch/i.test(typeRaw)) {
            types = [];
            const cre = /<Case\b[^>]*>\s*(兵种\d+)\s*<\/Case>/g;
            let cm;
            while ((cm = cre.exec(typeRaw))) types.push(cm[1]);
            if (types.length === 0) continue;
        } else {
            const t = typeRaw.trim();
            if (!/^兵种\d+$/.test(t)) continue; // 非规范 Type（如纯 boss 标记）跳过
            types = [t];
        }
        const lvl = Number(tag1(inner, 'Level'));
        const qty = Number(tag1(inner, 'Quantity'));
        list.push({ types: types, random: types.length > 1, level: isNaN(lvl) ? null : lvl, quantity: isNaN(qty) ? 1 : qty });
    }
    return list;
}

// ── 主流程 ──
const files = walk(STAGES_DIR, []);
const teams = [];
const unresolved = {};        // 兵种N → 出现次数（units.json 查不到）
const familyTally = {};       // spritename 家族（敌人-X 第一段）→ 次数
const factionTally = {};
let stageWithTeams = 0;

function sumCount(members) {
    let s = 0;
    for (const m of members) s += m.count;
    return s;
}

// 从一个「组」(SubWave 或 SubStage) body 构建一支元战队（或 null）
function buildTeam(rel, stageName, groupId, body) {
    const enemies = extractEnemies(body);
    if (enemies.length === 0) return null;

    const merged = {}; // repType@level(#r) -> member
    for (const en of enemies) {
        // 代表兵种 = 第一个可解析的候选（随机型取首个能查到的）
        let rep = null, repType = null;
        for (const t of en.types) { if (byType[t]) { rep = byType[t]; repType = t; break; } }
        if (!rep) { for (const t of en.types) unresolved[t] = (unresolved[t] || 0) + 1; continue; }
        if (rep.is_hostile === false) continue; // NPC/友军不入元战队
        const fam = String(rep.spritename || '').replace(/^敌人-/, '');
        familyTally[fam] = (familyTally[fam] || 0) + en.quantity;
        const lvl = en.level != null ? en.level : (Number(rep.level) || 1);
        const key = repType + '@' + lvl + (en.random ? '#r' : '');
        if (!merged[key]) merged[key] = {
            type: repType, id: rep.id, name: cleanName(rep), spritename: rep.spritename,
            level: lvl, count: 0, random: !!en.random,
            humanoid: isHumanoidTemplate(rep.spritename),
            randomTypes: en.random ? en.types.slice() : undefined
        };
        merged[key].count += en.quantity;
    }
    const members = [];
    for (const k in merged) members.push(merged[k]);
    if (members.length === 0) return null;

    // 势力投票（按 count 加权 spritename 命中）
    const fvote = {};
    for (const mem of members) {
        const f = factionFor(mem.spritename);
        if (f) fvote[f] = (fvote[f] || 0) + mem.count;
    }
    let faction = 'unknown', best = 0;
    for (const f in fvote) if (fvote[f] > best) { best = fvote[f]; faction = f; }
    const conf = faction === 'unknown' ? 'unknown'
        : (best / Math.max(1, sumCount(members)) >= 0.6 ? 'rule' : 'rule-weak');

    let unitCount = 0, levelSum = 0, levelMin = Infinity, levelMax = -Infinity, power = 0;
    for (const mem of members) {
        unitCount += mem.count;
        levelSum += mem.level * mem.count;
        power += mem.level * mem.count; // 初版战力代理 = Σ count×level（看分布后再细化）
        if (mem.level < levelMin) levelMin = mem.level;
        if (mem.level > levelMax) levelMax = mem.level;
    }
    return {
        id: rel + '#' + groupId, sourceStage: rel, sourceName: stageName, group: groupId,
        faction: faction, factionConfidence: conf, members: members,
        unitCount: unitCount, distinctTypes: members.length,
        avgLevel: Math.round((levelSum / unitCount) * 10) / 10,
        levelMin: levelMin, levelMax: levelMax, powerRating: power
    };
}

for (const file of files) {
    const rel = path.relative(STAGES_DIR, file).replace(/\\/g, '/');
    const stageName = path.basename(file, '.xml');
    let xml;
    try { xml = fs.readFileSync(file, 'utf8'); } catch (e) { continue; }
    if (xml.indexOf('<Enemy') === -1) continue;

    let producedForStage = false;
    for (const sub of splitSubStages(xml)) {
        // 粒度：subwave=每波一队（规模小、真实组合）；substage=整间房合并（roster 源）
        const groups = (GRANULARITY === 'substage')
            ? [{ id: sub.id, body: sub.body }]
            : splitSubWaves(sub.body).map(sw => ({ id: sub.id + '.' + sw.id, body: sw.body }));
        for (const g of groups) {
            const team = buildTeam(rel, stageName, g.id, g.body);
            if (!team) continue;
            teams.push(team);
            factionTally[team.faction] = (factionTally[team.faction] || 0) + 1;
            producedForStage = true;
        }
    }
    if (producedForStage) stageWithTeams++;
}

// ── 输出 ──
// 势力 roster 聚合：faction → 该势力全部 兵种 的 {等级区间, 权重=总出现 count}。
// 这是「按等级带采样 K 体」(M2 消费模型) 的直接来源；teams[] 保留逐波原始组合(provenance / Phase2 真实小队)。
const rosters = {};
for (const t of teams) {
    if (t.faction === 'unknown') continue;
    if (!rosters[t.faction]) rosters[t.faction] = { teamCount: 0, units: {} };
    rosters[t.faction].teamCount++;
    for (const m of t.members) {
        if (m.humanoid) continue; // 人形模板单位不入采样池（性能 + 非人形主题）
        const u = rosters[t.faction].units[m.type] ||
            (rosters[t.faction].units[m.type] = { type: m.type, name: m.name, spritename: m.spritename, minLevel: Infinity, maxLevel: -Infinity, weight: 0 });
        if (m.level < u.minLevel) u.minLevel = m.level;
        if (m.level > u.maxLevel) u.maxLevel = m.level;
        u.weight += m.count;
    }
}
for (const f in rosters) {
    const arr = [];
    for (const k in rosters[f].units) arr.push(rosters[f].units[k]);
    arr.sort((a, b) => b.weight - a.weight);
    rosters[f].unitCount = arr.length;
    rosters[f].units = arr;
}

const catalog = {
    generatedBy: 'tools/derive-arena-meta-teams.js',
    granularity: GRANULARITY,
    note: '竞技场元战队目录。teams[]=逐组真实组合(provenance/真实小队); rosters{}=按势力聚合的兵种池(按等级带采样K体用)。请勿手改——改采集规则后重跑。',
    stageFilesScanned: files.length,
    stagesWithTeams: stageWithTeams,
    teamCount: teams.length,
    factionBreakdown: factionTally,
    rosters: rosters,
    teams: teams
};

// ── 摘要 ──
function dist(arr, buckets) {
    const out = {};
    for (const b of buckets) out[b.label] = 0;
    for (const v of arr) for (const b of buckets) if (v >= b.min && v <= b.max) { out[b.label]++; break; }
    return out;
}
console.log('=== 元战队采集摘要 ===');
console.log('扫描关卡文件: ' + files.length + '  含敌人产出队伍的关卡: ' + stageWithTeams + '  元战队总数: ' + teams.length);
console.log('\n-- 势力分布 --');
Object.keys(factionTally).sort((a, b) => factionTally[b] - factionTally[a]).forEach(f => console.log('  ' + f + ': ' + factionTally[f]));
console.log('\n-- 队伍规模分布(unitCount) --');
console.log('  ' + JSON.stringify(dist(teams.map(t => t.unitCount), [
    { label: '1', min: 1, max: 1 }, { label: '2-3', min: 2, max: 3 }, { label: '4-6', min: 4, max: 6 }, { label: '7+', min: 7, max: 999 }])));
console.log('\n-- 平均等级分布 --');
console.log('  ' + JSON.stringify(dist(teams.map(t => t.avgLevel), [
    { label: '1-10', min: 1, max: 10 }, { label: '11-20', min: 11, max: 20 }, { label: '21-40', min: 21, max: 40 }, { label: '41-60', min: 41, max: 60 }, { label: '60+', min: 61, max: 9999 }])));
const unresolvedKeys = Object.keys(unresolved);
console.log('\n-- 未解析兵种(units.json 查无): ' + unresolvedKeys.length + ' 种 --');
if (unresolvedKeys.length) console.log('  ' + unresolvedKeys.slice(0, 30).join(', ') + (unresolvedKeys.length > 30 ? ' …' : ''));
const unknownFams = {};
teams.filter(t => t.faction === 'unknown').forEach(t => t.members.forEach(m => { const fam = String(m.spritename || '').replace(/^敌人-/, ''); unknownFams[fam] = (unknownFams[fam] || 0) + 1; }));
const unknownFamKeys = Object.keys(unknownFams).sort((a, b) => unknownFams[b] - unknownFams[a]);
console.log('\n-- 未识别势力的敌人家族(待补 FACTION_RULES): ' + unknownFamKeys.length + ' --');
console.log('  ' + unknownFamKeys.slice(0, 40).join(' | '));
console.log('\n-- 堕落城 元战队样例(前 5) --');
teams.filter(t => t.faction === '堕落城').slice(0, 5).forEach(t => {
    console.log('  [' + t.id + '] Lv' + t.levelMin + '-' + t.levelMax + ' x' + t.unitCount + ' pw=' + t.powerRating + ' :: ' +
        t.members.map(m => m.name + '(' + m.spritename.replace('敌人-', '') + ')×' + m.count).join(', '));
});

if (!CHECK_ONLY) {
    fs.writeFileSync(OUT_PATH, JSON.stringify(catalog, null, 2), 'utf8');
    // web 消费用的瘦身 roster 模块（arena-panel.js M2 采样直读；不含 teams[] 溯源数据）
    var webModule =
        '// AUTO-GENERATED by tools/derive-arena-meta-teams.js — 请勿手改，改采集规则后重跑。\n' +
        '// 竞技场堕落/元战队 roster：按势力聚合的非人形怪池（已剔人形模板），arena-panel.js M2 采样消费。\n' +
        '(function () {\n' +
        '    if (typeof window === "undefined") return;\n' +
        '    window.ArenaMetaRosters = ' + JSON.stringify({ granularity: GRANULARITY, factions: rosters }) + ';\n' +
        '})();\n';
    fs.writeFileSync(WEB_MODULE_PATH, webModule, 'utf8');
    console.log('\n[写出] ' + path.relative(ROOT, OUT_PATH) + '  +  ' + path.relative(ROOT, WEB_MODULE_PATH));
} else {
    console.log('\n[--check] 仅校验，未写文件');
}
