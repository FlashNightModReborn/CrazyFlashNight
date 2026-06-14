/**
 * XFL (uncompressed Flash) DOMDocument.xml + symbol parsing. Pure: takes XML
 * text, returns a typed model. The file reads live in the CLI / panel.
 *
 * CF7 art is authored as XFL in Adobe Animate CS6 (flashswf/arts/new/*). Linkage
 * metadata lives on `<symbols><Include>` and on `<media>` items
 * (DOMBitmapItem / DOMSoundItem / ...).
 */
import { XMLParser } from 'fast-xml-parser';

type XmlNode = Record<string, unknown>;

const ARRAY_TAGS = new Set([
  'Include',
  'DOMBitmapItem',
  'DOMSoundItem',
  'DOMVideoItem',
  'DOMFontItem',
  'DOMSymbolItem',
  'DOMTimeline',
  'DOMLayer',
  'DOMFrame',
]);

const parser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: '@_',
  isArray: (tag: string) => ARRAY_TAGS.has(tag),
});

function toArray(v: unknown): unknown[] {
  if (v === undefined || v === null) return [];
  return Array.isArray(v) ? v : [v];
}

function attr(node: unknown, key: string): string | undefined {
  if (node && typeof node === 'object' && key in node) {
    const v = (node as XmlNode)[key];
    return v === undefined || v === null ? undefined : String(v);
  }
  return undefined;
}

function numAttr(node: unknown, key: string): number | undefined {
  const s = attr(node, key);
  if (s === undefined) return undefined;
  const n = Number(s);
  return Number.isNaN(n) ? undefined : n;
}

function hrefToName(href: string): string {
  return href.replace(/\.xml$/i, '');
}

export interface XflSymbolRef {
  href: string;
  name: string;
  itemID?: string | undefined;
  linkageExportForAS: boolean;
  linkageIdentifier?: string | undefined;
  linkageClassName?: string | undefined;
}

export type XflMediaKind = 'bitmap' | 'sound' | 'video' | 'font';

export interface XflMediaItem {
  name: string;
  kind: XflMediaKind;
  linkageExportForAS: boolean;
  linkageIdentifier?: string | undefined;
}

export interface XflDocumentInfo {
  frameRate?: number | undefined;
  xflVersion?: string | undefined;
  creatorInfo?: string | undefined;
  platform?: string | undefined;
}

export interface XflDocument {
  info: XflDocumentInfo;
  symbols: XflSymbolRef[];
  media: XflMediaItem[];
}

export interface FrameLabel {
  timeline: string;
  layer: string;
  index: number;
  name: string;
  labelType?: string | undefined;
  duration: number;
}

/** Parse a DOMDocument.xml into a document model (symbols + media + info). */
export function parseXflDocument(xml: string): XflDocument {
  const root = parser.parse(xml) as XmlNode;
  const doc = root['DOMDocument'] as XmlNode | undefined;

  const symbols: XflSymbolRef[] = [];
  const symbolsNode = doc?.['symbols'] as XmlNode | undefined;
  for (const inc of toArray(symbolsNode?.['Include'])) {
    const href = attr(inc, '@_href') ?? '';
    symbols.push({
      href,
      name: hrefToName(href),
      itemID: attr(inc, '@_itemID'),
      linkageExportForAS: attr(inc, '@_linkageExportForAS') === 'true',
      linkageIdentifier: attr(inc, '@_linkageIdentifier'),
      linkageClassName: attr(inc, '@_linkageClassName'),
    });
  }

  const media: XflMediaItem[] = [];
  const mediaNode = doc?.['media'] as XmlNode | undefined;
  const mediaKinds: Array<[string, XflMediaKind]> = [
    ['DOMBitmapItem', 'bitmap'],
    ['DOMSoundItem', 'sound'],
    ['DOMVideoItem', 'video'],
    ['DOMFontItem', 'font'],
  ];
  for (const [tag, kind] of mediaKinds) {
    for (const m of toArray(mediaNode?.[tag])) {
      media.push({
        name: attr(m, '@_name') ?? '',
        kind,
        linkageExportForAS: attr(m, '@_linkageExportForAS') === 'true',
        linkageIdentifier: attr(m, '@_linkageIdentifier'),
      });
    }
  }

  const info: XflDocumentInfo = {
    frameRate: numAttr(doc, '@_frameRate'),
    xflVersion: attr(doc, '@_xflVersion'),
    creatorInfo: attr(doc, '@_creatorInfo'),
    platform: attr(doc, '@_platform'),
  };

  return { info, symbols, media };
}

function collectTimelines(root: XmlNode): unknown[] {
  const res: unknown[] = [];
  const doc = root['DOMDocument'] as XmlNode | undefined;
  res.push(...toArray((doc?.['timelines'] as XmlNode | undefined)?.['DOMTimeline']));
  const sym = root['DOMSymbolItem'] as XmlNode | undefined;
  res.push(...toArray((sym?.['timeline'] as XmlNode | undefined)?.['DOMTimeline']));
  return res;
}

/** Extract named frame labels from a DOMDocument.xml or a LIBRARY symbol .xml. */
export function extractFrameLabels(xml: string): FrameLabel[] {
  const root = parser.parse(xml) as XmlNode;
  const out: FrameLabel[] = [];
  for (const tl of collectTimelines(root)) {
    const tlName = attr(tl, '@_name') ?? '';
    const layersNode = (tl as XmlNode)['layers'] as XmlNode | undefined;
    for (const layer of toArray(layersNode?.['DOMLayer'])) {
      const layerName = attr(layer, '@_name') ?? '';
      const framesNode = (layer as XmlNode)['frames'] as XmlNode | undefined;
      for (const frame of toArray(framesNode?.['DOMFrame'])) {
        const name = attr(frame, '@_name');
        if (name === undefined || name === '') continue;
        out.push({
          timeline: tlName,
          layer: layerName,
          index: numAttr(frame, '@_index') ?? 0,
          name,
          labelType: attr(frame, '@_labelType'),
          duration: numAttr(frame, '@_duration') ?? 1,
        });
      }
    }
  }
  return out;
}

/**
 * Canonicalize a LIBRARY symbol .xml for structural duplicate detection: drop
 * identity + volatile attributes (name, itemID, lastModified, itemIcon,
 * sourceLastImported) and collapse whitespace. Two symbols with the same
 * canonical form are duplicates *ignoring their names* — i.e. this finds
 * renamed copies of the same geometry, which is the point. Clusters are meant
 * to be reviewed by a human before merging (the heuristic can over-match when
 * the only difference is an inner instance name).
 */
export function canonicalizeSymbolXml(xml: string): string {
  return xml
    .replace(/\s+(name|itemID|lastModified|itemIcon|sourceLastImported)="[^"]*"/g, '')
    .replace(/>\s+</g, '><')
    .replace(/\s+/g, ' ')
    .trim();
}
