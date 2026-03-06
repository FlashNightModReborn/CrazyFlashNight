import { describe, expect, it } from "vitest";

import { DEFAULT_FIELD_REGISTRY } from "@cf7-balance-tool/core";

import { scanXmlContent } from "../src/scanner.js";

describe("scanXmlContent", () => {
  it("collects leaf tags and attributes", () => {
    const xml = `
      <root>
        <item weapontype="压制机枪">
          <name>XM556-H-Stinger</name>
          <data>
            <power>40</power>
            <magicdefence>
              <电>10</电>
            </magicdefence>
          </data>
          <lifecycle>
            <attr_0>
              <skill>
                <skillname>凶斩</skillname>
              </skill>
            </attr_0>
          </lifecycle>
        </item>
      </root>
    `;

    const occurrences = scanXmlContent(
      xml,
      "data/items/武器_手枪_压制机枪.xml",
      "equipment",
      DEFAULT_FIELD_REGISTRY
    );

    expect(occurrences.some((item) => item.field === "@weapontype")).toBe(true);
    expect(occurrences.some((item) => item.field === "power")).toBe(true);
    expect(occurrences.some((item) => item.field === "skillname")).toBe(true);
    expect(
      occurrences.some(
        (item) =>
          item.path.endsWith("data.magicdefence.电") &&
          item.classification === "nested-numeric"
      )
    ).toBe(true);
  });
});