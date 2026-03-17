const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("cf7Packer", {
  runtime: "electron",
  versions: process.versions,

  loadConfig: () => ipcRenderer.invoke("cf7-packer:load-config"),
  getTags: () => ipcRenderer.invoke("cf7-packer:get-tags"),
  previewFiles: (opts) => ipcRenderer.invoke("cf7-packer:preview-files", opts),
  diffFiles: (opts) => ipcRenderer.invoke("cf7-packer:diff-files", opts),
  run: (opts) => ipcRenderer.invoke("cf7-packer:run", opts),
  buildSfx: (opts) => ipcRenderer.invoke("cf7-packer:build-sfx", opts),
  cancel: () => ipcRenderer.invoke("cf7-packer:cancel"),
  openFile: (relativePath) => ipcRenderer.invoke("cf7-packer:open-file", relativePath),
  revealFile: (relativePath) => ipcRenderer.invoke("cf7-packer:reveal-file", relativePath),
  pickOutputDir: (currentPath) => ipcRenderer.invoke("cf7-packer:pick-output-dir", currentPath),
  revealOutput: (targetPath) => ipcRenderer.invoke("cf7-packer:reveal-output", targetPath),
  excludeFile: (req) => ipcRenderer.invoke("cf7-packer:exclude-file", req),

  onLog: (callback) => {
    const handler = (_event, data) => callback(data);
    ipcRenderer.on("cf7-packer:log", handler);
    return () => ipcRenderer.removeListener("cf7-packer:log", handler);
  },
  onProgress: (callback) => {
    const handler = (_event, data) => callback(data);
    ipcRenderer.on("cf7-packer:progress", handler);
    return () => ipcRenderer.removeListener("cf7-packer:progress", handler);
  }
});
