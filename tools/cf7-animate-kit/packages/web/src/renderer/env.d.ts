/// <reference types="vite/client" />

import type { AnkitApi } from "../shared/ipc-types.js";

declare global {
  interface Window {
    ankit?: AnkitApi;
  }
}

export {};
