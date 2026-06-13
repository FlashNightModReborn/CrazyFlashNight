/**
 * Ambient types for the CEP runtime globals and our minimal CSInterface shim.
 *
 * `window.__adobe_cep__` is injected by Adobe's CEP host into every panel; it
 * is the low-level bridge our shim (src/lib/CSInterface.js) wraps. We type only
 * the members we actually call.
 */

export interface AdobeCepHostEnvironment {
  appName: string;
  appVersion: string;
  appLocale: string;
  appUILocale: string;
  appId: string;
  isAppOnline: boolean;
}

export interface AdobeCepBridge {
  /** Run an expression in the host (Animate JSFL) VM; result is a string. */
  evalScript(script: string, callback: (result: string) => void): void;
  /** JSON string of the host environment. */
  getHostEnvironment(): string;
  /** OS description string. */
  getOSInformation(): string;
}

declare global {
  interface Window {
    __adobe_cep__?: AdobeCepBridge;
    /**
     * Optional dev marker. index.html sets this when serving the Vite dev
     * server, so the app can branch on a real-host vs browser-preview.
     */
    __CF7AK_DEV__?: boolean;
  }
}

// NOTE: We deliberately do NOT `declare module './CSInterface.js'` here — that
// file is real JS with JSDoc and `allowJs:true`, so TypeScript infers its types
// directly (a fake ambient module would shadow/conflict with the inferred one).

export {};
