import { PROMOTIONS } from '../data/config.js';
import { getCardDefinition } from '../data/cards.js';
export function clamp(value, min, max) {
    return Math.min(max, Math.max(min, value));
}
export function interpolateStat(min, max, level) {
    return Math.max(1, Math.floor(min + ((max - min) / 59) * level));
}
export function getRuntimeStats(cardId, cardState) {
    const definition = getCardDefinition(cardId);
    let maxHp = interpolateStat(definition.statRanges.hp.min, definition.statRanges.hp.max, cardState.level);
    let attack = interpolateStat(definition.statRanges.unarmedAttack.min, definition.statRanges.unarmedAttack.max, cardState.level);
    let defense = interpolateStat(definition.statRanges.baseDefense.min, definition.statRanges.baseDefense.max, cardState.level);
    const speed = interpolateStat(definition.statRanges.speed.min, definition.statRanges.speed.max, cardState.level);
    for (const promotionId of cardState.purchasedPromotions) {
        const promotion = PROMOTIONS[promotionId];
        maxHp += promotion.hp;
        attack += promotion.attack;
        defense += promotion.defense;
    }
    return { maxHp, attack, defense, speed };
}
export function baseBounty(cardId, level) {
    const { expRange } = getCardDefinition(cardId);
    return Math.floor(expRange.min + ((expRange.max - expRange.min) / 59) * level);
}
export function bounty(cardId, level) {
    return Math.max(1, Math.round(baseBounty(cardId, level) * 5));
}
export function needXp(cardId, level) {
    const { expRange } = getCardDefinition(cardId);
    return Math.floor((expRange.min + ((expRange.max - expRange.min) / 59) * level) * level);
}
export function promotionStats(promotions) {
    return promotions.reduce((acc, promotionId) => {
        const promotion = PROMOTIONS[promotionId];
        acc.maxHp += promotion.hp;
        acc.attack += promotion.attack;
        acc.defense += promotion.defense;
        return acc;
    }, { maxHp: 0, attack: 0, defense: 0 });
}
//# sourceMappingURL=math.js.map