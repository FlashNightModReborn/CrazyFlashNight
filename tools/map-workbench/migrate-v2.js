#!/usr/bin/env node
'use strict';
// 一次性迁移：从第一阶段冻结树机械提取旧规则/布局。不是日常生成器，不覆盖作者后续创作。
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const cp = require('child_process');
const root = path.resolve(__dirname, '../..');
const sourceCommit = '3ac9227cbdfdeb6d73f99e408414b03bfc338b5d';
function source(file) { return cp.execFileSync('git', ['show', sourceCommit + ':' + file], { cwd: root, encoding: 'utf8', maxBuffer: 4 * 1024 * 1024 }).replace(/^\uFEFF/, ''); }
function need(ok, message) { if (!ok) throw new Error(message); }
function stable(prefix, value) { return prefix + crypto.createHash('sha256').update(value).digest('hex').slice(0, 16); }
const always = () => ({ type: 'always' });
function combine(type, children) {
    if (type === 'all') children = children.filter(c => c.type !== 'always');
    return children.length === 0 ? always() : children.length === 1 ? children[0] : { type, children };
}
function parseExpression(text, chainNames) {
    const tokens = text.match(/\(|\)|&&|\|\||>=|!=|[A-Za-z_][A-Za-z0-9_]*(?:\.[^\s()&|]+)?|[0-9]+/g) || [];
    need(tokens.join('') === text.replace(/\s+/g, ''), '旧解锁表达式含未支持语法：' + text);
    let position = 0;
    function atom() {
        let token = tokens[position++];
        if (token === '(') { const result = either(); need(tokens[position++] === ')', '旧解锁表达式括号不匹配'); return result; }
        if (token === 'true') return always();
        if (tokens[position] === '!=') {
            need((token === 'infra' || chainNames[token]) && tokens[++position] === 'undefined', '未支持的旧存在性检查');
            position++; return always();
        }
        if (chainNames[token]) {
            need(tokens[position++] === '>=' && /^[0-9]+$/.test(tokens[position]), '旧链进度条件不正确');
            return { type: 'chain', key: chainNames[token], min: Number(tokens[position++]) };
        }
        if (token && token.startsWith('infra.')) return { type: 'infra', key: token.slice(6), min: 1 };
        throw new Error('未识别的旧条件词：' + token);
    }
    function both() { const out = [atom()]; while (tokens[position] === '&&') { position++; out.push(atom()); } return combine('all', out); }
    function either() { const out = [both()]; while (tokens[position] === '||') { position++; out.push(both()); } return combine('any', out); }
    const value = either(); need(position === tokens.length, '旧条件存在未消费内容'); return value;
}
function build() {
    const definition = JSON.parse(source('data/map/map_definition.json'));
    need(definition.version === 1, '迁移基线必须是第一阶段定义');
    const registry = JSON.parse(source('data/map/task_npc_registry.json'));
    const sceneRouter = source('scripts/逻辑/关卡系统/关卡系统_lsy_场景转换.as');
    const outdoorPrefix = sceneRouter.match(/关卡标志\.indexOf\("([^"]+)"\)\s*===\s*0\s*\?\s*"外部地图"\s*:\s*"基地地图"/);
    need(outdoorPrefix, '实际场景类型路由不再匹配，须先人工审查迁移器');
    const service = source('scripts/类定义/org/flashNight/arki/map/MapPanelService.as');
    const sourceMethod = service.slice(service.indexOf('private static function isUnlocked('), service.indexOf('private static function buildUnlockFlags('));
    const method = sourceMethod.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\r\n]*/g, '');
    const chainNames = {};
    for (const match of method.matchAll(/var\s+(p_[a-z]+)\s*=\s*[^;]*progress\.([^\s;:]+)\s*:\s*undefined/g)) chainNames[match[1]] = match[2];
    need(Object.keys(chainNames).length > 0, '旧任务链变量映射缺失');
    const rules = {}, vectors = [];
    for (const [key, meta] of Object.entries(definition.unlockGroups)) {
        const match = method.match(new RegExp('case "' + key + '":([\\s\\S]*?)(?=case |default:)'));
        need(match, '旧解锁分组缺失：' + key);
        const body = match[1];
        const branches = [];
        const early = body.match(/if\s*\(([^;]+)\)\s*return true;/);
        if (early) branches.push(parseExpression(early[1], chainNames));
        const remaining = early ? body.replace(early[0], '') : body;
        const fallback = remaining.match(/return\s+([^;]+);/);
        need(fallback, '旧解锁分组无返回表达式：' + key);
        branches.push(parseExpression(fallback[1], chainNames));
        rules['unlock.' + key] = { label: meta.label, tone: key, condition: combine('any', branches) };
        vectors.push({ group: key, sourceExpression: body.trim(), condition: rules['unlock.' + key].condition });
    }
    const xml = source('data/map/map_panel.xml');
    const avatarRules = {};
    for (const match of xml.matchAll(/<rule\s+([^>]+)\/>/g)) {
        const values = {};
        for (const attr of match[1].matchAll(/([A-Za-z]+)="([^"]*)"/g)) values[attr[1]] = attr[2];
        need(values.avatarId && values.npc && ((values.chain && values.min) || values.requireInfra), '旧头像条件不完整');
        const nodes = [];
        if (values.chain) { need(/^[0-9]+$/.test(values.min), '旧头像最小进度无效'); nodes.push({ type: 'chain', key: values.chain, min: Number(values.min) }); }
        if (values.requireInfra) nodes.push(combine('any', values.requireInfra.split('|').map(key => ({ type: 'infra', key, min: 1 }))));
        (avatarRules[values.avatarId] ||= []).push(combine('all', nodes));
    }
    const npcs = {}, placements = {}, locations = {};
    const byAvatar = new Map();
    for (const item of registry.task_npcs) {
        const npcId = stable('npc_', item.name), placementId = stable('place_', item.placement);
        npcs[npcId] ||= { label: item.name, runtimeNames: [item.name], aliases: [], placementPolicy: 'multiple' };
        need(!placements[placementId] && !byAvatar.has(item.avatarId), '旧人物驻点重复');
        placements[placementId] = { npcId, locationId: item.hotspot, label: item.name, enabled: true,
            presenceWhen: combine('all', avatarRules[item.avatarId] || []), worldBinding: null, legacyWorldAdapter: true };
        byAvatar.set(item.avatarId, placementId);
    }
    for (const alias of registry.aliases) {
        const npc = npcs[stable('npc_', alias.canonical)]; need(npc, '旧人物别名缺少目标'); npc.aliases.push(alias.name);
    }
    for (const pageId of definition.pageOrder) {
        const page = definition.pages[pageId], mapping = definition.pageUnlockGroups[pageId] || {};
        page.visibleWhen = always();
        page.tone = pageId === 'school' ? 'schoolOutside' : pageId === 'defense' ? 'defense' : 'base';
        for (const hotspot of page.hotspots) {
            const group = (mapping.hotspots || {})[hotspot.id];
            locations[hotspot.id] = { label: hotspot.label, sceneName: hotspot.sceneName, sceneKind: hotspot.sceneName.startsWith(outdoorPrefix[1]) ? 'outdoor' : 'base',
                enabled: true, enterWhen: group ? { type: 'rule', key: 'unlock.' + group } : always(), visibleWhen: group ? { type: 'rule', key: 'unlock.' + group } : always(), tone: group || 'base' };
            hotspot.locationId = hotspot.id; delete hotspot.sceneName;
        }
        for (const filter of page.filters) filter.tone = (mapping.filters || {})[filter.id] || page.tone;
        // 冻结旧 renderer 的 base/hierarchy 角色，运行期只读此字段，不保留页面 ID 判断。
        if (pageId === 'base') for (const filter of page.filters) if (filter.id === 'hierarchy') filter.viewMode = 'hierarchy';
        // 旧玩家界面隐藏未开放地点/整页；把这个既有展示条件显式落入可见规则，避免新旧 visible/enter 混为一谈。
        const pageConditions = [...new Set(page.hotspots.map(h => (mapping.hotspots || {})[h.id] || ''))];
        page.visibleWhen = pageConditions.includes('') ? always() : combine('any', pageConditions.map(group => ({ type: 'rule', key: 'unlock.' + group })));
        for (const slot of [...page.staticAvatars, ...(page.dynamicAvatars || [])]) {
            need(byAvatar.has(slot.id), '头像未命中旧驻点目录：' + slot.id);
            slot.placementId = byAvatar.get(slot.id); slot.visibleWhen = always();
            if (page.staticAvatars.includes(slot)) {
                const source = Object.values(definition.avatarSources).filter(entry => entry.assetUrl === slot.assetUrl).at(-1); need(source, '头像来源缺失：' + slot.id);
                slot.relX ??= source.relX; slot.relY ??= source.relY; slot.w ??= source.size.w; slot.h ??= source.size.h;
                slot.assetUrl = source.assetUrl || slot.assetUrl;
            }
        }
    }
    definition.version = 2;
    definition.rules = rules; definition.locations = locations; definition.npcs = npcs; definition.placements = placements;
    definition.assets = {};
    delete definition.unlockGroups; delete definition.pageUnlockGroups;
    return { definition, evidence: { sourceCommit, sourceMethodSha256: crypto.createHash('sha256').update(sourceMethod).digest('hex'),
        sceneRouterSha256: crypto.createHash('sha256').update(sceneRouter).digest('hex'), sceneKindSource: 'published scene router prefix, not visual page membership',
        ruleCount: Object.keys(rules).length, avatarRuleCount: Object.values(avatarRules).reduce((n, a) => n + a.length, 0), vectors } };
}
if (require.main === module) {
    const result = build();
    const applying = process.argv.includes('--apply'), preparing = applying || process.argv.includes('--prepared');
    if (preparing) {
        const dotnet = process.env.CF7_DOTNET_EXE || cp.execFileSync('powershell.exe', ['-NoProfile', '-Command', '. ./launcher/resolve-dotnet.ps1; Resolve-Cf7Dotnet -ProjectRoot (Get-Location).Path'], { cwd: root, encoding: 'utf8' }).trim();
        const cli = path.join(__dirname, 'bin/Release/net10.0/MapWorkbench.dll');
        const prepared = cp.spawnSync(dotnet, [cli, 'prepare-definition', root], { cwd: root, input: JSON.stringify(result.definition), encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 });
        const response = JSON.parse(prepared.stdout || '{}'); need(prepared.status === 0 && response.success, response.error || prepared.stderr || 'C# 迁移准备失败');
        result.definition = response.definition; result.evidence.runtimeSourceCount = response.runtimeSourceCount;
    }
    if (applying) need(fs.readFileSync(path.join(root, 'data/map/map_definition.json'), 'utf8') === source('data/map/map_definition.json'), '当前地图已变化，不能覆盖；请先核对第一阶段基线');
    const output = applying ? path.join(root, 'data/map/map_definition.json') : path.join(root, 'tmp/map-workbench/map-definition.' + (preparing ? 'prepared-' : '') + 'v2.json');
    fs.mkdirSync(path.dirname(output), { recursive: true });
    fs.writeFileSync(output, JSON.stringify(result.definition, null, 2) + '\n', 'utf8');
    const evidence = path.join(root, 'tmp/map-workbench/migration-v2-evidence.json');
    fs.mkdirSync(path.dirname(evidence), { recursive: true }); fs.writeFileSync(evidence, JSON.stringify(result.evidence, null, 2) + '\n', 'utf8');
    console.log(JSON.stringify({ output, evidence, locations: Object.keys(result.definition.locations).length, npcs: Object.keys(result.definition.npcs).length,
        placements: Object.keys(result.definition.placements).length, rules: result.evidence.ruleCount, avatarRules: result.evidence.avatarRuleCount }));
}
module.exports = { build, parseExpression };
