import assert from 'node:assert/strict';
import test from 'node:test';
import {
  closeHelpUi,
  createHelpUiState,
  HELP_PROFILE,
  openHelpUi,
} from '../src/app/help-profile.js';
import {
  ALL_VALIDATION_REASON_CODES,
  PLAYER_TERMINOLOGY_VERSION,
  PLAYER_TEXT_SCHEMA_VERSION,
  playerTextForReason,
} from '../src/app/player-text-catalog.js';
import { applyCommand } from '../src/core/engine.js';
import { requireFaction } from '../src/core/factions.js';
import { piecesAtNode } from '../src/core/selectors.js';
import { createGame } from '../src/core/state.js';
import type { ValidationReasonCode } from '../src/core/types.js';
import { validateCommand } from '../src/core/validator.js';

const EXPECTED_REASON_CODES: readonly ValidationReasonCode[] = [
  'game_over',
  'action_phase_required',
  'active_faction_mismatch',
  'node_unknown',
  'origin_equals_target',
  'target_not_adjacent',
  'allied_transit_invalid',
  'allied_destination_forbidden',
  'neutral_attack_forbidden',
  'hostile_garrison_ambiguous',
  'selection_empty',
  'selection_duplicate',
  'piece_unavailable',
  'piece_wrong_faction',
  'piece_wrong_origin',
  'mixed_garrison_state',
  'attack_width_exceeded',
  'assault_reentry_locked',
  'action_points_insufficient',
  'garrison_capacity_full',
  'command_element_partial_selection',
  'reorganization_selection_invalid',
  'reorganization_wrong_node',
  'task_group_template_mismatch',
  'formation_unknown',
  'formation_mix_unsupported',
  'planning_phase_required',
  'planning_already_committed',
  'xp_amount_invalid',
  'xp_insufficient',
  'card_unknown',
  'promotion_already_purchased_this_round',
  'promotion_complete',
  'promotion_sequence_required',
  'card_level_insufficient',
  'military_funds_insufficient',
  'production_node_invalid',
  'production_node_unavailable',
  'production_slot_missing',
  'population_capacity_insufficient',
  'production_order_missing',
  'production_order_mismatch',
  'production_order_locked',
  'production_reservation_invalid',
  'faction_unknown',
  'faction_defeated',
  'commander_unknown',
  'commander_state_invalid',
  'command_post_required',
];

test('PHASE-A-PLAYER-TEXT catalog covers every stable validator reason with player guidance', () => {
  assert.equal(PLAYER_TEXT_SCHEMA_VERSION, 'warlord.player-text-catalog.v1');
  assert.equal(PLAYER_TERMINOLOGY_VERSION, HELP_PROFILE.terminologyVersion);
  assert.deepEqual(new Set(ALL_VALIDATION_REASON_CODES), new Set(EXPECTED_REASON_CODES));
  assert.equal(ALL_VALIDATION_REASON_CODES.length, new Set(ALL_VALIDATION_REASON_CODES).size);

  const params = {
    selected: 5,
    maximum: 2,
    required: 8,
    available: 3,
    requiredLevel: 10,
    nodeName: '北部关口',
    promotionName: '战术强化',
  };
  const anchors = new Set(HELP_PROFILE.sections.map((section) => section.anchor));
  const helpVisibleCopy = HELP_PROFILE.sections.flatMap((section) => [
    section.title,
    section.summary,
    ...section.details,
  ]);
  for (const copy of helpVisibleCopy) {
    assert.equal(/[A-Za-z]/.test(copy), false, `help copy must not leak Latin engineering terms: ${copy}`);
  }
  for (const reasonCode of ALL_VALIDATION_REASON_CODES) {
    const text = playerTextForReason(reasonCode, params);
    assert.match(text.reason, /[\u3400-\u9fff]/, `${reasonCode} reason must be Chinese player copy`);
    assert.match(text.nextStep, /[\u3400-\u9fff]/, `${reasonCode} next step must be Chinese player copy`);
    assert.equal(anchors.has(text.helpAnchor), true, `${reasonCode} help anchor must exist`);
    assert.equal(text.assistiveText, `${text.reason} ${text.nextStep}`);
    assert.equal(text.assistiveText.includes(reasonCode), false);
    assert.equal(/\b(?:AP|AUTO|EXACT|AS2|Launcher|WebGL|fixture)\b/.test(text.assistiveText), false);
    assert.equal(/[A-Za-z]/.test(text.assistiveText), false, `${reasonCode} player guidance must not contain Latin text`);
  }
});

test('PHASE-A-PLAYER-TEXT validator and engine propagate stable reason data', () => {
  const state = createGame({ seed: 'player-text-reason-propagation' });
  const command = {
    type: 'MOVE_OR_ATTACK' as const,
    factionId: 'red' as const,
    pieceIds: [] as string[],
    originNodeId: 'R-HQ' as const,
    targetNodeId: 'R-Economy' as const,
  };
  const validation = validateCommand(state, command);
  assert.equal(validation.ok, false);
  assert.equal(validation.reasonCode, 'selection_empty');
  assert.deepEqual(validation.reasonParams, {});

  const result = applyCommand(state, command);
  assert.equal(result.ok, false);
  assert.equal(result.reasonCode, validation.reasonCode);
  assert.deepEqual(result.reasonParams, validation.reasonParams);
  assert.equal(typeof result.error === 'string', true, 'legacy error remains technical compatibility only');

  const selected = piecesAtNode(state, 'R-HQ', 'red')[0];
  assert.ok(selected);
  requireFaction(state, 'red').actionPoints = 0;
  const noActionPoints = validateCommand(state, { ...command, pieceIds: [selected.pieceId] });
  assert.equal(noActionPoints.reasonCode, 'action_points_insufficient');
  assert.deepEqual(noActionPoints.reasonParams, { required: 1, available: 0 });
  assert.match(playerTextForReason(noActionPoints.reasonCode, noActionPoints.reasonParams).assistiveText, /行动点不足.*请减少/);
});

test('PHASE-A-HELP opening, navigation and closing do not mutate game, selection or camera state', () => {
  const preserved = {
    game: createGame({ seed: 'help-state-preservation' }),
    selectedNodeId: 'R-HQ',
    selectedPieceIds: ['red-card-14-1'],
    camera: { centerX: 1.25, centerZ: -0.5, zoomPercent: 125 },
  };
  const before = structuredClone(preserved);
  let help = createHelpUiState();
  help = openHelpUi(help, 'movement');
  assert.deepEqual(help, { open: true, anchor: 'movement' });
  help = openHelpUi(help, 'action-points');
  assert.deepEqual(help, { open: true, anchor: 'action-points' });
  help = closeHelpUi(help);
  assert.deepEqual(help, { open: false, anchor: 'action-points' });
  assert.deepEqual(preserved, before);
});
