// Preload (CommonJS). Runs in an isolated context with Node's `require`, and
// exposes ONLY the typed, channel-bound bridge below to the renderer. The
// renderer never sees ipcRenderer, fs, or an-host directly.
const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("ankit", {
  runtime: "electron",
  versions: process.versions,

  // --- Tab A: AN maintenance ---
  doctor: () => ipcRenderer.invoke("ankit:doctor"),
  pickSwf: () => ipcRenderer.invoke("ankit:pick-swf"),
  pickDat: () => ipcRenderer.invoke("ankit:pick-dat"),
  installSwf: (req) => ipcRenderer.invoke("ankit:install-swf", req),
  clearCache: (req) => ipcRenderer.invoke("ankit:clear-cache", req),
  setJvmMemory: (req) => ipcRenderer.invoke("ankit:set-jvm-memory", req),
  tightenSidebar: (req) => ipcRenderer.invoke("ankit:tighten-sidebar", req),
  openFolder: (req) => ipcRenderer.invoke("ankit:open-folder", req),

  // --- Tab B: SOL inspector / editor ---
  openSol: () => ipcRenderer.invoke("ankit:open-sol"),
  previewSolSave: (req) => ipcRenderer.invoke("ankit:preview-sol-save", req),
  saveSol: (req) => ipcRenderer.invoke("ankit:save-sol", req),
});
