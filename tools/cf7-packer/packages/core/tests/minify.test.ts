import { describe, it, expect } from "vitest";
import { minifyJson, minifyXml, minifyByExtension } from "../src/minify.js";

describe("minifyJson", () => {
  it("removes indentation from formatted JSON", () => {
    const input = '{\n  "name": "test",\n  "value": 42\n}';
    expect(minifyJson(input)).toBe('{"name":"test","value":42}');
  });

  it("handles already minified JSON", () => {
    const input = '{"a":1}';
    expect(minifyJson(input)).toBe('{"a":1}');
  });

  it("handles empty object", () => {
    expect(minifyJson("{}")).toBe("{}");
  });

  it("handles empty array", () => {
    expect(minifyJson("[]")).toBe("[]");
  });

  it("throws on invalid JSON", () => {
    expect(() => minifyJson("{invalid}")).toThrow();
  });
});

describe("minifyXml", () => {
  it("removes whitespace between tags", () => {
    const input = "<root>\n  <child>text</child>\n</root>";
    expect(minifyXml(input)).toBe("<root><child>text</child></root>");
  });

  it("preserves CDATA content", () => {
    const input = "<root>\n  <data><![CDATA[  hello\n  world  ]]></data>\n</root>";
    const result = minifyXml(input);
    expect(result).toContain("<![CDATA[  hello\n  world  ]]>");
    expect(result).toBe("<root><data><![CDATA[  hello\n  world  ]]></data></root>");
  });

  it("handles multiple CDATA sections", () => {
    const input = "<a><![CDATA[x]]></a>\n<b><![CDATA[y]]></b>";
    const result = minifyXml(input);
    expect(result).toContain("<![CDATA[x]]>");
    expect(result).toContain("<![CDATA[y]]>");
  });

  it("trims leading/trailing whitespace", () => {
    const input = "  \n<root/>\n  ";
    expect(minifyXml(input)).toBe("<root/>");
  });

  it("handles empty input", () => {
    expect(minifyXml("")).toBe("");
  });

  it("falls back on CDATA placeholder collision", () => {
    // Content containing the placeholder pattern should cause fallback
    const input = "<root>__CDATA_0__<![CDATA[data]]></root>";
    const result = minifyXml(input);
    // Should return original content unchanged
    expect(result).toBe(input);
  });
});

describe("minifyByExtension", () => {
  it("minifies .json files", () => {
    const result = minifyByExtension('{ "a": 1 }', ".json");
    expect(result).toBe('{"a":1}');
  });

  it("minifies .xml files", () => {
    const result = minifyByExtension("<a>\n  <b/>\n</a>", ".xml");
    expect(result).toBe("<a><b/></a>");
  });

  it("returns null for unknown extension", () => {
    expect(minifyByExtension("data", ".txt")).toBeNull();
  });

  it("returns null for invalid JSON", () => {
    expect(minifyByExtension("{bad}", ".json")).toBeNull();
  });

  it("is case-insensitive for extensions", () => {
    expect(minifyByExtension('{"a":1}', ".JSON")).toBe('{"a":1}');
    expect(minifyByExtension("<a/>", ".XML")).toBe("<a/>");
  });
});
