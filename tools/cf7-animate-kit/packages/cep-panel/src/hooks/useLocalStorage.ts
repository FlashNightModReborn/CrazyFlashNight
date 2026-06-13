/**
 * useLocalStorage — tiny persisted-state hooks (mirrors cf7-packer's pattern).
 *
 * CEP runs in a sandboxed CEF webview where localStorage is available but can
 * throw in some host configs, so every access is wrapped in try/catch and
 * falls back gracefully. `persistEnabled` lets a caller suspend writes (e.g.
 * mid-drag) so we don't thrash storage during a resize.
 */
import { useState, useEffect } from 'react';

function readRaw(key: string): string | null {
  try {
    if (typeof window === 'undefined' || !window.localStorage) return null;
    return window.localStorage.getItem(key);
  } catch {
    return null;
  }
}

function writeRaw(key: string, value: string): void {
  try {
    if (typeof window === 'undefined' || !window.localStorage) return;
    window.localStorage.setItem(key, value);
  } catch {
    /* storage disabled — ignore */
  }
}

export function useStoredString<T extends string = string>(
  key: string,
  fallback: NoInfer<T>,
  persistEnabled = true,
) {
  const [value, setValue] = useState<T>(() => {
    const stored = readRaw(key);
    return stored != null ? (stored as T) : fallback;
  });

  useEffect(() => {
    if (!persistEnabled) return;
    writeRaw(key, value);
  }, [key, persistEnabled, value]);

  return [value, setValue] as const;
}

export function useStoredNumber(key: string, fallback: number, persistEnabled = true) {
  const [value, setValue] = useState<number>(() => {
    const stored = readRaw(key);
    const parsed = stored != null ? Number(stored) : Number.NaN;
    return Number.isFinite(parsed) ? parsed : fallback;
  });

  useEffect(() => {
    if (!persistEnabled) return;
    writeRaw(key, String(value));
  }, [key, persistEnabled, value]);

  return [value, setValue] as const;
}

export function useStoredBool(key: string, fallback: boolean, persistEnabled = true) {
  const [value, setValue] = useState<boolean>(() => {
    const stored = readRaw(key);
    if (stored == null) return fallback;
    return stored === '1' || stored === 'true';
  });

  useEffect(() => {
    if (!persistEnabled) return;
    writeRaw(key, value ? '1' : '0');
  }, [key, persistEnabled, value]);

  return [value, setValue] as const;
}
