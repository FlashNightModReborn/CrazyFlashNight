/**
 * 武器求解器 — 逆问题：给定固定输入，求解 bulletPower 使 averageDPS 命中目标。
 *
 * 替代原版"人肉试错凑平衡"。averageDPS 随 power 单调增、balanceDPS 弱依赖 power，
 * 故 (averageDPS - 目标) 单调 → 二分稳解。覆盖最常见的"固定其余、解单发威力"场景。
 */
import { computeWeaponRow } from "./weapons.js";
import type { WeaponInput, WeaponOutput } from "./weapons.js";

export interface WeaponSolveResult {
  solvedPower: number;
  output: WeaponOutput;
  target: number;
  averageDPS: number;
  balanceDPS: number;
  converged: boolean;
}

/**
 * @param fixed   除 bulletPower 外的全部输入（bulletPower 给了也会被覆盖）。
 * @param target  目标 averageDPS；省略时取 balanceDPS（自洽平衡，每轮重算）。
 */
export function solveWeaponPower(
  fixed: Omit<WeaponInput, "bulletPower"> & { bulletPower?: number },
  target?: number,
  opts?: { lo?: number; hi?: number; iterations?: number }
): WeaponSolveResult {
  let lo = opts?.lo ?? 0;
  let hi = opts?.hi ?? 1e7;
  const iters = opts?.iterations ?? 64;

  for (let i = 0; i < iters; i++) {
    const mid = (lo + hi) / 2;
    const r = computeWeaponRow({ ...fixed, bulletPower: mid });
    const tgt = target ?? r.balanceDPS;
    if (r.averageDPS > tgt) hi = mid;
    else lo = mid;
  }

  const solvedPower = (lo + hi) / 2;
  const output = computeWeaponRow({ ...fixed, bulletPower: solvedPower });
  const finalTarget = target ?? output.balanceDPS;
  const converged =
    Math.abs(output.averageDPS - finalTarget) / (Math.abs(finalTarget) + 1e-9) < 0.01;

  return {
    solvedPower,
    output,
    target: finalTarget,
    averageDPS: output.averageDPS,
    balanceDPS: output.balanceDPS,
    converged,
  };
}
