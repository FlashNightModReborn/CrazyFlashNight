import path from "node:path";
import type { PackConfig } from "./types.js";

const INVALID_PATH_CHARS = /[<>:"/\\|?*\u0000-\u001f]/g;
const OUTPUT_TOKEN = /\{(version|mode|tag|date|timestamp)\}/g;

function pad2(value: number): string {
  return String(value).padStart(2, "0");
}

export function sanitizePathToken(value: string, fallback = "default"): string {
  const sanitized = value
    .trim()
    .replace(INVALID_PATH_CHARS, "-")
    .replace(/[. ]+$/g, "")
    .replace(/\s+/g, " ");

  return sanitized || fallback;
}

export function renderOutputDirTemplate(template: string, config: PackConfig, now = new Date()): string {
  const replacements = {
    version: String(config.version),
    mode: config.source.mode,
    tag: sanitizePathToken(config.source.tag ?? "worktree"),
    date: `${now.getFullYear()}-${pad2(now.getMonth() + 1)}-${pad2(now.getDate())}`,
    timestamp: [
      now.getFullYear(),
      pad2(now.getMonth() + 1),
      pad2(now.getDate())
    ].join("") + "-" + [
      pad2(now.getHours()),
      pad2(now.getMinutes()),
      pad2(now.getSeconds())
    ].join("")
  } satisfies Record<string, string>;

  return template.replace(OUTPUT_TOKEN, (_match, token: keyof typeof replacements) => replacements[token]);
}

export function resolveOutputDir(config: PackConfig, configDirOrPath: string, outputDir?: string, now?: Date): string {
  const basePath = path.resolve(configDirOrPath);
  const configDir = path.extname(basePath) ? path.dirname(basePath) : basePath;
  const rendered = renderOutputDirTemplate(outputDir ?? config.output.dir, config, now);
  return path.resolve(configDir, rendered);
}
