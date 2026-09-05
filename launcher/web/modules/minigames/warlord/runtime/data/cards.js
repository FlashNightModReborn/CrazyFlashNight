import snapshotJson from './warlord-cards.snapshot.js';
export const CARD_SNAPSHOT = snapshotJson;
export const CARD_DEFINITIONS = Object.freeze(Object.fromEntries(CARD_SNAPSHOT.cards.map((card) => [card.cardId, Object.freeze(card)])));
export const CARD_IDS = Object.freeze([...CARD_SNAPSHOT.cards]
    .sort((a, b) => a.cardId - b.cardId)
    .map((card) => card.cardId));
/** 唯一指挥官卡只由 Commander ledger 重建，不进入普通兵种排产。 */
export const PRODUCTION_CARD_IDS = Object.freeze(CARD_IDS.filter((cardId) => !CARD_DEFINITIONS[cardId]?.tags.includes('commander')));
export function getCardDefinition(cardId) {
    const card = CARD_DEFINITIONS[cardId];
    if (!card)
        throw new Error(`Unknown cardId ${cardId}`);
    return card;
}
export function isCommanderCard(cardId) {
    return getCardDefinition(cardId).tags.includes('commander');
}
//# sourceMappingURL=cards.js.map