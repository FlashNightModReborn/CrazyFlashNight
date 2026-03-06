import fs from "node:fs";
import path from "node:path";

import type {
  BalanceProjectConfig,
  FieldRegistry
} from "@cf7-balance-tool/core";

export interface LoadedProjectContext {
  config: BalanceProjectConfig;
  fieldRegistry: FieldRegistry;
  projectConfigPath: string;
  projectRoot: string;
  resolvedDirs: {
    items: string;
    mods?: string;
    enemies?: string;
  };
}

export function loadProjectContext(projectConfigPath: string): LoadedProjectContext {
  const absoluteProjectConfigPath = path.resolve(projectConfigPath);
  const projectRoot = path.dirname(absoluteProjectConfigPath);

  const rawProjectConfig = fs.readFileSync(absoluteProjectConfigPath, "utf8");
  const config = JSON.parse(rawProjectConfig) as BalanceProjectConfig;

  const fieldConfigPath = path.resolve(
    projectRoot,
    config.fieldConfig ?? "./data/field-config.json"
  );
  const rawFieldConfig = fs.readFileSync(fieldConfigPath, "utf8");
  const fieldRegistry = JSON.parse(rawFieldConfig) as FieldRegistry;

  const resolvedDirs: LoadedProjectContext["resolvedDirs"] = {
    items: path.resolve(projectRoot, config.dataDirs.items)
  };

  if (config.dataDirs.mods) {
    resolvedDirs.mods = path.resolve(projectRoot, config.dataDirs.mods);
  }

  if (config.dataDirs.enemies) {
    resolvedDirs.enemies = path.resolve(projectRoot, config.dataDirs.enemies);
  }

  return {
    config,
    fieldRegistry,
    projectConfigPath: absoluteProjectConfigPath,
    projectRoot,
    resolvedDirs
  };
}