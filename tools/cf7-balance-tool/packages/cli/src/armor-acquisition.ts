/** K-point evidence stays attached to its real acquisition route, including paid recipes. */
export function armorAcquisitionFile(evidenceRef: string): string {
  const file = evidenceRef.split("#")[0]!;
  if (!/^data\/(?:kshop|crafting)\/[^#]+\.json$/.test(file) || file.includes("..") || file.includes("\\")) {
    throw new Error(`${evidenceRef}: 需要仓库内 K 店或合成 JSON 证据`);
  }
  return file;
}

/** An explicit scope can verify new records while reporting unrelated catalog gaps separately. */
export function armorItemScope(args: string[], names: string[]): Set<string> | undefined {
  if (args.length === 0) return undefined;
  if (args.length !== 2 || args[0] !== "--items") throw new Error("定向核验使用 --items 名称1,名称2");
  const selected = args[1]!.split(",").map((name) => name.trim());
  if (selected.some((name) => !name || !names.includes(name)) || new Set(selected).size !== selected.length) {
    throw new Error("定向核验名单必须逐项存在于 plan，且不可重复或为空");
  }
  return new Set(selected);
}

export function readArmorKPointPrices(parsed: unknown, evidenceRef: string): Map<string, number> {
  const file = armorAcquisitionFile(evidenceRef);
  if (!Array.isArray(parsed)) throw new Error(`${evidenceRef}: 需要条目数组`);
  const crafting = file.startsWith("data/crafting/");
  const recipeId = evidenceRef.split("#")[1];
  if (crafting && !recipeId) throw new Error(`${evidenceRef}: 合成K点证据必须指定 recipeId`);
  const result = new Map<string, number>();
  for (const [index, raw] of parsed.entries()) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) throw new Error(`${evidenceRef}[${index}]: 需要对象`);
    const entry = raw as Record<string, unknown>;
    if (crafting && entry.recipeId !== recipeId) continue;
    const item = crafting ? entry.name : entry.item;
    const rawPrice = crafting ? entry.kprice : entry.price;
    // Existing K-shop JSON uses both numbers and decimal strings. Recipes keep
    // their numeric kprice contract and must never fall back to the gold field.
    const price = !crafting && typeof rawPrice === "string" && /^\d+$/.test(rawPrice)
      ? Number(rawPrice) : rawPrice;
    if (typeof item !== "string" || item.trim() === "") throw new Error(`${evidenceRef}[${index}]: 缺少产物名称`);
    if (typeof price !== "number" || !Number.isSafeInteger(price) || price < 0) throw new Error(`${evidenceRef}[${index}]: K点成本必须为非负整数`);
    if (result.has(item)) throw new Error(`${evidenceRef}: 重复条目 ${item}`);
    result.set(item, price);
  }
  if (crafting && result.size !== 1) throw new Error(`${evidenceRef}: 找不到唯一的合成配方`);
  return result;
}
