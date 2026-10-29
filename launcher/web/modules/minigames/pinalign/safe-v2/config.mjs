/** Prototype & Lockbox V2 choices. All times are milliseconds. */
export const CONFIG = Object.freeze({
  version: '2026-10-29-safe-v2-visual-t1t2',
  password: Object.freeze({ min: 100, max: 999, digits: 3, pattern: '^[1-9][0-9]{2}$' }),
  timing: Object.freeze({ unlockMs: 950, demoMs: 12000 }),
  interaction: Object.freeze({
    completionThreshold: 0.94,
    detentSnapStart: 0.88,
    jammedMaxProgress: 0.12,
    stopperNudgeProgress: -0.045,
    dragPixels: 52,
    hitRadiusPixels: 38,
    hitGapPixels: 8,
    arcTolerancePixels: 28,
  }),
  operationView: Object.freeze({ direction: Object.freeze([-.15, .12, 1]), width: 1.16, height: 1.09, padding: 1.16, fov: 36 }),
  openingView: Object.freeze({ referenceAspect: 1.6, fittedFovDegrees: 31.91305, marginDegrees: .8 }),
  provisional: Object.freeze([
    '密码为 100–999 三位整数；备忘采用单步视觉图推（瑞文查章 / 六印排异 / 转格掩模），一次视觉推导直出三位密码。',
    '每只箱串联结构Ⅰ（卸载）与结构Ⅱ（牵引）两结构，每结构三形制 × 正反双极性止挡销，共 36 种物理组合。',
    '结构表面去除剧透白字箭头，改由黄铜止挡销（限位端）与导槽敞口（行程端）交代真实物理方向。',
    '未卸荷强拉结构Ⅱ会产生 ~12% 物理受阻微位移，使联锁挡肩真实撞击黄铜联锁下舌并触发金属震颤回弹。',
    '有效短拖达 88% 进入止点啮合吸附区，越过 94% 咔哒锁入止点，并触发联锁脱扣微颤反馈。',
    '密码与工具的正常收尾均为 950 毫秒；慢速演示独立，非每次强制播放。',
    '熟练 3–5 秒、新手 30–60 秒为体验目标，没有倒计时失败或工具耐久损耗。',
  ]),
});

export const POLARITIES = Object.freeze([1, -1]);

export const TOOLS = Object.freeze([
  Object.freeze({ id: 'wedge', name: '卸载键', short: '卸载', description: '宽平头嵌入结构Ⅰ的开放检修座，避开黄铜止挡销推动卸载件越过止点。' }),
  Object.freeze({ id: 'hook', name: '牵引钩', short: '牵引', description: '钩头挂入结构Ⅱ的大牵引眼，顺导槽敞口方向牵引竖直小锁舌。' }),
]);

export const STRUCTURES = Object.freeze({
  a: Object.freeze([
    Object.freeze({
      id: 'A0', stage: 'a', index: 0, title: '横向卸载楔',
      feature: '水平双导轨与三角斜楔；一端设黄铜止挡销，另一端为敞口导槽。',
      point: '楔块靠近止挡销侧的宽矩形作用座。',
      action: '卸载键背离黄铜止挡销水平短推（正置向右 / 反置向左），越过止点松手。',
      direction: 'right', reverseDirection: 'left', tool: 'wedge', manualPage: 0,
      reversePoint: '楔块右侧（靠近右止挡销）的宽矩形作用座。',
      reverseAction: '卸载键背离右侧止挡销向左短推，到止点松手。',
      result: '楔块沿导轨横移，斜面顶起黄铜承压联锁舌并卡入止点；结构Ⅱ解除阻挡。',
      error: '钩头无法贴合宽槽；朝黄铜止挡销一侧反向推动会直接撞击限位销。',
      recovery: '换卸载键并朝导槽敞口方向重试；未过止点松手会回弹复位。',
      next: '保持卸载状态，可继续操作结构Ⅱ牵引件。',
    }),
    Object.freeze({
      id: 'A1', stage: 'a', index: 1, title: '竖向卸载楔',
      feature: '竖直双导轨与纵向斜楔；止挡销位于起始端，另一端为竖直行程槽。',
      point: '楔块靠近止挡销端的宽矩形作用座。',
      action: '卸载键背离黄铜止挡销竖直短推（正置向上 / 反置向下），到止点松手。',
      direction: 'up', reverseDirection: 'down', tool: 'wedge', manualPage: 1,
      reversePoint: '楔块上端（靠近顶部止挡销）的宽矩形作用座。',
      reverseAction: '卸载键背离顶部止挡销向下短压，到止点松手。',
      result: '竖楔沿导轨位移，斜面顶起承压联锁舌，到达止点后咔哒锁定。',
      error: '钩头不能传递稳定推力；朝黄铜止挡销方向施力会被限位块顶死。',
      recovery: '换卸载键并朝导槽敞口方向重试；已完成的前级状态不会丢失。',
      next: '保持卸载状态，可继续操作结构Ⅱ牵引件。',
    }),
    Object.freeze({
      id: 'A2', stage: 'a', index: 2, title: '偏心卸载凸轮',
      feature: '偏心圆盘顶住联锁滚头；圆盘外缘一侧设黄铜止挡销。',
      point: '偏心盘外缘顶部的宽矩形作用座。',
      action: '卸载键背离黄铜止挡销沿短弧拨转（正置顺时针 / 反置逆时针）至止点。',
      direction: 'clockwise', reverseDirection: 'counterclockwise', tool: 'wedge', manualPage: 2,
      reversePoint: '偏心盘外缘宽矩形座（右侧设黄铜止挡销）。',
      reverseAction: '卸载键背离右侧止挡销沿逆时针短弧拨至止点。',
      result: '偏心凸轮旋至卸载止点，凸缘顶起承压联锁舌并自锁保持。',
      error: '钩头挂不住宽座；朝黄铜止挡销一侧逆向拨转会撞击限位销。',
      recovery: '换卸载键，向无止挡销的弧槽侧短拨重试；无需连续绕圈。',
      next: '保持卸载状态，可继续操作结构Ⅱ牵引件。',
    }),
  ]),
  b: Object.freeze([
    Object.freeze({
      id: 'B0', stage: 'b', index: 0, title: '直拉滑闩',
      feature: '水平直杆穿双导套，杆端设大圆眼；圆眼一侧立有黄铜止挡销。',
      point: '直杆端部的大牵引圆眼。',
      action: '先卸荷；牵引钩挂圆眼背离黄铜止挡销水平短拉（正置向左 / 反置向右）。',
      direction: 'left', reverseDirection: 'right', tool: 'hook', manualPage: 3,
      reversePoint: '直杆端部的大圆眼（左侧立有黄铜止挡销）。',
      reverseAction: '先卸荷；牵引钩挂圆眼背离左侧止挡销向右短拉。',
      result: '直杆带动共用输出滑架，经钢索与导轮牵引竖直小锁舌完全让位。',
      error: '结构Ⅰ未完成时拉动约 12% 即会撞击黄铜承压联锁舌；卸载键无法挂住圆眼。',
      recovery: '先完成结构Ⅰ卸载，再用牵引钩朝导槽敞口方向短拉。',
      next: '触发统一开启流程，把手收回粗门闩、箱门外开。',
    }),
    Object.freeze({
      id: 'B1', stage: 'b', index: 1, title: '折臂牵引杠杆',
      feature: 'L 形折臂配右侧固定支点与左端圆眼；折臂一侧设黄铜止挡销。',
      point: '左侧长臂末端的大牵引圆眼。',
      action: '先卸荷；牵引钩挂圆眼背离止挡销扳动（正置向下 / 反置向上）。',
      direction: 'down', reverseDirection: 'up', tool: 'hook', manualPage: 4,
      reversePoint: '左侧长臂末端的大圆眼（下方设黄铜止挡销）。',
      reverseAction: '先卸荷；牵引钩挂左圆眼背离下方止挡销向上提拉。',
      result: '折臂绕支点摆动，后曲柄经槽形连杆驱动输出滑架，牵引竖直小锁舌。',
      error: '未卸载时折臂仅微动即被联锁下舌卡死；朝止挡销方向扳动受阻。',
      recovery: '先完成结构Ⅰ卸载，换牵引钩朝无止挡销方向扳动；卸载止点保持。',
      next: '触发统一开启流程，把手收回粗门闩、箱门外开。',
    }),
    Object.freeze({
      id: 'B2', stage: 'b', index: 2, title: '转盘牵引闩',
      feature: '三叶转盘配偏心圆眼与后曲柄；圆眼旁一侧设黄铜止挡销。',
      point: '三叶盘外缘的大牵引圆眼。',
      action: '先卸荷；牵引钩挂圆眼背离止挡销沿短弧钩转（正置逆时针 / 反置顺时针）。',
      direction: 'counterclockwise', reverseDirection: 'clockwise', tool: 'hook', manualPage: 5,
      reversePoint: '三叶盘外缘的大圆眼（左侧设黄铜止挡销）。',
      reverseAction: '先卸荷；牵引钩挂圆眼背离左侧止挡销沿顺时针短弧钩转。',
      result: '三叶盘旋转，后曲柄驱动共用输出滑架，经钢索牵引竖直小锁舌至止点。',
      error: '结构Ⅰ未完成时转盘仅微转即撞上联锁舌；朝止挡销方向钩转被挡死。',
      recovery: '先完成结构Ⅰ卸载，向无止挡销一侧短弧钩转；无需累计圈数。',
      next: '触发统一开启流程，把手收回粗门闩、箱门外开。',
    }),
  ]),
});

export function resolveStructureSpec(stage, index, dir = 1) {
  const list = STRUCTURES[stage];
  if (!list || !list[index]) throw new RangeError(`Unknown structure ${stage}${index}`);
  const base = list[index];
  const polarity = dir === -1 ? -1 : 1;
  if (polarity === 1) {
    return Object.freeze({
      ...base,
      dir: 1,
      polarityLabel: '正向极性 (+)',
    });
  }
  return Object.freeze({
    ...base,
    dir: -1,
    direction: base.reverseDirection,
    point: base.reversePoint || base.point,
    action: base.reverseAction || base.action,
    polarityLabel: '反向极性 (-)',
  });
}

export const PUZZLE_TYPES = Object.freeze([
  Object.freeze({
    id: 'matrix', title: '瑞文查章', manualPage: 6,
    recognition: '2×2 四格防伪章递推，下方附四枚带三位钢印号的候选章。',
    help: '观察第一行左章到右章的指针旋向变化（顺转90°或对向翻转180°），对第二行左章做同样变换即可唯一定出“？”处的目标章；在下方四枚对照章中找出该章，直接抄录其三位钢印号。',
  }),
  Object.freeze({
    id: 'odd', title: '六印排异', manualPage: 7,
    recognition: '六枚质检钢印（①–⑥）并列排布，其中五枚同制、唯一一枚异制。',
    help: '对比六枚印章的几何不变量（外环全闭合或带缺口、内芯双对称铆钉或单偏心铆钉、内标正立或倒置）。五枚正常章共享同一规制，唯一一枚破规章下方的三位数字即为本箱密码。',
  }),
  Object.freeze({
    id: 'grille', title: '转格掩模', manualPage: 8,
    recognition: '左为带顶部红缺口（▲）的 3×3 数字底盘，右为标有 ①②③ 的三孔漏格掩模。',
    help: '将右侧三孔掩模的定位缺口与左侧 3×3 底盘的顶部红缺口对齐（缺口同向直接套合，缺口在底边则旋转 180° 对齐），按 ①百位 → ②十位 → ③个位 顺序直读三孔位置上的三个数字。',
  }),
]);
