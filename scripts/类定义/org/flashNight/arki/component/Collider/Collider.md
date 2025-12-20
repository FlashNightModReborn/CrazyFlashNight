# Collider 碰撞检测套件

## 运行测试

```actionscript
import org.flashNight.arki.component.Collider.TestColliderSuite;
TestColliderSuite.getInstance().runAllTests()
```

---

## 性能优化记录

### 优化前基准（2024-12-20）

| 碰撞器类型 | getAABB | checkCollision | 总时间 |
|-----------|---------|----------------|--------|
| AABBCollider | 12 ms | 19 ms | 31 ms |
| CoverageAABBCollider | 11 ms | 18 ms | 29 ms |
| PolygonCollider (rotated) | 17 ms | 143 ms | 160 ms |
| RayCollider (varied dirs) | 54 ms | 113 ms | 167 ms |

### P0-Ray 优化

#### 1. RayCollider.getAABB 复用缓存边界
- **问题**：每次调用都重新计算 `_ray.getEndpoint()` 和 `Math.min/max`
- **方案**：直接复用构造时已计算的 `this.left/right/top/bottom`
- **收益**：getAABB 从 54ms → ~12ms（-78%）

#### 2. Ray 类添加零分配方法
- 新增 `getEndpointX()`, `getEndpointY()` - 返回端点坐标而非 Vector
- 新增 `closestParamTo(px, py)` - 返回参数 t 而非 Vector
- 新增 `closestPointToX(px, py)`, `closestPointToY(px, py)` - 返回坐标分量

#### 3. RayCollider.checkCollision 内联优化
- 内联 getEndpoint、getCenter、closestPointTo 逻辑
- 使用纯数值计算替代 Vector 对象创建
- 消除所有运行时对象分配

### P0-Polygon 优化

#### 1. SAT 快速判定
- **策略**：先用分离轴定理检测 6 条轴（2 条 AABB 轴 + 4 条多边形边法线）
- **收益**：不碰撞情况立即返回，无需后续计算
- **复杂度**：O(1) 常数时间判定

#### 2. Sutherland-Hodgman 裁剪
- **问题**：旧方案使用 atan2 排序 + O(n²) 去重
- **方案**：用 AABB 的 4 条边依次裁剪多边形，直接生成有序顶点序列
- **收益**：
  - 彻底消除 `Math.atan2` 调用
  - 消除 O(n²) 去重循环
  - 输出已按顺序排列，无需排序

### P1 优化

#### 缓存多边形几何数据
- 缓存字段：`_cachedArea`（面积）、`_e1x/_e1y` ~ `_e4x/_e4y`（边向量）
- 懒更新：通过 `_geometryDirty` 标记，仅在顶点变化后重新计算
- 在 update 方法中自动标记 `_geometryDirty = true`

### P2 优化（2024-12-20）

#### 1. 拆分 clipByEdge 为 4 个专用函数
- **问题**：通用 `clipByEdge` 在循环内有 `axis/sign` 分支判断
- **方案**：拆分为 `clipXMin`, `clipXMax`, `clipYMin`, `clipYMax`
- **收益**：消除循环内分支，每个函数逻辑更简洁

#### 2. 添加退化保护
- **问题**：数值误差可能导致"点/线接触"被误判为碰撞
- **方案**：`intersectionArea < 0.0001` 时返回 `CollisionResult.FALSE`
- **收益**：避免 `PolygonCollider.result`（静态真对象）被错误返回

#### 3. Containment 快路径
- **快路径1**：`polyAABB ⊆ otherAABB` → `ratio = 1`，跳过裁剪
- **快路径2**：AABB 四角全在多边形内 → `ratio = area(AABB) / polyArea`
- **收益**：完全包含场景无需执行 Sutherland-Hodgman 裁剪

#### 4. 清理更新路径分配
- **RayCollider.updateFrom***：
  - 消除 `new Vector()` 分配
  - 内联端点计算 `ox + dx * maxDist`（消除 `getEndpointX/Y()` 方法调用）
  - 内联 min/max 比较
- **PolygonCollider.updateFromBullet**：
  - 使用实例缓存 `_pt` 进行坐标转换（消除 `{x:, y:}` 分配）
  - 消除 `atan2/cos/sin` 调用（`length * cos(atan2(vy,vx)) = vx`）

### Bug 修复记录

#### clipByEdge Y 轴裁剪参数顺序错误（2024-12-20）
- **问题**：Sutherland-Hodgman 裁剪 Y 轴边界时，`sign` 参数传了 0
  - `clipByEdge(..., top, 1, 0, 1)` ← sign=0 导致内侧判断失效
  - `clipByEdge(..., bottom, 1, 0, -1)` ← 同上
- **根因**：函数签名 `(inX, inY, inCount, outX, outY, edgeVal, axis, sign, dummy)` 中 `dummy` 参数位置混淆
- **修复**：
  - `clipByEdge(..., top, 1, 1, 0)` ← sign=1 保留 y >= top
  - `clipByEdge(..., bottom, 1, -1, 0)` ← sign=-1 保留 y <= bottom
- **教训**：将 `dummy` 重命名为 `unused` 以明确其用途

---

## 架构设计

### 职责分离原则

| 层级 | 职责 | 示例 |
|-----|------|-----|
| 外部层 | 空间分区、AABB 宽相剔除 | BulletCollisionHandler |
| 碰撞器层 | 精确检测（假设已通过宽相过滤） | PolygonCollider.checkCollision |

**重要**：AABB 早退检测应在外部调用层实现，而非碰撞器内部，避免冗余计算。

### 碰撞器类型

- `AABBCollider` - 轴对齐边界框，最快
- `CoverageAABBCollider` - 带覆盖率计算的 AABB
- `PolygonCollider` - 凸四边形，支持旋转
- `RayCollider` - 射线/线段碰撞

---

## 测试结果（优化前）

```
===== Starting TestColliderSuite =====
---- testAABBColliderCore ----
[PASS] AABBCollider getAABB left
[PASS] AABBCollider getAABB right
[PASS] AABBCollider getAABB top
[PASS] AABBCollider getAABB bottom
[PASS] AABBCollider checkCollision overlap
[PASS] AABBCollider checkCollision non-overlap
[PASS] AABBCollider checkCollision edge contact left
[PASS] AABBCollider checkCollision edge contact right
[PASS] AABBCollider checkCollision edge contact top
[PASS] AABBCollider checkCollision edge contact bottom
[PASS] AABBCollider checkCollision containment
[PASS] AABBCollider checkCollision contained
[PASS] AABBCollider checkCollision partial overlap top-left
[PASS] AABBCollider checkCollision partial overlap top-right
[PASS] AABBCollider checkCollision partial overlap bottom-left
[PASS] AABBCollider checkCollision partial overlap bottom-right
[PASS] AABBCollider checkCollision adjacent left
[PASS] AABBCollider checkCollision adjacent right
[PASS] AABBCollider checkCollision adjacent top
[PASS] AABBCollider checkCollision adjacent bottom
[PASS] AABBCollider checkCollision completely outside
[PASS] AABBCollider checkCollision multiple overlaps
---- testCoverageAABBColliderCore ----
[PASS] CoverageAABB getAABB left
[PASS] CoverageAABB getAABB right
[PASS] CoverageAABB getAABB top (zOffset)
[PASS] CoverageAABB getAABB bottom (zOffset)
[PASS] CoverageAABB collision should happen
[PASS] CoverageAABB overlapRatio ~ 0.25
[PASS] Collision should happen (overlap 0.01)
[PASS] Overlap ratio ~ 0.01
[PASS] Collision should happen (overlap 0.09)
[PASS] Overlap ratio ~ 0.09
[PASS] Collision should happen (overlap 0.25)
[PASS] Overlap ratio ~ 0.25
[PASS] Collision should happen (overlap 0.49)
[PASS] Overlap ratio ~ 0.49
[PASS] Collision should happen (overlap 0.81)
[PASS] Overlap ratio ~ 0.81
[PASS] Collision should happen (overlap 1.0)
[PASS] Overlap ratio ~ 1.0
[PASS] Collision should happen (edge touching)
[PASS] Collision should happen (overlap 0.16)
[PASS] Overlap ratio ~ 0.04
[PASS] Collision should happen (full containment)
[PASS] Overlap ratio ~ 0.25
[PASS] Collision should not happen (no overlap)
---- testPolygonColliderCore ----
[PASS] PolygonCollider getAABB left
[PASS] PolygonCollider getAABB right
[PASS] PolygonCollider getAABB top (zOffset)
[PASS] PolygonCollider getAABB bottom (zOffset)
[PASS] PolygonCollider vs AABBCollider should collide
[PASS] Polygon overlapRatio ~ 0.25
[PASS] PolygonCollider vs partially overlapping AABBCollider should collide
[PASS] Polygon partial overlapRatio ~ 0.06
[PASS] PolygonCollider vs far AABBCollider no collision
---- testPolygonColliderVariety ----
[PASS] PolygonCollider partial overlap #1 (should collide)
[PASS] Polygon partial overlap ratio #1 => ~0.18
[PASS] PolygonCollider no overlap #2 (should not collide)
[PASS] PolygonCollider fully covers AABB #3
[PASS] Polygon full coverage ratio #3 => ~0.06
[INFO] Seeded random polygon vs AABB => Colliding, ratio=0.61
---- testRayColliderCore ----
[PASS] RayCollider horizontal getAABB left
[PASS] RayCollider horizontal getAABB right
[PASS] RayCollider horizontal getAABB top
[PASS] RayCollider horizontal getAABB bottom
[PASS] RayCollider getAABB top with zOffset
[PASS] RayCollider getAABB bottom with zOffset
[PASS] RayCollider diagonal getAABB left = 0
[PASS] RayCollider diagonal getAABB top = 0
[PASS] RayCollider diagonal getAABB right ~ 70.71
[PASS] RayCollider diagonal getAABB bottom ~ 70.71
[PASS] RayCollider should collide with AABB in path
[PASS] RayCollider collision should have overlapCenter
[PASS] RayCollider overlapCenter.x should be within target AABB x range
[PASS] RayCollider should not collide with distant AABB
[PASS] RayCollider setRay updated left
[PASS] RayCollider setRay updated right
[PASS] RayCollider setRay updated top
[PASS] RayCollider setRay updated bottom
[PASS] RayCollider with origin inside AABB should collide
[PASS] RayCollider with endpoint inside AABB should collide
---- testRayColliderEdgeCases ----
[INFO] RayCollider edge touching bottom: true
[PASS] RayCollider just below AABB should not collide
[PASS] RayCollider just above AABB should not collide
[PASS] RayCollider through AABB corner should collide
[INFO] RayCollider endpoint at AABB edge: true
[PASS] RayCollider too short should not collide
[PASS] RayCollider through AABB should collide
[PASS] RayCollider should collide without zOffset
[PASS] RayCollider should not collide with large zOffset
---- testRayColliderDirections ----
[PASS] RayCollider from right should hit target
[PASS] RayCollider from left should hit target
[PASS] RayCollider from down should hit target
[PASS] RayCollider from up should hit target
[PASS] RayCollider from down-right should hit target
[PASS] RayCollider from down-left should hit target
[PASS] RayCollider from up-right should hit target
[PASS] RayCollider from up-left should hit target
[PASS] RayCollider away-right should miss target
[PASS] RayCollider away-left should miss target
[PASS] RayCollider away-down should miss target
[PASS] RayCollider away-up should miss target
---- testPointColliderCore ----
[PASS] PointCollider getAABB left
[PASS] PointCollider getAABB right
[PASS] PointCollider getAABB top
[PASS] PointCollider getAABB bottom
[PASS] PointCollider getAABB top with zOffset
[PASS] PointCollider getAABB bottom with zOffset
[PASS] PointCollider inside AABB should collide
[PASS] PointCollider collision center x
[PASS] PointCollider collision center y
[PASS] PointCollider outside AABB should not collide
[PASS] PointCollider on AABB edge should collide
[PASS] PointCollider on AABB corner should collide
[PASS] PointCollider setPosition updated left
[PASS] PointCollider setPosition updated right
[PASS] PointCollider setPosition updated top
[PASS] PointCollider setPosition updated bottom
[PASS] PointCollider after setPosition should not collide
[PASS] PointCollider with large zOffset should not collide
[PASS] PointCollider vs CoverageAABB inside should collide
[PASS] PointCollider vs PolygonCollider inside should collide
[PASS] PointCollider vs PolygonCollider outside should not collide
[PASS] PointCollider negative coord left
[PASS] PointCollider negative coord top
[PASS] PointColliderFactory created point left
[PASS] PointColliderFactory created point right
[PASS] PointColliderFactory created point should collide
---- testEdgeCases ----
[PASS] AABBCollider edge touching should NOT collide
[PASS] CoverageAABBCollider edge touching should NOT collide
[PASS] CoverageAABBCollider edge touching overlapRatio = 0
[PASS] PolygonCollider edge touching should NOT collide
[PASS] PolygonCollider edge touching overlapRatio = 0
[PASS] AABBCollider fully contains another AABBCollider
[PASS] AABBCollider full containment overlapRatio = 1
[PASS] CoverageAABBCollider fully contains another CoverageAABBCollider
[PASS] CoverageAABBCollider full containment overlapRatio ~ 0.25
[PASS] PolygonCollider fully contains another PolygonCollider
[PASS] PolygonCollider full containment overlapRatio ~ 0.25
[PASS] AABBCollider partially overlaps with CoverageAABBCollider
[PASS] AABBCollider partial overlap overlapRatio = 1
[PASS] PolygonCollider edge touching with CoverageAABBCollider should NOT collide
[PASS] PolygonCollider edge touching with CoverageAABBCollider overlapRatio = 0
---- testNumericalBoundaries ----
[PASS] Large coordinate AABB collision
[PASS] Negative coordinate AABB collision
[PASS] Cross-zero AABB collision
[PASS] Negative zOffset collision
[PASS] Tiny AABB exact overlap
[PASS] Float precision AABB collision
[PASS] Long ray should reach distant target
[PASS] Ray from negative origin should hit target
---- testDegenerateCases ----
[INFO] Zero-width AABB collision: true
[INFO] Zero-height AABB collision: true
[INFO] Point AABB collision: true
[PASS] Zero-length ray AABB left = origin.x
[PASS] Zero-length ray AABB right = origin.x
[PASS] Zero-length ray at AABB center should collide
[PASS] Zero-length ray outside AABB should not collide
[PASS] Identical AABBs should collide
[PASS] Identical CoverageAABBs should collide
[PASS] Identical CoverageAABBs overlapRatio = 1.0
[INFO] Same AABB with large zOffset collision: false
---- testCrossColliderInteraction ----
[PASS] AABB -> CoverageAABB collision
[PASS] CoverageAABB -> PolygonCollider collision
[PASS] PolygonCollider -> AABB no collision (out of range)
[PASS] RayCollider -> AABBCollider collision
[PASS] RayCollider -> AABBCollider no collision
[PASS] RayCollider -> CoverageAABBCollider collision
[PASS] RayCollider -> CoverageAABBCollider no collision (too short)
[PASS] RayCollider -> PolygonCollider collision
[PASS] RayCollider -> PolygonCollider no collision (y=0)
[PASS] Diagonal ray -> AABB collision
[PASS] Diagonal ray -> CoverageAABB collision
[PASS] Diagonal ray -> Polygon collision
---- testOrderedSeparation ----
[PASS] AABBCollider left of target should not collide
[PASS] AABBCollider left of target should return ORDERFALSE
[PASS] AABBCollider right of target should not collide
[PASS] AABBCollider right of target should return FALSE (isOrdered=true)
[PASS] AABBCollider edge touching should not collide
[PASS] AABBCollider edge touching should return ORDERFALSE
[PASS] CoverageAABB left of target should not collide
[PASS] CoverageAABB left of target should return ORDERFALSE
[PASS] CoverageAABB right of target should not collide
[PASS] CoverageAABB right of target should return FALSE (isOrdered=true)
[PASS] PolygonCollider left of target should not collide
[PASS] PolygonCollider left of target should return ORDERFALSE
[PASS] PolygonCollider right of target should not collide
[PASS] PolygonCollider right of target should return FALSE (isOrdered=true)
[PASS] PolygonCollider edge touching should not collide
[PASS] PolygonCollider edge touching should return ORDERFALSE
[PASS] RayCollider left of target should not collide
[PASS] RayCollider left of target should return ORDERFALSE
[PASS] RayCollider right of target should not collide
[PASS] RayCollider right of target should return FALSE (isOrdered=true)
[INFO] RayCollider edge touching (rayRight==otherLeft): isColliding=true
---- testOrderedSeparation (Y-axis) ----
[PASS] AABBCollider above target should not collide
[PASS] AABBCollider above target: isOrdered should be true
[PASS] AABBCollider above target should return YORDERFALSE
[PASS] AABBCollider below target should not collide
[PASS] AABBCollider below target: isOrdered should be true
[PASS] AABBCollider below target: isYOrdered should be true
[PASS] AABBCollider Y-edge touching should not collide
[PASS] AABBCollider Y-edge touching should return YORDERFALSE
[PASS] CoverageAABB above target should not collide
[PASS] CoverageAABB above target should return YORDERFALSE
[PASS] PolygonCollider above target should not collide
[PASS] PolygonCollider above target should return YORDERFALSE
[PASS] PolygonCollider below target should not collide
[PASS] PolygonCollider below target: isYOrdered should be true
[PASS] RayCollider above target should not collide
[PASS] RayCollider above target should return YORDERFALSE
[PASS] RayCollider below target should not collide
[PASS] RayCollider below target: isYOrdered should be true
---- testOrderedSeparation (PointCollider) ----
[PASS] PointCollider left of target should not collide
[PASS] PointCollider left of target should return ORDERFALSE
[PASS] PointCollider right of target should not collide
[PASS] PointCollider right of target should return FALSE (isOrdered=true)
[PASS] PointCollider on left edge should collide
[PASS] PointCollider just left of target should not collide
[PASS] PointCollider just left should return ORDERFALSE
[PASS] PointCollider above target should not collide
[PASS] PointCollider above target: isOrdered should be true
[PASS] PointCollider above target should return YORDERFALSE
[PASS] PointCollider below target should not collide
[PASS] PointCollider below target: isOrdered should be true
[PASS] PointCollider below target: isYOrdered should be true
[PASS] PointCollider on top edge should collide
---- testPolygonSATEdgeCases ----
[PASS] Axis-aligned polygon should collide with overlapping AABB
[PASS] Axis-aligned polygon overlap ratio ~ 0.25
[PASS] Axis-aligned polygon edge touching should NOT collide
[PASS] Edge touching polygon should return ORDERFALSE
[PASS] 45-degree rotated polygon should collide with center box
[PASS] 45-degree polygon should NOT collide with corner box
[PASS] Thin horizontal polygon should collide
[PASS] Thin vertical polygon should collide
[PASS] Thin polygon just outside AABB should NOT collide
[PASS] Precision edge contact should NOT collide
[PASS] Epsilon separated polygon should NOT collide
[INFO] Micro overlap polygon collision: true
[PASS] 30-degree rotated polygon should collide with center box
[PASS] 60-degree rotated polygon should collide with center box
---- testPolygonSATEdgeCases completed ----
---- testUpdateFunctions ----
[PASS] AABBCollider updateFromTransparentBullet left
[PASS] AABBCollider updateFromTransparentBullet right
[PASS] AABBCollider updateFromTransparentBullet top
[PASS] AABBCollider updateFromTransparentBullet bottom
[PASS] PointCollider updateFromTransparentBullet left
[PASS] PointCollider updateFromTransparentBullet right
[PASS] PointCollider updateFromTransparentBullet top
[PASS] PointCollider updateFromTransparentBullet bottom
[PASS] PolygonCollider updateFromTransparentBullet left
[PASS] PolygonCollider updateFromTransparentBullet right
[PASS] PolygonCollider updateFromTransparentBullet top
[PASS] PolygonCollider updateFromTransparentBullet bottom
[PASS] RayCollider setRay left
[PASS] RayCollider setRay right
[PASS] RayCollider setRay top
[PASS] RayCollider setRay bottom
[PASS] RayCollider setRayFast left
[PASS] RayCollider setRayFast right
[PASS] RayCollider setRayFast top
[PASS] RayCollider setRayFast bottom
---- testUpdateFunctions: PointCollider unit semantics ----
[PASS] PointCollider setPosition x (simulating registration point)
[PASS] PointCollider setPosition y (simulating registration point)
[PASS] PointCollider setPosition x (simulating area center)
[PASS] PointCollider setPosition y (simulating area center)
[PASS] PointCollider: registration point y (200) should differ from area center y (125)
[PASS] PointCollider updateFromUnitRegistrationPoint x (real MovieClip)
[PASS] PointCollider updateFromUnitRegistrationPoint y (real MovieClip)
  [SKIP] updateFromUnitArea real MovieClip test: _root.gameworld not available
---- testUpdateFunctions completed ----
---- testPerformance ----
使用固定种子: 12345 (可复现)
---- Testing AABBCollider ----
  getAABB:        11 ms (6000 calls)
  checkCollision: 19 ms (6000 calls)
  Total:          30 ms
---- Testing CoverageAABBCollider ----
  getAABB:        10 ms (6000 calls)
  checkCollision: 19 ms (6000 calls)
  Total:          29 ms
---- Testing PolygonCollider (rotated) ----
  getAABB:        18 ms (6000 calls)
  checkCollision: 36 ms (6000 calls)
  Total:          54 ms
---- Testing RayCollider (varied dirs) ----
  getAABB:        10 ms (6000 calls)
  checkCollision: 20 ms (6000 calls)
  Total:          30 ms
---- Testing PointCollider ----
  getAABB:        11 ms (6000 calls)
  checkCollision: 20 ms (6000 calls)
  Total:          31 ms
---- testUpdatePerformance ----
  --- updateFromTransparentBullet ---
    AABBCollider:         14 ms
    PointCollider:        14 ms
    PolygonCollider:      25 ms
    CoverageAABBCollider: 23 ms
    RayCollider:          21 ms
  --- updateFromBullet (simulating per-frame update) ---
    [baseline loop]:      4 ms (loop + % + array access)
    AABBCollider:         19 ms
    PointCollider:        23 ms
    PolygonCollider:      20 ms
    CoverageAABBCollider: 20 ms
    RayCollider:          40 ms
  --- updateFromUnitArea ---
    AABBCollider:         17 ms
    PointCollider:        34 ms
    PolygonCollider:      11 ms
    CoverageAABBCollider: 16 ms
    RayCollider:          46 ms
  --- RayCollider setRay/setRayFast ---
    setRay (Vector):      53 ms
    setRayFast (nums):    37 ms
  --- Performance Summary (10000 iterations) ---
  updateFromTransparentBullet (relative to AABB):
    AABB: 1.00x | Point: 1x | Poly: 1.79x | Cov: 1.64x | Ray: 1.5x
  updateFromBullet (loop overhead: 4ms, using 100 collider instances):
    (net time after subtracting loop overhead)
    AABB: 15ms (1.00x) | Point: 19ms (1.27x) | Poly: 16ms (1.07x)
    Cov: 16ms (1.07x) | Ray: 36ms (2.4x)
  updateFromUnitArea (relative to AABB):
    AABB: 1.00x | Point: 2x | Poly: 0.65x | Cov: 0.94x | Ray: 2.71x
  RayCollider setRay vs setRayFast:
    setRay: 53ms | setRayFast: 37ms | speedup: 1.43x
---- testUpdatePerformance completed ----
===== TestColliderSuite Completed =====


```
