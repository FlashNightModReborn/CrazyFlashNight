// PM19 二面体对称变换（纯函数模块：无 DOM 依赖，main.mjs 与 Node smoke 共用）
// 数学依据：19×19 完整质数幻方的轨道群包含全部 8 个二面体对称（轴反转 + 转置），
// 旋转 / 镜像当前棋盘仍在同一轨道内，结果恒为合法幻方（行 / 列 / 双对角和不变）。
//
// 与 renderer.mjs vertex shader 的逐帧契约（旋转中心 = size / 2，y 向下的 grid 空间）：
//   uSpin = +π/2  ↔ rot90：  new[r][c] = old[n-1-c][r]
//   uSpin =  π    ↔ rot180： new[r][c] = old[n-1-r][n-1-c]
//   uSpin = -π/2  ↔ rot270： new[r][c] = old[c][n-1-r]
//   uMirror = -1  ↔ mirrorH：new[r][c] = old[r][n-1-c]
// 动画把 uSpin / uMirror 缓动插值到目标值，结束瞬间换数据并归零，视觉无缝。

export const DIHEDRAL_KINDS = [
  { name: "rot90", spin: Math.PI / 2, mirror: 1, source: (row, column, n) => (n - 1 - column) * n + row },
  { name: "rot180", spin: Math.PI, mirror: 1, source: (row, column, n) => (n - 1 - row) * n + (n - 1 - column) },
  { name: "rot270", spin: -Math.PI / 2, mirror: 1, source: (row, column, n) => column * n + (n - 1 - row) },
  { name: "mirrorH", spin: 0, mirror: -1, source: (row, column, n) => row * n + (n - 1 - column) },
];

// 把 source 棋盘按 kind 变换写入 target（两缓冲不得重叠）。
// kind.source(row, column, n) 给出新位置 (row, column) 在旧棋盘中的扁平下标（行主序）。
export function transformBoardInto(source, target, size, kind) {
  for (let row = 0; row < size; row += 1) {
    for (let column = 0; column < size; column += 1) {
      target[row * size + column] = source[kind.source(row, column, size)];
    }
  }
  return target;
}
