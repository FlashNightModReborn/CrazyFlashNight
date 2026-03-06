const { contextBridge } = require("electron");

contextBridge.exposeInMainWorld("cf7Balance", {
  runtime: "electron",
  versions: process.versions
});