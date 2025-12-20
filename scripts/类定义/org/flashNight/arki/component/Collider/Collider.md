import org.flashNight.arki.component.Collider.TestColliderSuite;
TestColliderSuite.getInstance().runAllTests()



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
---- testPerformance ----
使用固定种子: 12345 (可复现)
---- Testing AABBCollider ----
  getAABB:        11 ms (6000 calls)
  checkCollision: 19 ms (6000 calls)
  Total:          30 ms
---- Testing CoverageAABBCollider ----
  getAABB:        11 ms (6000 calls)
  checkCollision: 18 ms (6000 calls)
  Total:          29 ms
---- Testing PolygonCollider (rotated) ----
  getAABB:        18 ms (6000 calls)
  checkCollision: 149 ms (6000 calls)
  Total:          167 ms
---- Testing RayCollider (varied dirs) ----
  getAABB:        57 ms (6000 calls)
  checkCollision: 116 ms (6000 calls)
  Total:          173 ms
===== TestColliderSuite Completed =====
