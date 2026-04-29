import { readFileSync } from "node:fs";

/**
 * Parse REPAIR_DICT_* static const arrays from SaveManager.as.
 *
 * Expected source format (AS2):
 *   public static var REPAIR_DICT_SKILLS:Array = [
 *       "拳脚攻击",
 *       "升龙拳",
 *       ...
 *   ];
 *
 * Implementation: locate the line `public static var <CONST>:Array = [`, then
 * collect string literals until matching `];`. Handles multi-line arrays and
 * `//` line comments inside. Strict format — tightening the source declaration
 * (e.g. ditching the `:Array` annotation) breaks this parser. CI gate covers it.
 */
export function extractAs2DictConstant(saveManagerPath: string, constantName: string): string[] {
  const src = readFileSync(saveManagerPath, "utf-8");
  // Anchor: "public static var <CONST>:Array = ["
  const re = new RegExp(`public\\s+static\\s+var\\s+${constantName}\\s*:\\s*Array\\s*=\\s*\\[`);
  const startMatch = re.exec(src);
  if (!startMatch) {
    throw new Error(
      `[as2-constants] Required constant ${constantName} not found in ${saveManagerPath}. `
      + `Add a 'public static var ${constantName}:Array = [...]' declaration.`,
    );
  }

  // Find the matching `];` after start, respecting string literals.
  let i = startMatch.index + startMatch[0].length;
  let depth = 1;
  const literals: string[] = [];
  let cur = "";
  let inStr = false;
  let strQuote = "";
  let inLineComment = false;

  while (i < src.length && depth > 0) {
    const c = src[i];
    const n = src[i + 1];

    if (inLineComment) {
      if (c === "\n") inLineComment = false;
      i++;
      continue;
    }
    if (!inStr && c === "/" && n === "/") {
      inLineComment = true;
      i += 2;
      continue;
    }

    if (inStr) {
      if (c === "\\" && i + 1 < src.length) {
        // Escape: copy next char verbatim (AS2 escape rules approx JS for ASCII).
        cur += src[i + 1];
        i += 2;
        continue;
      }
      if (c === strQuote) {
        literals.push(cur);
        cur = "";
        inStr = false;
        i++;
        continue;
      }
      cur += c;
      i++;
      continue;
    }

    if (c === '"' || c === "'") {
      inStr = true;
      strQuote = c;
      cur = "";
      i++;
      continue;
    }
    if (c === "[") {
      depth++;
      i++;
      continue;
    }
    if (c === "]") {
      depth--;
      i++;
      if (depth === 0) break;
      continue;
    }
    i++;
  }

  if (depth !== 0) {
    throw new Error(`[as2-constants] Unterminated array literal for ${constantName}`);
  }

  return literals;
}
