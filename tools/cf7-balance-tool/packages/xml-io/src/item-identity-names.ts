import { XMLParser } from "fast-xml-parser";

// ItemUtil uses the name as a dictionary key. Numeric and trimmed tool fields
// are parsed separately so report identities retain the XML leaf's whitespace.
const namesParser = new XMLParser({
  trimValues: false,
  parseTagValue: false,
  isArray: (_name, path) => path === "root.item",
  updateTag: (tag, path) => path === "root" || path === "root.item" || path === "root.item.name" ? tag : false
});

export function readItemIdentityNames(xml: string): string[] {
  const items = namesParser.parse(xml).root?.item ?? [];
  return items.map((item: { name?: string }) => item.name ?? "");
}
