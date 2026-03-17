/// <reference types="vite/client" />

import type { PackerIpcApi } from "../shared/ipc-types.js";

declare global {
  interface Window {
    cf7Packer?: PackerIpcApi;
  }
}

export {};
