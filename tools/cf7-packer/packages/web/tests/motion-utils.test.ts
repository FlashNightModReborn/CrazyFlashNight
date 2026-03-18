import { describe, expect, it } from "vitest";
import {
  getMotionProfile,
  resolveMotionLevel
} from "../src/renderer/components/motion-utils.js";

describe("motion-utils", () => {
  it("keeps the preferred level when reduced motion is not requested", () => {
    expect(resolveMotionLevel("standard", false)).toBe("standard");
    expect(resolveMotionLevel("light", false)).toBe("light");
  });

  it("softens standard motion when reduced motion is requested", () => {
    expect(resolveMotionLevel("standard", true)).toBe("light");
    expect(resolveMotionLevel("light", true)).toBe("light");
    expect(resolveMotionLevel("off", true)).toBe("off");
  });

  it("returns lightweight timing profiles", () => {
    expect(getMotionProfile("off")).toEqual({
      level: "off",
      settleMs: 0,
      emphasisMs: 0,
      overlayOpacity: 0,
      surfaceLift: 0
    });

    expect(getMotionProfile("light")).toMatchObject({
      level: "light",
      settleMs: 140,
      emphasisMs: 170
    });

    expect(getMotionProfile("standard").settleMs).toBeGreaterThan(getMotionProfile("light").settleMs);
  });
});
