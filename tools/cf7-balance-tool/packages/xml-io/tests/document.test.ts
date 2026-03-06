import { describe, expect, it } from "vitest";

import { parseXmlDocument } from "../src/document.js";

const sampleXml = `<?xml version="1.0" encoding="UTF-8"?>
<!--
物品ID已自动生成，无需手动维护-->
<root>
  <item weapontype="压制机枪">
      <name>XM556-OC-Overlord</name>
      <data>
        <power>40</power>
      </data>
    </item>
  <item weapontype="压制机枪">
      <name>XM556-H-Stinger</name>
      <data>
        <power>40</power>
      </data>
    </item>
</root>
`;

const sampleModXml = `<?xml version="1.0" encoding="UTF-8"?>
<root>
  <mod>
    <name>战术鱼骨零件</name>
    <use>长枪</use>
    <stats>
      <useSwitch>
        <use name="突击步枪">
          <provideTags>NOAH,电力</provideTags>
        </use>
      </useSwitch>
    </stats>
  </mod>
</root>
`;

describe("XmlDocument", () => {
  it("preserves the original source on no-op round-trip", () => {
    const document = parseXmlDocument(sampleXml);

    expect(document.serialize()).toBe(sampleXml);
  });

  it("reads and updates a leaf text node with minimal replacement", () => {
    const document = parseXmlDocument(sampleXml);

    expect(document.getNodeText("root.item[1].data.power")).toBe("40");

    document.setNodeText("root.item[1].data.power", "55");
    const serialized = document.serialize();

    expect(serialized).toContain("<power>55</power>");
    expect(serialized).toContain("<name>XM556-OC-Overlord</name>");
    expect(serialized).toContain("<!--\n物品ID已自动生成，无需手动维护-->");
    expect((serialized.match(/<power>40<\/power>/g) ?? []).length).toBe(1);
  });

  it("reads and updates an attribute value without changing quote style", () => {
    const document = parseXmlDocument(sampleModXml);

    expect(document.getAttribute("root.mod.stats.useSwitch.use", "name")).toBe(
      "突击步枪"
    );

    document.setAttribute("root.mod.stats.useSwitch.use", "name", "霰弹枪");

    expect(document.serialize()).toContain('<use name="霰弹枪">');
  });

  it("rejects setting text on a non-leaf node", () => {
    const document = parseXmlDocument(sampleXml);

    expect(() => document.setNodeText("root.item[1].data", "invalid")).toThrow(
      /non-leaf node/
    );
  });
});