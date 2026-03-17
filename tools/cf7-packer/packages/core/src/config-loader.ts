import fs from "node:fs";
import path from "node:path";
import { parse as parseYaml } from "yaml";
import { packConfigSchema } from "./config-schema.js";
import type { PackConfig, LayerRule } from "./types.js";

function buildLayerRule(raw: { name: string; description?: string | undefined; source: string; include: string[]; exclude: string[] }): LayerRule {
  const rule: LayerRule = {
    name: raw.name,
    source: raw.source,
    include: raw.include,
    exclude: raw.exclude
  };
  if (raw.description !== undefined) {
    rule.description = raw.description;
  }
  return rule;
}

function buildConfig(parsed: ReturnType<typeof packConfigSchema.parse>, resolvedRepoRoot: string): PackConfig {
  const config: PackConfig = {
    version: parsed.version,
    meta: { name: parsed.meta.name },
    source: {
      mode: parsed.source.mode,
      repoRoot: resolvedRepoRoot
    },
    output: {
      dir: parsed.output.dir,
      clean: parsed.output.clean
    },
    layers: parsed.layers.map(buildLayerRule),
    globalExclude: parsed.globalExclude
  };

  if (parsed.meta.description !== undefined) {
    config.meta.description = parsed.meta.description;
  }
  if (parsed.source.tag != null) {
    config.source.tag = parsed.source.tag;
  }

  return config;
}

/**
 * 从 YAML 文件加载并校验打包配置。
 * repoRoot 会被解析为相对于配置文件所在目录的绝对路径。
 */
export function loadConfig(configPath: string): PackConfig {
  const absolutePath = path.resolve(configPath);
  const content = fs.readFileSync(absolutePath, "utf8");
  const raw: unknown = parseYaml(content);
  const parsed = packConfigSchema.parse(raw);

  const configDir = path.dirname(absolutePath);
  const resolvedRepoRoot = path.resolve(configDir, parsed.source.repoRoot);

  return buildConfig(parsed, resolvedRepoRoot);
}

/**
 * 从内存中的 JS 对象校验配置（用于 GUI 传入）。
 */
export function parseConfig(raw: unknown, configDir: string): PackConfig {
  const parsed = packConfigSchema.parse(raw);
  const resolvedRepoRoot = path.resolve(configDir, parsed.source.repoRoot);

  return buildConfig(parsed, resolvedRepoRoot);
}
