const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("cf7Packer", {
  runtime: "electron",
  versions: process.versions,

  loadConfig: () => ipcRenderer.invoke("cf7-packer:load-config"),
  getTags: () => ipcRenderer.invoke("cf7-packer:get-tags"),
  run: (opts) => ipcRenderer.invoke("cf7-packer:run", opts),
  cancel: () => ipcRenderer.invoke("cf7-packer:cancel"),
  pickOutputDir: (currentPath) => ipcRenderer.invoke("cf7-packer:pick-output-dir", currentPath),
  revealOutput: (targetPath) => ipcRenderer.invoke("cf7-packer:reveal-output", targetPath),

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
