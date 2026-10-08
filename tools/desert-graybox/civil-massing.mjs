/**
 * Civilian planning masses for the desert spatial study.
 * Coordinates remain local to each unchanged geographic anchor. Districts,
 * building types and service arrangements are candidates, not adopted lore.
 * Region and city share a layout; region deliberately omits small components.
 */
export function refineCivil(c, ctx) {
  const { THREE, data, mode } = ctx;
  if (mode === 'base') return false;
  const supported = new Set(['commune', 'waste', 'fallen', 'constitutional', 'refugees', 'receiving', 'communes']);
  if (!supported.has(c.place.id)) return false;
  const detailed = mode === 'city';
  const heightScale = detailed ? 1 : 1.65;
  const placeById = new Map(data.places.map(place => [place.id, place]));
  const areaById = new Map((data.areas || []).map(area => [area.id, area]));
  const roads = (data.routes || []).filter(route => route.kind !== 'boat').flatMap(route => {
    const points = route.points.map(point => typeof point === 'string' ? placeById.get(point)?.xy : point).filter(Boolean);
    return points.slice(1).map((end, index) => [points[index], end]);
  });
  const roleLabels = {
    exchange_forecourt: '交割前场', factory_quarter: '生产厂区', workers_housing: '住区',
    limited_cultivation: '有限耕地', abandoned_field_grid: '失养田网',
    local_street_skeleton: '街坊联系', damaged_core_blocks: '残损城区', occupied_core_blocks: '在用城区',
    transition_blocks: '过渡街坊', peripheral_fragments: '稀疏城缘', institutional_courtyard: '公共院落',
    public_branch_forecourt: '支路前场', administrative_court: '总部院落',
    camp_arrival: '到达空地', household_clusters: '临时住区', finite_water_point: '有限水点',
    shared_loading_apron: '公共交割面', warehouse_edge: '仓棚装卸边',
    separate_hamlets: '独立村落', hamlet_field_remnants: '村外田界',
  };

  function district(role, label, build, extra = {}) {
    const before = new Set(c.object.children);
    const subgroup = new THREE.Group();
    subgroup.name = `${c.place.id}_${role}`;
    subgroup.userData = {
      placeId: c.place.id, designRole: roleLabels[role] || label, subareaId: role, label, status: 'candidate_massing',
      geographicParent: c.place.id, layoutIsSurveyed: false, ...extra,
    };
    c.object.add(subgroup);
    build();
    // All helpers create meshes in the unchanged place-local coordinate frame.
    // Identity child groups preserve that frame and keep the meshes editable.
    for (const child of [...c.object.children]) {
      if (child !== subgroup && !before.has(child)) {
        child.userData.designRole = roleLabels[role] || label;
        child.userData.subareaId = role;
        subgroup.add(child);
      }
    }
    return subgroup;
  }

  function line(a, b, width, heightM = 1, material = 'dry', liftM = 0) {
    const dx = b[0] - a[0], dy = b[1] - a[1];
    if (Math.hypot(dx, dy) < 1e-8) return;
    c.box((a[0] + b[0]) / 2, (a[1] + b[1]) / 2,
      Math.hypot(dx, dy), width, heightM, material, liftM, Math.atan2(dy, dx));
  }

  function distanceToSegment(point, a, b) {
    const dx = b[0] - a[0], dy = b[1] - a[1];
    const t = Math.max(0, Math.min(1, ((point[0] - a[0]) * dx + (point[1] - a[1]) * dy) / (dx * dx + dy * dy || 1)));
    return Math.hypot(point[0] - a[0] - t * dx, point[1] - a[1] - t * dy);
  }

  function inPolygon(point, polygon) {
    let inside = false;
    for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      const a = polygon[i], b = polygon[j];
      if ((a[1] > point[1]) !== (b[1] > point[1]) &&
          point[0] < (b[0] - a[0]) * (point[1] - a[1]) / (b[1] - a[1]) + a[0]) inside = !inside;
    }
    return inside;
  }

  function allowed(x, y, w, d, areaId, reserveRoad = true) {
    const point = [c.place.xy[0] + x, c.place.xy[1] + y];
    const polygon = areaById.get(areaId)?.polygon;
    // Roofs extend slightly beyond the walls; test their corners too.
    if (polygon && ![-1, 1].every(sx => [-1, 1].every(sy =>
      inPolygon([point[0] + sx * w * 0.54, point[1] + sy * d * 0.54], polygon)))) return false;
    if (!reserveRoad) return true;
    const radius = Math.hypot(w, d) * 0.54;
    return roads.every(([a, b]) => distanceToSegment(point, a, b) > radius + (detailed ? 0.14 : 0.24));
  }

  function building(x, y, w, d, h, areaId, material = 'concrete') {
    if (!allowed(x, y, w, d, areaId)) return false;
    c.house(x, y, w, d, h * heightScale, material);
    return true;
  }

  function industrialHall(x, y, w, d, h, areaId) {
    if (!building(x, y, w, d, h, areaId)) return;
    const teeth = detailed ? 4 : 2;
    for (let i = 0; i < teeth; i++) {
      const offset = (i - (teeth - 1) / 2) * w / (teeth + 0.8);
      c.box(x + offset, y, w / (teeth + 1.8), d * 0.9, h * heightScale * 0.16, 'pale', h * heightScale * 1.08);
    }
  }

  function yard(x, y, w, d, material = 'pale') {
    c.box(x, y, w, d, 0.6, material);
  }

  function fieldOutline(x, y, w, d, broken = false) {
    const t = detailed ? 0.035 : 0.055;
    if (broken) {
      line([x - w / 2, y - d / 2], [x + w * 0.05, y - d / 2], t, 1.6);
      line([x + w * 0.3, y - d / 2], [x + w / 2, y - d / 2], t, 1.6);
      line([x - w / 2, y - d / 2], [x - w / 2, y + d * 0.15], t, 1.6);
      line([x - w / 2, y + d * 0.35], [x - w / 2, y + d / 2], t, 1.6);
    } else {
      line([x - w / 2, y - d / 2], [x + w / 2, y - d / 2], t, 1.8);
      line([x - w / 2, y - d / 2], [x - w / 2, y + d / 2], t, 1.8);
    }
  }

  function commune() {
    const area = 'oldirrigation';
    district('exchange_forecourt', '公社交割前场与既有道路接口', () => {
      yard(0.06, 0.05, 0.65, 0.55);
      line([-1.5, -1.875], [0, 0], 0.16, 0.8, 'pale');
      line([0, 0], [0.18, 1.35], 0.13, 0.8, 'pale');
      line([0.18, 1.35], [1.18, 2.57], 0.11, 0.8, 'pale');
      line([0.15, 0.42], [3.25, 0.42], 0.11, 0.8, 'pale');
      building(-0.72, 0.18, 0.42, 0.35, 15, area, 'roof');
      if (detailed) {
        c.box(0.42, 0.24, 0.23, 0.16, 4, 'dark');
        c.box(0.43, -0.08, 0.17, 0.1, 3, 'dry');
      }
    }, { routeContract: 'Southwest connection follows commune-city/east-west-trade; the settlement does not gate those public routes.' });

    district('factory_quarter', '化肥与钢铁生产遗存的厂区体量', () => {
      industrialHall(0.35, 3.1, 1.22, 0.86, 31, area);
      industrialHall(2.08, 3.45, 1.35, 0.95, 37, area);
      for (const [x, y, radius, height] of [[1.93, 4.6, 0.14, 77], [2.37, 4.7, 0.12, 61], [0.7, 4.15, 0.2, 26]]) {
        if (allowed(x, y, radius * 2, radius * 2, area)) c.drum(x, y, radius, height * heightScale, height > 40 ? 'roof' : 'light');
      }
      building(2.4, 1.9, 0.62, 0.43, 15, area, 'dry');
      if (detailed) for (let i = 0; i < 3; i++) c.box(1.2 + i * 0.45, 2.25, 0.32, 0.14, 3.5, 'roof');
    }, { loreBoundary: 'Existing industrial capacity is sourced; exact plant arrangement and surviving equipment are a proposal.' });

    district('workers_housing', '工人住区与小型生活院落', () => {
      const homes = [[-1.65, -0.05], [-1.5, 0.68], [-2.15, 0.62], [0.73, -0.67], [1.36, -0.63], [2.01, -0.54]];
      homes.forEach(([x, y], i) => {
        if (!detailed && i % 2 === 1) return;
        building(x, y, 0.42, 0.34, 13 + (i % 2) * 4, area);
      });
      line([0.4, -0.2], [2.25, -0.2], 0.09, 0.7, 'pale');
      if (detailed) {
        building(0.84, -1.28, 0.43, 0.3, 12, area, 'dry');
        building(1.56, -1.21, 0.44, 0.28, 12, area, 'dry');
      }
    });

    district('limited_cultivation', '少量仍可用耕地', () => {
      for (const [x, y] of [[3.8, 3.1], [3.8, 4.21]]) {
        if (!allowed(x, y, 0.95, 0.95, area)) continue;
        fieldOutline(x, y, 0.95, 0.95);
        for (let i = 0; i < (detailed ? 5 : 3); i++) {
          const count = detailed ? 5 : 3;
          c.box(x - 0.34 + i * 0.68 / (count - 1), y + 0.02, 0.045, 0.73, 1.8, 'roof');
        }
      }
      c.drum(3.08, 4.21, 0.16, 4, 'water');
    }, { waterContract: 'Small managed plots and finite storage; does not give the commune groundwater control or abundant irrigation.' });

    district('abandoned_field_grid', '大面积失养田网与断续渠迹', () => {
      for (let row = 0; row < 3; row++) for (let col = 0; col < 3; col++) {
        const x = 5.12 + col * 1.16, y = 0.85 + row * 1.21;
        if (allowed(x, y, 1.02, 1.08, area)) fieldOutline(x, y, 1.02, 1.08, (row + col) % 3 !== 0);
      }
      line([3.77, 0.03], [5.02, 0.03], 0.09, 0.8, 'dark');
      line([5.46, 0.03], [6.75, 0.03], 0.09, 0.8, 'dark');
    }, { surfaceTreatment: 'Dry interrupted infrastructure traces, not green productive farmland.' });
  }

  function urban(damaged) {
    const area = damaged ? 'wastecity' : 'fallencity';
    const boundary = areaById.get(area)?.polygon;
    if (!boundary) throw new Error(`Missing civilian district boundary: ${area}`);
    // Small connected streets define neighborhoods rather than freestanding towers.
    const streetRows = detailed ? [-5.8, -2.4, 1.0, 4.4] : [-2.4, 4.4];
    district('local_street_skeleton', '城市内部街坊联系示意', () => {
      for (const y of streetRows) {
        const a = [-5.2, y], b = [5.6, y];
        for (let x = a[0]; x < b[0]; x += 1.35) {
          if (allowed(x + 0.675, y, 1.35, 0.12, area, false)) line([x, y], [x + 1.35, y], 0.1, 0.65, 'dry');
        }
      }
      for (const x of (detailed ? [-3.65, -0.15, 3.3] : [-0.15])) for (let y = -6.4; y < 5; y += 1.25) {
        if (allowed(x, y + 0.625, 0.12, 1.25, area, false)) line([x, y], [x, y + 1.25], 0.1, 0.65, 'dry');
      }
    }, { routeContract: 'Low relief internal street clues only; main source routes retain their existing alignment and clearance.' });

    const core = damaged ? [[-1.9, -4.0], [1.55, -4.0], [4.8, -4.0], [1.5, -7.3]] :
      [[-1.9, -4.0], [1.55, -4.0], [-5.2, -4.0], [-1.9, -7.3]];
    district(damaged ? 'damaged_core_blocks' : 'occupied_core_blocks', damaged ? '东区残损街坊团块' : '西区仍在使用的连续街坊', () => {
      core.forEach(([x, y], i) => block(x, y, damaged, 1, i, area));
    });

    const transition = [[-5.25, -0.6], [-1.9, -0.6], [1.55, -0.6], [4.85, -0.6], [-1.9, 2.7], [1.55, 2.7]];
    district('transition_blocks', '由城区向城缘降低的过渡街坊', () => {
      transition.forEach(([x, y], i) => block(x, y, damaged, 0.67, i + 10, area));
    });

    district('peripheral_fragments', '稀疏低层城缘与开放缺口', () => {
      const edge = [[-5.3, 2.7], [4.85, 2.7], [-5.3, 6.0], [-1.9, 6.0], [1.55, 6.0], [4.85, 6.0], [-5.3, -7.3], [4.85, -7.3]];
      edge.forEach(([x, y], i) => {
        if (!damaged && i === 0) return; // Reserved for the separate public courtyard below.
        if (!detailed && i % 2) return;
        block(x, y, damaged, 0.4, i + 30, area);
      });
    }, { gradient: 'Smaller, lower and fewer edge masses; source city polygon is an outer envelope, not a uniformly filled estate.' });

    if (!damaged) district('institutional_courtyard', '幸存公共建筑的院落体量', () => {
      // This identifies surviving institutional fabric, not the university's exact address.
      building(-5.05, 2.66, 1.4, 0.4, 31, area, 'light');
      building(-5.85, 2.04, 0.38, 0.95, 23, area);
      building(-4.25, 2.04, 0.38, 0.95, 23, area);
    }, { loreBoundary: 'Institutional courtyard placeholder; does not locate a named university, faction HQ or production landmark.' });
  }

  function block(x, y, damaged, density, ordinal, area) {
    const h = (22 + (ordinal % 3) * 7) * density;
    const w = 1.7 * Math.max(density, 0.68), d = 1.55 * Math.max(density, 0.68);
    // Plates bind related masses into a readable urban block but never form a tall pedestal.
    if (allowed(x, y, w + 0.12, d + 0.12, area, false)) yard(x, y, w + 0.12, d + 0.12, damaged ? 'dry' : 'pale');
    if (!detailed) {
      if (damaged && ordinal % 2 === 0) {
        brokenBuilding(x, y, w * 0.82, d * 0.66, h, area, ordinal);
      } else {
        building(x, y + d * 0.25, w, d * 0.36, h, area);
        building(x - w * 0.35, y - d * 0.13, w * 0.3, d * 0.66, h * 0.76, area, 'dry');
      }
      return;
    }
    const wings = [[x, y + d * 0.31, w, d * 0.3], [x - w * 0.35, y - d * 0.13, w * 0.3, d * 0.62]];
    if (density > 0.5) wings.push([x + w * 0.36, y - d * 0.13, w * 0.27, d * 0.62]);
    wings.forEach(([bx, by, bw, bd], i) => {
      if (damaged && (ordinal + i) % 3 !== 1) brokenBuilding(bx, by, bw, bd, h * (1 - i * 0.12), area, ordinal + i);
      else building(bx, by, bw, bd, h * (1 - i * 0.12), area, i === 1 ? 'dry' : 'concrete');
    });
  }

  function brokenBuilding(x, y, w, d, h, area, ordinal) {
    if (!allowed(x, y, w, d, area)) return;
    c.box(x, y, w, d, 3.5, 'dark');
    c.box(x - w * 0.45, y, w * 0.1, d, h * heightScale * 0.68, 'dry');
    c.box(x, y + d * 0.44, w, d * 0.12, h * heightScale, 'concrete');
    if (detailed) {
      c.box(x + w * 0.3, y - d * 0.2, w * 0.32, d * 0.26, 5, 'roof', 0, (ordinal % 3 - 1) * 0.35);
      c.box(x - w * 0.1, y + d * 0.12, w * 0.38, d * 0.36, 2.2, 'dry');
    }
  }

  function constitutional() {
    district('public_branch_forecourt', '宪政派独立支路前场', () => {
      yard(-0.19, 0, 0.8, 0.74);
      line([-0.85, -0.85], [0, 0], 0.16, 0.65, 'pale');
      line([-0.62, 1.03], [0, 0], 0.16, 0.65, 'pale');
      if (detailed) {
        c.box(-0.37, -0.43, 0.24, 0.1, 3, 'dark');
        c.box(-0.41, 0.43, 0.24, 0.1, 3, 'dark');
      }
    }, { routeContract: 'Existing northwest liaison and southwest city branches meet outside the administrative court; no monopoly checkpoint.' });
    district('administrative_court', '总部院落与服务翼楼', () => {
      // The open west side faces both source branches; the eastern building is off their corridor.
      c.house(0.74, 0.07, 0.47, 1.13, 27 * heightScale);
      c.house(0.3, 0.71, 0.7, 0.3, 18 * heightScale);
      c.house(0.31, -0.61, 0.7, 0.3, 16 * heightScale);
      line([1.1, -0.88], [1.1, 0.94], 0.035, 5, 'roof');
      line([-0.04, 0.94], [1.1, 0.94], 0.035, 5, 'roof');
      line([-0.04, -0.88], [1.1, -0.88], 0.035, 5, 'roof');
      c.box(0.1, 0.22, 0.025, 0.025, 34 * heightScale, 'dark');
      if (detailed) {
        c.house(1.41, -0.46, 0.36, 0.58, 12 * heightScale, 'dry');
        c.box(1.23, 0.31, 0.3, 0.12, 4, 'roof');
      }
    }, { loreBoundary: 'Independent administrative compound massing only; party offices and exact internal use remain unspecified.' });
  }

  function refugees() {
    district('camp_arrival', '侧谷居民聚落的到达空地', () => {
      yard(0, 0, 0.52, 0.46, 'dry');
      line([-0.86, -0.43], [0, 0], 0.11, 0.7, 'pale');
      line([0, 0], [0.62, 0.57], 0.08, 0.7, 'pale');
    }, { routeContract: 'Leaves the existing southwest exchange/conscript route clear; adds no gate, barracks or third supply compound.' });
    district('household_clusters', '帐篷与临时住屋小簇', () => {
      const homes = [[-0.63, 0.23], [-0.25, 0.41], [0.14, 0.43], [-0.58, 0.69], [-0.12, 0.86], [0.47, -0.18], [0.7, -0.62], [0.15, -0.7], [-0.35, -0.8]];
      homes.forEach(([x, y], i) => {
        if (!detailed && i % 3 === 2) return;
        if (i % 3 === 0) c.house(x, y, 0.26, 0.2, 9 * heightScale, 'dry');
        else c.tent(x, y, 0.18, 8 * heightScale);
      });
      if (detailed) {
        line([-0.73, 0.49], [-0.45, 0.46], 0.025, 1.5, 'roof');
        line([0.35, -0.46], [0.69, -0.46], 0.025, 1.5, 'roof');
      }
    });
    district('finite_water_point', '小型蓄水与送水交接点候选', () => {
      c.drum(0.72, 0.66, 0.15, 5 * heightScale, 'water');
      c.box(0.44, 0.8, 0.28, 0.13, 2.2, 'roof');
      c.house(0.96, 0.37, 0.24, 0.17, 7 * heightScale, 'pale');
      if (detailed) for (let i = 0; i < 3; i++) c.drum(0.49 + i * 0.13, 0.28, 0.04, 1.8, 'dark');
    }, { waterContract: 'Finite stored or delivered water; source/supplier and service level unresolved. No well, permanent river or guaranteed military subsidy.' });
  }

  function receiving() {
    district('shared_loading_apron', '西城公共物流接口与交割面', () => {
      yard(0, 0, 0.8, 0.68, 'pale');
      line([-0.7, 0.34], [0, 0], 0.13, 0.75, 'pale');
      line([0, 0], [-0.26, -0.92], 0.13, 0.75, 'pale');
    }, { ownership: 'Shared geographic interface; no new exclusive ownership by Black Iron or any other faction.' });
    district('warehouse_edge', '退让道路的仓棚与装卸边界', () => {
      building(-0.98, -0.32, 0.65, 0.72, 23, null);
      building(0.64, -0.74, 0.53, 0.72, 19, null, 'dry');
      for (let i = 0; i < (detailed ? 4 : 2); i++) {
        const x = 0.9 + (i % 2) * 0.28, y = -1.1 - Math.floor(i / 2) * 0.3;
        if (allowed(x, y, 0.19, 0.23, null)) c.box(x, y, 0.19, 0.23, 7 * heightScale, 'roof');
      }
    });
  }

  function communes() {
    district('separate_hamlets', '彼此分开的其他公社与村落', () => {
      const hamlets = [[-1.7, 0.55], [0.35, 1.04], [1.25, -1.13]];
      hamlets.forEach(([x, y], i) => {
        c.house(x - 0.32, y, 0.45, 0.28, (18 + i * 3) * heightScale);
        c.house(x + 0.34, y + 0.25, 0.43, 0.3, 16 * heightScale, 'dry');
        if (detailed) c.house(x, y - 0.45, 0.36, 0.27, 14 * heightScale);
        line([x, y - 0.05], [0, 0], 0.09, 0.7, 'pale');
      });
    }, { ownership: 'Several independent settlements, not an enlarged Rongdu commune.' });
    district('hamlet_field_remnants', '村落周围的耕地与失养边界', () => {
      fieldOutline(-1.65, -0.54, 1.25, 0.7, true);
      fieldOutline(0.37, 1.95, 1.15, 0.6);
      fieldOutline(1.47, -2.07, 1.1, 0.62, true);
    });
  }

  const handlers = {
    commune, waste: () => urban(true), fallen: () => urban(false),
    constitutional, refugees, receiving, communes,
  };
  handlers[c.place.id]();
  c.object.userData.civilRefinement = {
    version: 1, mode, geographicAnchorUnchanged: true,
    representation: 'functional graybox groups, not finished art or surveyed city plan',
    candidateBuildingHeightMultiplier: heightScale,
    mainRoadClearance: 'Source road segments retained; urban and commune building placement reserves their corridors.',
  };
  return true;
}
