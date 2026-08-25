import snapshotJson from './warlord-cards.snapshot.js';
export const CARD_SNAPSHOT = snapshotJson;
export const CARD_DEFINITIONS = Object.freeze(Object.fromEntries(CARD_SNAPSHOT.cards.map((card) => [card.cardId, Object.freeze(card)])));
export const CARD_IDS = Object.freeze([...CARD_SNAPSHOT.cards]
    .sort((a, b) => a.cardId - b.cardId)
    .map((card) => card.cardId));
export function getCardDefinition(cardId) {
    const card = CARD_DEFINITIONS[cardId];
    if (!card)
        throw new Error(`Unknown cardId ${cardId}`);
    return card;
}
//# sourceMappingURL=cards.js.map