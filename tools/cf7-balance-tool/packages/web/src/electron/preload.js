const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("cf7Balance", {
  runtime: "electron",
  versions: process.versions,
  getArtifactState: () => ipcRenderer.invoke("cf7:get-artifact-state"),
  getReportHistory: () => ipcRenderer.invoke("cf7:get-report-history"),
  getOutputSettings: () => ipcRenderer.invoke("cf7:get-output-settings"),
  saveOutputSettings: (settings) => ipcRenderer.invoke("cf7:save-output-settings", settings),
  resetOutputSettings: () => ipcRenderer.invoke("cf7:reset-output-settings"),
  pickOutputPath: (key, currentValue) =>
    ipcRenderer.invoke("cf7:pick-output-path", key, currentValue),
  pickPreviewReport: () => ipcRenderer.invoke("cf7:pick-preview-report"),
  pickBatchUpdates: () => ipcRenderer.invoke("cf7:pick-batch-updates"),
  revealPath: (targetPath) => ipcRenderer.invoke("cf7:reveal-path", targetPath),
  saveBatchUpdates: (updates) => ipcRenderer.invoke("cf7:save-batch-updates", updates),
  runBatchPreview: (updates) => ipcRenderer.invoke("cf7:run-batch-preview", updates),
  runBatchSet: (updates) => ipcRenderer.invoke("cf7:run-batch-set", updates)
});

