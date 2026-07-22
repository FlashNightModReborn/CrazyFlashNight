#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const DEFAULT_CONTRACT = "launcher/contracts/panel-contracts.v1.json";
const AUTHORITY_KINDS = ["protocol", "transport", "business-authority"];
const REQUIRED_VECTOR_VALUES = {
  "npcshop.purchaseQuantity": {
    valid: [1, 99, 100, 101, 4549, 999999],
    invalid: [0, 1000000]
  },
  "crafting.craftCount": {
    valid: [1, 99],
    invalid: [100]
  },
  "kshop.purchaseQuantity": {
    valid: [1, 99, 100, 101, 4549, 999999],
    invalid: [0, 1000000]
  }
};
const REQUIRED_INTERACTION_POLICIES = {
  "npcshop.purchaseQuantity": {
    previewInputMaximumField: "purchaseLimit",
    directCommitMaximumField: "maxPurchasable",
    maximumAction: "set-direct-commit-maximum",
    infeasibleIntent: "allow-preview-block-commit",
    previewInFlight: "visible-lock"
  }
};

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function slash(value) {
  return String(value).replace(/\\/g, "/");
}

function escapeRegExp(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function canonicalExpression(value) {
  return String(value).replace(/\s+/g, "");
}

function stripCodeComments(source) {
  source = String(source);
  let result = "";
  let quote = null;
  let verbatim = false;
  let lineComment = false;
  let blockComment = false;
  for (let index = 0; index < source.length; index += 1) {
    const current = source[index];
    const next = source[index + 1];
    if (lineComment) {
      if (current === "\r" || current === "\n") { lineComment = false; result += current; }
      else result += " ";
      continue;
    }
    if (blockComment) {
      if (current === "*" && next === "/") { result += "  "; blockComment = false; index += 1; }
      else result += current === "\r" || current === "\n" ? current : " ";
      continue;
    }
    if (quote !== null) {
      result += current;
      if (verbatim && current === '"' && next === '"') { result += next; index += 1; continue; }
      if (!verbatim && current === "\\" && next !== undefined) { result += next; index += 1; continue; }
      if (current === quote) { quote = null; verbatim = false; }
      continue;
    }
    if (current === "/" && next === "/") { result += "  "; lineComment = true; index += 1; continue; }
    if (current === "/" && next === "*") { result += "  "; blockComment = true; index += 1; continue; }
    if (current === '"' || current === "'") {
      quote = current; verbatim = current === '"' && index > 0 && source[index - 1] === "@"; result += current; continue;
    }
    result += current;
  }
  return result;
}

function addError(errors, code, at, message) {
  errors.push({ code: code, path: at, message: message });
}

function exactKeys(value, required, optional, at, errors) {
  if (!isObject(value)) {
    addError(errors, "schema.type", at, "expected object");
    return false;
  }
  const allowed = new Set(required.concat(optional || []));
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) addError(errors, "schema.unknown_key", at + "." + key, "unknown property");
  }
  for (const key of required) {
    if (!Object.prototype.hasOwnProperty.call(value, key)) {
      addError(errors, "schema.missing_key", at + "." + key, "required property is missing");
    }
  }
  return true;
}

function stringValue(value, at, errors) {
  if (typeof value !== "string" || value.length === 0) {
    addError(errors, "schema.string", at, "expected non-empty string");
    return false;
  }
  return true;
}

function integerValue(value, at, errors) {
  if (!Number.isSafeInteger(value)) {
    addError(errors, "schema.integer", at, "expected safe integer");
    return false;
  }
  return true;
}

function stringArray(value, at, errors) {
  if (!Array.isArray(value) || value.length === 0) {
    addError(errors, "schema.array", at, "expected non-empty string array");
    return false;
  }
  value.forEach(function (entry, index) { stringValue(entry, at + "[" + index + "]", errors); });
  return true;
}

function safeRelativeFile(value, at, errors) {
  if (!stringValue(value, at, errors)) return;
  const normalized = slash(value);
  if (path.isAbsolute(value) || normalized === ".." || normalized.startsWith("../") || normalized.includes("/../")) {
    addError(errors, "schema.path", at, "source path must remain inside the repository");
  }
}

function validateBoundarySchema(boundary, at, errors) {
  if (!exactKeys(boundary,
    ["name", "side", "authority", "hostEnforcement"],
    ["value", "dynamic", "responseFields"], at, errors)) return;
  stringValue(boundary.name, at + ".name", errors);
  if (boundary.side !== "min" && boundary.side !== "max") {
    addError(errors, "schema.enum", at + ".side", "expected min or max");
  }
  if (!AUTHORITY_KINDS.includes(boundary.authority)) {
    addError(errors, "schema.enum", at + ".authority", "unknown authority kind");
  }
  if (boundary.hostEnforcement !== "fixed" && boundary.hostEnforcement !== "none") {
    addError(errors, "schema.enum", at + ".hostEnforcement", "expected fixed or none");
  }
  if (Object.prototype.hasOwnProperty.call(boundary, "value")) integerValue(boundary.value, at + ".value", errors);
  if (Object.prototype.hasOwnProperty.call(boundary, "dynamic") && typeof boundary.dynamic !== "boolean") {
    addError(errors, "schema.boolean", at + ".dynamic", "expected boolean");
  }
  if (Object.prototype.hasOwnProperty.call(boundary, "responseFields")) {
    stringArray(boundary.responseFields, at + ".responseFields", errors);
  }
}

function validateInteractionPolicySchema(policy, at, errors) {
  if (!exactKeys(policy,
    ["previewInputMaximumField", "directCommitMaximumField", "maximumAction", "infeasibleIntent", "previewInFlight"],
    [], at, errors)) return;
  Object.keys(policy).forEach(function (key) { stringValue(policy[key], at + "." + key, errors); });
  const enums = {
    maximumAction: ["set-direct-commit-maximum"],
    infeasibleIntent: ["allow-preview-block-commit"],
    previewInFlight: ["visible-lock"]
  };
  Object.keys(enums).forEach(function (key) {
    if (!enums[key].includes(policy[key])) addError(errors, "schema.enum", at + "." + key, "unknown interaction policy value");
  });
}

function validateSourceCheckSchema(check, at, errors) {
  if (!isObject(check)) {
    addError(errors, "schema.type", at, "expected object");
    return;
  }
  const common = ["kind", "file"];
  const definitions = {
    "csharp-const-int": ["symbol", "fieldId", "boundary"],
    "csharp-integer-guard": ["argument", "minimum", "maximum", "occurrences"],
    "as2-number-assignment": ["symbol", "fieldId", "boundary"],
    "as2-ternary-else-int": ["variable", "condition", "fieldId", "boundary"]
  };
  if (!Object.prototype.hasOwnProperty.call(definitions, check.kind)) {
    exactKeys(check, common, [], at, errors);
    addError(errors, "schema.enum", at + ".kind", "unknown source check kind");
    return;
  }
  const specific = definitions[check.kind];
  if (!exactKeys(check, common.concat(specific), [], at, errors)) return;
  stringValue(check.kind, at + ".kind", errors);
  safeRelativeFile(check.file, at + ".file", errors);
  specific.forEach(function (key) {
    if (key === "occurrences") integerValue(check[key], at + ".occurrences", errors);
    else stringValue(check[key], at + "." + key, errors);
  });
  if (check.occurrences !== undefined && check.occurrences < 1) {
    addError(errors, "schema.range", at + ".occurrences", "occurrences must be positive");
  }
}

function validateContractSchema(contract, errors) {
  if (!exactKeys(contract, ["contractVersion", "authorityKinds", "domains", "vectors"], [], "$", errors)) return;
  integerValue(contract.contractVersion, "$.contractVersion", errors);
  if (!Array.isArray(contract.authorityKinds)) {
    addError(errors, "schema.array", "$.authorityKinds", "expected array");
  } else {
    contract.authorityKinds.forEach(function (entry, index) {
      stringValue(entry, "$.authorityKinds[" + index + "]", errors);
    });
  }
  if (!Array.isArray(contract.domains) || contract.domains.length === 0) {
    addError(errors, "schema.array", "$.domains", "expected non-empty domain array");
  } else {
    contract.domains.forEach(function (domain, domainIndex) {
      const at = "$.domains[" + domainIndex + "]";
      if (!exactKeys(domain,
        ["id", "wireDomain", "hostTask", "flashResponseTask", "hostResponseHandler", "hostPayloadMode", "flashSources", "commands", "numericFields", "sourceChecks"],
        [], at, errors)) return;
      stringValue(domain.id, at + ".id", errors);
      stringValue(domain.wireDomain, at + ".wireDomain", errors);
      safeRelativeFile(domain.hostTask, at + ".hostTask", errors);
      stringValue(domain.flashResponseTask, at + ".flashResponseTask", errors);
      stringValue(domain.hostResponseHandler, at + ".hostResponseHandler", errors);
      if (domain.hostPayloadMode !== "normalized" && domain.hostPayloadMode !== "passthrough") {
        addError(errors, "schema.enum", at + ".hostPayloadMode", "expected normalized or passthrough");
      }
      stringArray(domain.flashSources, at + ".flashSources", errors);
      if (Array.isArray(domain.flashSources)) {
        domain.flashSources.forEach(function (file, index) {
          safeRelativeFile(file, at + ".flashSources[" + index + "]", errors);
        });
      }
      if (!Array.isArray(domain.commands) || domain.commands.length === 0) {
        addError(errors, "schema.array", at + ".commands", "expected non-empty command array");
      } else {
        domain.commands.forEach(function (command, commandIndex) {
          const commandAt = at + ".commands[" + commandIndex + "]";
          if (!exactKeys(command, ["cmd", "action", "access"], [], commandAt, errors)) return;
          stringValue(command.cmd, commandAt + ".cmd", errors);
          stringValue(command.action, commandAt + ".action", errors);
          if (command.access !== "read" && command.access !== "write") {
            addError(errors, "schema.enum", commandAt + ".access", "expected read or write");
          }
        });
      }
      if (!Array.isArray(domain.numericFields) || domain.numericFields.length === 0) {
        addError(errors, "schema.array", at + ".numericFields", "expected non-empty numericFields array");
      } else {
        domain.numericFields.forEach(function (field, fieldIndex) {
          const fieldAt = at + ".numericFields[" + fieldIndex + "]";
          if (!exactKeys(field, ["id", "integer", "requestPaths", "boundaries"], ["interactionPolicy"], fieldAt, errors)) return;
          stringValue(field.id, fieldAt + ".id", errors);
          if (field.integer !== true) addError(errors, "schema.literal", fieldAt + ".integer", "v1 numeric fields must be integer=true");
          if (!Array.isArray(field.requestPaths) || field.requestPaths.length === 0) {
            addError(errors, "schema.array", fieldAt + ".requestPaths", "expected non-empty request path array");
          } else {
            field.requestPaths.forEach(function (requestPath, requestIndex) {
              const requestAt = fieldAt + ".requestPaths[" + requestIndex + "]";
              if (!exactKeys(requestPath, ["cmd", "path"], [], requestAt, errors)) return;
              stringValue(requestPath.cmd, requestAt + ".cmd", errors);
              stringValue(requestPath.path, requestAt + ".path", errors);
            });
          }
          if (!Array.isArray(field.boundaries) || field.boundaries.length === 0) {
            addError(errors, "schema.array", fieldAt + ".boundaries", "expected non-empty boundary array");
          } else {
            field.boundaries.forEach(function (boundary, boundaryIndex) {
              validateBoundarySchema(boundary, fieldAt + ".boundaries[" + boundaryIndex + "]", errors);
            });
          }
          if (Object.prototype.hasOwnProperty.call(field, "interactionPolicy")) {
            validateInteractionPolicySchema(field.interactionPolicy, fieldAt + ".interactionPolicy", errors);
          }
        });
      }
      if (!Array.isArray(domain.sourceChecks) || domain.sourceChecks.length === 0) {
        addError(errors, "schema.array", at + ".sourceChecks", "expected non-empty sourceChecks array");
      } else {
        domain.sourceChecks.forEach(function (check, checkIndex) {
          validateSourceCheckSchema(check, at + ".sourceChecks[" + checkIndex + "]", errors);
        });
      }
    });
  }
  if (!isObject(contract.vectors)) {
    addError(errors, "schema.type", "$.vectors", "expected object keyed by domain and field");
  } else {
    for (const domainKey of Object.keys(contract.vectors)) {
      const domainVectors = contract.vectors[domainKey];
      const domainAt = "$.vectors." + domainKey;
      if (!isObject(domainVectors)) {
        addError(errors, "schema.type", domainAt, "expected object keyed by field id");
        continue;
      }
      for (const vectorKey of Object.keys(domainVectors)) {
        const vector = domainVectors[vectorKey];
        const at = domainAt + "." + vectorKey;
        if (!exactKeys(vector,
          ["fieldId", "cmd", "payloadPath", "valid", "invalid", "hostPolicy", "businessOutcome"],
          [], at, errors)) continue;
        stringValue(vector.fieldId, at + ".fieldId", errors);
        stringValue(vector.cmd, at + ".cmd", errors);
        stringValue(vector.payloadPath, at + ".payloadPath", errors);
        ["valid", "invalid"].forEach(function (kind) {
          if (!Array.isArray(vector[kind]) || vector[kind].length === 0) {
            addError(errors, "schema.array", at + "." + kind, "expected non-empty integer array");
          } else {
            vector[kind].forEach(function (value, index) {
              integerValue(value, at + "." + kind + "[" + index + "]", errors);
            });
          }
        });
        if (vector.hostPolicy !== "enforce-static-boundaries" && vector.hostPolicy !== "delegate-to-flash") {
          addError(errors, "schema.enum", at + ".hostPolicy", "unknown host policy");
        }
        if (vector.businessOutcome !== "authority-dependent") {
          addError(errors, "schema.literal", at + ".businessOutcome", "business outcome must remain authority-dependent");
        }
      }
    }
  }
}

function findBoundary(domain, fieldId, boundaryName) {
  const field = domain.numericFields.find(function (entry) { return entry.id === fieldId; });
  if (!field) return null;
  return field.boundaries.find(function (entry) { return entry.name === boundaryName; }) || null;
}

function validateSemantics(contract, errors) {
  if (contract.contractVersion !== 1) {
    addError(errors, "contract.version", "$.contractVersion", "only panel contract version 1 is supported");
  }
  const authoritySet = new Set(contract.authorityKinds);
  if (authoritySet.size !== AUTHORITY_KINDS.length
      || AUTHORITY_KINDS.some(function (kind) { return !authoritySet.has(kind); })) {
    addError(errors, "contract.authority_kinds", "$.authorityKinds", "authorityKinds must be the exact v1 authority set");
  }

  const domainIds = new Set();
  const wireCommands = new Set();
  const responseTasks = new Set();
  contract.domains.forEach(function (domain, domainIndex) {
    const domainAt = "$.domains[" + domainIndex + "]";
    if (domainIds.has(domain.id)) addError(errors, "contract.duplicate_domain", domainAt + ".id", "duplicate domain id " + domain.id);
    domainIds.add(domain.id);
    if (responseTasks.has(domain.flashResponseTask)) {
      addError(errors, "contract.duplicate_response_task", domainAt + ".flashResponseTask",
        "duplicate Flash response task " + domain.flashResponseTask);
    }
    responseTasks.add(domain.flashResponseTask);

    const commandNames = new Set();
    const actions = new Set();
    domain.commands.forEach(function (command, commandIndex) {
      const commandAt = domainAt + ".commands[" + commandIndex + "]";
      if (commandNames.has(command.cmd)) addError(errors, "contract.duplicate_cmd", commandAt + ".cmd", "duplicate cmd " + command.cmd);
      commandNames.add(command.cmd);
      if (actions.has(command.action)) addError(errors, "contract.duplicate_action", commandAt + ".action", "duplicate action " + command.action);
      actions.add(command.action);
      const wireKey = domain.wireDomain + "\u0000" + command.cmd;
      if (wireCommands.has(wireKey)) addError(errors, "contract.duplicate_wire_cmd", commandAt + ".cmd", "duplicate wire domain/cmd pair");
      wireCommands.add(wireKey);
    });

    const fieldIds = new Set();
    domain.numericFields.forEach(function (field, fieldIndex) {
      const fieldAt = domainAt + ".numericFields[" + fieldIndex + "]";
      if (fieldIds.has(field.id)) addError(errors, "contract.duplicate_field", fieldAt + ".id", "duplicate numeric field " + field.id);
      fieldIds.add(field.id);
      const requestPaths = new Set();
      field.requestPaths.forEach(function (requestPath, requestIndex) {
        const requestAt = fieldAt + ".requestPaths[" + requestIndex + "]";
        if (!commandNames.has(requestPath.cmd)) addError(errors, "contract.unknown_cmd", requestAt + ".cmd", "request path references unknown cmd");
        const key = requestPath.cmd + "\u0000" + requestPath.path;
        if (requestPaths.has(key)) addError(errors, "contract.duplicate_request_path", requestAt, "duplicate cmd/path pair");
        requestPaths.add(key);
      });

      const boundaryNames = new Set();
      const boundaryKinds = new Set();
      const staticMins = [];
      const staticMaxes = [];
      field.boundaries.forEach(function (boundary, boundaryIndex) {
        const boundaryAt = fieldAt + ".boundaries[" + boundaryIndex + "]";
        if (boundaryNames.has(boundary.name)) addError(errors, "contract.duplicate_boundary", boundaryAt + ".name", "duplicate boundary name");
        boundaryNames.add(boundary.name);
        const kindKey = boundary.side + "\u0000" + boundary.authority;
        if (boundaryKinds.has(kindKey)) addError(errors, "contract.duplicate_boundary_kind", boundaryAt, "duplicate side/authority boundary");
        boundaryKinds.add(kindKey);

        const dynamic = boundary.dynamic === true;
        const hasValue = Object.prototype.hasOwnProperty.call(boundary, "value");
        if (dynamic) {
          if (boundary.authority !== "business-authority") {
            addError(errors, "contract.dynamic_authority", boundaryAt + ".authority", "dynamic boundary must be business-authority");
          }
          if (hasValue) addError(errors, "contract.dynamic_fixed_value", boundaryAt + ".value", "dynamic business boundary cannot carry a fixed value");
          if (boundary.hostEnforcement !== "none") {
            addError(errors, "contract.dynamic_host_cap", boundaryAt + ".hostEnforcement", "dynamic business boundary cannot be a Host fixed cap");
          }
          if (boundary.side !== "max") addError(errors, "contract.dynamic_side", boundaryAt + ".side", "dynamic business boundary must be a maximum");
          if (!Array.isArray(boundary.responseFields) || boundary.responseFields.length === 0) {
            addError(errors, "contract.dynamic_response", boundaryAt + ".responseFields", "dynamic boundary needs authority response fields");
          }
        } else {
          if (boundary.authority === "business-authority") {
            addError(errors, "contract.business_not_dynamic", boundaryAt + ".authority", "business-authority maximum must remain dynamic");
          }
          if (!hasValue) addError(errors, "contract.static_value", boundaryAt + ".value", "static boundary needs an integer value");
          if (boundary.responseFields !== undefined) {
            addError(errors, "contract.static_response", boundaryAt + ".responseFields", "static boundary cannot declare authority response fields");
          }
          if (hasValue && boundary.side === "min") staticMins.push(boundary.value);
          if (hasValue && boundary.side === "max") staticMaxes.push(boundary.value);
        }
        if (boundary.hostEnforcement === "fixed" && (!hasValue || dynamic || boundary.authority === "business-authority")) {
          addError(errors, "contract.invalid_host_fixed", boundaryAt + ".hostEnforcement", "Host fixed enforcement is only valid for a static protocol/transport boundary");
        }
        if (boundary.name === "effective-maximum"
            && !(boundary.side === "max" && boundary.authority === "business-authority"
              && dynamic && boundary.hostEnforcement === "none" && !hasValue)) {
          addError(errors, "contract.effective_maximum", boundaryAt, "effective-maximum must be dynamic business authority with no Host cap");
        }
      });
      if (!boundaryNames.has("effective-maximum")) {
        addError(errors, "contract.missing_effective_maximum", fieldAt + ".boundaries", "authority-dependent field needs effective-maximum");
      }
      if (staticMins.length !== 1) addError(errors, "contract.minimum_count", fieldAt + ".boundaries", "numeric field needs exactly one static minimum");
      if (staticMaxes.length < 1) addError(errors, "contract.maximum_count", fieldAt + ".boundaries", "numeric field needs at least one static maximum");
      if (staticMins.length === 1 && staticMaxes.some(function (maximum) { return maximum < staticMins[0]; })) {
        addError(errors, "contract.inverted_range", fieldAt + ".boundaries", "static maximum is below the minimum");
      }

      const policyKey = domain.id + "." + field.id;
      const requiredPolicy = REQUIRED_INTERACTION_POLICIES[policyKey];
      if (requiredPolicy && !isObject(field.interactionPolicy)) {
        addError(errors, "contract.interaction_policy_missing", fieldAt + ".interactionPolicy",
          "required interaction policy is missing for " + policyKey);
      } else if (isObject(field.interactionPolicy)) {
        const effectiveMaximum = field.boundaries.find(function (boundary) { return boundary.name === "effective-maximum"; });
        ["previewInputMaximumField", "directCommitMaximumField"].forEach(function (key) {
          const responseFields = effectiveMaximum && effectiveMaximum.responseFields;
          if (!Array.isArray(responseFields) || !responseFields.includes(field.interactionPolicy[key])) {
            addError(errors, "contract.interaction_policy_response_field", fieldAt + ".interactionPolicy." + key,
              "interaction policy must reference an effective-maximum response field");
          }
        });
        if (field.interactionPolicy.previewInputMaximumField === field.interactionPolicy.directCommitMaximumField) {
          addError(errors, "contract.interaction_policy_distinct", fieldAt + ".interactionPolicy",
            "preview input and direct-commit maxima must remain distinct");
        }
        if (requiredPolicy) {
          Object.keys(requiredPolicy).forEach(function (key) {
            if (field.interactionPolicy[key] !== requiredPolicy[key]) {
              addError(errors, "contract.interaction_policy_drift", fieldAt + ".interactionPolicy." + key,
                "expected " + JSON.stringify(requiredPolicy[key]));
            }
          });
        }
      }
    });

    domain.sourceChecks.forEach(function (check, checkIndex) {
      const checkAt = domainAt + ".sourceChecks[" + checkIndex + "]";
      if (check.fieldId !== undefined) {
        const boundary = findBoundary(domain, check.fieldId, check.boundary);
        if (!boundary) addError(errors, "contract.unknown_boundary", checkAt, "source check references an unknown field/boundary");
        else if (!Number.isSafeInteger(boundary.value)) {
          addError(errors, "contract.source_dynamic_boundary", checkAt + ".boundary", "numeric source anchor must reference a static boundary");
        }
      }
    });
  });

  ["npcshop", "crafting", "kshop"].forEach(function (requiredDomain) {
    if (!domainIds.has(requiredDomain)) addError(errors, "contract.required_domain", "$.domains", "missing required domain " + requiredDomain);
  });

  const vectorDomainKeys = Object.keys(contract.vectors);
  vectorDomainKeys.forEach(function (domainKey) {
    if (!domainIds.has(domainKey)) addError(errors, "contract.vector_unknown_domain", "$.vectors." + domainKey, "vectors reference unknown domain");
  });
  contract.domains.forEach(function (domain) {
    const domainVectors = contract.vectors[domain.id];
    if (!isObject(domainVectors)) {
      addError(errors, "contract.vector_missing_domain", "$.vectors." + domain.id, "numeric domain needs vectors");
      return;
    }
    const fields = new Map(domain.numericFields.map(function (field) { return [field.id, field]; }));
    for (const key of Object.keys(domainVectors)) {
      const vector = domainVectors[key];
      const vectorAt = "$.vectors." + domain.id + "." + key;
      const field = fields.get(key);
      if (!field) {
        addError(errors, "contract.vector_unknown_field", vectorAt, "vector key does not match a numeric field");
        continue;
      }
      if (vector.fieldId !== key) addError(errors, "contract.vector_field_id", vectorAt + ".fieldId", "fieldId must equal vector key");
      const requestMatch = field.requestPaths.some(function (entry) {
        return entry.cmd === vector.cmd && entry.path === vector.payloadPath;
      });
      if (!requestMatch) addError(errors, "contract.vector_request_path", vectorAt, "vector cmd/payloadPath is not declared by the field");
      const validSet = new Set(vector.valid);
      const invalidSet = new Set(vector.invalid);
      if (validSet.size !== vector.valid.length) addError(errors, "contract.vector_duplicate", vectorAt + ".valid", "valid vector values must be unique");
      if (invalidSet.size !== vector.invalid.length) addError(errors, "contract.vector_duplicate", vectorAt + ".invalid", "invalid vector values must be unique");
      validSet.forEach(function (value) {
        if (invalidSet.has(value)) addError(errors, "contract.vector_overlap", vectorAt, "value appears in both valid and invalid vectors: " + value);
      });
      const staticBounds = field.boundaries.filter(function (boundary) { return Number.isSafeInteger(boundary.value); });
      vector.valid.forEach(function (value, index) {
        const valid = staticBounds.every(function (boundary) {
          return boundary.side === "min" ? value >= boundary.value : value <= boundary.value;
        });
        if (!valid) addError(errors, "contract.vector_valid_outside", vectorAt + ".valid[" + index + "]", "valid value violates a static boundary");
      });
      vector.invalid.forEach(function (value, index) {
        const violates = staticBounds.some(function (boundary) {
          return boundary.side === "min" ? value < boundary.value : value > boundary.value;
        });
        if (!violates) addError(errors, "contract.vector_invalid_inside", vectorAt + ".invalid[" + index + "]", "invalid value does not violate a static boundary");
      });
    }
    fields.forEach(function (_field, fieldId) {
      if (!Object.prototype.hasOwnProperty.call(domainVectors, fieldId)) {
        addError(errors, "contract.vector_missing_field", "$.vectors." + domain.id, "missing vectors for " + fieldId);
      }
    });
  });

  for (const key of Object.keys(REQUIRED_VECTOR_VALUES)) {
    const parts = key.split(".");
    const vector = contract.vectors[parts[0]] && contract.vectors[parts[0]][parts[1]];
    if (!vector) continue;
    ["valid", "invalid"].forEach(function (kind) {
      const actual = new Set(vector[kind]);
      REQUIRED_VECTOR_VALUES[key][kind].forEach(function (value) {
        if (!actual.has(value)) {
          addError(errors, "contract.required_vector", "$.vectors." + key + "." + kind,
            "required boundary vector is missing value " + value);
        }
      });
    });
  }
}

function findBalancedBody(source, openIndex) {
  let depth = 0;
  let quote = null;
  let lineComment = false;
  let blockComment = false;
  for (let index = openIndex; index < source.length; index += 1) {
    const current = source[index];
    const next = source[index + 1];
    if (lineComment) {
      if (current === "\n") lineComment = false;
      continue;
    }
    if (blockComment) {
      if (current === "*" && next === "/") { blockComment = false; index += 1; }
      continue;
    }
    if (quote !== null) {
      if (current === "\\") { index += 1; continue; }
      if (current === quote) quote = null;
      continue;
    }
    if (current === "/" && next === "/") { lineComment = true; index += 1; continue; }
    if (current === "/" && next === "*") { blockComment = true; index += 1; continue; }
    if (current === "\"" || current === "'") { quote = current; continue; }
    if (current === "{") depth += 1;
    else if (current === "}") {
      depth -= 1;
      if (depth === 0) return source.slice(openIndex + 1, index);
    }
  }
  return null;
}

function parseCSharpCommandMap(source) {
  const signature = /\b(?:private|internal|public)\s+static\s+bool\s+TryResolveCommand\s*\([^)]*\)/g.exec(source);
  if (!signature) return { error: "TryResolveCommand method is missing" };
  const open = source.indexOf("{", signature.index + signature[0].length);
  if (open < 0) return { error: "TryResolveCommand body is missing" };
  const body = findBalancedBody(source, open);
  if (body === null) return { error: "TryResolveCommand body is unterminated" };
  const markers = [];
  const markerPattern = /\b(case\s+"([^"]+)"|default)\s*:/g;
  let match;
  while ((match = markerPattern.exec(body)) !== null) {
    markers.push({ index: match.index, end: markerPattern.lastIndex, cmd: match[2] || null });
  }
  const commands = new Map();
  const errors = [];
  markers.forEach(function (marker, index) {
    if (marker.cmd === null) return;
    const end = index + 1 < markers.length ? markers[index + 1].index : body.length;
    const block = body.slice(marker.end, end);
    const actions = [];
    const actionPattern = /\baction\s*=\s*"([^"]+)"\s*;/g;
    let actionMatch;
    while ((actionMatch = actionPattern.exec(block)) !== null) actions.push(actionMatch[1]);
    if (actions.length !== 1 || !/\breturn\s+true\s*;/.test(block)) {
      errors.push("case " + marker.cmd + " must assign exactly one action and return true");
      return;
    }
    if (commands.has(marker.cmd)) {
      errors.push("duplicate C# case " + marker.cmd);
      return;
    }
    commands.set(marker.cmd, {
      action: actions[0],
      access: /\bisWrite\s*=\s*true\s*;/.test(block) ? "write" : "read"
    });
  });
  return { commands: commands, errors: errors };
}

function matchingParen(source, openIndex) {
  let depth = 0;
  let quote = null;
  for (let index = openIndex; index < source.length; index += 1) {
    const current = source[index];
    if (quote !== null) {
      if (current === "\\") { index += 1; continue; }
      if (current === quote) quote = null;
      continue;
    }
    if (current === "\"" || current === "'") { quote = current; continue; }
    if (current === "(") depth += 1;
    else if (current === ")") {
      depth -= 1;
      if (depth === 0) return index;
    }
  }
  return -1;
}

function splitArguments(value) {
  const result = [];
  let start = 0;
  let round = 0;
  let square = 0;
  let curly = 0;
  let quote = null;
  for (let index = 0; index < value.length; index += 1) {
    const current = value[index];
    if (quote !== null) {
      if (current === "\\") { index += 1; continue; }
      if (current === quote) quote = null;
      continue;
    }
    if (current === "\"" || current === "'") { quote = current; continue; }
    if (current === "(") round += 1;
    else if (current === ")") round -= 1;
    else if (current === "[") square += 1;
    else if (current === "]") square -= 1;
    else if (current === "{") curly += 1;
    else if (current === "}") curly -= 1;
    else if (current === "," && round === 0 && square === 0 && curly === 0) {
      result.push(value.slice(start, index).trim());
      start = index + 1;
    }
  }
  result.push(value.slice(start).trim());
  return result;
}

function parseCalls(source, name) {
  const calls = [];
  const pattern = new RegExp("\\b" + escapeRegExp(name) + "\\s*\\(", "g");
  let match;
  while ((match = pattern.exec(source)) !== null) {
    const open = source.indexOf("(", match.index);
    const close = matchingParen(source, open);
    if (close < 0) return { calls: calls, error: name + " call is unterminated" };
    calls.push(splitArguments(source.slice(open + 1, close)));
    pattern.lastIndex = close + 1;
  }
  return { calls: calls, error: null };
}

function sourceReader(root, overrides, errors) {
  const normalizedOverrides = {};
  Object.keys(overrides || {}).forEach(function (key) { normalizedOverrides[slash(key)] = overrides[key]; });
  return function read(relativePath, at) {
    const key = slash(relativePath);
    if (Object.prototype.hasOwnProperty.call(normalizedOverrides, key)) return stripCodeComments(normalizedOverrides[key]);
    const full = path.resolve(root, relativePath);
    const rootPrefix = path.resolve(root) + path.sep;
    if (full !== path.resolve(root) && !full.startsWith(rootPrefix)) {
      addError(errors, "source.outside_root", at, "source path escapes repository root");
      return null;
    }
    try {
      return stripCodeComments(fs.readFileSync(full, "utf8"));
    } catch (error) {
      addError(errors, "source.read", at, "cannot read " + key + ": " + error.code);
      return null;
    }
  };
}

function validateSources(contract, root, overrides, errors) {
  const read = sourceReader(root, overrides, errors);
  const taskRegistryPath = "launcher/src/Bus/TaskRegistry.cs";
  const taskRegistrySource = read(taskRegistryPath, "$.taskRegistry");
  contract.domains.forEach(function (domain, domainIndex) {
    const domainAt = "$.domains[" + domainIndex + "]";
    const hostSource = read(domain.hostTask, domainAt + ".hostTask");
    if (hostSource !== null) {
      const parsed = parseCSharpCommandMap(hostSource);
      if (parsed.error) addError(errors, "source.csharp_command_parser", domainAt + ".hostTask", parsed.error);
      else {
        (parsed.errors || []).forEach(function (message) {
          addError(errors, "source.csharp_command_case", domainAt + ".hostTask", message);
        });
        const expected = new Map(domain.commands.map(function (command) { return [command.cmd, command]; }));
        expected.forEach(function (command, cmd) {
          const actual = parsed.commands.get(cmd);
          if (!actual) addError(errors, "source.csharp_command_missing", domainAt + ".commands", "Host mapping is missing " + cmd);
          else {
            if (actual.action !== command.action) {
              addError(errors, "source.csharp_action_drift", domainAt + ".commands", cmd + " maps to " + actual.action + ", expected " + command.action);
            }
            if (actual.access !== command.access) {
              addError(errors, "source.csharp_access_drift", domainAt + ".commands", cmd + " is " + actual.access + ", expected " + command.access);
            }
          }
        });
        parsed.commands.forEach(function (_command, cmd) {
          if (!expected.has(cmd)) addError(errors, "source.csharp_command_uncontracted", domainAt + ".commands", "Host exposes uncontracted cmd " + cmd);
        });
      }
      if (domain.hostPayloadMode === "passthrough") {
        const buildCalls = parseCalls(hostSource, "BuildFlashCommand");
        const rawForwardCount = buildCalls.calls.filter(function (argumentsList) {
          return argumentsList.length >= 3
            && canonicalExpression(argumentsList[0]) === "action"
            && canonicalExpression(argumentsList[1]) === "fid"
            && canonicalExpression(argumentsList[2]) === "parsed";
        }).length;
        if (buildCalls.error || rawForwardCount !== 1) {
          addError(errors, "source.csharp_passthrough_drift", domainAt + ".hostPayloadMode",
            buildCalls.error || "expected exactly one BuildFlashCommand(action, fid, parsed) raw forward");
        }
        ["TryReadInteger", "TryNormalizePayload"].forEach(function (method) {
          const calls = parseCalls(hostSource, method);
          if (calls.error || calls.calls.length !== 0) {
            addError(errors, "source.csharp_passthrough_guard", domainAt + ".hostPayloadMode",
              method + " must not add a Host business/quantity cap in passthrough mode");
          }
        });
      }
    }

    const flashActions = new Map();
    let flashResponseTaskCount = 0;
    domain.flashSources.forEach(function (flashFile, flashIndex) {
      const source = read(flashFile, domainAt + ".flashSources[" + flashIndex + "]");
      if (source === null) return;
      const pattern = /_root\.gameCommands\s*\[\s*"([^"]+)"\s*\]\s*=/g;
      let match;
      while ((match = pattern.exec(source)) !== null) {
        flashActions.set(match[1], (flashActions.get(match[1]) || 0) + 1);
      }
      const responsePattern = new RegExp("[\"']" + escapeRegExp(domain.flashResponseTask) + "[\"']", "g");
      while (responsePattern.exec(source) !== null) flashResponseTaskCount++;
    });
    domain.commands.forEach(function (command) {
      const count = flashActions.get(command.action) || 0;
      if (count !== 1) {
        addError(errors, "source.flash_action_drift", domainAt + ".flashSources",
          command.action + " registration count is " + count + ", expected 1");
      }
    });
    if (flashResponseTaskCount < 1) {
      addError(errors, "source.flash_response_task_drift", domainAt + ".flashResponseTask",
        domain.flashResponseTask + " is not emitted by the contracted Flash sources");
    }
    if (taskRegistrySource !== null) {
      const responseRegistrationsPattern = new RegExp("router\\.RegisterAsync\\s*\\(\\s*[\"']"
        + escapeRegExp(domain.flashResponseTask) + "[\"']\\s*,", "g");
      const registrationPattern = new RegExp("router\\.RegisterAsync\\s*\\(\\s*[\"']"
        + escapeRegExp(domain.flashResponseTask)
        + "[\"']\\s*,\\s*" + escapeRegExp(domain.hostResponseHandler) + "\\s*\\)", "g");
      const responseRegistrations = taskRegistrySource.match(responseRegistrationsPattern) || [];
      const registrations = taskRegistrySource.match(registrationPattern) || [];
      if (registrations.length !== 1 || responseRegistrations.length !== 1) {
        addError(errors, "source.csharp_response_task_drift", domainAt + ".hostResponseHandler",
          "TaskRegistry registration count for " + domain.flashResponseTask + " -> "
            + domain.hostResponseHandler + " is " + registrations.length + " and total task registrations are "
            + responseRegistrations.length + ", both expected 1");
      }
    }

    domain.sourceChecks.forEach(function (check, checkIndex) {
      const checkAt = domainAt + ".sourceChecks[" + checkIndex + "]";
      const source = read(check.file, checkAt + ".file");
      if (source === null) return;
      let expectedValue = null;
      if (check.fieldId !== undefined) {
        const boundary = findBoundary(domain, check.fieldId, check.boundary);
        expectedValue = boundary ? boundary.value : null;
      }
      if (check.kind === "csharp-const-int") {
        const pattern = new RegExp("\\bconst\\s+int\\s+" + escapeRegExp(check.symbol) + "\\s*=\\s*(-?\\d+)\\s*;", "g");
        const values = [];
        let match;
        while ((match = pattern.exec(source)) !== null) values.push(Number(match[1]));
        if (values.length !== 1 || values[0] !== expectedValue) {
          addError(errors, "source.csharp_const_drift", checkAt,
            check.symbol + " parsed values " + JSON.stringify(values) + ", expected [" + expectedValue + "]");
        }
      } else if (check.kind === "csharp-integer-guard") {
        const parsed = parseCalls(source, "TryReadInteger");
        if (parsed.error) addError(errors, "source.csharp_guard_parser", checkAt, parsed.error);
        const target = [check.argument, check.minimum, check.maximum].map(canonicalExpression);
        const count = parsed.calls.filter(function (argumentsList) {
          if (argumentsList.length < 3) return false;
          return target.every(function (expected, index) {
            return canonicalExpression(argumentsList[index]) === expected;
          });
        }).length;
        if (count !== check.occurrences) {
          addError(errors, "source.csharp_guard_drift", checkAt,
            "parsed integer guard count is " + count + ", expected " + check.occurrences
              + " for " + check.argument + " in [" + check.minimum + ", " + check.maximum + "]");
        }
      } else if (check.kind === "as2-number-assignment") {
        const pattern = new RegExp(escapeRegExp(check.symbol) + "(?:\\s*:\\s*[A-Za-z_$][\\w$]*)?\\s*=\\s*(-?\\d+)\\s*;", "g");
        const values = [];
        let match;
        while ((match = pattern.exec(source)) !== null) values.push(Number(match[1]));
        if (values.length !== 1 || values[0] !== expectedValue) {
          addError(errors, "source.as2_assignment_drift", checkAt,
            check.symbol + " parsed values " + JSON.stringify(values) + ", expected [" + expectedValue + "]");
        }
      } else if (check.kind === "as2-ternary-else-int") {
        const pattern = new RegExp("\\bvar\\s+" + escapeRegExp(check.variable)
          + "(?:\\s*:\\s*[A-Za-z_$][\\w$]*)?\\s*=\\s*" + escapeRegExp(check.condition)
          + "\\s*\\?\\s*[^:;]+\\s*:\\s*(-?\\d+)\\s*;", "g");
        const values = [];
        let match;
        while ((match = pattern.exec(source)) !== null) values.push(Number(match[1]));
        if (values.length !== 1 || values[0] !== expectedValue) {
          addError(errors, "source.as2_ternary_drift", checkAt,
            check.variable + " else values " + JSON.stringify(values) + ", expected [" + expectedValue + "]");
        }
      }
    });
  });
}

function countsFor(contract) {
  if (!contract || !Array.isArray(contract.domains)) {
    return { domains: 0, commands: 0, numericFields: 0, vectors: 0, sourceChecks: 0 };
  }
  return {
    domains: contract.domains.length,
    commands: contract.domains.reduce(function (sum, domain) { return sum + (Array.isArray(domain.commands) ? domain.commands.length : 0); }, 0),
    numericFields: contract.domains.reduce(function (sum, domain) { return sum + (Array.isArray(domain.numericFields) ? domain.numericFields.length : 0); }, 0),
    vectors: isObject(contract.vectors) ? Object.keys(contract.vectors).reduce(function (sum, key) {
      return sum + (isObject(contract.vectors[key]) ? Object.keys(contract.vectors[key]).length : 0);
    }, 0) : 0,
    sourceChecks: contract.domains.reduce(function (sum, domain) { return sum + (Array.isArray(domain.sourceChecks) ? domain.sourceChecks.length : 0); }, 0)
  };
}

function validateRepository(options) {
  options = options || {};
  const root = path.resolve(options.root || ROOT);
  const contractPath = options.contractPath || DEFAULT_CONTRACT;
  const errors = [];
  let contract = options.contract || null;
  if (contract === null) {
    const full = path.isAbsolute(contractPath) ? contractPath : path.resolve(root, contractPath);
    try {
      contract = JSON.parse(fs.readFileSync(full, "utf8"));
    } catch (error) {
      addError(errors, error instanceof SyntaxError ? "contract.json" : "contract.read", "$", error.message);
    }
  }
  if (contract !== null) {
    const beforeSchema = errors.length;
    validateContractSchema(contract, errors);
    if (errors.length === beforeSchema) {
      validateSemantics(contract, errors);
      validateSources(contract, root, options.sourceOverrides || {}, errors);
    }
  }
  errors.sort(function (left, right) {
    return (left.path + "\u0000" + left.code + "\u0000" + left.message)
      .localeCompare(right.path + "\u0000" + right.code + "\u0000" + right.message);
  });
  return {
    tool: "validate-panel-contracts",
    contractVersion: contract && contract.contractVersion || null,
    contractPath: slash(contractPath),
    ok: errors.length === 0,
    checked: countsFor(contract),
    errors: errors
  };
}

function parseCli(argv) {
  const result = { contractPath: DEFAULT_CONTRACT };
  for (let index = 0; index < argv.length; index += 1) {
    if (argv[index] === "--contract" && index + 1 < argv.length) result.contractPath = argv[++index];
    else if (argv[index] === "--root" && index + 1 < argv.length) result.root = argv[++index];
    else throw new Error("unknown or incomplete argument: " + argv[index]);
  }
  return result;
}

if (require.main === module) {
  let report;
  try {
    report = validateRepository(parseCli(process.argv.slice(2)));
  } catch (error) {
    report = {
      tool: "validate-panel-contracts",
      contractVersion: null,
      contractPath: DEFAULT_CONTRACT,
      ok: false,
      checked: { domains: 0, commands: 0, numericFields: 0, vectors: 0, sourceChecks: 0 },
      errors: [{ code: "cli.argument", path: "$", message: error.message }]
    };
  }
  process.stdout.write(JSON.stringify(report, null, 2) + "\n");
  process.exitCode = report.ok ? 0 : 1;
}

module.exports = {
  AUTHORITY_KINDS: AUTHORITY_KINDS,
  DEFAULT_CONTRACT: DEFAULT_CONTRACT,
  REQUIRED_VECTOR_VALUES: REQUIRED_VECTOR_VALUES,
  REQUIRED_INTERACTION_POLICIES: REQUIRED_INTERACTION_POLICIES,
  parseCSharpCommandMap: parseCSharpCommandMap,
  parseCalls: parseCalls,
  validateRepository: validateRepository
};
