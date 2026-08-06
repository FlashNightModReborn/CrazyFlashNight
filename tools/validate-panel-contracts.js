#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const DEFAULT_CONTRACT = "launcher/contracts/panel-contracts.v2.json";
const AUTHORITY_KINDS = ["protocol", "transport", "business-authority"];
const COMMAND_CAPABILITIES = ["query", "transaction"];
const BUSINESS_DECISION_OWNER = "as2";
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

function codePositionMask(source) {
  source = String(source);
  const mask = new Uint8Array(source.length);
  let quote = null;
  let verbatim = false;
  for (let index = 0; index < source.length; index += 1) {
    const current = source[index];
    const next = source[index + 1];
    if (quote !== null) {
      if (verbatim && current === '"' && next === '"') { index += 1; continue; }
      if (!verbatim && current === "\\" && next !== undefined) { index += 1; continue; }
      if (current === quote) { quote = null; verbatim = false; }
      continue;
    }
    mask[index] = 1;
    if (current === '"' || current === "'") {
      quote = current;
      verbatim = current === '"' && index > 0 && source[index - 1] === "@";
    }
  }
  return mask;
}

function executableMatches(source, pattern) {
  const code = stripCodeComments(String(source));
  const mask = codePositionMask(code);
  const flags = pattern.flags.includes("g") ? pattern.flags : pattern.flags + "g";
  const matcher = new RegExp(pattern.source, flags);
  const matches = [];
  let match;
  while ((match = matcher.exec(code)) !== null) {
    if (mask[match.index]) matches.push(match);
    if (match[0].length === 0) matcher.lastIndex += 1;
  }
  return matches;
}

function isUnqualifiedIdentifierAt(source, index) {
  if (index > 0 && /[A-Za-z0-9_$\u0080-\uFFFF]/.test(source[index - 1])) {
    return false;
  }
  let cursor = index - 1;
  while (cursor >= 0 && /\s/.test(source[cursor])) cursor -= 1;
  return cursor < 0 || source[cursor] !== ".";
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
  const optional = check.kind === "csharp-integer-guard" ? ["allowedAlternates"] : [];
  if (!exactKeys(check, common.concat(specific), optional, at, errors)) return;
  stringValue(check.kind, at + ".kind", errors);
  safeRelativeFile(check.file, at + ".file", errors);
  specific.forEach(function (key) {
    if (key === "occurrences") integerValue(check[key], at + ".occurrences", errors);
    else stringValue(check[key], at + "." + key, errors);
  });
  if (check.occurrences !== undefined && check.occurrences < 1) {
    addError(errors, "schema.range", at + ".occurrences", "occurrences must be positive");
  }
  if (check.kind === "csharp-integer-guard" && check.allowedAlternates !== undefined) {
    if (!Array.isArray(check.allowedAlternates)) {
      addError(errors, "schema.array", at + ".allowedAlternates", "expected array");
    } else {
      const signatures = new Set([canonicalExpression(check.minimum) + "|" + canonicalExpression(check.maximum)]);
      check.allowedAlternates.forEach(function (alternate, index) {
        const alternateAt = at + ".allowedAlternates[" + index + "]";
        if (!exactKeys(alternate, ["minimum", "maximum", "occurrences"], [], alternateAt, errors)) return;
        stringValue(alternate.minimum, alternateAt + ".minimum", errors);
        stringValue(alternate.maximum, alternateAt + ".maximum", errors);
        integerValue(alternate.occurrences, alternateAt + ".occurrences", errors);
        if (alternate.occurrences < 1) {
          addError(errors, "schema.range", alternateAt + ".occurrences",
            "occurrences must be positive");
        }
        const signature = canonicalExpression(alternate.minimum)
          + "|" + canonicalExpression(alternate.maximum);
        if (signatures.has(signature)) {
          addError(errors, "schema.duplicate", alternateAt,
            "guard boundary signature is duplicated");
        }
        signatures.add(signature);
      });
    }
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
        ["id", "wireDomain", "hostTask", "flashResponseTask", "hostResponseHandler", "hostPayloadMode", "flashCommandHandler", "flashSources", "commands", "numericFields", "sourceChecks"],
        [], at, errors)) return;
      stringValue(domain.id, at + ".id", errors);
      stringValue(domain.wireDomain, at + ".wireDomain", errors);
      safeRelativeFile(domain.hostTask, at + ".hostTask", errors);
      stringValue(domain.flashResponseTask, at + ".flashResponseTask", errors);
      stringValue(domain.hostResponseHandler, at + ".hostResponseHandler", errors);
      if (domain.hostPayloadMode !== "normalized"
          && domain.hostPayloadMode !== "passthrough"
          && domain.hostPayloadMode !== "passthrough-owner-sanitized"
          && domain.hostPayloadMode !== "normalized-domainless-owner-rebuilt") {
        addError(errors, "schema.enum", at + ".hostPayloadMode",
          "expected normalized, passthrough, passthrough-owner-sanitized, "
            + "or normalized-domainless-owner-rebuilt");
      }
      if (domain.flashCommandHandler !== null
          && (typeof domain.flashCommandHandler !== "string"
            || domain.flashCommandHandler.length === 0)) {
        addError(errors, "schema.string_or_null", at + ".flashCommandHandler",
          "expected a non-empty qualified handler receiver or null for inline dispatch");
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
          if (!exactKeys(command,
            ["cmd", "action", "capability", "access", "businessDecisionOwner"],
            [], commandAt, errors)) return;
          stringValue(command.cmd, commandAt + ".cmd", errors);
          stringValue(command.action, commandAt + ".action", errors);
          if (!COMMAND_CAPABILITIES.includes(command.capability)) {
            addError(errors, "schema.enum", commandAt + ".capability", "expected query or transaction");
          }
          if (command.access !== "read" && command.access !== "write") {
            addError(errors, "schema.enum", commandAt + ".access", "expected read or write");
          }
          stringValue(command.businessDecisionOwner, commandAt + ".businessDecisionOwner", errors);
        });
      }
      if (!Array.isArray(domain.numericFields)) {
        addError(errors, "schema.array", at + ".numericFields", "expected numericFields array");
      } else {
        domain.numericFields.forEach(function (field, fieldIndex) {
          const fieldAt = at + ".numericFields[" + fieldIndex + "]";
          if (!exactKeys(field, ["id", "integer", "requestPaths", "boundaries"], ["interactionPolicy"], fieldAt, errors)) return;
          stringValue(field.id, fieldAt + ".id", errors);
          if (field.integer !== true) addError(errors, "schema.literal", fieldAt + ".integer", "v2 numeric fields must be integer=true");
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
      if (!Array.isArray(domain.sourceChecks)) {
        addError(errors, "schema.array", at + ".sourceChecks", "expected sourceChecks array");
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
  if (contract.contractVersion !== 2) {
    addError(errors, "contract.version", "$.contractVersion", "only panel contract version 2 is supported");
  }
  const authoritySet = new Set(contract.authorityKinds);
  if (contract.authorityKinds.length !== AUTHORITY_KINDS.length
      || authoritySet.size !== AUTHORITY_KINDS.length
      || AUTHORITY_KINDS.some(function (kind) { return !authoritySet.has(kind); })) {
    addError(errors, "contract.authority_kinds", "$.authorityKinds", "authorityKinds must be the exact v2 authority set");
  }

  const domainIds = new Set();
  const wireCommands = new Set();
  const responseTasks = new Set();
  const responseHandlers = new Set();
  const actions = new Set();
  contract.domains.forEach(function (domain, domainIndex) {
    const domainAt = "$.domains[" + domainIndex + "]";
    if (domainIds.has(domain.id)) addError(errors, "contract.duplicate_domain", domainAt + ".id", "duplicate domain id " + domain.id);
    domainIds.add(domain.id);
    if (responseTasks.has(domain.flashResponseTask)) {
      addError(errors, "contract.duplicate_response_task", domainAt + ".flashResponseTask",
        "duplicate Flash response task " + domain.flashResponseTask);
    }
    responseTasks.add(domain.flashResponseTask);
    if (responseHandlers.has(domain.hostResponseHandler)) {
      addError(errors, "contract.duplicate_response_handler", domainAt + ".hostResponseHandler",
        "duplicate Host response handler " + domain.hostResponseHandler);
    }
    responseHandlers.add(domain.hostResponseHandler);

    const commandNames = new Set();
    domain.commands.forEach(function (command, commandIndex) {
      const commandAt = domainAt + ".commands[" + commandIndex + "]";
      if (commandNames.has(command.cmd)) addError(errors, "contract.duplicate_cmd", commandAt + ".cmd", "duplicate cmd " + command.cmd);
      commandNames.add(command.cmd);
      if (actions.has(command.action)) {
        addError(errors, "contract.duplicate_action", commandAt + ".action",
          "duplicate global Flash action " + command.action);
      }
      actions.add(command.action);
      const wireKey = domain.wireDomain + "\u0000" + command.cmd;
      if (wireCommands.has(wireKey)) addError(errors, "contract.duplicate_wire_cmd", commandAt + ".cmd", "duplicate wire domain/cmd pair");
      wireCommands.add(wireKey);
      if (command.capability === "query" && command.access !== "read") {
        addError(errors, "contract.capability_access_conflict", commandAt,
          "query capability must use read access");
      }
      if (command.businessDecisionOwner !== BUSINESS_DECISION_OWNER) {
        addError(errors, "contract.business_decision_owner_conflict", commandAt + ".businessDecisionOwner",
          "current executable contract requires AS2 as the sole business decision owner");
      }
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
    if (domain.numericFields.length > 0 && domain.sourceChecks.length === 0) {
      addError(errors, "contract.source_checks_missing", domainAt + ".sourceChecks",
        "a domain with numeric fields needs executable source checks");
    }
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
    if (domain.numericFields.length === 0) {
      if (domainVectors !== undefined) {
        addError(errors, "contract.vector_without_numeric_fields", "$.vectors." + domain.id,
          "a domain without numeric fields must not carry vector filler");
      }
      return;
    }
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
    if (!vector) {
      addError(errors, "contract.required_vector", "$.vectors." + key,
        "required boundary vector is missing");
      continue;
    }
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
  const bodyCodePositions = codePositionMask(body);
  let match;
  while ((match = markerPattern.exec(body)) !== null) {
    if (!bodyCodePositions[match.index]) continue;
    markers.push({ index: match.index, end: markerPattern.lastIndex, cmd: match[2] || null });
  }
  const commands = new Map();
  const errors = [];
  markers.forEach(function (marker, index) {
    if (marker.cmd === null) return;
    const end = index + 1 < markers.length ? markers[index + 1].index : body.length;
    const block = body.slice(marker.end, end);
    const blockCodePositions = codePositionMask(block);
    function collectExpressions(pattern) {
      const expressions = [];
      let expressionMatch;
      while ((expressionMatch = pattern.exec(block)) !== null) {
        if (blockCodePositions[expressionMatch.index]
            && isUnqualifiedIdentifierAt(block, expressionMatch.index)) {
          expressions.push(expressionMatch[1].trim());
        }
      }
      return expressions;
    }
    const actionAssignments = collectExpressions(/\baction\s*=\s*([^;]+)\s*;/g);
    const writeAssignments = collectExpressions(/\bisWrite\s*=\s*([^;]+)\s*;/g);
    const returnExpressions = collectExpressions(/\breturn\s+([^;]+)\s*;/g);
    const action = actionAssignments.length === 1 ? quotedLiteral(actionAssignments[0]) : null;
    const exactWriteShape = writeAssignments.length === 0
      || (writeAssignments.length === 1
        && (canonicalExpression(writeAssignments[0]) === "true"
          || canonicalExpression(writeAssignments[0]) === "false"));
    const exactReturnShape = returnExpressions.length === 1
      && canonicalExpression(returnExpressions[0]) === "true";
    if (action === null || !exactWriteShape || !exactReturnShape) {
      errors.push("case " + marker.cmd
        + " must assign one literal action, optionally assign literal isWrite=true/false once, "
        + "and contain exactly one return true");
      return;
    }
    if (commands.has(marker.cmd)) {
      errors.push("duplicate C# case " + marker.cmd);
      return;
    }
    commands.set(marker.cmd, {
      action: action,
      access: writeAssignments.length === 1
        && canonicalExpression(writeAssignments[0]) === "true" ? "write" : "read"
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
  const codePositions = codePositionMask(source);
  let match;
  while ((match = pattern.exec(source)) !== null) {
    if (!codePositions[match.index]) continue;
    const open = source.indexOf("(", match.index);
    const close = matchingParen(source, open);
    if (close < 0) return { calls: calls, error: name + " call is unterminated" };
    calls.push(splitArguments(source.slice(open + 1, close)));
    pattern.lastIndex = close + 1;
  }
  return { calls: calls, error: null };
}

function parseBareCalls(source, name) {
  const calls = [];
  const pattern = new RegExp("\\b" + escapeRegExp(name) + "\\s*\\(", "g");
  const codePositions = codePositionMask(source);
  let match;
  while ((match = pattern.exec(source)) !== null) {
    if (!codePositions[match.index] || !isUnqualifiedIdentifierAt(source, match.index)) continue;
    const open = source.indexOf("(", match.index);
    const close = matchingParen(source, open);
    if (close < 0) return { calls: calls, error: name + " call is unterminated" };
    calls.push(splitArguments(source.slice(open + 1, close)));
    pattern.lastIndex = close + 1;
  }
  return { calls: calls, error: null };
}

function parseQualifiedCalls(source, name) {
  const calls = [];
  const identifier = "[A-Za-z_$\\u0080-\\uFFFF][A-Za-z0-9_$\\u0080-\\uFFFF]*";
  const pattern = new RegExp("(" + identifier + "(?:\\s*\\.\\s*" + identifier + ")*)\\s*\\.\\s*"
    + escapeRegExp(name) + "\\s*\\(", "g");
  const codePositions = codePositionMask(source);
  let match;
  while ((match = pattern.exec(source)) !== null) {
    if (!codePositions[match.index]) continue;
    const open = source.indexOf("(", match.index + match[0].lastIndexOf(name));
    const close = matchingParen(source, open);
    if (close < 0) return { calls: calls, error: name + " call is unterminated" };
    calls.push({
      receiver: canonicalExpression(match[1]),
      arguments: splitArguments(source.slice(open + 1, close)),
      start: match.index,
      end: close + 1
    });
    pattern.lastIndex = close + 1;
  }
  return { calls: calls, error: null };
}

function parseFunctionParameterNames(value) {
  if (String(value).trim().length === 0) return [];
  return splitArguments(value).map(function (parameter) {
    const match = /^\s*([A-Za-z_$\u0080-\uFFFF][A-Za-z0-9_$\u0080-\uFFFF]*)/.exec(parameter);
    return match ? match[1] : null;
  });
}

function parseAs2GameCommandRegistrations(source) {
  const registrations = new Map();
  const errors = [];
  const pattern = /_root\s*\.\s*gameCommands\s*(?:\[\s*(["'])([^"']+)\1\s*\]|\.\s*([A-Za-z_$][A-Za-z0-9_$]*))\s*=(?!=)/g;
  const codePositions = codePositionMask(source);
  let match;
  while ((match = pattern.exec(source)) !== null) {
    if (!codePositions[match.index] || !isUnqualifiedIdentifierAt(source, match.index)) continue;
    const action = match[2] || match[3];
    let cursor = pattern.lastIndex;
    while (cursor < source.length && /\s/.test(source[cursor])) cursor += 1;
    const functionHeader = /^function\s*\(([^)]*)\)\s*(?::\s*[A-Za-z_$][\w$\.]*)?\s*\{/.exec(source.slice(cursor));
    let body = null;
    let parameterNames = [];
    if (functionHeader) {
      const open = cursor + functionHeader[0].lastIndexOf("{");
      body = findBalancedBody(source, open);
      parameterNames = parseFunctionParameterNames(functionHeader[1]);
      if (body === null) {
        errors.push("unterminated gameCommands function for " + action);
      }
    }
    if (!registrations.has(action)) registrations.set(action, []);
    registrations.get(action).push({ body: body, parameterNames: parameterNames });
  }
  return { registrations: registrations, errors: errors };
}

function findCSharpMethodBody(source, methodName) {
  const pattern = new RegExp("\\b" + escapeRegExp(methodName) + "\\s*\\([^)]*\\)\\s*\\{", "g");
  const codePositions = codePositionMask(source);
  const bodies = [];
  let match;
  while ((match = pattern.exec(source)) !== null) {
    if (!codePositions[match.index]) continue;
    const open = source.lastIndexOf("{", pattern.lastIndex - 1);
    const body = findBalancedBody(source, open);
    if (body === null) return { body: null, error: methodName + " body is unterminated" };
    bodies.push(body);
  }
  if (bodies.length !== 1) {
    return { body: null, error: methodName + " body count is " + bodies.length + ", expected 1" };
  }
  return { body: bodies[0], error: null };
}

function quotedLiteral(value) {
  const match = /^\s*(["'])([^"']*)\1\s*$/.exec(String(value));
  return match ? match[2] : null;
}

function parseStaticStringPropertyValues(source, propertyName) {
  const values = [];
  const codePositions = codePositionMask(source);
  const escapedProperty = escapeRegExp(propertyName);
  [
    {
      pattern: new RegExp("\\b" + escapedProperty + "\\s*:\\s*([\"'])([^\"']*)\\1", "g"),
      valueIndex: 2
    },
    {
      pattern: new RegExp("\\.\\s*" + escapedProperty + "\\s*=\\s*([\"'])([^\"']*)\\1\\s*;", "g"),
      valueIndex: 2
    },
    {
      pattern: new RegExp("\\[\\s*([\"'])" + escapedProperty
        + "\\1\\s*\\]\\s*=\\s*([\"'])([^\"']*)\\2\\s*;", "g"),
      valueIndex: 3
    }
  ].forEach(function (definition) {
    let match;
    while ((match = definition.pattern.exec(source)) !== null) {
      if (codePositions[match.index]) values.push(match[definition.valueIndex]);
    }
  });
  return values;
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
  const taskRegistryCalls = taskRegistrySource === null
    ? { calls: [], error: null }
    : parseQualifiedCalls(taskRegistrySource, "RegisterAsync");
  if (taskRegistryCalls.error) {
    addError(errors, "source.csharp_response_task_parser", "$.taskRegistry", taskRegistryCalls.error);
  }
  const globalFlashRegistrations = new Map();
  const scannedFlashSources = new Set();
  contract.domains.forEach(function (domain, domainIndex) {
    domain.flashSources.forEach(function (flashFile, flashIndex) {
      const key = slash(flashFile);
      if (scannedFlashSources.has(key)) return;
      scannedFlashSources.add(key);
      const at = "$.domains[" + domainIndex + "].flashSources[" + flashIndex + "]";
      const source = read(flashFile, at);
      if (source === null) return;
      const parsedRegistrations = parseAs2GameCommandRegistrations(source);
      parsedRegistrations.errors.forEach(function (message) {
        addError(errors, "source.flash_registration_parser", at, message);
      });
      parsedRegistrations.registrations.forEach(function (entries, action) {
        if (!globalFlashRegistrations.has(action)) globalFlashRegistrations.set(action, []);
        entries.forEach(function (entry) {
          globalFlashRegistrations.get(action).push({
            body: entry.body,
            parameterNames: entry.parameterNames,
            source: key
          });
        });
      });
    });
  });
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
      const domainGuards = [];
      const handleWebRequest = findCSharpMethodBody(hostSource, "HandleWebRequest");
      const domainGuardPattern = /if\s*\(\s*!\s*string\.Equals\s*\(\s*(?:parsed\.Value<string>\s*\(\s*"domain"\s*\)|ReadExactString\s*\(\s*parsed\s*\[\s*"domain"\s*\]\s*\))\s*,\s*"([^"]+)"\s*,\s*StringComparison\.Ordinal\s*\)\s*\)\s*\{/g;
      let domainGuardMatch;
      if (handleWebRequest.body !== null) {
        const guardSource = stripCodeComments(handleWebRequest.body);
        const guardCodePositions = codePositionMask(guardSource);
        while ((domainGuardMatch = domainGuardPattern.exec(guardSource)) !== null) {
          if (!guardCodePositions[domainGuardMatch.index]) continue;
          const guardOpen = guardSource.lastIndexOf("{", domainGuardPattern.lastIndex - 1);
          const guardBody = findBalancedBody(guardSource, guardOpen);
          const rejectCalls = guardBody === null
            ? { calls: [], error: "domain guard body is unterminated" }
            : parseBareCalls(guardBody, "RejectAndRemember");
          let returnCount = 0;
          if (guardBody !== null) {
            const returnPattern = /\breturn\s*;/g;
            const returnCodePositions = codePositionMask(guardBody);
            let returnMatch;
            while ((returnMatch = returnPattern.exec(guardBody)) !== null) {
              if (returnCodePositions[returnMatch.index]) returnCount += 1;
            }
          }
          const exactRejects = rejectCalls.calls.filter(function (argumentsList) {
            return argumentsList.length >= 3
              && canonicalExpression(argumentsList[0]) === "callId"
              && canonicalExpression(argumentsList[1]) === "cmd"
              && quotedLiteral(argumentsList[argumentsList.length - 1]) === "unsupported_domain";
          });
          domainGuards.push({
            domain: domainGuardMatch[1],
            validBranch: guardBody !== null
              && !rejectCalls.error
              && rejectCalls.calls.length === 1
              && exactRejects.length === 1
              && returnCount === 1
          });
        }
      }
      const requiresDomainGuard = domain.hostPayloadMode === "normalized";
      if ((requiresDomainGuard && handleWebRequest.error !== null)
          || (requiresDomainGuard && domainGuards.length !== 1)
          || (domainGuards.length > 0
            && (domainGuards.length !== 1
              || domainGuards[0].domain !== domain.wireDomain
              || !domainGuards[0].validBranch))) {
        addError(errors, "source.csharp_domain_identity_drift", domainAt + ".wireDomain",
          (handleWebRequest.error ? handleWebRequest.error + "; " : "")
            + "Host domain guards are " + JSON.stringify(domainGuards)
            + (requiresDomainGuard
              ? ", expected exactly [" + JSON.stringify(domain.wireDomain) + "]"
              : ", expected no guard or exactly [" + JSON.stringify(domain.wireDomain) + "]"));
      }
      if (handleWebRequest.body !== null) {
        const resolutionCalls = parseBareCalls(handleWebRequest.body, "TryResolveCommand");
        const exactResolutionCalls = resolutionCalls.calls.filter(function (argumentsList) {
          return argumentsList.length === 3
            && canonicalExpression(argumentsList[0]) === "cmd"
            && canonicalExpression(argumentsList[1]) === "outaction"
            && canonicalExpression(argumentsList[2]) === "outisWrite";
        });
        if (resolutionCalls.error || resolutionCalls.calls.length !== 1
            || exactResolutionCalls.length !== 1) {
          addError(errors, "source.csharp_command_resolution_drift", domainAt + ".hostTask",
            resolutionCalls.error
              || "HandleWebRequest must call TryResolveCommand(cmd, out action, out isWrite) exactly once");
        }
        const resolutionGuards = [];
        const resolutionGuardPattern = /if\s*\(\s*!\s*TryResolveCommand\s*\(\s*cmd\s*,\s*out\s+action\s*,\s*out\s+isWrite\s*\)\s*\)\s*\{/g;
        const resolutionCodePositions = codePositionMask(handleWebRequest.body);
        let resolutionGuardMatch;
        while ((resolutionGuardMatch = resolutionGuardPattern.exec(handleWebRequest.body)) !== null) {
          if (!resolutionCodePositions[resolutionGuardMatch.index]) continue;
          const guardOpen = handleWebRequest.body.lastIndexOf("{", resolutionGuardPattern.lastIndex - 1);
          const guardBody = findBalancedBody(handleWebRequest.body, guardOpen);
          const rejectCalls = guardBody === null
            ? { calls: [], error: "command resolver guard body is unterminated" }
            : parseBareCalls(guardBody, "RejectAndRemember");
          const exactRejects = rejectCalls.calls.filter(function (argumentsList) {
            const callIdentity = canonicalExpression(argumentsList[0]);
            return argumentsList.length >= 2
              && (callIdentity === "callId" || callIdentity === "webCallId")
              && canonicalExpression(argumentsList[1]) === "cmd"
              && quotedLiteral(argumentsList[argumentsList.length - 1]) === "unsupported_cmd";
          });
          let returnCount = 0;
          if (guardBody !== null) {
            const returnPattern = /\breturn\s*;/g;
            const returnCodePositions = codePositionMask(guardBody);
            let returnMatch;
            while ((returnMatch = returnPattern.exec(guardBody)) !== null) {
              if (returnCodePositions[returnMatch.index]) returnCount += 1;
            }
          }
          resolutionGuards.push(guardBody !== null
            && !rejectCalls.error
            && rejectCalls.calls.length === 1
            && exactRejects.length === 1
            && returnCount === 1);
        }
        if (resolutionGuards.length !== 1 || resolutionGuards[0] !== true) {
          addError(errors, "source.csharp_command_resolution_drift", domainAt + ".hostTask",
            "HandleWebRequest must fail closed from one exact "
              + "if (!TryResolveCommand(cmd, out action, out isWrite)) branch");
        }
        const handleCodePositions = codePositionMask(handleWebRequest.body);
        ["action", "isWrite"].forEach(function (outputName) {
          const assignmentPattern = new RegExp("\\b" + outputName + "\\s*=(?!=)", "g");
          let assignmentCount = 0;
          let assignmentMatch;
          while ((assignmentMatch = assignmentPattern.exec(handleWebRequest.body)) !== null) {
            if (handleCodePositions[assignmentMatch.index]
                && isUnqualifiedIdentifierAt(handleWebRequest.body, assignmentMatch.index)) {
              assignmentCount += 1;
            }
          }
          if (assignmentCount !== 0) {
            addError(errors, "source.csharp_command_output_drift", domainAt + ".hostTask",
              "HandleWebRequest overwrites resolver output " + outputName);
          }
        });
        let pendingWriteBindingCount = 0;
        const pendingWriteBindingPattern = /\bIsWrite\s*=\s*isWrite\b/g;
        let pendingWriteBindingMatch;
        while ((pendingWriteBindingMatch = pendingWriteBindingPattern.exec(handleWebRequest.body)) !== null) {
          if (handleCodePositions[pendingWriteBindingMatch.index]) pendingWriteBindingCount += 1;
        }
        let writeGateUseCount = 0;
        const writeGateUsePattern = /\bif\s*\(\s*isWrite\b/g;
        let writeGateUseMatch;
        while ((writeGateUseMatch = writeGateUsePattern.exec(handleWebRequest.body)) !== null) {
          if (handleCodePositions[writeGateUseMatch.index]) writeGateUseCount += 1;
        }
        if (pendingWriteBindingCount !== 1 || writeGateUseCount < 1) {
          addError(errors, "source.csharp_access_binding_drift", domainAt + ".hostTask",
            "HandleWebRequest must bind IsWrite=isWrite exactly once and use isWrite in a write gate");
        }
        const buildCalls = parseQualifiedCalls(handleWebRequest.body, "BuildFlashCommand");
        const expectedPayload = domain.hostPayloadMode === "normalized"
          ? "normalized"
          : domain.hostPayloadMode === "normalized-domainless-owner-rebuilt"
            ? "normalizedPayload"
          : domain.hostPayloadMode === "passthrough-owner-sanitized"
            ? "flashRequest"
            : "parsed";
        const exactBuildCalls = buildCalls.calls.filter(function (call) {
          return call.receiver === "PanelBridge"
            && call.arguments.length >= 3
            && canonicalExpression(call.arguments[0]) === "action"
            && canonicalExpression(call.arguments[1]) === "fid"
            && canonicalExpression(call.arguments[2]) === expectedPayload;
        });
        if (buildCalls.error || buildCalls.calls.length !== 1 || exactBuildCalls.length !== 1) {
          addError(errors, "source.csharp_flash_dispatch_drift", domainAt + ".hostTask",
            buildCalls.error
              || "HandleWebRequest must contain exactly one PanelBridge.BuildFlashCommand(action, fid, "
                + expectedPayload + ") dispatch");
        }
      }
      if (domain.hostPayloadMode === "passthrough-owner-sanitized"
          && handleWebRequest.body !== null) {
        const body = handleWebRequest.body;
        const bodyCodePositions = codePositionMask(body);
        const requiredStatements = [
          /\bvar\s+flashRequest\s*=\s*parsed\s*!=\s*null\s*\?\s*\(JObject\)\s*parsed\.DeepClone\s*\(\s*\)\s*:\s*new\s+JObject\s*\(\s*\)\s*;/g,
          /\bflashRequest\.Remove\s*\(\s*"panelInstanceId"\s*\)\s*;/g,
          /\bflashRequest\.Remove\s*\(\s*"domain"\s*\)\s*;/g
        ];
        const statementCounts = requiredStatements.map(function (pattern) {
          let count = 0;
          let match;
          while ((match = pattern.exec(body)) !== null) {
            if (bodyCodePositions[match.index]) count += 1;
          }
          return count;
        });
        if (statementCounts.some(function (count) { return count !== 1; })) {
          addError(errors, "source.csharp_owner_sanitizer_drift",
            domainAt + ".hostPayloadMode",
            "owner-sanitized passthrough must deep-clone parsed exactly once and remove "
              + "panelInstanceId/domain exactly once before Flash dispatch; counts="
              + JSON.stringify(statementCounts));
        }
      }
      if (domain.hostPayloadMode === "normalized-domainless-owner-rebuilt"
          && handleWebRequest.body !== null) {
        const body = stripCodeComments(handleWebRequest.body);
        const bodyCodePositions = codePositionMask(body);
        const domainlessPattern = /if\s*\(\s*!\s*WebOverlayForm\.IsStrictDomainlessPanelEnvelope\s*\(\s*parsed\s*\)\s*\)\s*\{/g;
        const domainlessGuards = [];
        let domainlessMatch;
        while ((domainlessMatch = domainlessPattern.exec(body)) !== null) {
          if (!bodyCodePositions[domainlessMatch.index]) continue;
          const guardOpen = body.lastIndexOf("{", domainlessPattern.lastIndex - 1);
          const guardBody = findBalancedBody(body, guardOpen);
          const rejectCalls = guardBody === null
            ? { calls: [], error: "domainless guard body is unterminated" }
            : parseBareCalls(guardBody, "RejectAndRemember");
          const exactRejects = rejectCalls.calls.filter(function (argumentsList) {
            return argumentsList.length >= 3
              && canonicalExpression(argumentsList[0]) === "webCallId"
              && canonicalExpression(argumentsList[1]) === "cmd"
              && quotedLiteral(argumentsList[argumentsList.length - 1]) === "invalid_domain";
          });
          const returnMatches = guardBody === null ? []
            : executableMatches(guardBody, /\breturn\s*;/g);
          domainlessGuards.push(guardBody !== null && !rejectCalls.error
            && rejectCalls.calls.length === 1 && exactRejects.length === 1
            && returnMatches.length === 1);
        }

        const normalizeCalls = parseBareCalls(body, "TryNormalizePayload");
        const exactNormalizeCalls = normalizeCalls.calls.filter(function (argumentsList) {
          return argumentsList.length === 3
            && canonicalExpression(argumentsList[0]) === "cmd"
            && canonicalExpression(argumentsList[1]) === "parsed"
            && canonicalExpression(argumentsList[2]) === "outnormalizedPayload";
        });
        if (domainlessGuards.length !== 1 || domainlessGuards[0] !== true
            || normalizeCalls.error || normalizeCalls.calls.length !== 1
            || exactNormalizeCalls.length !== 1) {
          addError(errors, "source.csharp_domainless_normalizer_drift",
            domainAt + ".hostPayloadMode",
            "domainless normalized mode requires one fail-closed strict-domainless guard "
              + "and one TryNormalizePayload(cmd, parsed, out normalizedPayload) call");
        }

        const requiredOwnerBindings = [
          /\bOwnerPanel\s*=\s*ownerPanel\b/g,
          /\bOwnerPanelInstanceId\s*=\s*ownerPanelInstanceId\b/g,
          /\bNormalizedPayload\s*=\s*\(JObject\)\s*normalizedPayload\.DeepClone\s*\(\s*\)/g
        ];
        const ownerBindingCounts = requiredOwnerBindings.map(function (pattern) {
          return executableMatches(body, pattern).length;
        });
        const forbiddenRawCloneCount = executableMatches(
          body, /\bparsed\.DeepClone\s*\(\s*\)/g).length;
        const forbiddenFlashRequestCount = executableMatches(body, /\bflashRequest\b/g).length;
        if (ownerBindingCounts.some(function (count) { return count !== 1; })
            || forbiddenRawCloneCount !== 0 || forbiddenFlashRequestCount !== 0) {
          addError(errors, "source.csharp_owner_rebuild_drift",
            domainAt + ".hostPayloadMode",
            "domainless normalized mode must freeze exact owner fields and a defensive normalized payload "
              + "without cloning or stripping the raw Web envelope; counts="
              + JSON.stringify(ownerBindingCounts.concat([
                forbiddenRawCloneCount, forbiddenFlashRequestCount
              ])));
        }

        const handleFlashResponse = findCSharpMethodBody(hostSource, "HandleFlashResponse");
        const sanitizeCalls = handleFlashResponse.body === null
          ? { calls: [], error: handleFlashResponse.error }
          : parseBareCalls(handleFlashResponse.body, "TrySanitizeResponseLocked");
        const exactSanitizeCalls = sanitizeCalls.calls.filter(function (argumentsList) {
          return argumentsList.length === 3
            && canonicalExpression(argumentsList[0]) === "msg"
            && canonicalExpression(argumentsList[1]) === "entry"
            && canonicalExpression(argumentsList[2]) === "outsanitized";
        });
        const responseOwnerBindings = handleFlashResponse.body === null ? [] : [
          /\bwebMsg\s*\[\s*"panel"\s*\]\s*=\s*entry\.OwnerPanel\s*;/g,
          /\bwebMsg\s*\[\s*"panelInstanceId"\s*\]\s*=\s*entry\.OwnerPanelInstanceId\s*;/g,
          /\bwebMsg\s*\[\s*"cmd"\s*\]\s*=\s*entry\.WebCmd\s*;/g,
          /\bwebMsg\s*\[\s*"callId"\s*\]\s*=\s*entry\.WebCallId\s*;/g
        ].map(function (pattern) {
          return executableMatches(handleFlashResponse.body, pattern).length;
        });
        if (handleFlashResponse.body === null || sanitizeCalls.error
            || sanitizeCalls.calls.length !== 1 || exactSanitizeCalls.length !== 1
            || responseOwnerBindings.length !== 4
            || responseOwnerBindings.some(function (count) { return count !== 1; })) {
          addError(errors, "source.csharp_response_owner_rebuild_drift",
            domainAt + ".hostPayloadMode",
            "domainless normalized mode must sanitize once and rebuild the exact Web owner envelope "
              + "from pending state; owner counts=" + JSON.stringify(responseOwnerBindings));
        }
      }
      if (domain.hostPayloadMode === "passthrough"
          || domain.hostPayloadMode === "passthrough-owner-sanitized") {
        ["TryReadInteger", "TryNormalizePayload"].forEach(function (method) {
          const calls = parseCalls(hostSource, method);
          if (calls.error || calls.calls.length !== 0) {
            addError(errors, "source.csharp_passthrough_guard", domainAt + ".hostPayloadMode",
              method + " must not add a Host business/quantity cap in passthrough mode");
          }
        });
      }
    }

    let flashResponseTaskCount = 0;
    domain.flashSources.forEach(function (flashFile, flashIndex) {
      const source = read(flashFile, domainAt + ".flashSources[" + flashIndex + "]");
      if (source === null) return;
      parseStaticStringPropertyValues(source, "task").forEach(function (value) {
        if (value === domain.flashResponseTask) flashResponseTaskCount += 1;
      });
    });
    const domainFlashSources = new Set(domain.flashSources.map(slash));
    const delegatedDispatch = domain.flashCommandHandler !== null;
    const delegatedReceivers = new Set();
    domain.commands.forEach(function (command) {
      const registrations = globalFlashRegistrations.get(command.action) || [];
      if (registrations.length !== 1 || registrations[0].body === null) {
        addError(errors, "source.flash_action_drift", domainAt + ".flashSources",
          command.action + " assignment count is " + registrations.length
            + " and must contain exactly one executable function registration");
        return;
      }
      const registration = registrations[0];
      if (!domainFlashSources.has(registration.source)) {
        addError(errors, "source.flash_action_source_drift", domainAt + ".flashSources",
          command.action + " is registered by " + registration.source
            + ", outside this domain's contracted Flash sources");
      }
      if (delegatedDispatch) {
        const dispatchCalls = parseQualifiedCalls(registration.body, "handle");
        const forwardedParameter = registration.parameterNames.length === 1
          ? registration.parameterNames[0] : null;
        const delegatedShapeCalls = dispatchCalls.calls.filter(function (call) {
          return call.arguments.length === 2
            && quotedLiteral(call.arguments[0]) === command.cmd
            && forwardedParameter !== null
            && canonicalExpression(call.arguments[1]) === forwardedParameter;
        });
        delegatedShapeCalls.forEach(function (call) {
          delegatedReceivers.add(call.receiver);
        });
        const exactCalls = delegatedShapeCalls.filter(function (call) {
          return call.receiver === canonicalExpression(domain.flashCommandHandler);
        });
        let thinWrapper = false;
        if (exactCalls.length === 1) {
          const prefix = registration.body.slice(0, exactCalls[0].start).trim();
          const suffix = registration.body.slice(exactCalls[0].end).trim();
          thinWrapper = (prefix === "" || prefix === "return")
            && /^[;\s]*$/.test(suffix);
        }
        if (dispatchCalls.error || delegatedShapeCalls.length !== 1
            || exactCalls.length !== 1 || !thinWrapper) {
          addError(errors, "source.flash_command_dispatch_drift", domainAt + ".flashSources",
            command.action + " must be a thin wrapper that dispatches exactly once to a qualified handle("
              + JSON.stringify(command.cmd) + ", <its sole function parameter>)");
        }
      } else {
        const unexpectedDispatchCalls = parseQualifiedCalls(registration.body, "handle");
        const forwardedParameter = registration.parameterNames.length === 1
          ? registration.parameterNames[0] : null;
        const delegatedShapeCalls = unexpectedDispatchCalls.calls.filter(function (call) {
          return call.arguments.length === 2
            && quotedLiteral(call.arguments[0]) === command.cmd
            && forwardedParameter !== null
            && canonicalExpression(call.arguments[1]) === forwardedParameter;
        });
        if (unexpectedDispatchCalls.error || delegatedShapeCalls.length !== 0) {
          addError(errors, "source.flash_dispatch_mode_drift", domainAt + ".flashCommandHandler",
            command.action + " is inline but contains a delegated handle("
              + JSON.stringify(command.cmd) + ", <its sole function parameter>) wrapper");
        }
        const inlineResponseTasks = parseStaticStringPropertyValues(registration.body, "task");
        const expectedResponseCount = inlineResponseTasks.filter(function (task) {
          return task === domain.flashResponseTask;
        }).length;
        if (expectedResponseCount < 1
            || inlineResponseTasks.some(function (task) { return task !== domain.flashResponseTask; })) {
          addError(errors, "source.flash_response_task_drift", domainAt + ".flashResponseTask",
            command.action + " must emit only the contracted inline response task "
              + JSON.stringify(domain.flashResponseTask) + ", got "
              + JSON.stringify(inlineResponseTasks));
        }
      }
    });
    if (delegatedDispatch
        && (delegatedReceivers.size !== 1
          || !delegatedReceivers.has(canonicalExpression(domain.flashCommandHandler)))) {
      addError(errors, "source.flash_command_handler_drift", domainAt + ".flashSources",
        "delegated domain commands must use contracted AS2 handler "
          + JSON.stringify(domain.flashCommandHandler) + ", got "
          + JSON.stringify(Array.from(delegatedReceivers)));
    }
    if (flashResponseTaskCount < 1) {
      addError(errors, "source.flash_response_task_drift", domainAt + ".flashResponseTask",
        domain.flashResponseTask + " is not emitted by the contracted Flash sources");
    }
    if (taskRegistrySource !== null) {
      const responseRegistrations = taskRegistryCalls.calls.filter(function (call) {
        return call.receiver === "router"
          && call.arguments.length >= 2
          && quotedLiteral(call.arguments[0]) === domain.flashResponseTask;
      });
      const registrations = responseRegistrations.filter(function (call) {
        return canonicalExpression(call.arguments[1]) === canonicalExpression(domain.hostResponseHandler);
      });
      const handlerRegistrations = taskRegistryCalls.calls.filter(function (call) {
        return call.receiver === "router"
          && call.arguments.length >= 2
          && canonicalExpression(call.arguments[1]) === canonicalExpression(domain.hostResponseHandler);
      }).map(function (call) {
        return quotedLiteral(call.arguments[0]);
      });
      if (registrations.length !== 1 || responseRegistrations.length !== 1
          || handlerRegistrations.length !== 1
          || handlerRegistrations[0] !== domain.flashResponseTask) {
        addError(errors, "source.csharp_response_task_drift", domainAt + ".hostResponseHandler",
          "TaskRegistry registration count for " + domain.flashResponseTask + " -> "
            + domain.hostResponseHandler + " is " + registrations.length + " and total task registrations are "
            + responseRegistrations.length + "; handler tasks are "
            + JSON.stringify(handlerRegistrations) + ", all expected to bind exactly once");
      }
    }

    domain.sourceChecks.forEach(function (check, checkIndex) {
      const checkAt = domainAt + ".sourceChecks[" + checkIndex + "]";
      const source = read(check.file, checkAt + ".file");
      if (source === null) return;
      const sourceCodePositions = codePositionMask(source);
      let expectedValue = null;
      if (check.fieldId !== undefined) {
        const boundary = findBoundary(domain, check.fieldId, check.boundary);
        expectedValue = boundary ? boundary.value : null;
      }
      if (check.kind === "csharp-const-int") {
        const pattern = new RegExp("\\bconst\\s+int\\s+" + escapeRegExp(check.symbol) + "\\s*=\\s*(-?\\d+)\\s*;", "g");
        const values = [];
        let match;
        while ((match = pattern.exec(source)) !== null) {
          if (sourceCodePositions[match.index]) values.push(Number(match[1]));
        }
        if (values.length !== 1 || values[0] !== expectedValue) {
          addError(errors, "source.csharp_const_drift", checkAt,
            check.symbol + " parsed values " + JSON.stringify(values) + ", expected [" + expectedValue + "]");
        }
      } else if (check.kind === "csharp-integer-guard") {
        const parsed = parseBareCalls(source, "TryReadInteger");
        if (parsed.error) addError(errors, "source.csharp_guard_parser", checkAt, parsed.error);
        const argument = canonicalExpression(check.argument);
        const relevantCalls = parsed.calls.filter(function (argumentsList) {
          return argumentsList.length >= 3
            && canonicalExpression(argumentsList[0]) === argument;
        });
        const guardDefinitions = [{
          minimum: check.minimum,
          maximum: check.maximum,
          occurrences: check.occurrences
        }].concat(check.allowedAlternates || []);
        let recognizedCount = 0;
        guardDefinitions.forEach(function (guard) {
          const minimum = canonicalExpression(guard.minimum);
          const maximum = canonicalExpression(guard.maximum);
          const count = relevantCalls.filter(function (argumentsList) {
            return canonicalExpression(argumentsList[1]) === minimum
              && canonicalExpression(argumentsList[2]) === maximum;
          }).length;
          recognizedCount += count;
          if (count !== guard.occurrences) {
            addError(errors, "source.csharp_guard_drift", checkAt,
              "parsed integer guard count is " + count + ", expected " + guard.occurrences
                + " for " + check.argument + " in [" + guard.minimum + ", " + guard.maximum + "]");
          }
        });
        if (recognizedCount !== relevantCalls.length) {
          addError(errors, "source.csharp_guard_drift", checkAt,
            "found " + (relevantCalls.length - recognizedCount)
              + " uncontracted integer guard(s) for " + check.argument);
        }
      } else if (check.kind === "as2-number-assignment") {
        const pattern = new RegExp(escapeRegExp(check.symbol) + "(?:\\s*:\\s*[A-Za-z_$][\\w$]*)?\\s*=\\s*(-?\\d+)\\s*;", "g");
        const values = [];
        let match;
        while ((match = pattern.exec(source)) !== null) {
          if (sourceCodePositions[match.index]
              && isUnqualifiedIdentifierAt(source, match.index)) {
            values.push(Number(match[1]));
          }
        }
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
        while ((match = pattern.exec(source)) !== null) {
          if (sourceCodePositions[match.index]) values.push(Number(match[1]));
        }
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
