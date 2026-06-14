import { describe, it, expect } from 'vitest';
import {
  parseXflDocument,
  collectLinkageItems,
  lintLinkage,
  summarizeLint,
  extractFrameLabels,
  canonicalizeSymbolXml,
  clusterDuplicates,
} from '../src/authoring/index.js';

const DOM = `<?xml version="1.0" encoding="UTF-8"?>
<DOMDocument xmlns="http://ns.adobe.com/xfl/2008/" frameRate="30" xflVersion="2.2"
  creatorInfo="Adobe Flash Professional CS6" platform="Windows">
  <symbols>
    <Include href="hero/body.xml" itemID="a-1" linkageExportForAS="true" linkageIdentifier="hero_body"/>
    <Include href="Graphic/shape 1.xml" itemID="a-2"/>
    <Include href="dup/a.xml" itemID="a-3" linkageExportForAS="true" linkageIdentifier="dup_id"/>
    <Include href="dup/b.xml" itemID="a-4" linkageExportForAS="true" linkageIdentifier="dup_id"/>
    <Include href="bad/x.xml" itemID="a-5" linkageExportForAS="true"/>
  </symbols>
  <media>
    <DOMSoundItem name="snd.wav" linkageExportForAS="true" linkageIdentifier="snd_reload"/>
    <DOMBitmapItem name="bg.png"/>
  </media>
  <timelines>
    <DOMTimeline name="Scene 1">
      <layers>
        <DOMLayer name="labels">
          <frames>
            <DOMFrame index="0" name="start" labelType="name" duration="5"/>
            <DOMFrame index="5" duration="3"/>
            <DOMFrame index="8" name="loop" labelType="name" duration="2"/>
          </frames>
        </DOMLayer>
      </layers>
    </DOMTimeline>
  </timelines>
</DOMDocument>`;

describe('authoring: XFL parsing + lint', () => {
  const doc = parseXflDocument(DOM);

  it('parses document info', () => {
    expect(doc.info.frameRate).toBe(30);
    expect(doc.info.creatorInfo).toContain('CS6');
  });

  it('parses symbols with linkage flags and derived names', () => {
    expect(doc.symbols).toHaveLength(5);
    const hero = doc.symbols.find((s) => s.name === 'hero/body');
    expect(hero?.linkageExportForAS).toBe(true);
    expect(hero?.linkageIdentifier).toBe('hero_body');
    const shape = doc.symbols.find((s) => s.name === 'Graphic/shape 1');
    expect(shape?.linkageExportForAS).toBe(false);
    expect(shape?.linkageIdentifier).toBeUndefined();
  });

  it('parses media items', () => {
    expect(doc.media).toHaveLength(2);
    const snd = doc.media.find((m) => m.name === 'snd.wav');
    expect(snd?.kind).toBe('sound');
    expect(snd?.linkageIdentifier).toBe('snd_reload');
  });

  it('lints duplicate identifiers and exported-without-id', () => {
    const findings = lintLinkage(collectLinkageItems(doc));
    const sum = summarizeLint(findings);
    const codes = findings.map((f) => f.code).sort();
    expect(codes).toContain('duplicate-identifier');
    expect(codes).toContain('exported-no-identifier');
    expect(sum.errors).toBe(2);
  });

  it('naming warnings only fire when a pattern is supplied', () => {
    const items = collectLinkageItems(doc);
    expect(lintLinkage(items).filter((f) => f.code === 'naming')).toHaveLength(0);
    const withPattern = lintLinkage(items, { namingPattern: /^[a-z_]+$/ });
    // "snd.wav"? no — that's the name; identifier is "snd_reload" which matches.
    // "hero_body", "dup_id" match; none should fail this lax pattern.
    expect(withPattern.filter((f) => f.code === 'naming')).toHaveLength(0);
  });

  it('extracts named frame labels only', () => {
    const labels = extractFrameLabels(DOM);
    expect(labels).toHaveLength(2);
    expect(labels.map((l) => l.name)).toEqual(['start', 'loop']);
    expect(labels[0]?.index).toBe(0);
    expect(labels[1]?.index).toBe(8);
  });
});

describe('authoring: structural duplicate detection', () => {
  it('canonicalize ignores itemID/lastModified so identical geometry clusters', () => {
    const a = `<DOMSymbolItem name="x" itemID="111" lastModified="9">  <timeline>  <shape/>  </timeline></DOMSymbolItem>`;
    const b = `<DOMSymbolItem name="y" itemID="222" lastModified="8"><timeline><shape/></timeline></DOMSymbolItem>`;
    expect(canonicalizeSymbolXml(a)).toBe(canonicalizeSymbolXml(b));
    const clusters = clusterDuplicates([
      { name: 'x', key: canonicalizeSymbolXml(a) },
      { name: 'y', key: canonicalizeSymbolXml(b) },
      { name: 'z', key: canonicalizeSymbolXml('<DOMSymbolItem><timeline><ellipse/></timeline></DOMSymbolItem>') },
    ]);
    expect(clusters).toHaveLength(1);
    expect(clusters[0]?.members.sort()).toEqual(['x', 'y']);
  });
});
