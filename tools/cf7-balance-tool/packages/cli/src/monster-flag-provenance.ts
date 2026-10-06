/**
 * 标识的人工权威判定 — 只认 git HEAD 里已提交的 `<标识>`。
 *
 * 工作树里的值分两种：人工写的、工具上一批自写的，二者在文件里长得一模一样，
 * 光看盘上没法分辨「这条档次是制作组点的」还是「这条档次是上次拟合凑出来的」。
 * 本批要全量重算并覆写工具自写的系数，所以判定按提交历史来：HEAD 里有的字段一律不覆盖。
 * 未进 HEAD 的整份新文件按工具侧处理 —— 那种文件里不存在人工标注。
 */
import { execFileSync } from "node:child_process";
import path from "node:path";

import { readFlagsFromSource } from "@cf7-balance-tool/xml-io";
import type { MonsterCensusConfig } from "@cf7-balance-tool/xml-io";

const PROPERTIES_DIR = "data/enemy_properties";

/** 模板名 → 标识字段 → 数值，取自 HEAD 那份敌人属性 XML。 */
export function headFlags(repoRoot: string, config: MonsterCensusConfig): Record<string, Record<string, number>> {
  const tracked = trackedAtHead(repoRoot)
    .filter((file) => file.endsWith(".xml") && !config.excludedSourceFiles.includes(file.slice(PROPERTIES_DIR.length + 1)))
    .sort();
  const out: Record<string, Record<string, number>> = {};
  for (const relative of tracked) {
    Object.assign(out, readFlagsFromSource(gitShow(repoRoot, relative), config));
  }
  return out;
}

/** HEAD 里 data/enemy_properties 的文件清单；git 不可用或没有 HEAD 时直接失败，不能退化成"全部按工具侧写"。 */
function trackedAtHead(repoRoot: string): string[] {
  const output = git(repoRoot, ["ls-tree", "-r", "--name-only", "HEAD", "--", PROPERTIES_DIR]);
  return output.split("\n").map((line) => line.trim()).filter(Boolean);
}

function gitShow(repoRoot: string, relativePath: string): string {
  return git(repoRoot, ["show", `HEAD:${relativePath}`]);
}

function git(repoRoot: string, args: string[]): string {
  return execFileSync("git", ["-c", "core.quotepath=off", ...args], {
    cwd: repoRoot,
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
    stdio: ["ignore", "pipe", "pipe"],
  });
}

/** 相对仓库根的 POSIX 路径，供报错时用。 */
export function repoRelative(repoRoot: string, target: string): string {
  return path.relative(repoRoot, target).split(path.sep).join("/");
}
