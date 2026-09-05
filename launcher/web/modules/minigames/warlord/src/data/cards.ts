import snapshotJson from './warlord-cards.snapshot.js';
import type { CardDefinition, CardId } from '../core/types.js';

interface SnapshotShape {
  schemaVersion: number;
  snapshotVersion: string;
  rulesVersion: string;
  cards: CardDefinition[];
}

export const CARD_SNAPSHOT = snapshotJson as unknown as SnapshotShape;
export const CARD_DEFINITIONS = Object.freeze(
  Object.fromEntries(CARD_SNAPSHOT.cards.map((card) => [card.cardId, Object.freeze(card)])),
) as Readonly<Record<CardId, Readonly<CardDefinition>>>;

export const CARD_IDS = Object.freeze(
  [...CARD_SNAPSHOT.cards]
    .sort((a, b) => a.cardId - b.cardId)
    .map((card) => card.cardId),
) as readonly CardId[];

/** 唯一指挥官卡只由 Commander ledger 重建，不进入普通兵种排产。 */
export const PRODUCTION_CARD_IDS = Object.freeze(
  CARD_IDS.filter((cardId) => !CARD_DEFINITIONS[cardId]?.tags.includes('commander')),
) as readonly CardId[];

export function getCardDefinition(cardId: CardId): Readonly<CardDefinition> {
  const card = CARD_DEFINITIONS[cardId];
  if (!card) throw new Error(`Unknown cardId ${cardId}`);
  return card;
}

export function isCommanderCard(cardId: CardId): boolean {
  return getCardDefinition(cardId).tags.includes('commander');
}
