import { CARD_IDS, getCardDefinition } from '../data/cards.js';
export const WARLORD_PORTRAIT_IDENTIFIERS = CARD_IDS.map((cardId) => getCardDefinition(cardId).identifier);
export function identifierForCard(cardId) {
    return getCardDefinition(cardId).identifier;
}
export function getEnemyPortraitResolver() {
    return window.EnemyPortraits ?? window.PortraitResolver ?? null;
}
export async function resolvePortraitDescriptors(resolver) {
    await resolver.loadManifest();
    const result = new Map();
    for (const identifier of WARLORD_PORTRAIT_IDENTIFIERS) {
        const descriptor = resolver.resolve({ portraitRef: identifier, identifier });
        if (descriptor)
            result.set(identifier, descriptor);
    }
    return result;
}
export function textureUrlFor(descriptor) {
    return textureUrlsFor(descriptor)[0] ?? null;
}
export function textureUrlsFor(descriptor) {
    if (!descriptor)
        return [];
    return [...new Set([descriptor.pngUrl, descriptor.svgUrl, descriptor.legacyUrl]
            .filter((url) => typeof url === 'string' && url.length > 0))];
}
export async function mountPortraits(root) {
    const resolver = getEnemyPortraitResolver();
    if (!resolver?.mount)
        return;
    const containers = Array.from(root.querySelectorAll('[data-warlord-portrait]'));
    await Promise.all(containers.map(async (container) => {
        const identifier = container.dataset.warlordPortrait;
        const image = container.querySelector('img');
        if (!identifier || !image)
            return;
        await resolver.mount?.(container, image, { portraitRef: identifier, identifier });
    }));
}
//# sourceMappingURL=portrait-texture-source.js.map