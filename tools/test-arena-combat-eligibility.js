#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.resolve(__dirname, '..');
const readJson = file => JSON.parse(fs.readFileSync(path.join(ROOT, file), 'utf8'));
const units = readJson('data/units/units.json');
const byType = new Map(units.map(unit => ['兵种' + unit.id, unit]));
const meta = readJson('data/arena/meta_teams.json');
const generated = { window: {} };
vm.runInNewContext(fs.readFileSync(path.join(ROOT, 'launcher/web/modules/arena-meta-rosters.js'), 'utf8'), generated);
const web = generated.window.ArenaMetaRosters;
let passed = 0;
let failed = 0;

function test(name, run) {
    try {
        run();
        passed++;
        console.log('PASS ' + name);
    } catch (error) {
        failed++;
        console.error('FAIL ' + name + ': ' + error.message);
    }
}

const protectedType = type => !!(byType.get(type) && byType.get(type).NPC);
const protectedMember = member => protectedType(member.type)
    || !!((member.parameters || member.Parameters || {}).NPC);

test('Host faction/escalation source contains no protected NPC', () => {
    for (const [faction, roster] of Object.entries(meta.rosters)) {
        for (const unit of roster.units) {
            assert(!protectedMember(unit), faction + '/' + unit.type);
        }
    }
});

test('Web faction pools match the clean Host source', () => {
    assert.deepStrictEqual(JSON.parse(JSON.stringify(web.factions)), meta.rosters);
    for (const roster of Object.values(web.factions)) {
        assert(roster.units.every(unit => !protectedMember(unit)));
    }
});

test('story provenance retains all three protected sisters with their protection flag', () => {
    const teamId = '诺亚前线基地深处第二层/终结者占领的研究院.xml#9.0';
    for (const teams of [meta.teams, web.teams]) {
        const team = teams.find(item => item.id === teamId);
        assert(team, 'missing story team');
        assert.deepStrictEqual(Array.from(team.members, member => member.type), ['兵种218', '兵种219', '兵种220']);
        assert(team.members.every(member => member.npc === true), 'missing NPC protection metadata');
    }
});

test('every retained member projects its effective NPC protection', () => {
    for (const teams of [meta.teams, web.teams]) {
        for (const team of teams) {
            for (const member of team.members) {
                assert.strictEqual(member.npc === true, protectedMember(member), team.id + '/' + member.type);
            }
        }
    }
});

test('combat sisters and existing nonhostile combat candidates remain available', () => {
    const rockTypes = new Set(meta.rosters['摇滚公园'].units.map(unit => unit.type));
    for (const type of ['兵种50', '兵种51', '兵种52']) assert(rockTypes.has(type), type);
    const neutralCombat = meta.rosters['黑铁会'].units.find(unit => unit.type === '兵种90');
    assert(neutralCombat && neutralCombat.isHostile === false, 'nonhostile is not NPC protection');
    const calibrated = readJson('data/arena/arena_calibrated_rosters.json').rosters
        .find(roster => roster.id === 'roster-85b57b64c404023b');
    assert(calibrated && calibrated.members.every(member => !protectedMember(member)));
});

// Execute the production sampler with deterministic randomness. Only rendering
// and the transport are stubbed; team selection, expansion and filtering are real.
function sampler(catalog) {
    const state = {
        _knownEnemies: {}, _knownEnemyCount: 0,
        _snapshot: { arenaAuthority: { calibratedRosters: [] } },
        _activeCards: [{ id: 'eligibility-test', standardRole: 'monster', levelMin: 60, levelMax: 60, opponentCount: 1 }],
        _previewPending: {}, _pendingReq: {}, _cardKind: {}, _monsterSquad: {},
        _previewCache: {}, _previewError: {}, _cardEls: [], _selectedCardIdx: -1,
        _reqSeq: 0, _session: 1
    };
    const fixedMath = Object.create(Math);
    fixedMath.random = () => 0;
    const context = {
        window: { ArenaCore: { state }, ArenaMetaRosters: catalog },
        ArenaCore: { state }, Math: fixedMath,
        ArenaShell: { rostersAvailable: () => true },
        ArenaChallengeBrowser: {
            STANDARD_OPPONENT_CAP: 6, HIDDEN_MIXED_TEAM_MAX_UNITS: 8,
            renderCardSummary() {}, updateCardStates() {}
        },
        ArenaCustomEditor: {
            customHasParameters: value => !!value && Object.keys(value).length > 0,
            cloneCustomParameters: value => JSON.parse(JSON.stringify(value))
        },
        Bridge: { send() { throw new Error('unexpected mercenary transport'); } }
    };
    vm.runInNewContext(fs.readFileSync(path.join(ROOT, 'launcher/web/modules/arena/arena-preview-authority.js'), 'utf8'), context);
    const api = context.window.ArenaPreviewAuthority;
    api.setKnownEnemies(units.map(unit => unit.spritename));
    return { api, state };
}

function member(id, extra) {
    const unit = byType.get('兵种' + id);
    return Object.assign({ type: '兵种' + id, name: unit.name, spritename: unit.spritename,
        level: 60, count: 1, npc: !!unit.NPC }, extra);
}

function team(id, members) {
    return { id, sourceName: id, faction: '摇滚公园', levelMin: 60, levelMax: 60,
        avgLevel: 60, powerRating: members.length * 60, unitCount: members.length,
        distinctTypes: members.length, members };
}

test('known sprite never unlocks its protected NPC variant', () => {
    const { api } = sampler(web);
    const candidates = [member(218), member(219), member(220), member(50), member(51), member(52), member(93)];
    assert.deepStrictEqual(Array.from(api.filterKnownUnits(candidates), unit => unit.type),
        ['兵种50', '兵种51', '兵种52', '兵种93']);
});

test('standard monster cards reject protected source teams without deleting provenance', () => {
    const catalog = { factions: {}, mercenaries: [], teams: [
        team('protected-story', [member(218), member(219), member(220)]),
        team('combat', [member(50), member(51), member(52)])
    ] };
    const { api, state } = sampler(catalog);
    api.requestPreviewForCard(0);
    assert(state._monsterSquad[0]);
    assert(state._monsterSquad[0].opponents.every(unit => ['兵种50', '兵种51', '兵种52'].includes(unit.type)));
    assert.strictEqual(catalog.teams.length, 2, 'sampler must not mutate the source catalog');
});

test('mixed real-team fallback excludes protected nonhuman members', () => {
    const humanUnit = units.find(unit => /主角/.test(unit.spritename) && !unit.NPC);
    const human = member(humanUnit.id, { humanoid: true });
    const { api } = sampler({ factions: {}, mercenaries: [], teams: [
        team('protected-mixed', [human, member(218)]),
        team('combat-mixed', [human, member(50)])
    ] });
    const squad = api.sampleMixedSquadForTests({ levelMin: 60, levelMax: 60, opponentCount: 2 });
    assert(squad && squad.teamId === 'combat-mixed');
    assert(squad.opponents.every(unit => unit.type !== '兵种218'));
});

test('synthetic fallback cannot recycle a protected humanoid template', () => {
    const humanUnit = units.find(unit => /主角/.test(unit.spritename) && !unit.NPC);
    const human = member(humanUnit.id, { humanoid: true, npc: true });
    const monster = Object.assign(member(50), { minLevel: 60, maxLevel: 60, weight: 1 });
    const { api } = sampler({ factions: { test: { units: [monster] } }, mercenaries: [],
        teams: [team('protected-template', [human])] });
    assert.strictEqual(api.sampleSyntheticMixedSquadForTests({ levelMin: 60, levelMax: 60, opponentCount: 2 }), null);
});

console.log(`Arena combat eligibility: ${passed} passed, ${failed} failed.`);
if (failed) process.exitCode = 1;
