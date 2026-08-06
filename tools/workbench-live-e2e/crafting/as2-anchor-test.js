#!/usr/bin/env node
"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const SourceContract = require("./source-contract");

function replaceSpan(source, observed, replacement) {
  return source.slice(0, observed.start) + replacement + source.slice(observed.end);
}

function replaceModifiers(member, expectation, replacement) {
  const marker = expectation.modifiers.join(" ") + " function " + expectation.functionName;
  assert.ok(member.includes(marker), "production member must expose its exact modifier prefix");
  return member.replace(marker,
    (replacement ? replacement + " " : "") + "function " + expectation.functionName);
}

function addParameter(member, functionName) {
  const marker = "function " + functionName + "(";
  const open = member.indexOf(marker);
  assert.ok(open >= 0, "production member must expose its exact function marker");
  const insertion = open + marker.length;
  const remainder = member.slice(insertion);
  const prefix = /^\s*\)/.test(remainder) ? "__craftingV7Extra:Object" : "__craftingV7Extra:Object, ";
  return member.slice(0, insertion) + prefix + member.slice(insertion);
}

function driftReturnType(member) {
  const drifted = member.replace(/(\)\s*:\s*)[\p{L}\p{Nl}_$][\p{L}\p{Nl}\p{Nd}\p{Mn}\p{Mc}\p{Pc}_$]*/u,
    "$1__CraftingV7ReturnType");
  assert.notStrictEqual(drifted, member, "production member must expose one return type");
  return drifted;
}

function expectContractReject(source, expectation, label) {
  assert.throws(() => {
    const observed = SourceContract.extractAs2FunctionContract(source, expectation);
    SourceContract.assertAs2FunctionExpectation(observed, expectation);
  }, (error) => error && /^as2_algorithm_/.test(String(error.code || "")), label);
}

function run(root) {
  const productionRoot = path.resolve(root);
  let baselineAccepted = 0;
  let neutralAccepted = 0;
  let rejected = 0;
  const variantsPerAnchor = 14;

  SourceContract.AS2_ALGORITHM_EXPECTATIONS.forEach((expectation, anchorIndex) => {
    const source = fs.readFileSync(path.resolve(productionRoot, expectation.relativePath), "utf8");
    const observed = SourceContract.extractAs2FunctionContract(source, expectation);
    assert.strictEqual(SourceContract.assertAs2FunctionExpectation(observed, expectation), true);
    baselineAccepted += 1;

    const member = source.slice(observed.start, observed.end);
    const functionMarker = "function " + expectation.functionName;
    const neutralMember = member.replace(functionMarker,
      "function /* crafting-v7-neutral */   " + expectation.functionName);
    assert.notStrictEqual(neutralMember, member);
    const neutralSource = replaceSpan(source, observed,
      "\n/* crafting-v7-neutral-boundary */\n" + neutralMember + "\n");
    const neutralObserved = SourceContract.extractAs2FunctionContract(neutralSource, expectation);
    assert.strictEqual(SourceContract.assertAs2FunctionExpectation(neutralObserved, expectation), true);
    neutralAccepted += 1;

    const wrapperModifiers = expectation.modifiers.join(" ");
    const bodyOpen = member.indexOf("{");
    assert.ok(bodyOpen >= 0, "production member must expose one body boundary");
    const bodyDrift = member.slice(0, member.lastIndexOf("}")) + ";\n}";
    const classMarker = "class " + expectation.className;
    assert.ok(source.includes(classMarker), "production source must expose its exact class marker");
    const wrongVisibility = expectation.modifiers[0] === "private" ? "public" : "private";
    const wrongModifiers = expectation.modifiers.length === 2
      ? wrongVisibility + " static" : wrongVisibility;
    const missingModifiers = expectation.modifiers.length === 2 ? "static" : "";
    const mutations = [
      ["class-external member", source.slice(0, observed.start) + source.slice(observed.end)
        + "\n" + member + "\n"],
      ["conditional member", replaceSpan(source, observed, "if(false) {\n" + member + "\n}")],
      ["extra-block member", replaceSpan(source, observed, "{\n" + member + "\n}")],
      ["outer-function member", replaceSpan(source, observed,
        wrapperModifiers + " function __craftingV7Outer" + anchorIndex + "():Void {\n"
          + member + "\n}")],
      ["wrong modifier", replaceSpan(source, observed,
        replaceModifiers(member, expectation, wrongModifiers))],
      ["missing modifier", replaceSpan(source, observed,
        replaceModifiers(member, expectation, missingModifiers))],
      ["duplicate target member", replaceSpan(source, observed, member + "\n" + member)],
      ["nested helper function", replaceSpan(source, observed,
        member.slice(0, bodyOpen + 1) + "\nfunction __craftingV7Nested():Void {}\n"
          + member.slice(bodyOpen + 1))],
      ["nested target class", "function __craftingV7FileOuter():Void {\n" + source + "\n}"],
      ["duplicate target class", source + "\n" + source],
      ["signature drift", replaceSpan(source, observed,
        addParameter(member, expectation.functionName))],
      ["return drift", replaceSpan(source, observed, driftReturnType(member))],
      ["body drift", replaceSpan(source, observed, bodyDrift)],
      ["target class name drift", source.replace(classMarker, classMarker + "Drift")],
    ];
    assert.strictEqual(mutations.length, variantsPerAnchor);
    mutations.forEach(([label, mutated]) => {
      assert.notStrictEqual(mutated, source, label);
      expectContractReject(mutated, expectation,
        expectation.functionName + " must reject " + label);
      rejected += 1;
    });
  });

  const anchors = SourceContract.AS2_ALGORITHM_EXPECTATIONS.length;
  assert.strictEqual(anchors, 24);
  assert.strictEqual(baselineAccepted, anchors);
  assert.strictEqual(neutralAccepted, anchors);
  assert.strictEqual(rejected, anchors * variantsPerAnchor);
  SourceContract.AS2_ALGORITHM_EXPECTATIONS.forEach((expectation) => {
    ["signatureTokenSha256", "returnTokenSha256", "bodyTokenSha256",
      "normalizedTokenSha256"].forEach((field) => {
      assert.match(expectation[field], /^[a-f0-9]{64}$/);
      assert.notStrictEqual(expectation[field], "0".repeat(64));
    });
  });
  return { anchors, baselineAccepted, neutralAccepted, variantsPerAnchor, rejected,
    totalAssertions: baselineAccepted + neutralAccepted + rejected };
}

if (require.main === module) {
  const result = run(path.resolve(__dirname, "..", "..", ".."));
  process.stdout.write("Crafting AS2 structural anchors: " + result.totalAssertions + "/"
    + result.totalAssertions + "\n" + JSON.stringify(result) + "\n");
}

module.exports = { run };
