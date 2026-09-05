import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import test from 'node:test';
import { runInNewContext } from 'node:vm';

interface ProbeNode {
  parentElement: ProbeNode | null;
  hidden: boolean;
  isConnected: boolean;
  dataset: Record<string, string>;
  css: { display: string; visibility: string; opacity: string; transform: string };
  getBoundingClientRect(): { x: number; y: number; width: number; height: number };
  contains(node: unknown): boolean;
  querySelectorAll(): unknown[];
}

function fixture() {
  const nodes: Record<string, ProbeNode> = {};
  for (const selector of ['#panel-container', '.warlord-scale-shell', '.warlord-app',
    '.warlord-battle-layer', '.warlord-battle-controls [data-action="battle-close"]']) {
    nodes[selector] = {
      parentElement: nodes['#panel-container'] ?? null,
      hidden: false,
      isConnected: true,
      dataset: { sceneLifecycle: 'released_for_battle', authorityState: 'ready' },
      css: { display: 'block', visibility: 'visible', opacity: '1', transform: 'none' },
      getBoundingClientRect: () => ({ x: 10, y: 10, width: 100, height: 50 }),
      contains: () => false,
      querySelectorAll: () => [],
    };
  }
  const document = {
    currentScript: { src: 'http://localhost/warlord-panel.js' },
    visibilityState: 'visible',
    querySelector: (selector: string) => nodes[selector] ?? null,
    elementFromPoint: () => nodes['.warlord-battle-controls [data-action="battle-close"]'],
  };
  const window = {
    location: { href: document.currentScript.src },
    innerWidth: 1067, innerHeight: 600, devicePixelRatio: 1.5,
    getComputedStyle: (node: ProbeNode) => node.css,
    WarlordPanelDiagnostics: undefined as undefined | { read(): Record<string, unknown> },
  };
  runInNewContext(String(readFileSync(resolve(process.cwd(), 'warlord-panel.js'), 'utf8')), {
    window, document, URL, Panels: { register: () => {} },
    // The diagnostic must not mount a runtime, schedule frames or request pixels.
    requestAnimationFrame: () => { throw new Error('diagnostic started graphics'); },
    setTimeout: () => { throw new Error('diagnostic started polling'); },
  });
  return { nodes, document, read: () => window.WarlordPanelDiagnostics!.read() };
}

test('battle presentation probe describes static settlement without canvas or player content', () => {
  const harness = fixture();
  const sample = harness.read();
  assert.equal(sample.sceneLifecycle, 'released_for_battle');
  assert.equal(sample.canvasCount, 0);
  assert.equal(sample.closeButtonHit, true);
  assert.equal((sample.battle as { blockedByStyle: boolean }).blockedByStyle, false);
  assert.equal(JSON.stringify(sample).includes('innerHTML'), false);
  assert.equal(JSON.stringify(sample).includes('textContent'), false);
});

test('battle presentation probe separates absent DOM, hidden ancestor and hidden document', () => {
  const harness = fixture();
  harness.nodes['#panel-container']!.css.display = 'none';
  harness.document.visibilityState = 'hidden';
  let sample = harness.read();
  assert.equal(sample.documentVisibility, 'hidden');
  assert.equal((sample.battle as { blockedByStyle: boolean }).blockedByStyle, true);
  delete harness.nodes['.warlord-app'];
  delete harness.nodes['.warlord-battle-layer'];
  delete harness.nodes['.warlord-battle-controls [data-action="battle-close"]'];
  sample = harness.read();
  assert.equal(sample.app, null);
  assert.equal(sample.battle, null);
  assert.equal(sample.closeButtonHit, false);
});
