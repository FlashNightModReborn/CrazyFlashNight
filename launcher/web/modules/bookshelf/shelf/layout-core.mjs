/**
 * Pure, renderer-independent layouts for the v3 glTF object library.
 * glTF coordinates: +X right, +Y up, +Z toward the reader. All lengths use
 * the source model's units. Only cabinet boards change size; library objects
 * keep their source dimensions and rest rotation.
 */
export const BOARD_THICKNESS = 0.30;
export const CLEAR_HEIGHT = 6.80;
export const MAX_ITEM_HEIGHT = 6.55;
export const BOOK_YAW = 10 * Math.PI / 180;
export const LAYOUT_KEYS = Object.freeze(['wide', 'medium', 'narrow']);
export const BREAKPOINTS = Object.freeze({ narrow: 0.82, wide: 1.42, hysteresis: 0.08 });

/** Select by actual canvas aspect, with an 0.08 deadband around each boundary. */
export function chooseLayout(aspect, previous = '') {
  if (!Number.isFinite(aspect) || aspect <= 0) return LAYOUT_KEYS.includes(previous) ? previous : 'wide';
  const { narrow, wide, hysteresis: h } = BREAKPOINTS;
  if (previous === 'wide') return aspect >= wide - h ? 'wide' : aspect < narrow - h ? 'narrow' : 'medium';
  if (previous === 'narrow') return aspect <= narrow + h ? 'narrow' : aspect > wide + h ? 'wide' : 'medium';
  if (previous === 'medium') return aspect > wide + h ? 'wide' : aspect < narrow - h ? 'narrow' : 'medium';
  return aspect >= wide ? 'wide' : aspect < narrow ? 'narrow' : 'medium';
}

const BOOKS = Object.freeze({
  dust: { width: 1.23, height: 6.42, depth: 3.75 },
  babylon: { width: 1.30, height: 6.50, depth: 3.90 },
  guardian: { width: 1.38, height: 6.55, depth: 3.80 },
  'sail-twins': { width: 1.24, height: 6.32, depth: 3.80 }
});
const PROFILES = Object.freeze({
  wide: {
    width: 23.8, bookTierCount: 2, archiveRows: 1,
    books: [['sail-twins', 0, -8.50], ['dust', 1, -8.50], ['babylon', 1, -6.20], ['guardian', 1, -3.90]],
    collection: [0, 3.00],
    archives: [[0, -8.55], [0, -3.15], [0, 2.25], [0, 8.20]],
    reserves: [[0, -5.80], [0, -3.20], [0, 8.50], [1, -0.90], [1, 1.70], [1, 4.30], [1, 6.90], [1, 9.50]]
  },
  medium: {
    width: 16.0, bookTierCount: 3, archiveRows: 2,
    books: [['sail-twins', 1, -5.85], ['guardian', 1, -3.45], ['dust', 2, -5.85], ['babylon', 2, -3.55]],
    collection: [0, -3.50],
    archives: [[0, -2.75], [0, 2.75], [1, -2.75], [1, 2.75]],
    reserves: [[0, 1.00], [0, 3.60], [0, 6.20], [1, -0.75], [1, 1.85], [1, 4.45], [2, -0.75], [2, 1.85], [2, 4.45]]
  },
  narrow: {
    width: 11.6, bookTierCount: 4, archiveRows: 2,
    books: [['sail-twins', 1, -3.20], ['guardian', 1, -0.80], ['dust', 2, -3.20], ['babylon', 3, -3.20]],
    collection: [0, -0.70],
    archives: [[0, -2.72], [0, 2.72], [1, -2.72], [1, 2.72]],
    reserves: [[0, 4.00], [1, 2.30], [2, 0.00], [2, 2.60], [3, 0.00], [3, 2.60]]
  }
});

const round = n => Math.round(n * 1e6) / 1e6;
function aabbAt(position, size, base = false) {
  return {
    min: position.map((n, i) => round(n - (base && i === 1 ? 0 : size[i] / 2))),
    max: position.map((n, i) => round(n + (base && i === 1 ? size[i] : size[i] / 2)))
  };
}
function shiftedAabb(position, min, max) {
  return { min: min.map((n, i) => round(n + position[i])), max: max.map((n, i) => round(n + position[i])) };
}
function bookAabb(position, { width, height, depth }) {
  // Source spine lies 0.008 ahead of covers; decorative page seams extend
  // 0.025 behind them. Include both in the conservative rest-space envelope.
  const c = Math.cos(BOOK_YAW), s = Math.sin(BOOK_YAW), xs = [], zs = [];
  for (const x of [-width / 2, width / 2]) for (const z of [-depth / 2 - 0.025, depth / 2 + 0.008]) {
    xs.push(x * c + z * s); zs.push(-x * s + z * c);
  }
  return shiftedAabb(position, [Math.min(...xs), 0, Math.min(...zs)], [Math.max(...xs), height, Math.max(...zs)]);
}
function freezeDeep(value) {
  if (value && typeof value === 'object' && !Object.isFrozen(value)) {
    Object.values(value).forEach(freezeDeep); Object.freeze(value);
  }
  return value;
}

/** Build a frozen layout. Placements are in each original glTF parent's space. */
function buildLayout(key) {
  const p = PROFILES[key];
  const t = BOARD_THICKNESS, cabinetDepth = 4.65, archivePitch = 2.65, bookPitch = CLEAR_HEIGHT + t;
  const archiveTop = round(0.15 + p.archiveRows * archivePitch);
  const height = round(archiveTop + p.bookTierCount * bookPitch + t / 2);
  const tiers = Array.from({ length: p.bookTierCount }, (_, index) => {
    const floorY = round(archiveTop + t / 2 + index * bookPitch);
    return { index, floorY, ceilingY: round(floorY + CLEAR_HEIGHT), clearHeight: CLEAR_HEIGHT };
  });
  const placements = { ARCHIVE_BANK: [0, 0, 0] }, items = [], boards = [], shelves = [];
  const board = (name, kind, position, size) => {
    const value = { name, kind, position: position.map(round), size: size.map(round), aabb: aabbAt(position, size) };
    boards.push(value); return value;
  };
  const shelfYs = Array.from({ length: p.archiveRows + 1 }, (_, i) => round(0.15 + i * archivePitch));
  for (let i = 1; i <= p.bookTierCount; i++) shelfYs.push(round(archiveTop + i * bookPitch));
  shelfYs.forEach((y, i) => {
    const shelf = board(`MODULAR_SHELF_${i}`, 'shelf', [0, y, 0], [p.width - t, t, cabinetDepth]);
    shelves.push(shelf);
    if (i > 0) board(`MODULAR_LIP_${i}`, 'lip', [0, y - 0.01, 2.36], [p.width - t, t, 0.12]);
  });
  for (const sign of [-1, 1]) {
    board(`MODULAR_SIDE_${sign < 0 ? 'LEFT' : 'RIGHT'}`, 'side', [sign * (p.width / 2 - t / 2), height / 2, 0], [t, height, cabinetDepth]);
    board(`MODULAR_FOOT_${sign < 0 ? 'LEFT' : 'RIGHT'}`, 'foot', [sign * (p.width / 2 - 1.30), -0.14, 0], [1.2, 0.28, 3.8]);
  }
  board('MODULAR_BACK', 'back', [0, height / 2, -2.22], [p.width - 2 * t, height - 2 * t, 0.16]);
  for (const [id, tier, x] of p.books) {
    const dimensions = BOOKS[id], name = `BOOK_${id}`, position = [x, tiers[tier].floorY, 0.1];
    placements[name] = position;
    items.push({ name, id, kind: 'book', tier, position, size: [dimensions.width, dimensions.height, dimensions.depth], yaw: BOOK_YAW, aabb: bookAabb(position, dimensions) });
  }
  const [collectionTier, collectionX] = p.collection;
  const collectionPosition = [collectionX, tiers[collectionTier].floorY, 0.05];
  placements.COLLECTION_CF1_6 = collectionPosition;
  items.push({ name: 'COLLECTION_CF1_6', id: 'crazy-flasher', kind: 'collection', tier: collectionTier, position: collectionPosition, size: [5.65, 6.55, 4.04], yaw: 0,
    aabb: shiftedAabb(collectionPosition, [-2.825, 0, -1.975], [2.825, 6.55, 2.065]) });
  for (let i = 0; i < 6; i++) placements[`DISC_CF${i + 1}`] = [round(-2.21 + i * 0.88), 0.23, 0];
  const archiveKeys = ['current', 'recent02', 'recent03', 'all'];
  const archiveSlots = p.archives.map(([row, x], index) => {
    const id = archiveKeys[index], isDrawer = id === 'all', name = isDrawer ? 'ARCHIVE_ALL_DRAWER' : `ARCHIVE_SHORTCUT_${id}`;
    const position = [x, round((isDrawer ? 0.39 : 0.38) + row * archivePitch), isDrawer ? 0 : 0.05];
    const aabb = isDrawer ? shiftedAabb(position, [-2.55, 0, -2.06], [2.55, 2.035, 2.61])
      : shiftedAabb(position, [-2.525, 0, -2.05], [2.525, 2.05, 2.35]);
    placements[name] = position;
    const item = { name, id: `archive:${id}`, kind: isDrawer ? 'archiveDirectory' : 'archiveShortcut', row, position, size: aabb.max.map((n, axis) => round(n - aabb.min[axis])), aabb };
    items.push(item); return item;
  });
  // The same fixed-size case can occupy any future slot. The slot's AABB includes
  // a 10-degree book yaw, but is intentionally left completely empty in the scene.
  const reserveSlots = p.reserves.map(([tier, x], index) => {
    const position = [x, tiers[tier].floorY, 0.1], size = [2.20, MAX_ITEM_HEIGHT, 4.26];
    return { id: `reserve:${key}:${index + 1}`, tier, position, size, maxBookWidth: 1.5, maxBookDepth: 4.0, maxBookHeight: MAX_ITEM_HEIGHT, aabb: aabbAt(position, size, true) };
  });
  const bounds = { min: [-p.width / 2, -0.28, -cabinetDepth / 2], max: [p.width / 2, height, 2.61] };
  return freezeDeep({
    key, width: p.width, height, depth: round(bounds.max[2] - bounds.min[2]), cabinetDepth,
    boardThickness: t, clearHeight: CLEAR_HEIGHT, maxItemHeight: MAX_ITEM_HEIGHT,
    bookTierCount: p.bookTierCount, archiveRowCount: p.archiveRows, archivePitch,
    placements, tiers, boards, shelves, items, archiveSlots, reserveSlots, bounds,
    // Inspection/pull motion can be fitted independently from the closed cabinet.
    interactionBounds: { min: [...bounds.min], max: [bounds.max[0], bounds.max[1], round(2.61 + 3.15)] }
  });
}
const LAYOUTS = Object.fromEntries(LAYOUT_KEYS.map(key => [key, buildLayout(key)]));

export function layoutFor(key) {
  if (!LAYOUTS[key]) throw new RangeError(`Unknown shelf layout: ${key}`);
  return LAYOUTS[key];
}

/** Strict positive-volume AABB collision test. Touching board/support faces are OK. */
export function aabbOverlap(a, b, epsilon = 1e-5) {
  return [0, 1, 2].every(axis => Math.min(a.max[axis], b.max[axis]) - Math.max(a.min[axis], b.min[axis]) > epsilon);
}

/** Pure geometry acceptance checks, used in Node without THREE or a WebGL context. */
export function validateLayout(layoutOrKey) {
  const l = typeof layoutOrKey === 'string' ? layoutFor(layoutOrKey) : layoutOrKey;
  const errors = [], library = l.items.filter(item => item.kind === 'book' || item.kind === 'collection');
  if (l.clearHeight < CLEAR_HEIGHT - 1e-6) errors.push('Book clear height is less than 6.80.');
  if (Math.abs(l.boardThickness - BOARD_THICKNESS) > 1e-6) errors.push('Board thickness changed.');
  if (l.items.filter(item => item.kind === 'book').length !== 4) errors.push('Expected four books.');
  if (l.archiveSlots.filter(item => item.kind === 'archiveShortcut').length !== 3 || l.archiveSlots.filter(item => item.kind === 'archiveDirectory').length !== 1) errors.push('Expected three archive shortcuts and one all-archives drawer.');
  if (Object.keys(l.placements).filter(name => /^DISC_CF[1-6]$/.test(name)).length !== 6) errors.push('Expected all six CF cases.');
  for (const tier of l.tiers) if (tier.ceilingY - tier.floorY < CLEAR_HEIGHT - 1e-5) errors.push(`Tier ${tier.index} is too short.`);
  for (const shelf of l.shelves) if (Math.abs(shelf.size[1] - BOARD_THICKNESS) > 1e-6) errors.push(`${shelf.name} has a different board thickness.`);
  for (const slot of l.reserveSlots) {
    const future = bookAabb(slot.position, { width: slot.maxBookWidth, height: slot.maxBookHeight, depth: slot.maxBookDepth });
    if ([0, 1, 2].some(axis => future.min[axis] < slot.aabb.min[axis] - 1e-5 || future.max[axis] > slot.aabb.max[axis] + 1e-5)) errors.push(`${slot.id} cannot contain its advertised future book.`);
  }
  const objects = [...l.items, ...l.reserveSlots.map(slot => ({ ...slot, name: slot.id, kind: 'reserve' }))];
  for (const item of objects) {
    if (item.aabb.min[0] < -l.width / 2 + BOARD_THICKNESS - 1e-5 || item.aabb.max[0] > l.width / 2 - BOARD_THICKNESS + 1e-5) errors.push(`${item.name} crosses a cabinet side.`);
    for (const board of l.boards) if (aabbOverlap(item.aabb, board.aabb)) errors.push(`${item.name} intersects ${board.name}.`);
    if (item.tier !== undefined) {
      const tier = l.tiers[item.tier];
      if (item.aabb.min[1] < tier.floorY - 1e-5 || item.aabb.max[1] > tier.ceilingY + 1e-5) errors.push(`${item.name} crosses a shelf.`);
    }
  }
  for (const item of library) if (item.size[1] > MAX_ITEM_HEIGHT + 1e-6) errors.push(`${item.name} exceeds max height 6.55.`);
  for (let i = 0; i < objects.length; i++) for (let j = i + 1; j < objects.length; j++) {
    if (aabbOverlap(objects[i].aabb, objects[j].aabb)) errors.push(`${objects[i].name} overlaps ${objects[j].name}.`);
  }
  return { ok: errors.length === 0, errors, key: l.key, itemCount: l.items.length, reserveCount: l.reserveSlots.length };
}
