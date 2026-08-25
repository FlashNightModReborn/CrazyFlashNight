import type { CardId } from '../core/types.js';
import { CARD_IDS, getCardDefinition } from '../data/cards.js';

export interface PortraitDescriptor {
  portraitRef?: string;
  requestedPortraitRef?: string;
  status?: string;
  svgUrl?: string;
  pngUrl?: string;
  legacyUrl?: string;
}

export interface EnemyPortraitResolver {
  loadManifest(): Promise<unknown>;
  resolve(context: { portraitRef: string; identifier: string }): PortraitDescriptor | null;
  mount?: (
    container: HTMLElement,
    image: HTMLImageElement,
    context: { portraitRef: string; identifier: string; legacyUrl?: string },
  ) => Promise<PortraitDescriptor | null>;
  fallbackUrl?: () => string;
}

declare global {
  interface Window {
    EnemyPortraits?: EnemyPortraitResolver;
    PortraitResolver?: EnemyPortraitResolver;
  }
}

export const WARLORD_PORTRAIT_IDENTIFIERS = CARD_IDS.map(
  (cardId) => getCardDefinition(cardId).identifier,
);

export function identifierForCard(cardId: CardId): string {
  return getCardDefinition(cardId).identifier;
}

export function getEnemyPortraitResolver(): EnemyPortraitResolver | null {
  return window.EnemyPortraits ?? window.PortraitResolver ?? null;
}

export async function resolvePortraitDescriptors(
  resolver: EnemyPortraitResolver,
): Promise<Map<string, PortraitDescriptor>> {
  await resolver.loadManifest();
  const result = new Map<string, PortraitDescriptor>();
  for (const identifier of WARLORD_PORTRAIT_IDENTIFIERS) {
    const descriptor = resolver.resolve({ portraitRef: identifier, identifier });
    if (descriptor) result.set(identifier, descriptor);
  }
  return result;
}

export function textureUrlFor(descriptor: PortraitDescriptor | null): string | null {
  return textureUrlsFor(descriptor)[0] ?? null;
}

export function textureUrlsFor(descriptor: PortraitDescriptor | null): string[] {
  if (!descriptor) return [];
  return [...new Set([descriptor.pngUrl, descriptor.svgUrl, descriptor.legacyUrl]
    .filter((url): url is string => typeof url === 'string' && url.length > 0))];
}

export async function mountPortraits(root: ParentNode): Promise<void> {
  const resolver = getEnemyPortraitResolver();
  if (!resolver?.mount) return;
  const containers = Array.from(root.querySelectorAll<HTMLElement>('[data-warlord-portrait]'));
  await Promise.all(containers.map(async (container) => {
    const identifier = container.dataset.warlordPortrait;
    const image = container.querySelector<HTMLImageElement>('img');
    if (!identifier || !image) return;
    await resolver.mount?.(container, image, { portraitRef: identifier, identifier });
  }));
}
