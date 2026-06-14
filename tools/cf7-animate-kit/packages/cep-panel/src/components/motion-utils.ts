/**
 * motion-utils — lightweight, CSS-driven motion (mirrors cf7-packer).
 * No animation library; we just expose a profile of durations/offsets that the
 * shell publishes as CSS custom properties and toggles via class names.
 * CEP/Chromium-88 friendly: only transitions + transforms, no Web Animations.
 */
export type MotionLevel = 'off' | 'light' | 'standard';

export interface MotionProfile {
  level: MotionLevel;
  settleMs: number;
  emphasisMs: number;
  surfaceLift: number;
}

export function getMotionProfile(level: MotionLevel): MotionProfile {
  switch (level) {
    case 'off':
      return { level, settleMs: 0, emphasisMs: 0, surfaceLift: 0 };
    case 'standard':
      return { level, settleMs: 200, emphasisMs: 240, surfaceLift: 6 };
    case 'light':
    default:
      return { level: 'light', settleMs: 140, emphasisMs: 170, surfaceLift: 4 };
  }
}

export const MOTION_OPTIONS: ReadonlyArray<{ value: MotionLevel; label: string }> = [
  { value: 'off', label: 'Off' },
  { value: 'light', label: 'Light' },
  { value: 'standard', label: 'Standard' },
];
