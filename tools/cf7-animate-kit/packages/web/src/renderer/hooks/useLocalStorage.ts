import { useState, useEffect } from "react";

/**
 * Persists a number under `key`. When `persistEnabled` is false (e.g. mid-drag)
 * the latest value is held in memory but not written, so we don't thrash
 * localStorage on every pointermove.
 */
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

/** Persists a string (or string-literal union) under `key`. */
export function useStoredString<T extends string>(key: string, fallback: T, persistEnabled = true) {
  const [value, setValue] = useState<T>(() => {
    if (typeof window === "undefined") return fallback;
    const stored = window.localStorage.getItem(key);
    return stored ? (stored as T) : fallback;
  });

  useEffect(() => {
    if (!persistEnabled) return;
    window.localStorage.setItem(key, value);
  }, [key, persistEnabled, value]);

  return [value, setValue] as const;
}

/** Persists a boolean under `key`. */
export function useStoredBoolean(key: string, fallback: boolean, persistEnabled = true) {
  const [value, setValue] = useState<boolean>(() => {
    if (typeof window === "undefined") return fallback;
    const stored = window.localStorage.getItem(key);
    if (stored === null) return fallback;
    return stored === "true";
  });

  useEffect(() => {
    if (!persistEnabled) return;
    window.localStorage.setItem(key, value ? "true" : "false");
  }, [key, persistEnabled, value]);

  return [value, setValue] as const;
}
