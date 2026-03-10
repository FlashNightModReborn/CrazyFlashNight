# RayColliderTest

## 启动测试

### 1. TestLoader.as 内容

```actionscript
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
trace("=== RayColliderTest ===");
var tester = new RayColliderTest();
```

### 2. 编译运行

```bash
bash scripts/compile_test.sh
```

前提：Flash CS6 已启动，TestLoader XFL 工程已打开。

---

## 测试覆盖

| # | 测试 | 验证点 |
|---|------|--------|
| 1 | testConstructor | dir(3,4) maxDist=100 → AABB (0,60,0,80) |
| 2 | testConstructorNegativeDirection | dir(-1,0) origin(100,50) → AABB (20,100,50,50) |
| 3 | testSetRay | 重设 dir(0,1) → AABB 纵向更新 |
| 4 | testSetRayFast | 数值参数版本，归一化 + AABB |
| 5 | testGetAABB | zOffset=10 正确偏移 Y 轴 |
| 6 | testCheckCollision_Hit | Slab 命中，tEntry/entryXY 精度 |
| 7 | testCheckCollision_Miss | 目标远离射线范围 |
| 8 | testCheckCollision_OrderFalse | AABB 完全在目标左侧 → isOrdered=false |
| 9 | testCheckCollision_YOrderFalse | AABB 完全在目标上方 → isYOrdered=false |
| 10 | testCheckCollision_RayInsideAABB | 起点在 AABB 内 → tEntry=0 |
| 11 | testCheckCollision_ParallelRay | 水平射线 dy=0，invDy=1e10 |
| 12 | testCheckCollision_TEntry | 水平射线 tEntry=精确距离 |
| 13 | testCheckCollision_EdgeGraze | 边界恰好接触 → 视为分离 |
| 14 | testUpdateFromTransparentBullet | origin 更新 + AABB 重算 |
| 15 | testUpdateFromBullet | MovieClip mock + AABB 重算 |

---

## 基准日志

### 2026-03-10 优化前（baseline）

```
Results: 50 passed, 0 failed, 50 total

>>> Benchmark: checkCollision (hit path)
  500000 ops, 2847ms, 5694 ns/op
>>> Benchmark: checkCollision (ORDERFALSE path)
  500000 ops, 1507ms, 3014 ns/op
>>> Benchmark: setRayFast
  500000 ops, 1704ms, 3408 ns/op
>>> Benchmark: getAABB
  500000 ops, 792ms, 1584 ns/op
>>> Benchmark: updateFromTransparentBullet
  500000 ops, 1062ms, 2124 ns/op
```

### 2026-03-10 优化后（H01/H02 链式访问缓存 + H15 构造函数 Math.min/max 消除）

```
Results: 50 passed, 0 failed, 50 total

>>> Benchmark: checkCollision (hit path)
  500000 ops, 2669ms, 5338 ns/op
>>> Benchmark: checkCollision (ORDERFALSE path)
  500000 ops, 1499ms, 2998 ns/op
>>> Benchmark: setRayFast
  500000 ops, 1590ms, 3180 ns/op
>>> Benchmark: getAABB
  500000 ops, 792ms, 1584 ns/op
>>> Benchmark: updateFromTransparentBullet
  500000 ops, 935ms, 1870 ns/op
```

### 对比

| 方法 | 优化前 (ns/op) | 优化后 (ns/op) | 改善 |
|------|-------------|-------------|------|
| checkCollision (hit) | 5694 | 5338 | **-6.3%** |
| checkCollision (ORDERFALSE) | 3014 | 2998 | -0.5% |
| setRayFast | 3408 | 3180 | **-6.7%** |
| getAABB | 1584 | 1584 | 0% |
| updateFromTransparentBullet | 2124 | 1870 | **-12.0%** |

### 优化手段

1. **H01/H02** — `_ray.direction.x` 等 3 层链式访问缓存到局部变量 `var r = _ray; var dir = r.direction;`
2. **H15** — 构造函数中 `Math.min`/`Math.max` + `getEndpoint()` 替换为内联条件赋值
3. **CR 缓存取消** — `var CR = CollisionResult` 在 hit path 是纯损耗（broadphase return 全部跳过），移除后 hit path 省 ~98ns GetVariable
