/**
 * 怪物标识四张查验表的 GUI 模型层（纯函数，无 Electron/DOM 依赖，供 vitest 直测）。
 *
 * 口径锚点：tools/cf7-balance-tool/docs/monster-flag-rulebook.md
 * - 全量表是唯一可写面：空格 = 该项不改；填了数 = 按填的写。
 * - 十项系数列可编辑：阶段/档次系数/成长系数/攻速系数/攻击倍率/段数系数/
 *   速度系数/高攻低血防系数/霸体系数/高防低血系数。
 * - 阶段额外允许 0（整行排除标记），其余列取非负有限数。
 * - 派生列（主线进度/档次描述/超出范围/误差值）与键列（模板/别名）只读。
 * - CSV 落盘合同：UTF-8 BOM + CRLF（见 monster-flags-csv 生成器输出）。
 */

export interface MonsterTableCsv {
  headers: string[];
  rows: string[][];
}

export interface MonsterTableMeta {
  path: string;
  exists: boolean;
  updatedAt?: string;
}

export interface MonsterTablePayload extends MonsterTableMeta {
  headers: string[];
  rows: string[][];
}

export interface MonsterTablesResult {
  full: MonsterTablePayload;
  outOfRange: MonsterTablePayload;
  highError: MonsterTablePayload;
  human: MonsterTablePayload;
}

export interface MonsterRowState {
  id: string;
  cells: string[];
  original: string[];
}

export const MONSTER_COEFFICIENT_COLUMNS = [
  "\u9636\u6bb5",
  "\u6863\u6b21\u7cfb\u6570",
  "\u6210\u957f\u7cfb\u6570",
  "\u653b\u901f\u7cfb\u6570",
  "\u653b\u51fb\u500d\u7387",
  "\u6bb5\u6570\u7cfb\u6570",
  "\u901f\u5ea6\u7cfb\u6570",
  "\u9ad8\u653b\u4f4e\u8840\u9632\u7cfb\u6570",
  "\u9738\u4f53\u7cfb\u6570",
  "\u9ad8\u9632\u4f4e\u8840\u7cfb\u6570"
] as const;

const STAGE_COLUMN = "\u9636\u6bb5";

export function isEditableColumn(header: string): boolean {
  return (MONSTER_COEFFICIENT_COLUMNS as readonly string[]).includes(header);
}

/**
 * 校验单个系数格。空格 = 不改（合法）；数值必须是非负有限数；
 * 阶段只允许非负整数（0 = 整行排除标记）。返回 null 表示合法。
 */
export function validateMonsterCell(header: string, value: string): string | null {
  const trimmed = value.trim();
  if (trimmed === "") return null;
  if (!isEditableColumn(header)) {
    return "\u8be5\u5217\u4e3a\u6d3e\u751f/\u952e\u5217\uff0c\u4e0d\u53ef\u7f16\u8f91";
  }
  const num = Number(trimmed);
  if (!Number.isFinite(num)) {
    return "\u5fc5\u987b\u662f\u6570\u503c\u6216\u7a7a\u683c";
  }
  if (num < 0) {
    return "\u7cfb\u6570\u4e0d\u80fd\u4e3a\u8d1f";
  }
  if (header === STAGE_COLUMN && !Number.isInteger(num)) {
    return "\u9636\u6bb5\u5fc5\u987b\u662f\u975e\u8d1f\u6574\u6570";
  }
  return null;
}

/**
 * 解析 CSV。容忍引号包裹字段（含双引号转义与内嵌 CRLF），
 * 跳过 BOM 与末尾空行；列数不齐的行按实有列保留（不填充、不报错——
 * 错误表由 CLI 侧兜底，GUI 不做隐式修补）。
 */
export function parseMonsterCsv(text: string): MonsterTableCsv {
  let source = text;
  if (source.charCodeAt(0) === 0xfeff) source = source.slice(1);

  const records: string[][] = [];
  let field = "";
  let row: string[] = [];
  let inQuotes = false;
  let sawAny = false;

  const pushField = () => {
    row.push(field);
    field = "";
  };
  const pushRow = () => {
    if (row.length > 0 || field !== "" || sawAny) {
      pushField();
      records.push(row);
    }
    row = [];
    sawAny = false;
  };

  for (let i = 0; i < source.length; i++) {
    const ch = source[i];
    if (inQuotes) {
      if (ch === '"') {
        if (source[i + 1] === '"') {
          field += '"';
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field += ch;
      }
      continue;
    }
    if (ch === '"') {
      inQuotes = true;
      sawAny = true;
      continue;
    }
    if (ch === ",") {
      sawAny = true;
      pushField();
      continue;
    }
    if (ch === "\r") {
      if (source[i + 1] === "\n") i++;
      pushRow();
      continue;
    }
    if (ch === "\n") {
      pushRow();
      continue;
    }
    sawAny = true;
    field += ch;
  }
  pushRow();

  const headers = records[0];
  if (!headers || headers.length === 0) {
    return { headers: [], rows: [] };
  }
  const rows = records.slice(1);
  return { headers, rows: rows.filter((r) => !(r.length === 1 && r[0] === "")) };
}

/** 序列化为生成器同形 CSV：逗号连接、CRLF 换行、需要时引号包裹。 */
export function serializeMonsterCsv(headers: string[], rows: string[][]): string {
  const all = [headers, ...rows];
  return all
    .map((cells) => cells.map(escapeCell).join(","))
    .join("\r\n") + "\r\n";
}

function escapeCell(cell: string): string {
  const text = cell ?? "";
  if (/[",\r\n]/.test(text)) {
    return `"${text.replace(/"/g, '""')}"`;
  }
  return text;
}

/** 由解析表建立行状态（id 供 React key 与定位）。 */
export function createMonsterRows(rows: string[][]): MonsterRowState[] {
  return rows.map((cells, index) => ({
    id: `r${index}-${cells[0] ?? index}`,
    cells: [...cells],
    original: [...cells]
  }));
}

/** 更新一格：先校验，非法时返回原表 + 错误；合法返回新行数组。 */
export function updateMonsterCell(
  rows: MonsterRowState[],
  headers: string[],
  rowId: string,
  columnIndex: number,
  value: string
): { rows: MonsterRowState[]; error: string | null } {
  const header = headers[columnIndex];
  const error = validateMonsterCell(header ?? "", value);
  if (error) {
    return { rows, error };
  }
  const next = rows.map((row) => {
    if (row.id !== rowId) return row;
    const cells = [...row.cells];
    while (cells.length <= columnIndex) cells.push("");
    cells[columnIndex] = value.trim();
    return { ...row, cells };
  });
  return { rows: next, error: null };
}

/** 全行改回盘上现值。 */
export function revertMonsterRow(rows: MonsterRowState[], rowId: string): MonsterRowState[] {
  return rows.map((row) => (row.id === rowId ? { ...row, cells: [...row.original] } : row));
}

/** 有变更的格子总数（逐格比较，长度不齐的尾部按空串计）。 */
export function countMonsterChanges(rows: MonsterRowState[]): number {
  let count = 0;
  for (const row of rows) {
    const max = Math.max(row.cells.length, row.original.length);
    for (let i = 0; i < max; i++) {
      if ((row.cells[i] ?? "") !== (row.original[i] ?? "")) count++;
    }
  }
  return count;
}

/** 行是否有变更。 */
export function isMonsterRowChanged(row: MonsterRowState): boolean {
  const max = Math.max(row.cells.length, row.original.length);
  for (let i = 0; i < max; i++) {
    if ((row.cells[i] ?? "") !== (row.original[i] ?? "")) return true;
  }
  return false;
}

/** 把行状态回写成 CSV 文本（CRLF）。 */
export function buildMonsterCsvText(headers: string[], rows: MonsterRowState[]): string {
  return serializeMonsterCsv(headers, rows.map((row) => row.cells));
}
