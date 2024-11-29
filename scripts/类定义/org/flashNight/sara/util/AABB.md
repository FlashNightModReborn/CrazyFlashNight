# AABB（轴对齐边界框）类详细说明

## 目录

- [简介](#简介)
- [数学背景与概念](#数学背景与概念)
  - [什么是AABB？](#什么是aabb)
  - [AABB的用途](#aabb的用途)
- [类概述](#类概述)
- [属性与方法详解](#属性与方法详解)
  - [构造函数](#构造函数)
  - [克隆方法](#克隆方法)
  - [边界访问](#边界访问)
  - [尺寸和中心点计算](#尺寸和中心点计算)
  - [数据访问方法](#数据访问方法)
  - [碰撞检测方法](#碰撞检测方法)
    - [最小平移向量（MTV）计算](#最小平移向量mtv计算)
    - [点包含检测](#点包含检测)
    - [最近点计算](#最近点计算)
    - [线段相交检测](#线段相交检测)
    - [圆形相交检测](#圆形相交检测)
    - [射线相交检测](#射线相交检测)
    - [AABB相交检测](#aabb相交检测)
  - [合并与细分方法](#合并与细分方法)
    - [AABB合并](#aabb合并)
    - [批量合并](#批量合并)
    - [AABB细分](#aabb细分)
  - [其他实用方法](#其他实用方法)
    - [面积计算](#面积计算)
    - [从MovieClip创建AABB](#从movieclip创建aabb)
    - [绘制AABB](#绘制aabb)
    - [获取顶点与点集](#获取顶点与点集)
- [使用示例](#使用示例)
  - [示例1：创建和基本操作](#示例1创建和基本操作)
  - [示例2：碰撞检测](#示例2碰撞检测)
  - [示例3：最小平移向量应用](#示例3最小平移向量应用)
  - [示例4：合并和细分](#示例4合并和细分)
- [注意事项](#注意事项)
- [适合新手的提示](#适合新手的提示)
- [结语](#结语)

## 简介

本说明详细介绍了`AABB`（轴对齐边界框）类的实现和使用方法。通过深入的数学背景解释和丰富的使用示例，帮助您理解并应用该类于游戏开发中的碰撞检测、空间划分等功能，即使您是缺乏数学背景的新手程序员，也能轻松上手。

## 数学背景与概念

### 什么是AABB？

AABB（Axis-Aligned Bounding Box）即轴对齐边界框，是在二维或三维空间中，与坐标轴对齐的矩形或立方体。由于其边界与坐标轴平行，计算和判断变得非常简单高效。

### AABB的用途

- **碰撞检测**：用于快速判断两个物体是否可能发生碰撞。
- **空间划分**：用于划分空间，建立四叉树、八叉树等数据结构，优化查询性能。
- **视锥裁剪**：在渲染时确定哪些物体需要被绘制。

## 类概述

`AABB`类用于表示二维空间中的轴对齐矩形区域。它提供了创建、操作和查询AABB的各种方法，包括碰撞检测、合并、细分等。

## 属性与方法详解

### 构造函数

```actionscript
public function AABB(left:Number, right:Number, top:Number, bottom:Number)
```

**描述**：创建一个新的`AABB`实例，指定左、右、上、下边界。

**参数**：

- `left`：左边界（最小x值）
- `right`：右边界（最大x值）
- `top`：上边界（最小y值）
- `bottom`：下边界（最大y值）

**注意**：必须满足`left <= right`和`top <= bottom`，否则可能导致逻辑错误。

### 克隆方法

```actionscript
public function clone():AABB
```

**描述**：创建当前`AABB`的副本。

**返回值**：新的`AABB`实例，具有相同的边界。

### 边界访问

由于`left`、`right`、`top`和`bottom`属性是公开的，您可以直接访问和修改这些属性，无需通过访问器方法。

#### 获取边界

```actionscript
var left:Number = aabb.left;
var right:Number = aabb.right;
var top:Number = aabb.top;
var bottom:Number = aabb.bottom;
```

#### 设置边界

```actionscript
aabb.left = newLeft;
aabb.right = newRight;
aabb.top = newTop;
aabb.bottom = newBottom;
```

**注意**：

- 设置`left`时，`newLeft`必须小于等于当前的`right`。
- 设置`right`时，`newRight`必须大于等于当前的`left`。
- 设置`top`时，`newTop`必须小于等于当前的`bottom`。
- 设置`bottom`时，`newBottom`必须大于等于当前的`top`。
- 否则会导致逻辑错误。

### 尺寸和中心点计算

#### 获取宽度和高度

```actionscript
public function getWidth():Number
public function getLength():Number
```

- `getWidth()`：计算并返回`AABB`的宽度，即`right - left`。
- `getLength()`：计算并返回`AABB`的高度，即`bottom - top`。

#### 获取中心点

```actionscript
public function getCenter():Vector
```

**描述**：计算并返回`AABB`的中心点坐标。

**返回值**：

- `Vector`：包含`x`和`y`属性，分别表示中心点的横坐标和纵坐标。

### 数据访问方法

#### 获取顶点

```actionscript
public function getVertices():Array
```

**描述**：返回`AABB`的四个顶点，按左上、右上、右下、左下顺序。

**返回值**：

- `Array`：包含四个`Vector`实例，分别代表四个顶点。

#### 将AABB转换为PointSet

```actionscript
public function toPointSet():PointSet
```

**描述**：将`AABB`的四个顶点添加到`PointSet`中，便于后续的点集操作。

**返回值**：

- `PointSet`：包含四个顶点的`PointSet`实例。

### 碰撞检测方法

#### 最小平移向量（MTV）计算

##### 获取MTV（返回对象）

```actionscript
public function getMTV(other:AABB):Object
```

**描述**：计算当前`AABB`与另一个`AABB`之间的最小平移向量，用于解决碰撞。

**数学背景**：

- **重叠量计算**：在x轴和y轴上分别计算两个AABB的重叠量。
- **最小平移向量**：选择重叠量较小的轴作为移动方向，移动的距离为该轴上的重叠量。

**参数**：

- `other`：另一个`AABB`实例。

**返回值**：

- `{dx: Number, dy: Number}`：需要移动的最小距离。
- 如果没有重叠，返回`null`。

**示例**：

```actionscript
var mtv:Object = aabb1.getMTV(aabb2);
if (mtv != null) {
    // 发生碰撞，调整位置
    object.x += mtv.dx;
    object.y += mtv.dy;
}
```

##### 获取MTV（返回Vector）

```actionscript
public function getMTVV(other:AABB):Vector
```

**描述**：计算当前`AABB`与另一个`AABB`之间的最小平移向量，并以`Vector`实例返回，增强了接口的一致性。

**参数**：

- `other`：另一个`AABB`实例。

**返回值**：

- `Vector`：表示最小平移向量的`Vector`实例。
- 如果没有重叠，返回`null`。

**示例**：

```actionscript
var mtvVector:Vector = aabb1.getMTVV(aabb2);
if (mtvVector != null) {
    // 发生碰撞，调整位置
    object.x += mtvVector.x;
    object.y += mtvVector.y;
}
```

#### 点包含检测

```actionscript
public function containsPoint(x:Number, y:Number):Boolean
public function containsPointV(point:Vector):Boolean
```

**描述**：检查给定的点是否在`AABB`内或边界上。

**参数**：

- `x`、`y`：点的坐标（`containsPoint`）。
- `point`：包含点的`Vector`实例（`containsPointV`）。

**返回值**：

- `true`：点在`AABB`内或边界上。
- `false`：点在`AABB`外。

**示例**：

```actionscript
var pointX:Number = 75;
var pointY:Number = 75;
if (aabb1.containsPoint(pointX, pointY)) {
    trace("Point is inside aabb1.");
} else {
    trace("Point is outside aabb1.");
}

// 使用 Vector 参数
var point:Vector = new Vector(75, 75);
if (aabb1.containsPointV(point)) {
    trace("Point is inside aabb1.");
} else {
    trace("Point is outside aabb1.");
}
```

#### 最近点计算

```actionscript
public function closestPoint(x:Number, y:Number):Vector
public function closestPointV(point:Vector):Vector
```

**描述**：计算`AABB`内离给定点最近的点。

**数学背景**：

- 对于给定点，在每个轴上，如果点在AABB内，则该轴的坐标不变；如果在外，则取AABB在该轴上的最近边界值。

**参数**：

- `x`、`y`：给定点的坐标（`closestPoint`）。
- `point`：包含点的`Vector`实例（`closestPointV`）。

**返回值**：

- `Vector`：表示最近点坐标的`Vector`实例。

**示例**：

```actionscript
var closest:Vector = aabb1.closestPoint(150, 75);
trace("Closest Point: (" + closest.x + ", " + closest.y + ")");

// 使用 Vector 参数
var queryPoint:Vector = new Vector(150, 75);
var closestV:Vector = aabb1.closestPointV(queryPoint);
trace("Closest Point: (" + closestV.x + ", " + closestV.y + ")");
```

#### 线段相交检测

```actionscript
public function intersectsLine(x1:Number, y1:Number, x2:Number, y2:Number):Boolean
public function intersectsLineV(start:Vector, end:Vector):Boolean
```

**描述**：检查线段是否与`AABB`相交。

**数学背景**：

- 使用**梁-巴克斯基（Liang-Barsky）算法**，根据参数化的线段方程和AABB的边界，计算参数`t`的范围，判断是否存在相交。

**参数**：

- `x1`、`y1`、`x2`、`y2`：线段的起点和终点坐标（`intersectsLine`）。
- `start`、`end`：包含线段起点和终点的`Vector`实例（`intersectsLineV`）。

**返回值**：

- `true`：线段与`AABB`相交。
- `false`：线段与`AABB`不相交。

**示例**：

```actionscript
// 使用数值参数
if (aabb1.intersectsLine(50, 50, 150, 150)) {
    trace("Line intersects with aabb1.");
} else {
    trace("Line does not intersect with aabb1.");
}

// 使用 Vector 参数
var startPoint:Vector = new Vector(50, 50);
var endPoint:Vector = new Vector(150, 150);
if (aabb1.intersectsLineV(startPoint, endPoint)) {
    trace("Line intersects with aabb1.");
} else {
    trace("Line does not intersect with aabb1.");
}
```

#### 圆形相交检测

```actionscript
public function intersectsCircle(circleX:Number, circleY:Number, radius:Number):Boolean
public function intersectsCircleV(circleCenter:Vector, radius:Number):Boolean
```

**描述**：检查圆形是否与`AABB`相交。

**数学背景**：

- 找到AABB中离圆心最近的点，计算该点与圆心的距离，判断是否小于等于圆的半径。

**参数**：

- `circleX`、`circleY`、`radius`：圆心坐标和半径（`intersectsCircle`）。
- `circleCenter`、`radius`：包含圆心的`Vector`实例和半径（`intersectsCircleV`）。

**返回值**：

- `true`：圆形与`AABB`相交。
- `false`：圆形与`AABB`不相交。

**示例**：

```actionscript
// 使用数值参数
if (aabb1.intersectsCircle(75, 75, 30)) {
    trace("Circle intersects with aabb1.");
} else {
    trace("Circle does not intersect with aabb1.");
}

// 使用 Vector 参数
var circleCenter:Vector = new Vector(75, 75);
if (aabb1.intersectsCircleV(circleCenter, 30)) {
    trace("Circle intersects with aabb1.");
} else {
    trace("Circle does not intersect with aabb1.");
}
```

#### 射线相交检测

```actionscript
public function intersectsRay(rayOriginX:Number, rayOriginY:Number, rayDirX:Number, rayDirY:Number):Boolean
public function intersectsRayV(rayOrigin:Vector, rayDir:Vector):Boolean
```

**描述**：检查射线是否与`AABB`相交。

**数学背景**：

- 使用**射线与AABB的参数化方程**，计算射线在x轴和y轴上的进入和退出参数`t`，判断射线是否在AABB范围内。

**参数**：

- `rayOriginX`、`rayOriginY`、`rayDirX`、`rayDirY`：射线起点和方向的坐标（`intersectsRay`）。
- `rayOrigin`、`rayDir`：包含射线起点和方向的`Vector`实例（`intersectsRayV`）。

**返回值**：

- `true`：射线与`AABB`相交。
- `false`：射线与`AABB`不相交。

**示例**：

```actionscript
// 使用数值参数
if (aabb1.intersectsRay(50, 50, 1, 1)) {
    trace("Ray intersects with aabb1.");
} else {
    trace("Ray does not intersect with aabb1.");
}

// 使用 Vector 参数
var rayOrigin:Vector = new Vector(50, 50);
var rayDir:Vector = new Vector(1, 1);
if (aabb1.intersectsRayV(rayOrigin, rayDir)) {
    trace("Ray intersects with aabb1.");
} else {
    trace("Ray does not intersect with aabb1.");
}
```

#### AABB相交检测

```actionscript
public function intersects(other:AABB):Boolean
```

**描述**：检查当前`AABB`是否与另一个`AABB`相交。

**数学背景**：

- 判断两个AABB在x轴和y轴上是否存在重叠。

**参数**：

- `other`：另一个`AABB`实例。

**返回值**：

- `true`：两个`AABB`相交。
- `false`：两个`AABB`不相交。

**示例**：

```actionscript
var aabb1:AABB = new AABB(0, 100, 0, 100);
var aabb2:AABB = new AABB(50, 150, 50, 150);

if (aabb1.intersects(aabb2)) {
    trace("AABBs are intersecting.");
} else {
    trace("AABBs are not intersecting.");
}
```

### 合并与细分方法

#### AABB合并

```actionscript
public function merge(other:AABB):AABB
public function mergeWith(other:AABB):Void
```

**描述**：

- `merge`：将当前`AABB`与另一个`AABB`合并，返回一个新的`AABB`，边界包含两个AABB的所有区域。
- `mergeWith`：直接修改当前`AABB`的边界，使其包含另一个`AABB`。

**参数**：

- `other`：另一个`AABB`实例。

**返回值**：

- `merge`：新的合并后的`AABB`实例。
- `mergeWith`：无返回值，直接修改当前实例。

**示例**：

```actionscript
// 使用 merge 方法
var mergedAABB:AABB = aabb1.merge(aabb2);
trace("Merged AABB - Left: " + mergedAABB.left + ", Right: " + mergedAABB.right);
trace("Merged AABB - Top: " + mergedAABB.top + ", Bottom: " + mergedAABB.bottom);

// 使用 mergeWith 方法
aabb1.mergeWith(aabb2);
trace("AABB1 after mergeWith - Left: " + aabb1.left + ", Right: " + aabb1.right);
trace("AABB1 after mergeWith - Top: " + aabb1.top + ", Bottom: " + aabb1.bottom);
```

#### 批量合并

```actionscript
public static function mergeBatch(aabbs:Array):AABB
```

**描述**：合并一组`AABB`，返回一个包含所有AABB的最小边界的新`AABB`实例。

**参数**：

- `aabbs`：包含`AABB`实例的数组。

**注意**：

- 数组不能为空，否则会抛出错误。

**返回值**：

- 合并后的`AABB`实例。

**示例**：

```actionscript
var aabb1:AABB = new AABB(0, 50, 0, 50);
var aabb2:AABB = new AABB(40, 100, 40, 100);
var aabb3:AABB = new AABB(-10, 60, -10, 60);
var mergedAABB:AABB = AABB.mergeBatch([aabb1, aabb2, aabb3]);

trace("Merged AABB - Left: " + mergedAABB.left + ", Right: " + mergedAABB.right);
trace("Merged AABB - Top: " + mergedAABB.top + ", Bottom: " + mergedAABB.bottom);
```

#### AABB细分

```actionscript
public function subdivide():Array
```

**描述**：将当前`AABB`细分为四个更小的`AABB`，用于空间划分。

**返回值**：

- 包含四个`AABB`实例的数组，分别对应于：
  - `quad1`：右上区域
  - `quad2`：左上区域
  - `quad3`：左下区域
  - `quad4`：右下区域

**示例**：

```actionscript
var aabb:AABB = new AABB(0, 100, 0, 100);
var quads:Array = aabb.subdivide();
for (var i:Number = 0; i < quads.length; i++) {
    trace("Quad " + (i+1) + ": Left=" + quads[i].left + ", Right=" + quads[i].right +
          ", Top=" + quads[i].top + ", Bottom=" + quads[i].bottom);
}
```

### 其他实用方法

#### 面积计算

```actionscript
public function getArea():Number
```

**描述**：计算并返回`AABB`的面积。

**返回值**：

- 面积值，计算方式为`(right - left) * (bottom - top)`。

**示例**：

```actionscript
var aabb:AABB = new AABB(0, 100, 0, 50);
trace("Area: " + aabb.getArea()); // 输出：Area: 5000
```

#### 从MovieClip创建AABB

```actionscript
public static function fromMovieClip(area:MovieClip, z_offset:Number):AABB
```

**描述**：根据`MovieClip`在游戏世界中的位置和z轴偏移量创建`AABB`。

**参数**：

- `area`：`MovieClip`实例。
- `z_offset`：z轴偏移量，用于调整y坐标。

**返回值**：

- 新的`AABB`实例。

**示例**：

```actionscript
var movieClip:MovieClip = _root.createEmptyMovieClip("testMC", 1);
// 假设movieClip已经被绘制
var aabbFromClip:AABB = AABB.fromMovieClip(movieClip, 0);
trace("AABB from MovieClip - Left: " + aabbFromClip.left + ", Right: " + aabbFromClip.right);
```

#### 从Bullet创建AABB

```actionscript
public static function fromBullet(bullet:MovieClip):AABB
```

**描述**：从一个`Bullet` `MovieClip`实例创建`AABB`。

**参数**：

- `bullet`：`Bullet` `MovieClip`实例。

**返回值**：

- 新的`AABB`实例。

**示例**：

```actionscript
var bullet:MovieClip = _root.createEmptyMovieClip("bulletMC", 2);
// 假设bullet已经被绘制
var aabbFromBullet:AABB = AABB.fromBullet(bullet);
trace("AABB from Bullet - Left: " + aabbFromBullet.left + ", Right: " + aabbFromBullet.right);
```

#### 绘制AABB

```actionscript
public function draw(dmc:MovieClip):Void
```

**描述**：在指定的`MovieClip`上绘制当前的`AABB`，用于调试和可视化。

**参数**：

- `dmc`：用于绘制的`MovieClip`实例。

**示例**：

```actionscript
var aabb:AABB = new AABB(0, 100, 0, 50);
aabb.draw(_root); // 在根舞台上绘制AABB
```

#### 获取顶点与点集

##### 获取顶点

```actionscript
public function getVertices():Array
```

**描述**：返回`AABB`的四个顶点，按左上、右上、右下、左下顺序。

**返回值**：

- `Array`：包含四个`Vector`实例，分别代表四个顶点。

**示例**：

```actionscript
var aabb:AABB = new AABB(0, 100, 0, 50);
var vertices:Array = aabb.getVertices();
for (var i:Number = 0; i < vertices.length; i++) {
    var vertex:Vector = vertices[i];
    trace("Vertex " + (i+1) + ": (" + vertex.x + ", " + vertex.y + ")");
}
```

##### 将AABB转换为PointSet

```actionscript
public function toPointSet():PointSet
```

**描述**：将`AABB`的四个顶点添加到`PointSet`中，便于后续的点集操作。

**返回值**：

- `PointSet`：包含四个顶点的`PointSet`实例。

**示例**：

```actionscript
var aabb:AABB = new AABB(0, 100, 0, 50);
var pointSet:PointSet = aabb.toPointSet();

// 使用PointSet的方法
trace("PointSet size: " + pointSet.size());

var centroid:Vector = pointSet.getCentroid();
trace("Centroid: (" + centroid.x + ", " + centroid.y + ")");

for (var i:Number = 0; i < pointSet.size(); i++) {
    var point:Vector = pointSet.getPoint(i);
    trace("Point " + (i+1) + ": (" + point.x + ", " + point.y + ")");
}
```

## 使用示例

### 示例1：创建和基本操作

```actionscript
// 创建AABB实例
var aabb1:AABB = new AABB(0, 100, 0, 50);

// 获取边界值
trace("Left: " + aabb1.left);    // 输出：Left: 0
trace("Right: " + aabb1.right);  // 输出：Right: 100

// 设置新的边界值
aabb1.right = 120;
trace("New Right: " + aabb1.right); // 输出：New Right: 120

// 获取宽度和高度
trace("Width: " + aabb1.getWidth());     // 输出：Width: 120
trace("Height: " + aabb1.getLength());   // 输出：Height: 50

// 获取中心点
var center:Vector = aabb1.getCenter();
trace("Center X: " + center.x + ", Center Y: " + center.y); // 输出：Center X: 60, Center Y: 25
```

### 示例2：碰撞检测

```actionscript
// 创建两个AABB
var aabb1:AABB = new AABB(0, 100, 0, 100);
var aabb2:AABB = new AABB(50, 150, 50, 150);

// 检查是否相交
if (aabb1.intersects(aabb2)) {
    trace("AABBs are intersecting.");
} else {
    trace("AABBs are not intersecting.");
}

// 检查点是否在AABB内
var pointX:Number = 75;
var pointY:Number = 75;
if (aabb1.containsPoint(pointX, pointY)) {
    trace("Point is inside aabb1.");
} else {
    trace("Point is outside aabb1.");
}

// 使用 Vector 参数
var point:Vector = new Vector(75, 75);
if (aabb1.containsPointV(point)) {
    trace("Point is inside aabb1.");
} else {
    trace("Point is outside aabb1.");
}
```

### 示例3：最小平移向量应用

```actionscript
// 创建两个重叠的AABB
var aabb1:AABB = new AABB(0, 100, 0, 100);
var aabb2:AABB = new AABB(80, 180, 80, 180);

// 计算MTV（返回对象）
var mtv:Object = aabb1.getMTV(aabb2);
if (mtv != null) {
    trace("MTV dx: " + mtv.dx + ", dy: " + mtv.dy);
    // 假设aabb1代表物体，调整其位置以解决碰撞
    object.x += mtv.dx;
    object.y += mtv.dy;
} else {
    trace("No collision detected.");
}

// 计算MTV（返回Vector）
var mtvVector:Vector = aabb1.getMTVV(aabb2);
if (mtvVector != null) {
    trace("MTV Vector: (" + mtvVector.x + ", " + mtvVector.y + ")");
    // 调整物体位置
    object.x += mtvVector.x;
    object.y += mtvVector.y;
} else {
    trace("No collision detected.");
}
```

### 示例4：合并和细分

```actionscript
// 合并两个AABB
var aabb1:AABB = new AABB(0, 50, 0, 50);
var aabb2:AABB = new AABB(40, 100, 40, 100);
var mergedAABB:AABB = aabb1.merge(aabb2);

trace("Merged AABB - Left: " + mergedAABB.left + ", Right: " + mergedAABB.right);
trace("Merged AABB - Top: " + mergedAABB.top + ", Bottom: " + mergedAABB.bottom);

// 使用 mergeWith 方法
aabb1.mergeWith(aabb2);
trace("AABB1 after mergeWith - Left: " + aabb1.left + ", Right: " + aabb1.right);
trace("AABB1 after mergeWith - Top: " + aabb1.top + ", Bottom: " + aabb1.bottom);

// 批量合并
var aabb3:AABB = new AABB(-10, 60, -10, 60);
var allMerged:AABB = AABB.mergeBatch([aabb1, aabb2, aabb3]);
trace("All Merged AABB - Left: " + allMerged.left + ", Right: " + allMerged.right);
trace("All Merged AABB - Top: " + allMerged.top + ", Bottom: " + allMerged.bottom);

// 细分AABB
var quads:Array = allMerged.subdivide();
for (var i:Number = 0; i < quads.length; i++) {
    trace("Quad " + (i+1) + ": Left=" + quads[i].left + ", Right=" + quads[i].right +
          ", Top=" + quads[i].top + ", Bottom=" + quads[i].bottom);
}
```

## 注意事项

- **边界值有效性**：创建或修改`AABB`时，务必确保`left <= right`和`top <= bottom`，否则可能导致逻辑错误。
- **异常处理**：在设置边界或数据时，建议使用`try...catch`来捕获可能的异常，确保程序稳定性。
- **性能优化**：该类内部使用公开属性存储边界数据，经过优化以提高性能。访问边界时，建议直接使用属性而不是通过访问器方法。
- **调试**：使用`draw`方法可在舞台上绘制`AABB`，方便调试和可视化。

## 适合新手的提示

- **理解AABB的基本概念**：掌握AABB的定义和用途，有助于更好地应用于碰撞检测和空间管理。
- **实践碰撞检测**：通过实际项目中的碰撞检测实现，加深对AABB方法的理解。
- **利用细分与合并**：学习如何通过细分AABB进行空间划分，或通过合并AABB简化空间表示，提高项目的效率和性能。
- **调试与可视化**：利用`draw`方法在舞台上可视化AABB，帮助调试和理解AABB在游戏中的表现。

## 结语

`AABB`类是二维游戏开发中不可或缺的工具，提供了高效的碰撞检测和空间管理功能。通过本文档的详细说明和示例，您可以快速掌握并应用该类于您的项目中。不断实践和探索，您将能够充分发挥AABB在游戏开发中的潜力，构建更加流畅和高效的游戏体验。

如果有任何问题或需要进一步的功能扩展，请随时联系或参考相关资料。


```actionscript

// Create an instance of AABBTester
import org.flashNight.sara.util.*;
var tester:AABBTester = new AABBTester();

// Run all tests
tester.runAllTests();

```

```output

=== Starting AABB Class Tests ===
[PASS] clone() - left
[PASS] clone() - right
[PASS] clone() - top
[PASS] clone() - bottom
[PASS] clone() - independence after modification
[PASS] intersects() - overlapping boxes
[PASS] intersects() - non-overlapping boxes
[PASS] intersects() - edge-touching boxes
[PASS] getMTV() - minimal x-axis overlap
[PASS] getMTV() - corner-touching boxes (no overlap)
[PASS] getMTV() - x-axis only overlap
[PASS] getMTVV() - minimal x-axis overlap
[PASS] getMTVV() - corner-touching boxes (no overlap)
[PASS] getMTVV() - x-axis only overlap
[PASS] getMTV() - corner-touching boxes (no overlap)
[PASS] getMTV() - nested boxes
[PASS] getMTV() - identical boxes
[PASS] getMTV() - edge-touching boxes (no overlap)
[PASS] getMTV() - minimal x-axis overlap
[PASS] getMTV() - negative coordinates overlap
[PASS] getMTV() - equal penetration on both axes
[PASS] containsPoint() - point inside
[PASS] containsPoint() - point on top-left corner
[PASS] containsPoint() - point on bottom-right corner
[PASS] containsPoint() - point left outside
[PASS] containsPoint() - point below outside
[PASS] containsPointV() - point inside
[PASS] containsPointV() - point on edge
[PASS] containsPointV() - point outside
[PASS] closestPoint() - point inside
[PASS] closestPoint() - point left outside
[PASS] closestPoint() - point above outside
[PASS] closestPoint() - point bottom-right outside
[PASS] closestPointV() - point inside
[PASS] closestPointV() - point left outside
[PASS] closestPointV() - point above outside
[PASS] closestPointV() - point bottom-right outside
[PASS] intersectsLine() - line inside
[PASS] intersectsLine() - line partially inside
[PASS] intersectsLine() - line outside
[PASS] intersectsLine() - line touching edge
[PASS] intersectsLineV() - line inside
[PASS] intersectsLineV() - line partially inside
[PASS] intersectsLineV() - line outside
[PASS] intersectsLineV() - line touching edge
[PASS] intersectsCircle() - circle inside
[PASS] intersectsCircle() - circle overlapping edge
[PASS] intersectsCircle() - circle outside
[PASS] intersectsCircle() - circle overlapping corner
[PASS] intersectsCircleV() - circle inside
[PASS] intersectsCircleV() - circle overlapping edge
[PASS] intersectsCircleV() - circle outside
[PASS] intersectsCircleV() - circle overlapping corner
[PASS] intersectsRay() - ray from inside
[PASS] intersectsRay() - ray intersecting box
[PASS] intersectsRay() - ray not intersecting box
[PASS] intersectsRay() - ray parallel and not intersecting
[PASS] intersectsRayV() - ray from inside
[PASS] intersectsRayV() - ray intersecting box
[PASS] intersectsRayV() - ray not intersecting box
[PASS] intersectsRayV() - ray parallel and not intersecting
[PASS] merge() - left
[PASS] merge() - right
[PASS] merge() - top
[PASS] merge() - bottom
[PASS] mergeWith() - left
[PASS] mergeWith() - right
[PASS] mergeWith() - top
[PASS] mergeWith() - bottom
[PASS] mergeBatch() - left
[PASS] mergeBatch() - right (including +1)
[PASS] mergeBatch() - top
[PASS] mergeBatch() - bottom (including +1)
[PASS] subdivide() - number of quads
[PASS] subdivide() - quad1 left
[PASS] subdivide() - quad1 right
[PASS] subdivide() - quad1 top
[PASS] subdivide() - quad1 bottom
[PASS] subdivide() - quad2 left
[PASS] subdivide() - quad2 right
[PASS] subdivide() - quad2 top
[PASS] subdivide() - quad2 bottom
[PASS] subdivide() - quad3 left
[PASS] subdivide() - quad3 right
[PASS] subdivide() - quad3 top
[PASS] subdivide() - quad3 bottom
[PASS] subdivide() - quad4 left
[PASS] subdivide() - quad4 right
[PASS] subdivide() - quad4 top
[PASS] subdivide() - quad4 bottom
[PASS] getArea() - correct area calculation
[PASS] getArea() - zero area
[PASS] fromMovieClip() - left
[PASS] fromMovieClip() - right
[PASS] fromMovieClip() - top
[PASS] fromMovieClip() - bottom
[PASS] fromBullet() - left
[PASS] fromBullet() - right
[PASS] fromBullet() - top
[PASS] fromBullet() - bottom
[PASS] getCenter() - correct center
[PASS] getVertices() - number of vertices
[PASS] getVertices() - vertex 1
[PASS] getVertices() - vertex 2
[PASS] getVertices() - vertex 3
[PASS] getVertices() - vertex 4
[PERF] clone() executed 10000 times in 52 ms
[PERF] getWidth() and getLength() executed 200000 times in 254 ms
[PERF] getCenter() executed 100000 times in 481 ms
[PERF] getCenter() returning Vector executed 100000 times in 483 ms
[PERF] getVertices() executed 10000 times in 154 ms
[PERF] getMTV() executed 10000 times in 62 ms
[PERF] getMTVV() executed 10000 times in 79 ms
[PERF] containsPoint() executed 20000 times in 43 ms
[PERF] containsPointV() executed 20000 times in 43 ms
[PERF] closestPoint() executed 30000 times in 166 ms
[PERF] closestPointV() executed 30000 times in 172 ms
[PERF] intersectsLine() executed 40000 times in 158 ms
[PERF] intersectsLineV() executed 40000 times in 160 ms
[PERF] intersectsCircle() executed 30000 times in 104 ms
[PERF] intersectsCircleV() executed 30000 times in 106 ms
[PERF] intersectsRay() executed 30000 times in 156 ms
[PERF] intersectsRayV() executed 30000 times in 158 ms
[PERF] intersects() executed 20000 times in 41 ms
[PERF] merge() executed 10000 times in 62 ms
[PERF] mergeWith() executed 10000 times in 22 ms
[PERF] mergeBatch() executed 1000 times in 149 ms
[PERF] subdivide() executed 10000 times in 234 ms
[PERF] getArea() executed 100000 times in 174 ms
[PERF] fromMovieClip() executed 10000 times in 91 ms
[PERF] fromBullet() executed 10000 times in 89 ms
=== Test Summary ===
Total Tests: 106
Passed Tests: 106
Failed Tests: 0
All tests passed successfully!

```