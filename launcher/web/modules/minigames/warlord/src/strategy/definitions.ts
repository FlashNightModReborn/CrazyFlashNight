declare const opaqueIdBrand: unique symbol;

export type OpaqueId<TKind extends string> = string & {
  readonly [opaqueIdBrand]: TKind;
};

export type MapId = OpaqueId<'map'>;
export type NodeId = OpaqueId<'node'>;
export type EdgeId = OpaqueId<'edge'>;
export type EncounterDefinitionId = OpaqueId<'encounter-definition'>;
export type EncounterProfileId = OpaqueId<'encounter-profile'>;
export type ScenarioId = OpaqueId<'scenario'>;
export type FactionId = OpaqueId<'faction'>;
export type OrganizationId = OpaqueId<'organization'>;
export type FormationProfileId = OpaqueId<'formation-profile'>;
export type TaskGroupTemplateId = OpaqueId<'task-group-template'>;

export type OneOrMany<T> = T | readonly T[];

export interface MapNodeAuthoringV1 {
  readonly id: string;
  readonly kind: string;
  readonly garrisonCapacity: number;
  readonly attackWidth: number;
  readonly defenseBonus: number;
  readonly nodeAPBonus?: number;
  readonly encounterProfileRef: string;
}

export interface MapEdgeAuthoringV1 {
  readonly id: string;
  readonly a: string;
  readonly b: string;
}

export interface MapDefinitionAuthoringV1 {
  readonly schemaVersion: 1;
  readonly id: string;
  readonly rulesVersion: string;
  readonly encounterDefinitionRef: string;
  readonly nodes: OneOrMany<MapNodeAuthoringV1>;
  readonly edges: OneOrMany<MapEdgeAuthoringV1>;
}

export type EncounterDistanceBand = 'near' | 'medium' | 'far';

export interface EncounterProfileAuthoringV1 {
  readonly id: string;
  readonly distanceBand: EncounterDistanceBand;
  readonly spawnDistance: number;
}

export interface EncounterDefinitionAuthoringV1 {
  readonly schemaVersion: 1;
  readonly id: string;
  readonly rulesVersion: string;
  readonly profiles: OneOrMany<EncounterProfileAuthoringV1>;
}

export interface EncounterProfileDefinitionV1 {
  readonly id: EncounterProfileId;
  readonly distanceBand: EncounterDistanceBand;
  readonly spawnDistance: number;
}

export interface EncounterDefinitionV1 {
  readonly schemaVersion: 1;
  readonly id: EncounterDefinitionId;
  readonly rulesVersion: string;
  readonly profiles: readonly EncounterProfileDefinitionV1[];
}

export interface EncounterDefinitionBindingV1 {
  readonly definition: EncounterDefinitionV1;
  readonly configDigest: string;
}

export interface MapNodeDefinition {
  readonly id: NodeId;
  readonly kind: string;
  readonly garrisonCapacity: number;
  readonly attackWidth: number;
  readonly defenseBonus: number;
  readonly nodeAPBonus: number;
  readonly encounterProfileRef: EncounterProfileId;
  readonly distanceBand: EncounterDistanceBand;
  readonly spawnDistance: number;
}

export interface MapEdgeDefinition {
  readonly id: EdgeId;
  readonly a: NodeId;
  readonly b: NodeId;
}

export interface MapDefinition {
  readonly schemaVersion: 1;
  readonly id: MapId;
  readonly rulesVersion: string;
  readonly encounterDefinitionRef: EncounterDefinitionId;
  readonly encounterConfigDigest: string;
  readonly nodes: readonly MapNodeDefinition[];
  readonly edges: readonly MapEdgeDefinition[];
}

export interface MapNodePresentationV1 {
  readonly nodeRef: string;
  readonly x: number;
  readonly y: number;
  readonly visualAnchor?: string;
  readonly landmarkAssetRef?: string;
}

export interface MapPresentationDefinitionV1 {
  readonly schemaVersion: 1;
  readonly id: string;
  readonly mapRef: string;
  readonly themeRef: string;
  readonly nodes: OneOrMany<MapNodePresentationV1>;
}

export interface ScenarioFactionAuthoringV1 {
  readonly id: string;
  readonly displayName: string;
  readonly controller: 'player' | 'ai';
  readonly headquartersNodeRef: string;
  readonly supplyNodeRef: string;
}

export interface ScenarioNodeRuleAuthoringV1 {
  readonly nodeRef: string;
  readonly displayName: string;
  readonly strategicValue: number;
  readonly goldIncome: number;
  readonly population: number;
  readonly productionSlots: number;
}

export interface ScenarioNodeControlAuthoringV1 {
  readonly nodeRef: string;
  readonly factionRef: string;
}

export interface ScenarioDeploymentAuthoringV1 {
  readonly nodeRef: string;
  readonly factionRef: string;
  readonly cardIds: OneOrMany<number>;
}

export interface WarlordScenarioAuthoringV1 {
  readonly schemaVersion: 1;
  readonly id: string;
  readonly rulesVersion: string;
  readonly mapRef: string;
  readonly mapPresentationRef: string;
  readonly playerFactionRef: string;
  readonly turnOrder: OneOrMany<string>;
  readonly factions: OneOrMany<ScenarioFactionAuthoringV1>;
  readonly nodeRules: OneOrMany<ScenarioNodeRuleAuthoringV1>;
  readonly initialState: {
    readonly nodeControls: OneOrMany<ScenarioNodeControlAuthoringV1>;
    readonly standardDeployments: OneOrMany<ScenarioDeploymentAuthoringV1>;
    readonly allUnitsDeployments: OneOrMany<ScenarioDeploymentAuthoringV1>;
  };
}

export interface ScenarioFactionDefinitionV1 {
  readonly id: FactionId;
  readonly displayName: string;
  readonly controller: 'player' | 'ai';
  readonly headquartersNodeRef: NodeId;
  readonly supplyNodeRef: NodeId;
}

export interface ScenarioNodeRuleDefinitionV1 {
  readonly nodeRef: NodeId;
  readonly displayName: string;
  readonly strategicValue: number;
  readonly goldIncome: number;
  readonly population: number;
  readonly productionSlots: number;
}

export interface ScenarioNodeControlDefinitionV1 {
  readonly nodeRef: NodeId;
  readonly factionRef: FactionId;
}

export interface ScenarioDeploymentDefinitionV1 {
  readonly nodeRef: NodeId;
  readonly factionRef: FactionId;
  readonly cardIds: readonly number[];
}

export interface WarlordScenarioDefinitionV1 {
  readonly schemaVersion: 1;
  readonly id: ScenarioId;
  readonly rulesVersion: string;
  readonly mapRef: MapId;
  readonly mapPresentationRef: string;
  readonly playerFactionRef: FactionId;
  readonly turnOrder: readonly FactionId[];
  readonly factions: readonly ScenarioFactionDefinitionV1[];
  readonly nodeRules: readonly ScenarioNodeRuleDefinitionV1[];
  readonly initialState: {
    readonly nodeControls: readonly ScenarioNodeControlDefinitionV1[];
    readonly standardDeployments: readonly ScenarioDeploymentDefinitionV1[];
    readonly allUnitsDeployments: readonly ScenarioDeploymentDefinitionV1[];
  };
}

/** Shared semantic IDs from the Arena formation contract. No pixel coordinates belong here. */
export type ArenaFormationId = 'line' | 'column' | 'wedge' | 'shield' | 'grid';
export type FormationSlotRole = 'vanguard' | 'flank' | 'fire_support' | 'reserve';

export interface FormationProfileAuthoringV1 {
  readonly id: string;
  readonly displayName: string;
  readonly arenaFormationRef: ArenaFormationId;
  readonly slotRoles: OneOrMany<FormationSlotRole>;
}

export interface UnitTemplateMetricsAuthoringV1 {
  readonly cardRef: number;
  readonly commandLoad: number;
  readonly deploymentSize: number;
  readonly encounterCost: number;
  readonly apContribution: number;
}

export interface TaskGroupTemplateAuthoringV1 {
  readonly id: string;
  readonly displayName: string;
  readonly minimumMembers: number;
  readonly maximumMembers: number;
  readonly commandLoadDivisor: number;
  readonly formationProfileRefs: OneOrMany<string>;
}

export interface OrganizationDefinitionAuthoringV1 {
  readonly schemaVersion: 1;
  readonly id: string;
  readonly rulesVersion: string;
  readonly defaultFormationProfileRef: string;
  readonly unitTemplates: OneOrMany<UnitTemplateMetricsAuthoringV1>;
  readonly taskGroupTemplates: OneOrMany<TaskGroupTemplateAuthoringV1>;
  readonly formationProfiles: OneOrMany<FormationProfileAuthoringV1>;
}

export interface FormationProfileDefinitionV1 {
  readonly id: FormationProfileId;
  readonly displayName: string;
  readonly arenaFormationRef: ArenaFormationId;
  readonly slotRoles: readonly FormationSlotRole[];
}

export interface UnitTemplateMetricsDefinitionV1 {
  readonly cardRef: number;
  readonly commandLoad: number;
  readonly deploymentSize: number;
  readonly encounterCost: number;
  readonly apContribution: number;
}

export interface TaskGroupTemplateDefinitionV1 {
  readonly id: TaskGroupTemplateId;
  readonly displayName: string;
  readonly minimumMembers: number;
  readonly maximumMembers: number;
  readonly commandLoadDivisor: number;
  readonly formationProfileRefs: readonly FormationProfileId[];
}

export interface OrganizationDefinitionV1 {
  readonly schemaVersion: 1;
  readonly id: OrganizationId;
  readonly rulesVersion: string;
  readonly defaultFormationProfileRef: FormationProfileId;
  readonly unitTemplates: readonly UnitTemplateMetricsDefinitionV1[];
  readonly taskGroupTemplates: readonly TaskGroupTemplateDefinitionV1[];
  readonly formationProfiles: readonly FormationProfileDefinitionV1[];
}

export type StrategyValidationReasonCode =
  | 'invalid_type'
  | 'unexpected_field'
  | 'unsupported_schema_version'
  | 'invalid_opaque_id'
  | 'invalid_text'
  | 'invalid_number'
  | 'duplicate_id'
  | 'duplicate_edge'
  | 'unknown_reference'
  | 'self_loop'
  | 'attack_width_exceeds_garrison_capacity'
  | 'map_empty'
  | 'map_disconnected'
  | 'coverage_mismatch'
  | 'turn_order_mismatch'
  | 'player_faction_mismatch'
  | 'node_control_conflict'
  | 'deployment_faction_mismatch';

export interface StrategyValidationIssue {
  readonly reasonCode: StrategyValidationReasonCode;
  readonly path: string;
  readonly params: Readonly<Record<string, unknown>>;
}

export type MapValidationResult =
  | {
    readonly ok: true;
    readonly definition: MapDefinition;
    readonly issues: readonly [];
  }
  | {
    readonly ok: false;
    readonly issues: readonly StrategyValidationIssue[];
  };

export type ScenarioValidationResult =
  | {
    readonly ok: true;
    readonly definition: WarlordScenarioDefinitionV1;
    readonly issues: readonly [];
  }
  | {
    readonly ok: false;
    readonly issues: readonly StrategyValidationIssue[];
  };

export type OrganizationValidationResult =
  | {
    readonly ok: true;
    readonly definition: OrganizationDefinitionV1;
    readonly issues: readonly [];
  }
  | {
    readonly ok: false;
    readonly issues: readonly StrategyValidationIssue[];
  };

export type EncounterValidationResult =
  | {
    readonly ok: true;
    readonly definition: EncounterDefinitionV1;
    readonly issues: readonly [];
  }
  | {
    readonly ok: false;
    readonly issues: readonly StrategyValidationIssue[];
  };
