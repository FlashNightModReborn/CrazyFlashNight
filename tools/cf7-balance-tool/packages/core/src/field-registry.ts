import type {
  FieldClassification,
  FieldUsageRecord,
  FieldRegistry
} from "./contracts.js";

const CLASSIFICATION_ORDER: FieldClassification[] = [
  "unknown",
  "numeric",
  "nested-numeric",
  "string",
  "boolean",
  "attribute",
  "item-level",
  "passthrough",
  "computed"
];

export function classifyField(
  field: string,
  registry: FieldRegistry,
  pathSegments: string[] = []
): FieldClassification {
  if (registry.attributeFields.includes(field)) {
    return "attribute";
  }

  if (registry.numericFields.includes(field)) {
    return "numeric";
  }

  if (registry.numericSuffixes.some((suffix) => field.endsWith(suffix))) {
    return "numeric";
  }

  if (hasNestedNumericAncestor(pathSegments, registry)) {
    return "nested-numeric";
  }

  if (registry.nestedNumericFields.includes(field)) {
    return "nested-numeric";
  }

  if (registry.stringFields.includes(field)) {
    return "string";
  }

  if (registry.booleanFields.includes(field)) {
    return "boolean";
  }

  if (registry.itemLevelFields.includes(field)) {
    return "item-level";
  }

  if (registry.passthroughFields.includes(field)) {
    return "passthrough";
  }

  if (registry.computedFields.includes(field)) {
    return "computed";
  }

  return "unknown";
}

export function uniquePreservingOrder(values: Iterable<string>): string[] {
  return [...new Set(values)];
}

export function sortFieldUsage(records: FieldUsageRecord[]): FieldUsageRecord[] {
  return [...records].sort((left, right) => {
    const classificationDelta =
      CLASSIFICATION_ORDER.indexOf(left.classification) -
      CLASSIFICATION_ORDER.indexOf(right.classification);

    if (classificationDelta !== 0) {
      return classificationDelta;
    }

    if (left.occurrences !== right.occurrences) {
      return right.occurrences - left.occurrences;
    }

    return left.field.localeCompare(right.field);
  });
}

function hasNestedNumericAncestor(
  pathSegments: string[],
  registry: FieldRegistry
): boolean {
  if (pathSegments.length <= 1) {
    return false;
  }

  return pathSegments
    .slice(0, -1)
    .some((segment) => registry.nestedNumericFields.includes(segment));
}