/**
 * 标识来源台账 — 记「哪一格标识是工具自己写的、哪一格是人工给的」。
 *
 * 人工权威原本按 git HEAD 判（HEAD 里有的 `<标识>` 就当人工给的，工具不覆盖）。这条口径在工具写盘被提交之后自指失效：
 * HEAD 里从此也躺着工具自写的系数，于是每一行都像"人工已经打标"，统计面塌成工具一格没识别的样子，
 * 反推也被自己上一批的输出钉死。台账把来源写进数据侧，不再靠提交历史猜。
 *
 * - `writes`：工具落过的格 + 落进去的值（`monster-flags-apply` 与 `monster-flags-table-apply` 两条通道都登记在这里）。
 *   HEAD 里同值的格按工具侧处理（本次可以重算覆盖）；值不一致说明 HEAD 那颗不是这一批落的，先按人工侧留着。
 * - `claims`：制作组点名的人工批次，**只由人手填维护**，工具通道不往这里登记。这些格一律算人工，也不等提交就生效 ——
 *   表上改完还没进 git 的那批，HEAD 里仍是旧值，光读 HEAD 会把人工指令读丢。
 *   全量表的数值本来绝大多数是工具自己产出又搬回 XML 的，从表上写回的格一律算工具侧；
 *   否则「跑一次 table-apply --write」就能把自己写的数洗成永久人工权威。
 */
import fs from "node:fs";
import path from "node:path";

/** 模板名 → 标识字段 → 数值。 */
export type MonsterFlagCellMap = Record<string, Record<string, number>>;

export interface MonsterFlagLedger {
  version: number;
  /** 工具落过的格（含从全量表写回的）：值与 HEAD 一致时算工具侧，人工改过就不算了。 */
  writes: MonsterFlagCellMap;
  /** 制作组点名的人工批次：无条件算人工权威，值以这里为准。只有人手改这张表，工具不登记。 */
  claims: MonsterFlagCellMap;
}

export const MONSTER_FLAG_LEDGER_VERSION = 1;

export function emptyMonsterFlagLedger(): MonsterFlagLedger {
  return { version: MONSTER_FLAG_LEDGER_VERSION, writes: {}, claims: {} };
}

export function loadMonsterFlagLedger(ledgerPath: string): MonsterFlagLedger {
  if (!fs.existsSync(ledgerPath)) return emptyMonsterFlagLedger();
  const raw = JSON.parse(fs.readFileSync(ledgerPath, "utf8")) as unknown;
  if (!isRecord(raw) || !isRecord(raw.writes) || !isRecord(raw.claims)) {
    throw new Error(`标识来源台账结构不认识（需要 writes/claims 两张表）：${ledgerPath}`);
  }
  return {
    version: typeof raw.version === "number" ? raw.version : MONSTER_FLAG_LEDGER_VERSION,
    writes: readCellMap(raw.writes, ledgerPath),
    claims: readCellMap(raw.claims, ledgerPath),
  };
}

export function saveMonsterFlagLedger(ledgerPath: string, ledger: MonsterFlagLedger): void {
  fs.mkdirSync(path.dirname(ledgerPath), { recursive: true });
  fs.writeFileSync(ledgerPath, `${JSON.stringify(renderLedger(ledger), null, 2)}\n`, "utf8");
}

/** 落盘按模板名与字段名的中文序排，台账才有 diff 可看，不会每批都重排一遍。 */
function renderLedger(ledger: MonsterFlagLedger): MonsterFlagLedger {
  return { version: ledger.version, writes: renderCellMap(ledger.writes), claims: renderCellMap(ledger.claims) };
}

function renderCellMap(map: MonsterFlagCellMap): MonsterFlagCellMap {
  const out: MonsterFlagCellMap = {};
  for (const template of Object.keys(map).sort(byName)) {
    const fields = map[template] ?? {};
    for (const field of Object.keys(fields).sort(byName)) Object.assign(out, { [template]: { ...(out[template] ?? {}), [field]: fields[field] } });
  }
  return out;
}

function byName(left: string, right: string): number {
  return left.localeCompare(right, "zh");
}

/**
 * 人工权威 = git HEAD 那份 `<标识>` 摘掉工具自写的格，再并上制作组点名的人工批次。
 * 摘格只认同值：台账写着 24 而 HEAD 是 20，那颗 20 不是这批落的，按人工侧留着。
 * 代价是工具把同一格改成新值之后，HEAD 里那颗旧数会短暂算成人工权威，等新值提交进 HEAD 才复位；
 * 要真正钉住一格走 `claims`。
 */
export function humanAuthorityOf(committed: MonsterFlagCellMap, ledger: MonsterFlagLedger): MonsterFlagCellMap {
  const out: MonsterFlagCellMap = {};
  for (const [template, fields] of Object.entries(committed)) {
    const writes = ledger.writes[template] ?? {};
    const claims = ledger.claims[template] ?? {};
    const merged: Record<string, number> = {};
    for (const [field, value] of Object.entries(fields)) {
      if (writes[field] === value) continue;
      Object.assign(merged, { [field]: value });
    }
    for (const [field, value] of Object.entries(claims)) Object.assign(merged, { [field]: value });
    if (Object.keys(merged).length > 0) Object.assign(out, { [template]: merged });
  }
  const extra = Object.keys(ledger.claims).filter((template) => out[template] === undefined);
  for (const template of extra) {
    const claims = ledger.claims[template] ?? {};
    if (Object.keys(claims).length > 0) Object.assign(out, { [template]: { ...claims } });
  }
  return out;
}

/**
 * 工具落盘之后登记这批格：两条通道（反推写回、全量表读回）都走这里，落过的格一律算工具侧。
 * 同时把同格的认领摘掉，否则台账会一边说"工具写了 6"一边把人工的 5 当权威，盘上值再也没人能解释。
 * 认领要改值或撤销都由人手改台账。
 */
export function recordToolWrites(ledger: MonsterFlagLedger, updates: Array<{ spritename: string; flags: Record<string, number> }>): MonsterFlagLedger {
  const writes = mergeCells(ledger.writes, updates);
  const claims = omitCells(ledger.claims, updates);
  return { version: ledger.version, writes, claims };
}

function mergeCells(map: MonsterFlagCellMap, updates: Array<{ spritename: string; flags: Record<string, number> }>): MonsterFlagCellMap {
  const out: MonsterFlagCellMap = { ...map };
  for (const update of updates) {
    Object.assign(out, { [update.spritename]: { ...(out[update.spritename] ?? {}), ...update.flags } });
  }
  return out;
}

function omitCells(map: MonsterFlagCellMap, updates: Array<{ spritename: string; flags: Record<string, number> }>): MonsterFlagCellMap {
  const out: MonsterFlagCellMap = { ...map };
  for (const update of updates) {
    const fields = { ...(out[update.spritename] ?? {}) };
    for (const field of Object.keys(update.flags)) delete fields[field];
    if (Object.keys(fields).length === 0) delete out[update.spritename];
    else Object.assign(out, { [update.spritename]: fields });
  }
  return out;
}

function readCellMap(raw: Record<string, unknown>, ledgerPath: string): MonsterFlagCellMap {
  const out: MonsterFlagCellMap = {};
  for (const [template, fields] of Object.entries(raw)) {
    if (!isRecord(fields)) throw new Error(`标识来源台账里 ${template} 不是「字段 → 数值」的表：${ledgerPath}`);
    const entry: Record<string, number> = {};
    for (const [field, value] of Object.entries(fields)) {
      if (typeof value !== "number" || !Number.isFinite(value)) throw new Error(`标识来源台账里 ${template}.${field} 不是数：${ledgerPath}`);
      Object.assign(entry, { [field]: value });
    }
    Object.assign(out, { [template]: entry });
  }
  return out;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
