import { useState, useEffect } from "react";

export function useStoredNumber(key: string, fallback: number, persistEnabled = true) {
  const [value, setValue] = useState(() => {
    if (typeof window === "undefined") return fallback;
    const stored = window.localStorage.getItem(key);
    const parsed = stored ? Number(stored) : Number.NaN;
    return Number.isFinite(parsed) ? parsed : fallback;
  });

  useEffect(() => {
    if (!persistEnabled) return;
    window.localStorage.setItem(key, String(value));
  }, [key, persistEnabled, value]);

  return [value, setValue] as const;
}

export function useStoredString<T extends string>(key: string, fallback: T, persistEnabled = true) {
  const [value, setValue] = useState<T>(() => {
    if (typeof window === "undefined") return fallback;
    const stored = window.localStorage.getItem(key);
    return stored ? stored as T : fallback;
  });

  useEffect(() => {
    if (!persistEnabled) return;
    window.localStorage.setItem(key, value);
  }, [key, persistEnabled, value]);

  return [value, setValue] as const;
}
