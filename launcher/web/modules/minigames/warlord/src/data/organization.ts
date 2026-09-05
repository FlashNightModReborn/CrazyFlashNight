import type {
  FormationProfileDefinitionV1,
  FormationProfileId,
  OrganizationDefinitionAuthoringV1,
  OrganizationDefinitionV1,
  TaskGroupTemplateDefinitionV1,
  TaskGroupTemplateId,
  UnitTemplateMetricsDefinitionV1,
} from '../strategy/definitions.js';
import { validateOrganizationDefinition } from '../strategy/organization.js';
import type { CardId } from '../core/types.js';

export const ORGANIZATION_CONFIG_DIGEST = 'sha256:7FBBFE6B24592A7356B6AC9CACB14D49803FBA2214D8A9FFBD71599211114DA3';

export const DEMO_1_ORGANIZATION_AUTHORING = {
  schemaVersion: 1,
  id: 'demo1-organizations',
  rulesVersion: 'warlord.organization.v1',
  defaultFormationProfileRef: 'line',
  unitTemplates: [
    { cardRef: 12, commandLoad: 1, deploymentSize: 1, encounterCost: 1, apContribution: 1 },
    { cardRef: 13, commandLoad: 1, deploymentSize: 1, encounterCost: 1, apContribution: 1 },
    { cardRef: 14, commandLoad: 1, deploymentSize: 1, encounterCost: 1, apContribution: 1 },
    { cardRef: 15, commandLoad: 1, deploymentSize: 1, encounterCost: 2, apContribution: 1 },
    { cardRef: 82, commandLoad: 1, deploymentSize: 1, encounterCost: 2, apContribution: 1 },
    { cardRef: 83, commandLoad: 1, deploymentSize: 1, encounterCost: 2, apContribution: 1 },
    { cardRef: 84, commandLoad: 1, deploymentSize: 1, encounterCost: 2, apContribution: 1 },
    { cardRef: 85, commandLoad: 1, deploymentSize: 1, encounterCost: 3, apContribution: 1 },
    { cardRef: 111, commandLoad: 1, deploymentSize: 1, encounterCost: 2, apContribution: 1 },
    { cardRef: 112, commandLoad: 1, deploymentSize: 1, encounterCost: 2, apContribution: 1 },
    { cardRef: 113, commandLoad: 1, deploymentSize: 1, encounterCost: 3, apContribution: 1 },
  ],
  taskGroupTemplates: [{
    id: 'demo1.mixed-detachment',
    displayName: '混成任务编组',
    minimumMembers: 2,
    maximumMembers: 4,
    commandLoadDivisor: 1,
    formationProfileRefs: ['line', 'column', 'wedge', 'shield', 'grid'],
  }],
  formationProfiles: [
    { id: 'line', displayName: '横列', arenaFormationRef: 'line', slotRoles: ['vanguard', 'flank', 'fire_support', 'reserve'] },
    { id: 'column', displayName: '纵队', arenaFormationRef: 'column', slotRoles: ['vanguard', 'reserve', 'fire_support', 'flank'] },
    { id: 'wedge', displayName: '楔形', arenaFormationRef: 'wedge', slotRoles: ['vanguard', 'flank', 'flank', 'fire_support', 'reserve'] },
    { id: 'shield', displayName: '前盾后排', arenaFormationRef: 'shield', slotRoles: ['vanguard', 'vanguard', 'fire_support', 'reserve'] },
    { id: 'grid', displayName: '网格散点', arenaFormationRef: 'grid', slotRoles: ['vanguard', 'flank', 'fire_support', 'reserve'] },
  ],
} as const satisfies OrganizationDefinitionAuthoringV1;

const validation = validateOrganizationDefinition(DEMO_1_ORGANIZATION_AUTHORING);
if (!validation.ok) {
  throw new Error(`[warlord-organization:invalid_definition] ${JSON.stringify(validation.issues)}`);
}

export const DEMO_1_ORGANIZATION: OrganizationDefinitionV1 = validation.definition;

export function unitTemplateMetrics(cardId: CardId): UnitTemplateMetricsDefinitionV1 {
  const definition = DEMO_1_ORGANIZATION.unitTemplates.find((entry) => entry.cardRef === cardId);
  if (!definition) throw new Error(`Missing organization unit template for card ${cardId}.`);
  return definition;
}

export function formationProfile(profileId: FormationProfileId | string): FormationProfileDefinitionV1 {
  const definition = DEMO_1_ORGANIZATION.formationProfiles.find((entry) => entry.id === profileId);
  if (!definition) throw new Error(`Unknown formation profile ${profileId}.`);
  return definition;
}

export function taskGroupTemplate(
  templateId: TaskGroupTemplateId | string,
): TaskGroupTemplateDefinitionV1 {
  const definition = DEMO_1_ORGANIZATION.taskGroupTemplates.find((entry) => entry.id === templateId);
  if (!definition) throw new Error(`Unknown task-group template ${templateId}.`);
  return definition;
}
