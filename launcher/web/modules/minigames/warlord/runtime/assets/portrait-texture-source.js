import { CARD_IDS, getCardDefinition } from '../data/cards.js';
const PLAYER_AVATAR_KEYS = ['schema', 'gender', 'face', 'hair', 'equipment'];
const PLAYER_AVATAR_EQUIPMENT_KEYS = ['head', 'body', 'hand', 'leg', 'foot', 'neck'];
function hasExactKeys(value, expected) {
    const keys = Object.keys(value).sort();
    return keys.length === expected.length
        && keys.every((key, index) => key === expected.slice().sort()[index]);
}
function portraitText(value) {
    if (typeof value !== 'string' || value.length > 128)
        return null;
    return /[\u0000-\u001f\\"]/u.test(value) ? null : value;
}
/** Host/AS2 tuple 仅为纸娃娃输入，不含资源 URL、战斗属性或任何卡牌身份。 */
export function normalizePlayerAvatarPortrait(value) {
    if (value === null || typeof value !== 'object' || Array.isArray(value))
        return null;
    const input = value;
    if (!hasExactKeys(input, PLAYER_AVATAR_KEYS)
        || input.schema !== 'warlord.player-avatar-portrait.v1'
        || (input.gender !== '男' && input.gender !== '女'))
        return null;
    const face = portraitText(input.face);
    const hair = portraitText(input.hair);
    if (face === null || hair === null
        || input.equipment === null || typeof input.equipment !== 'object'
        || Array.isArray(input.equipment))
        return null;
    const equipmentInput = input.equipment;
    if (!hasExactKeys(equipmentInput, PLAYER_AVATAR_EQUIPMENT_KEYS))
        return null;
    const equipment = {};
    for (const key of PLAYER_AVATAR_EQUIPMENT_KEYS) {
        const entry = portraitText(equipmentInput[key]);
        if (entry === null)
            return null;
        equipment[key] = entry;
    }
    return {
        schema: 'warlord.player-avatar-portrait.v1',
        gender: input.gender,
        face,
        hair,
        equipment,
    };
}
/** Converts the Host-approved tuple into the shared MercPortraits actor shape. */
export function mercActorFromPlayerAvatarPortrait(value) {
    const portrait = normalizePlayerAvatarPortrait(value);
    if (!portrait)
        return null;
    return {
        gender: portrait.gender,
        face: portrait.face,
        hair: portrait.hair,
        equipment: { ...portrait.equipment },
    };
}
/**
 * The sandtable consumes the exact same paper-doll renderer as commander cards.
 * This is presentation-only: the Host tuple remains the sole appearance input.
 */
export async function renderPlayerAvatarPortraitDataUrl(value, size = 256) {
    const actor = mercActorFromPlayerAvatarPortrait(value);
    if (!actor || !window.MercPortraits?.renderDataUrl)
        return '';
    const url = await window.MercPortraits.renderDataUrl(actor, { size });
    return typeof url === 'string' && url.startsWith('data:image/png;base64,') ? url : '';
}
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
export async function mountPortraits(root, playerAvatarPortrait) {
    const resolver = getEnemyPortraitResolver();
    const containers = Array.from(root.querySelectorAll('[data-warlord-portrait]'));
    const enemyMounts = !resolver?.mount ? [] : containers.map(async (container) => {
        const identifier = container.dataset.warlordPortrait;
        const image = container.querySelector('img');
        if (!identifier || !image)
            return;
        await resolver.mount?.(container, image, { portraitRef: identifier, identifier });
    });
    const playerAvatarActor = mercActorFromPlayerAvatarPortrait(playerAvatarPortrait);
    const mercMounts = !playerAvatarActor || !window.MercPortraits?.mount ? []
        : Array.from(root.querySelectorAll('[data-warlord-player-avatar]')).map(async (container) => {
            const image = container.querySelector('img');
            if (!image)
                return;
            container.dataset.warlordPortraitKind = 'player_avatar';
            await window.MercPortraits?.mount(container, image, {
                ...playerAvatarActor,
            }, { variant: 'card', size: 112, alt: '' });
        });
    await Promise.all([...enemyMounts, ...mercMounts]);
}
//# sourceMappingURL=portrait-texture-source.js.map