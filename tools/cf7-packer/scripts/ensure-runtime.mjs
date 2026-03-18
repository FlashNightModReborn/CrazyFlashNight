#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const toolRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const requireFromTool = createRequire(path.join(toolRoot, "package.json"));

// electron 二进制由 launch.bat 独立下载到 %TEMP%，不依赖 node_modules/electron/dist
// 这里只检查 JS 依赖（构建和运行时所需的 npm 包）
const requiredModules = [
  "vite",
  "esbuild",
  "react",
  "react-dom",
  "d3",
  "yaml",
  "picomatch"
];

function log(message) {
  process.stdout.write(`${message}\n`);
}

function exists(targetPath) {
  return fs.existsSync(targetPath);
}

function latestMtime(targetPaths) {
  let latest = 0;
  for (const targetPath of targetPaths) {
    if (!exists(targetPath)) continue;
    const stat = fs.statSync(targetPath);
    if (stat.isDirectory()) {
      for (const entry of fs.readdirSync(targetPath, { withFileTypes: true })) {
        latest = Math.max(latest, latestMtime([path.join(targetPath, entry.name)]));
      }
      continue;
    }
    latest = Math.max(latest, stat.mtimeMs);
  }
  return latest;
}

function moduleInstalled(moduleName) {
  try {
    requireFromTool.resolve(moduleName);
    return true;
  } catch {
    return false;
  }
}

function run(command, args) {
  if (process.platform === "win32") {
    const quoted = [command, ...args].map((part) => part.includes(" ") ? `"${part}"` : part).join(" ");
    execFileSync(process.env.ComSpec ?? "cmd.exe", ["/d", "/s", "/c", quoted], {
      cwd: toolRoot,
      stdio: "inherit",
      env: process.env
    });
    return;
  }

  execFileSync(command, args, {
    cwd: toolRoot,
    stdio: "inherit",
    env: process.env
  });
}

function ensureInstall() {
  const nodeModules = path.join(toolRoot, "node_modules");
  const npmState = path.join(nodeModules, ".package-lock.json");
  const packageInputs = [
    path.join(toolRoot, "package.json"),
    path.join(toolRoot, "package-lock.json"),
    path.join(toolRoot, "packages", "core", "package.json"),
    path.join(toolRoot, "packages", "web", "package.json"),
    path.join(toolRoot, "packages", "cli", "package.json")
  ];

  const missingModules = requiredModules.filter((name) => !moduleInstalled(name));
  const inputsNewerThanInstall = latestMtime(packageInputs) > latestMtime([npmState]);

  if (!exists(nodeModules) || missingModules.length > 0 || inputsNewerThanInstall) {
    if (missingModules.length > 0) {
      log(`[!] 依赖缺失: ${missingModules.join(", ")}`);
    } else if (inputsNewerThanInstall) {
      log("[!] package.json / lockfile 已更新，正在同步依赖...");
    } else {
      log("[!] 首次运行，正在安装依赖...");
    }
    run(process.platform === "win32" ? "npm.cmd" : "npm", ["install"]);
  }
}

function ensureBuild(label, workspace, inputs, outputs) {
  if (latestMtime(inputs) <= latestMtime(outputs)) {
    return;
  }
  log(`[!] ${label} 产物过期，正在重建...`);
  run(process.platform === "win32" ? "npm.cmd" : "npm", ["run", "build", "--workspace", workspace]);
}

ensureInstall();

ensureBuild("core", "@cf7-packer/core", [
  path.join(toolRoot, "packages", "core", "src"),
  path.join(toolRoot, "packages", "core", "package.json"),
  path.join(toolRoot, "packages", "core", "tsconfig.json"),
  path.join(toolRoot, "tsconfig.base.json")
], [
  path.join(toolRoot, "packages", "core", "dist")
]);

ensureBuild("web", "@cf7-packer/web", [
  path.join(toolRoot, "packages", "web", "src"),
  path.join(toolRoot, "packages", "web", "package.json"),
  path.join(toolRoot, "packages", "web", "vite.config.ts"),
  path.join(toolRoot, "packages", "web", "tsconfig.json"),
  path.join(toolRoot, "packages", "web", "tsconfig.electron.json"),
  path.join(toolRoot, "packages", "core", "dist")
], [
  path.join(toolRoot, "packages", "web", "dist")
]);
