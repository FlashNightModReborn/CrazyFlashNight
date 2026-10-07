/**
 * 标识的人工权威判定 — git HEAD 已提交的 `<标识>` 摘掉标识来源台账里的工具自写格，再并上人工认领格。
 *
 * 工作树里的值分两种：人工写的、工具上一批自写的，二者在文件里长得一模一样，
 * 光看盘上没法分辨「这条档次是制作组点的」还是「这条档次是上次拟合凑出来的」。
 * 曾经按提交历史判（HEAD 里有就不覆盖），但工具写盘一旦提交，HEAD 里就也全是工具自己的数 ——
 * 那条口径会自指：每行都像人工已打标，统计面塌掉，反推也被上一批的输出钉死。
 * 所以现在按 `data/monster-flag-ledger.json` 判：工具落过的格算工具侧，其余算人工，人工认领的格一律优先。
 * 未进 HEAD 的整份新文件里没有已提交标识，台账也没登记过，整份按人工缺项处理（工具可以补）。
 */
import { execFileSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { humanAuthorityOf, loadMonsterFlagLedger, readFlagsFromSource } from "@cf7-balance-tool/xml-io";
import type { MonsterCensusConfig, MonsterFlagCellMap, MonsterFlagLedger } from "@cf7-balance-tool/xml-io";

const PROPERTIES_DIR = "data/enemy_properties";
const TOOL_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");

/** 标识来源台账：两条工具通道的自写登记 + 制作组手填点名的人工批次。 */
export const LEDGER_PATH = path.join(TOOL_ROOT, "data", "monster-flag-ledger.json");

export function readLedger(): MonsterFlagLedger {
  return loadMonsterFlagLedger(LEDGER_PATH);
}

/** 模板名 → 标识字段 → 数值，取自 HEAD 那份敌人属性 XML（未过台账，就是"已提交"这一件事）。 */
export function headFlags(repoRoot: string, config: MonsterCensusConfig): MonsterFlagCellMap {
  const tracked = trackedAtHead(repoRoot)
    .filter((file) => file.endsWith(".xml") && !config.excludedSourceFiles.includes(file.slice(PROPERTIES_DIR.length + 1)))
    .sort();
  const out: MonsterFlagCellMap = {};
  for (const relative of tracked) {
    Object.assign(out, readFlagsFromSource(gitShow(repoRoot, relative), config));
  }
  return out;
}

/** 本次的人工权威：HEAD 那份摘掉工具自写的格，并上人工认领的格。 */
export function humanAuthority(repoRoot: string, config: MonsterCensusConfig, ledger?: MonsterFlagLedger): MonsterFlagCellMap {
  return humanAuthorityOf(headFlags(repoRoot, config), ledger ?? readLedger());
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
