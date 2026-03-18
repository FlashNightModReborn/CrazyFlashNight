export type MotionLevel = "off" | "light" | "standard";

export interface MotionProfile {
  level: MotionLevel;
  settleMs: number;
  emphasisMs: number;
  overlayOpacity: number;
  surfaceLift: number;
}

export function resolveMotionLevel(preferred: MotionLevel, prefersReducedMotion: boolean): MotionLevel {
  if (!prefersReducedMotion) return preferred;
  if (preferred === "standard") return "light";
  return preferred;
}

export function getMotionProfile(level: MotionLevel): MotionProfile {
  switch (level) {
    case "off":
      return {
        level,
        settleMs: 0,
        emphasisMs: 0,
        overlayOpacity: 0,
        surfaceLift: 0
      };
    case "standard":
      return {
        level,
        settleMs: 190,
        emphasisMs: 220,
        overlayOpacity: 0.18,
        surfaceLift: 6
      };
    case "light":
    default:
      return {
        level: "light",
        settleMs: 140,
        emphasisMs: 170,
        overlayOpacity: 0.12,
        surfaceLift: 4
      };
  }
}
