import { describe, expect, it } from "vitest";

import {
  DEFAULT_FIELD_REGISTRY,
  classifyField,
  uniquePreservingOrder
} from "../src/index.js";

describe("classifyField", () => {
  it("classifies numeric fields", () => {
    expect(classifyField("power", DEFAULT_FIELD_REGISTRY)).toBe("numeric");
  });

  it("classifies attribute fields", () => {
    expect(classifyField("@path", DEFAULT_FIELD_REGISTRY)).toBe("attribute");
  });

  it("classifies suffix-based min and max fields as numeric", () => {
    expect(classifyField("躲闪率_max", DEFAULT_FIELD_REGISTRY)).toBe("numeric");
    expect(classifyField("hp_min", DEFAULT_FIELD_REGISTRY)).toBe("numeric");
  });

  it("classifies nested numeric children by container context", () => {
    expect(
      classifyField("电", DEFAULT_FIELD_REGISTRY, [
        "root",
        "item",
        "data",
        "magicdefence",
        "电"
      ])
    ).toBe("nested-numeric");
  });

  it("keeps unknown fields explicit", () => {
    expect(classifyField("mysteryField", DEFAULT_FIELD_REGISTRY)).toBe(
      "unknown"
    );
  });
});

describe("uniquePreservingOrder", () => {
  it("removes duplicates without reordering", () => {
    expect(uniquePreservingOrder(["a", "b", "a", "c"])).toEqual([
      "a",
      "b",
      "c"
    ]);
  });
});