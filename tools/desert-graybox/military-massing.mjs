/**
 * Functional military masses for the desert design study.
 * Geographic anchors and route identities come from the shared design JSON.
 * Regional/city footprints, heights and gate extents are explicitly symbolic.
 */
const SUPPORTED = new Set(['fort', 'frontbase', 'depot', 'secret', 'diplomacy', 'industry']);
const MAIN_ROUTE = {
  fort: 'assault', frontbase: 'front-supply', depot: 'depot-spur',
  secret: 'secret-access', diplomacy: 'diplomatic-access', industry: 'industry-fort',
};
const ROLE = {
  fort: '驻军、装甲集结、回收维修与局部团部',
  frontbase: '独立前线指挥、通信与保障节点',
  depot: '支路转运货场与小型哨所',
  secret: '后续章节复用西谷旧设施的残部聚落',
  diplomacy: '小型待定位外交驻地',
  industry: '军工生产、仓储与向外运输的腹地组团',
};
const ZONE_LABELS = {
  entry_and_exit: '进退门口', command_and_barracks: '指挥与营房',
  recovery_workshop: '回收维修场', armor_and_open_court: '装甲集结场',
  route_interfaces: '前线路口', operations_and_comms: '指挥通信区', forward_support: '前线保障区',
  branch_road_gates: '货场出入口', cargo_and_loading: '物资转运场',
  reused_edges: '旧设施围界', reused_workshop: '旧维修设施', regrouping_court: '残部驻留内院',
  small_arrival_court: '外交到访院', logistics_perimeter: '工业运输门口',
  heavy_production: '军工生产区', warehousing_and_marshalling: '仓储集散场',
};

function approaches(data, place) {
  const places = new Map(data.places.map(item => [item.id, item]));
  const result = [];
  for (const route of data.routes) {
    for (let i = 0; i < route.points.length; i++) {
      if (route.points[i] !== place.id) continue;
      for (const index of [i - 1, i + 1]) {
        if (index < 0 || index >= route.points.length) continue;
        const next = route.points[index];
        const xy = typeof next === 'string' ? places.get(next)?.xy : next;
        if (!xy) continue;
        const dx = xy[0] - place.xy[0], dy = xy[1] - place.xy[1];
        const distance = Math.hypot(dx, dy);
        if (distance > 1e-8) result.push({ routeId: route.id, neighborXY: [...xy], toward: [dx / distance, dy / distance] });
      }
    }
  }
  return result;
}

export function refineMilitary(c, ctx) {
  const { THREE, data, mode } = ctx;
  const id = c.place.id;
  if (mode === 'base' || !['region', 'city'].includes(mode) || !SUPPORTED.has(id)) return false;
  const scale = mode === 'region' ? 1 : 0.38;
  const heightScale = mode === 'region' ? 1 : 0.42;
  const incoming = approaches(data, c.place);
  const main = incoming.find(item => item.routeId === MAIN_ROUTE[id]) || incoming[0];
  const outward = main?.toward || [0, -1];
  const north = [-outward[0], -outward[1]], east = [north[1], -north[0]];
  const rotation = Math.atan2(east[1], east[0]);
  let currentZone = null;
  const zones = [];
  const toOffset = (x, y) => [(east[0] * x + north[0] * y) * scale, (east[1] * x + north[1] * y) * scale];
  const toGeographic = (x, y) => {
    const offset = toOffset(x, y);
    return [c.place.xy[0] + offset[0], c.place.xy[1] + offset[1]];
  };
  function zone(name, designRole, draw) {
    const group = new THREE.Group();
    group.name = `${id}_${name}`;
    const label = ZONE_LABELS[name] || name;
    const subareaId = `${id}-${name}`;
    group.userData = { placeId: id, designRole: label, label, subareaId, designDescription: designRole, candidate: true };
    c.object.add(group);
    const previous = currentZone;
    currentZone = group;
    draw();
    currentZone = previous;
    zones.push({ name, subareaId, designRole: label, label, meshes: group.children.length });
  }
  function attach(item) {
    if (currentZone) {
      currentZone.add(item); // Groups are identity transforms; c's terrain placement is retained.
      item.userData.designRole = currentZone.userData.designRole;
    }
    return item;
  }
  function box(x, y, width, depth, height, material = 'concrete', lift = 0, turn = 0) {
    const offset = toOffset(x, y);
    return attach(c.box(offset[0], offset[1], width * scale, depth * scale,
      height * heightScale, material, lift * heightScale, rotation + turn));
  }
  function house(x, y, width, depth, height, material = 'concrete') {
    box(x, y, width, depth, height, material);
    box(x, y, width * 1.045, depth * 1.045, Math.max(2, height * 0.065), 'roof', height);
  }
  function drum(x, y, radius, height, material = 'light', lift = 0) {
    const offset = toOffset(x, y);
    return attach(c.drum(offset[0], offset[1], radius * scale, height * heightScale, material, lift * heightScale));
  }
  function vehicle(x, y, recovered = false) {
    // Enlarged role silhouettes, never claimed as measured existing tank assets.
    for (const side of [-1, 1]) box(x + side * 0.13, y, 0.085, 0.55, 15, 'dark');
    box(x, y, 0.23, 0.48, 18, recovered ? 'dry' : 'roof', 6);
    if (recovered) {
      box(x, y + 0.06, 0.21, 0.24, 10, 'pale', 23);
      box(x, y - 0.16, 0.22, 0.12, 5, 'dark', 23);
    } else {
      box(x, y + 0.04, 0.18, 0.2, 14, 'concrete', 22);
      box(x, y - 0.19, 0.035, 0.33, 4, 'dark', 29);
    }
  }
  function cargo(x, y, columns, rows, material = 'roof') {
    for (let row = 0; row < rows; row++) for (let col = 0; col < columns; col++) {
      box(x + col * 0.25, y + row * 0.31, 0.19, 0.25, 22 + ((row + col) % 2) * 7, material);
    }
  }
  function yard(x, y, width, depth, role) {
    // Only corner strips: the central assembly/turning area remains unbuilt.
    const item = { centerXY: toGeographic(x, y), symbolicWidthKm: width * scale,
      symbolicDepthKm: depth * scale, designRole: role, intentionallyUnbuilt: true };
    c.object.userData.openYards.push(item);
    for (const dx of [-1, 1]) for (const dy of [-1, 1]) {
      box(x + dx * (width / 2 - 0.11), y + dy * depth / 2, 0.22, 0.025, 1.8, 'light');
      box(x + dx * width / 2, y + dy * (depth / 2 - 0.11), 0.025, 0.22, 1.8, 'light');
    }
  }

  function gatesFor(width, depth) {
    const gates = [];
    for (const approach of incoming) {
      const u = approach.toward[0] * east[0] + approach.toward[1] * east[1];
      const v = approach.toward[0] * north[0] + approach.toward[1] * north[1];
      const distance = Math.min(width / 2 / (Math.abs(u) || 1e-12), depth / 2 / (Math.abs(v) || 1e-12));
      const local = [u * distance, v * distance];
      const side = Math.abs(Math.abs(local[0]) - width / 2) < 1e-6 ? (u < 0 ? 'west' : 'east') : (v < 0 ? 'south' : 'north');
      let gate = gates.find(item => item.side === side && Math.hypot(item.local[0] - local[0], item.local[1] - local[1]) < 0.09);
      if (gate) gate.routeIds.push(approach.routeId);
      else {
        gate = { side, local, geographicXY: toGeographic(...local), routeIds: [approach.routeId], neighborXY: approach.neighborXY };
        gates.push(gate);
      }
    }
    if (!gates.length) gates.push({ side: 'south', local: [0, -depth / 2], geographicXY: toGeographic(0, -depth / 2), routeIds: [], neighborXY: null });
    return gates;
  }

  function perimeter(width, depth, height, gap, options = {}) {
    const gates = gatesFor(width, depth);
    const sides = options.sides || ['west', 'east', 'south', 'north'];
    for (const side of sides) {
      const horizontal = side === 'south' || side === 'north';
      const half = (horizontal ? width : depth) / 2;
      const fixed = side === 'south' ? -depth / 2 : side === 'north' ? depth / 2 : side === 'west' ? -width / 2 : width / 2;
      const gaps = gates.filter(gate => gate.side === side).map(gate => {
        const at = gate.local[horizontal ? 0 : 1];
        return [Math.max(-half, at - gap / 2), Math.min(half, at + gap / 2)];
      }).sort((a, b) => a[0] - b[0]);
      let start = -half;
      for (const [a, b] of [...gaps, [half, half]]) {
        if (a > start + 0.025) {
          const midpoint = (start + a) / 2, length = a - start;
          if (horizontal) box(midpoint, fixed, length, 0.045, height, 'dry');
          else box(fixed, midpoint, 0.045, length, height, 'dry');
        }
        start = Math.max(start, b);
      }
    }
    for (const gate of gates) {
      const horizontal = gate.side === 'south' || gate.side === 'north';
      for (const sign of [-1, 1]) box(gate.local[0] + (horizontal ? sign * gap / 2 : 0),
        gate.local[1] + (horizontal ? 0 : sign * gap / 2), 0.075, 0.075, height * 1.55, 'light');
    }
    c.object.userData.gateOpenings = gates.map(gate => ({ routeIds: gate.routeIds,
      geographicXY: gate.geographicXY, neighborXY: gate.neighborXY,
      localDesignXY: gate.local, symbolicOpeningKm: gap * scale,
      note: '实体开口由道路末段方向投射至放大围界；不是用地理中心点充当大门。' }));
  }

  c.object.userData.designRole = ROLE[id];
  c.object.userData.geographicAnchor = [...c.place.xy];
  c.object.userData.openYards = [];
  c.object.userData.buildingHeightScale = heightScale;
  c.object.userData.footprintScale = scale;
  c.object.userData.geographicHeadingFromRoute = main?.routeId || null;
  c.object.userData.footprint = 'Mode-specific enlarged role massing; ground anchor is fixed, compound extent is not surveyed.';
  c.object.userData.timeBoundary = id === 'secret' ? '后续章节残部重组状态，非原有全势力总部'
    : id === 'diplomacy' ? '待定位外交接口，独立身份不证明独立大型要塞'
      : '职能候选，不代表所有章节的驻军、车辆或通行状态';

  if (id === 'fort') {
    zone('entry_and_exit', '面向主攻、撤收与工业支援道路的实体门口', () => perimeter(5.3, 4.1, 18, 0.6));
    zone('command_and_barracks', '团部与营房，避开中央进退走廊', () => {
      house(1.7, 1.15, 1.05, 0.7, 105);
      for (const y of [-0.85, 0.15]) house(1.8, y, 0.67, 0.65, 66);
      box(2.24, 1.58, 0.035, 0.035, 185, 'dark');
    });
    zone('recovery_workshop', '回收维修棚、吊运架及待整备车辆', () => {
      house(-1.66, 1.03, 1.3, 0.68, 82, 'dry');
      for (const x of [-2.22, -1.08]) box(x, 0.55, 0.065, 0.07, 105, 'roof');
      box(-1.65, 0.55, 1.24, 0.075, 10, 'roof', 100);
      vehicle(-1.65, 0.53, true);
      cargo(-2.13, 1.58, 3, 1, 'pale');
    });
    zone('armor_and_open_court', '装甲分散集结与保留的回收转弯场坪', () => {
      vehicle(-1.7, -1.32); vehicle(-0.98, -1.32);
      yard(-0.3, 0.06, 1.4, 1.2, '进退通路和维修调车场');
      yard(0.62, -1.24, 0.8, 0.82, '空置集结位置，非全军覆灭残骸场');
    });
  } else if (id === 'frontbase') {
    zone('route_interfaces', '独立前线基地的来路、接触带通路和保障通路', () => perimeter(3.45, 2.85, 11, 0.5));
    zone('operations_and_comms', '指挥室、通信设备与天线轮廓', () => {
      house(0.94, 0.42, 0.92, 0.58, 100);
      house(0.96, -0.42, 0.65, 0.42, 54, 'light');
      box(1.2, 1.01, 0.045, 0.045, 245, 'roof');
      for (const lift of [135, 192]) box(1.2, 1.01, 0.44, 0.035, 7, 'pale', lift);
      drum(0.72, 1.04, 0.16, 28, 'pale');
    });
    zone('forward_support', '轻量保障、医疗与短时整备，不复制装甲大本营', () => {
      house(-0.93, -0.66, 0.68, 0.48, 47, 'light');
      house(-1.07, 0.2, 0.48, 0.42, 38, 'dry');
      drum(-0.76, -1.09, 0.12, 32, 'water');
      cargo(0.28, -1.06, 3, 1);
      yard(0.02, 0.05, 0.92, 1.05, '通信/补给人员进出与短停调度场');
    });
  } else if (id === 'depot') {
    zone('branch_road_gates', '支路双向进出，货场不切断干道', () => perimeter(2.0, 1.8, 9, 0.4));
    zone('cargo_and_loading', '物资仓棚、露天堆场和侧装卸口', () => {
      house(0.6, 0.1, 0.53, 1.03, 62, 'dry');
      box(0.22, 0.16, 0.2, 0.7, 8, 'light');
      cargo(-0.76, -0.64, 2, 2);
      house(0.65, -0.64, 0.3, 0.25, 28);
      yard(-0.07, -0.29, 0.72, 0.72, '货车转弯及分拣空地');
    });
  } else if (id === 'secret') {
    zone('reused_edges', '西谷旧设施的残存围界，入口朝旧服务路', () => perimeter(2.9, 2.45, 12, 0.43, { sides: ['west', 'north'] }));
    zone('reused_workshop', '复用修理棚、残存结构与后加附屋', () => {
      house(-0.79, 0.38, 1.07, 0.6, 64, 'dry');
      box(-0.85, 0.82, 1.05, 0.065, 42, 'concrete');
      box(-1.3, 0.71, 0.08, 0.52, 52, 'dry');
      house(0.76, 0.05, 0.56, 0.62, 46);
      house(0.38, 0.76, 0.47, 0.43, 31, 'pale');
      drum(-0.61, -0.23, 0.15, 38, 'dry');
    });
    zone('regrouping_court', '少量后加驻留设施与可周转内院', () => {
      house(0.89, -0.66, 0.35, 0.28, 26, 'roof');
      cargo(-1.0, -0.85, 2, 1, 'dry');
      yard(0.07, -0.21, 0.84, 0.85, '小型会合与改装间前场，保留潜入/围堵空间');
    });
  } else if (id === 'diplomacy') {
    zone('small_arrival_court', '待定位的小型营区入口与会面场坪', () => {
      perimeter(1.75, 1.35, 6, 0.4);
      house(0.17, 0.34, 0.95, 0.4, 53, 'light');
      house(-0.59, -0.38, 0.26, 0.27, 26);
      yard(0.1, -0.21, 0.72, 0.48, '外交到访与少量警卫空间');
      box(0.71, 0.46, 0.028, 0.028, 92, 'roof');
      box(0.79, 0.46, 0.18, 0.025, 19, 'pale', 65);
    });
  } else if (id === 'industry') {
    zone('logistics_perimeter', '生产腹地接驻地、前线和对外运输的门口', () => perimeter(8.0, 6.0, 10, 0.78));
    zone('heavy_production', '大跨厂房、排风屋脊与动力设施', () => {
      house(-2.07, 1.32, 2.5, 1.45, 140, 'dry');
      for (const x of [-2.88, -2.06, -1.24]) box(x, 1.32, 0.48, 1.48, 30, 'light', 140);
      for (const x of [-3.15, -2.65]) drum(x, 2.55, 0.11, x < -3 ? 285 : 225, 'roof');
      drum(-1.48, 2.53, 0.23, 71, 'pale');
      drum(-0.88, 2.53, 0.23, 71, 'pale');
      house(1.78, -1.24, 2.55, 1.22, 118);
      for (const x of [1.05, 1.78, 2.51]) box(x, -1.24, 0.43, 1.25, 23, 'pale', 118);
    });
    zone('warehousing_and_marshalling', '原料、成品仓与不被楼体填满的货运场', () => {
      house(1.02, 2.28, 1.36, 0.65, 79, 'light');
      cargo(-3.1, -2.44, 4, 2);
      cargo(2.3, 2.55, 3, 1, 'pale');
      yard(0.04, 0.0, 2.5, 1.3, '生产与出货车辆的分流和集散空地');
      yard(-2.27, -0.64, 1.43, 0.69, '西侧保障出口前的等待场');
    });
  }
  c.object.userData.functionalZones = zones;
  c.object.userData.gateAnchorDistinction = 'geographicAnchor固定于JSON；gateOpenings在符号围界上由道路方向推导，切换比例后其偏移随符号尺度改变。';
  c.object.userData.assemblyNote = '普通Group与Mesh；所有职能和建筑体量为可编辑灰模候选，不新增生产关卡或军事实装能力。';
  return true;
}
