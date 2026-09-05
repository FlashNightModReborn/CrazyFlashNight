import {
  DEMO_1_ORGANIZATION,
  ORGANIZATION_CONFIG_DIGEST,
  formationProfile,
  taskGroupTemplate,
  unitTemplateMetrics,
} from '../data/organization.js';
import type { ArenaFormationId } from '../strategy/definitions.js';
import type {
  CommandElementState,
  FactionId,
  GameState,
  NodeId,
  OrganizationRuntimeState,
  PieceState,
} from './types.js';

export interface OrganizationMetrics {
  commandLoad: number;
  deploymentSize: number;
  encounterCost: number;
  apContribution: number;
  memberCount: number;
}

export interface OrganizationAuditIssue {
  code: string;
  detail: string;
}

export function createOrganizationRuntimeState(): OrganizationRuntimeState {
  return {
    definitionId: DEMO_1_ORGANIZATION.id,
    rulesVersion: DEMO_1_ORGANIZATION.rulesVersion,
    configDigest: ORGANIZATION_CONFIG_DIGEST,
    nextCommandElementOrdinal: 0,
    commandElements: {},
    memberToElementId: {},
  };
}

function nextElementId(state: GameState, factionId: FactionId): string {
  state.organization.nextCommandElementOrdinal += 1;
  return `ce-${factionId}-${state.organization.nextCommandElementOrdinal}`;
}

function canonicalMemberIds(memberIds: readonly string[]): string[] {
  return [...memberIds].sort((left, right) => left.localeCompare(right));
}

function createElementInPlace(
  state: GameState,
  input: Omit<CommandElementState, 'elementId'> & { elementId?: string },
): CommandElementState {
  const elementId = input.elementId ?? nextElementId(state, input.factionId);
  if (state.organization.commandElements[elementId]) {
    throw new Error(`Command element identity collision: ${elementId}.`);
  }
  const memberIds = canonicalMemberIds(input.memberIds);
  const element: CommandElementState = {
    elementId,
    kind: input.kind,
    factionId: input.factionId,
    nodeId: input.nodeId,
    memberIds,
    formationProfileId: input.formationProfileId,
    taskGroupTemplateId: input.taskGroupTemplateId,
    createdRound: input.createdRound,
    reorganizedAtCommand: input.reorganizedAtCommand,
  };
  state.organization.commandElements[elementId] = element;
  for (const memberId of memberIds) {
    if (state.organization.memberToElementId[memberId]) {
      throw new Error(`Organization member already assigned: ${memberId}.`);
    }
    state.organization.memberToElementId[memberId] = elementId;
  }
  return element;
}

export function registerOrganizationMemberInPlace(state: GameState, piece: PieceState): CommandElementState {
  return createElementInPlace(state, {
    kind: 'singleton',
    factionId: piece.factionId,
    nodeId: piece.nodeId,
    memberIds: [piece.pieceId],
    formationProfileId: DEMO_1_ORGANIZATION.defaultFormationProfileRef as ArenaFormationId,
    taskGroupTemplateId: null,
    createdRound: state.strategicRound,
    reorganizedAtCommand: state.commandSequence,
  });
}

export function commandElementForMember(
  state: GameState,
  memberId: string,
): CommandElementState | null {
  const elementId = state.organization.memberToElementId[memberId];
  return elementId ? state.organization.commandElements[elementId] ?? null : null;
}

export function commandElementsAtNode(
  state: GameState,
  nodeId: NodeId,
  factionId?: FactionId,
): CommandElementState[] {
  return Object.values(state.organization.commandElements)
    .filter((element) => element.nodeId === nodeId && (!factionId || element.factionId === factionId))
    .sort((left, right) => left.elementId.localeCompare(right.elementId));
}

export function commandElementFormationProfileIds(
  elements: readonly CommandElementState[],
): ArenaFormationId[] {
  return [...new Set(elements.map((element) => element.formationProfileId))]
    .sort((left, right) => left.localeCompare(right));
}

export function unitMetricsForMember(state: GameState, memberId: string): OrganizationMetrics {
  const piece = state.pieces[memberId];
  if (!piece) throw new Error(`Missing organization member ${memberId}.`);
  const metrics = unitTemplateMetrics(piece.cardId);
  return {
    commandLoad: metrics.commandLoad,
    deploymentSize: metrics.deploymentSize,
    encounterCost: metrics.encounterCost,
    apContribution: metrics.apContribution,
    memberCount: 1,
  };
}

export function commandElementMetrics(
  state: GameState,
  element: CommandElementState,
): OrganizationMetrics {
  const total = element.memberIds.reduce<OrganizationMetrics>((sum, memberId) => {
    const metrics = unitMetricsForMember(state, memberId);
    return {
      commandLoad: sum.commandLoad + metrics.commandLoad,
      deploymentSize: sum.deploymentSize + metrics.deploymentSize,
      encounterCost: sum.encounterCost + metrics.encounterCost,
      apContribution: sum.apContribution + metrics.apContribution,
      memberCount: sum.memberCount + 1,
    };
  }, { commandLoad: 0, deploymentSize: 0, encounterCost: 0, apContribution: 0, memberCount: 0 });
  if (element.kind === 'task_group' && element.taskGroupTemplateId) {
    const template = taskGroupTemplate(element.taskGroupTemplateId);
    total.commandLoad = Math.max(1, Math.ceil(total.commandLoad / template.commandLoadDivisor));
  }
  return total;
}

export function selectedCommandElements(
  state: GameState,
  memberIds: readonly string[],
): { elements: CommandElementState[]; complete: boolean } {
  const selected = new Set(memberIds);
  const elementIds: string[] = [];
  const seenElements = new Set<string>();
  for (const memberId of memberIds) {
    const elementId = state.organization.memberToElementId[memberId];
    if (!elementId || seenElements.has(elementId)) continue;
    seenElements.add(elementId);
    elementIds.push(elementId);
  }
  const elements = elementIds
    .map((elementId) => state.organization.commandElements[elementId])
    .filter((element): element is CommandElementState => element !== undefined);
  const complete = elements.every((element) => element.memberIds.every((memberId) => selected.has(memberId)));
  return { elements, complete };
}

export function selectionOrganizationMetrics(
  state: GameState,
  memberIds: readonly string[],
): OrganizationMetrics {
  const resolved = selectedCommandElements(state, memberIds);
  if (!resolved.complete) throw new Error('Cannot calculate command metrics for a partial CommandElement selection.');
  return resolved.elements.reduce<OrganizationMetrics>((sum, element) => {
    const metrics = commandElementMetrics(state, element);
    return {
      commandLoad: sum.commandLoad + metrics.commandLoad,
      deploymentSize: sum.deploymentSize + metrics.deploymentSize,
      encounterCost: sum.encounterCost + metrics.encounterCost,
      apContribution: sum.apContribution + metrics.apContribution,
      memberCount: sum.memberCount + metrics.memberCount,
    };
  }, { commandLoad: 0, deploymentSize: 0, encounterCost: 0, apContribution: 0, memberCount: 0 });
}

export function nodeDeploymentSize(state: GameState, nodeId: NodeId): number {
  const node = state.map.nodes[nodeId];
  if (!node) return 0;
  return node.pieceIds.reduce((sum, memberId) => (
    sum + unitMetricsForMember(state, memberId).deploymentSize
  ), 0);
}

export function deploymentSizeForCard(cardId: PieceState['cardId']): number {
  return unitTemplateMetrics(cardId).deploymentSize;
}

export function memberApContribution(state: GameState, memberId: string): number {
  return unitMetricsForMember(state, memberId).apContribution;
}

export function prefixMembersWithinDeployment(
  state: GameState,
  memberIds: readonly string[],
  availableDeploymentSize: number,
): string[] {
  const { elements, complete } = selectedCommandElements(state, memberIds);
  if (!complete) return [];
  const accepted: string[] = [];
  let remaining = Math.max(0, availableDeploymentSize);
  for (const element of elements) {
    const size = commandElementMetrics(state, element).deploymentSize;
    if (size > remaining) break;
    accepted.push(...element.memberIds);
    remaining -= size;
  }
  return accepted;
}

export function mergeTaskGroupInPlace(
  state: GameState,
  elementIds: readonly string[],
  taskGroupTemplateId: string,
  formationProfileId: ArenaFormationId,
): CommandElementState {
  const elements = elementIds.map((elementId) => state.organization.commandElements[elementId]);
  if (elements.some((element) => !element)) throw new Error('Validated command element disappeared before merge.');
  const present = elements as CommandElementState[];
  const first = present[0];
  if (!first) throw new Error('Validated merge has no command elements.');
  const members = canonicalMemberIds(present.flatMap((element) => element.memberIds));
  for (const element of present) {
    delete state.organization.commandElements[element.elementId];
    for (const memberId of element.memberIds) delete state.organization.memberToElementId[memberId];
  }
  return createElementInPlace(state, {
    kind: 'task_group',
    factionId: first.factionId,
    nodeId: first.nodeId,
    memberIds: members,
    formationProfileId,
    taskGroupTemplateId,
    createdRound: state.strategicRound,
    reorganizedAtCommand: state.commandSequence,
  });
}

export function splitTaskGroupInPlace(
  state: GameState,
  elementId: string,
  extractedMemberIds: readonly string[],
): { remaining: CommandElementState | null; extracted: CommandElementState[] } {
  const element = state.organization.commandElements[elementId];
  if (!element) throw new Error('Validated command element disappeared before split.');
  const extractedSet = new Set(extractedMemberIds);
  const extractedIds = element.memberIds.filter((memberId) => extractedSet.has(memberId));
  const remainingIds = element.memberIds.filter((memberId) => !extractedSet.has(memberId));
  for (const memberId of element.memberIds) delete state.organization.memberToElementId[memberId];
  delete state.organization.commandElements[elementId];

  let remaining: CommandElementState | null = null;
  if (remainingIds.length > 0) {
    remaining = createElementInPlace(state, {
      elementId,
      kind: remainingIds.length === 1 ? 'singleton' : 'task_group',
      factionId: element.factionId,
      nodeId: element.nodeId,
      memberIds: remainingIds,
      formationProfileId: remainingIds.length === 1
        ? DEMO_1_ORGANIZATION.defaultFormationProfileRef as ArenaFormationId
        : element.formationProfileId,
      taskGroupTemplateId: remainingIds.length === 1 ? null : element.taskGroupTemplateId,
      createdRound: element.createdRound,
      reorganizedAtCommand: state.commandSequence,
    });
  }
  const extracted = extractedIds.map((memberId) => createElementInPlace(state, {
    kind: 'singleton',
    factionId: element.factionId,
    nodeId: element.nodeId,
    memberIds: [memberId],
    formationProfileId: DEMO_1_ORGANIZATION.defaultFormationProfileRef as ArenaFormationId,
    taskGroupTemplateId: null,
    createdRound: state.strategicRound,
    reorganizedAtCommand: state.commandSequence,
  }));
  return { remaining, extracted };
}

export function setFormationInPlace(
  state: GameState,
  elementId: string,
  formationProfileId: ArenaFormationId,
): void {
  formationProfile(formationProfileId);
  const element = state.organization.commandElements[elementId];
  if (!element) throw new Error('Validated command element disappeared before formation change.');
  element.formationProfileId = formationProfileId;
  element.reorganizedAtCommand = state.commandSequence;
}

export function removeOrganizationMemberInPlace(state: GameState, memberId: string): void {
  const elementId = state.organization.memberToElementId[memberId];
  delete state.organization.memberToElementId[memberId];
  if (!elementId) return;
  const element = state.organization.commandElements[elementId];
  if (!element) return;
  element.memberIds = element.memberIds.filter((candidate) => candidate !== memberId);
  if (element.memberIds.length === 0) {
    delete state.organization.commandElements[elementId];
    return;
  }
  if (element.memberIds.length === 1) {
    element.kind = 'singleton';
    element.taskGroupTemplateId = null;
    element.formationProfileId = DEMO_1_ORGANIZATION.defaultFormationProfileRef as ArenaFormationId;
  }
}

export function syncCommandElementLocationsInPlace(
  state: GameState,
  memberIds: readonly string[],
): void {
  const elementIds = new Set(memberIds
    .map((memberId) => state.organization.memberToElementId[memberId])
    .filter((elementId): elementId is string => elementId !== undefined));
  for (const elementId of elementIds) {
    const element = state.organization.commandElements[elementId];
    if (!element) continue;
    const memberNodes = element.memberIds.map((memberId) => state.pieces[memberId]?.nodeId);
    const firstNode = memberNodes[0];
    if (!firstNode || memberNodes.some((nodeId) => nodeId !== firstNode)) {
      throw new Error(`CommandElement ${elementId} members diverged across nodes.`);
    }
    element.nodeId = firstNode;
  }
}

export function auditOrganizationState(state: GameState): OrganizationAuditIssue[] {
  const issues: OrganizationAuditIssue[] = [];
  const seenMembers = new Set<string>();
  for (const element of Object.values(state.organization.commandElements)) {
    if (element.memberIds.length === 0) {
      issues.push({ code: 'empty_element', detail: element.elementId });
      continue;
    }
    if (new Set(element.memberIds).size !== element.memberIds.length) {
      issues.push({ code: 'duplicate_member_in_element', detail: element.elementId });
    }
    for (const memberId of element.memberIds) {
      const piece = state.pieces[memberId];
      if (!piece || piece.hp <= 0) issues.push({ code: 'missing_living_member', detail: memberId });
      if (seenMembers.has(memberId)) issues.push({ code: 'member_in_multiple_elements', detail: memberId });
      seenMembers.add(memberId);
      if (state.organization.memberToElementId[memberId] !== element.elementId) {
        issues.push({ code: 'reverse_index_mismatch', detail: memberId });
      }
      if (piece && (piece.factionId !== element.factionId || piece.nodeId !== element.nodeId)) {
        issues.push({ code: 'element_identity_mismatch', detail: memberId });
      }
    }
    if (element.kind === 'singleton' && element.memberIds.length !== 1) {
      issues.push({ code: 'singleton_member_count', detail: element.elementId });
    }
    if (element.kind === 'task_group' && !element.taskGroupTemplateId) {
      issues.push({ code: 'task_group_template_missing', detail: element.elementId });
    }
  }
  for (const piece of Object.values(state.pieces)) {
    if (piece.hp > 0 && !seenMembers.has(piece.pieceId)) {
      issues.push({ code: 'living_member_unassigned', detail: piece.pieceId });
    }
  }
  for (const [memberId, elementId] of Object.entries(state.organization.memberToElementId)) {
    if (!state.pieces[memberId] || !state.organization.commandElements[elementId]) {
      issues.push({ code: 'dangling_reverse_index', detail: memberId });
    }
  }
  return issues.sort((left, right) => (
    left.code.localeCompare(right.code) || left.detail.localeCompare(right.detail)
  ));
}
