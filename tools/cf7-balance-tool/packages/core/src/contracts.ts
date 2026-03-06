export interface BalanceProjectConfig {
  version: string;
  dataDirs: {
    items: string;
    mods?: string;
    enemies?: string;
  };
  fieldConfig?: string;
}

export interface FieldRegistry {
  numericFields: string[];
  numericSuffixes: string[];
  stringFields: string[];
  booleanFields: string[];
  passthroughFields: string[];
  nestedNumericFields: string[];
  itemLevelFields: string[];
  attributeFields: string[];
  computedFields: string[];
}

export type FieldClassification =
  | "numeric"
  | "string"
  | "boolean"
  | "passthrough"
  | "nested-numeric"
  | "item-level"
  | "attribute"
  | "computed"
  | "unknown";

export type XmlEntityKind =
  | "equipment"
  | "consumable"
  | "mod"
  | "enemy"
  | "bullet-case"
  | "list"
  | "misc";

export interface DiscoveredXmlFile {
  absolutePath: string;
  relativePath: string;
  entityKind: XmlEntityKind;
}

export interface FieldOccurrence {
  field: string;
  path: string;
  file: string;
  entityKind: XmlEntityKind;
  classification: FieldClassification;
}

export interface FieldUsageRecord {
  field: string;
  classification: FieldClassification;
  occurrences: number;
  files: string[];
  samplePaths: string[];
  entityKinds: XmlEntityKind[];
}

export interface FieldScanReport {
  generatedAt: string;
  projectConfigPath: string;
  projectRoot: string;
  totals: {
    files: number;
    fields: number;
    occurrences: number;
    unknownFields: number;
  };
  files: DiscoveredXmlFile[];
  usage: FieldUsageRecord[];
  unknownFields: string[];
}