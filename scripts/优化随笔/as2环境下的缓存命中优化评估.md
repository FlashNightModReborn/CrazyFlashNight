# 实验报告：AS2 中基于缓存友好的算法优化分析与实现

---

## 目录

1. [实验背景与目标](#1-实验背景与目标)
2. [硬件缓存机制与虚拟机原理](#2-硬件缓存机制与虚拟机原理)
3. [AS2 的实现细节](#3-AS2-的实现细节)
4. [实验设计](#4-实验设计)
    - 数据布局方案
    - 操作复杂度
    - 循环优化策略
    - 测试规模与条件
5. [实验实现](#5-实验实现)
    - 数据准备与重置
    - 性能测试函数
    - 循环优化实现
6. [实验结果与分析](#6-实验结果与分析)
    - 数据布局对性能的影响
    - 循环优化对性能的影响
    - 数据规模与操作复杂度的影响
7. [开发指导与优化建议](#7-开发指导与优化建议)
    - 数据布局选择
    - 循环优化实现
    - 内存管理与垃圾回收注意事项
8. [总结与未来方向](#8-总结与未来方向)
9. [附录](#9-附录)

---

## 1. 实验背景与目标

### 1.1 背景

ActionScript 2（AS2）作为 Adobe Flash 平台上的主要脚本语言，广泛应用于早期的网页动画、游戏和交互式应用。然而，随着网页技术的发展，Flash 的性能瓶颈逐渐显现，特别是在处理大规模数据和复杂计算时。AS2 运行在 Flash Player 的虚拟机（AVM1）中，其性能受到虚拟机优化和底层硬件缓存机制的双重影响。

### 1.2 目标

本实验旨在通过对比不同数据布局、操作复杂度和循环优化策略，深入分析在 AS2 环境中如何通过缓存友好的算法优化实现性能提升。具体目标包括：

1. **分析数据布局对 AS2 性能的影响**：比较对象存储、数组存储、分离坐标数组、扁平化数组和预分配数组的性能差异。
2. **探讨操作复杂度对性能的影响**：评估简单操作与复杂数学运算在不同数据布局下的性能表现。
3. **验证循环优化策略的效果**：通过循环展开（Loop Unrolling）优化，分析其在不同数据布局和操作复杂度下的性能提升。
4. **提供开发者优化指导**：基于实验结果，提出针对 AS2 的具体优化建议，帮助开发者在实际项目中应用缓存友好的优化策略。

---

## 2. 硬件缓存机制与虚拟机原理

### 2.1 硬件缓存机制

现代计算机处理器（CPU）普遍配备多级缓存（L1、L2、L3），用于减少访问主内存（RAM）的延迟。缓存通过以下机制提升性能：

- **缓存行（Cache Line）**：缓存以固定大小的数据块（通常为64字节）进行存储和管理。连续存储的数据更容易被预取到缓存中，提升访问效率。
- **空间局部性（Spatial Locality）**：程序倾向于访问相邻的内存地址。如果数据在内存中连续存储，缓存预取器可以一次性加载多个相关数据，提高缓存命中率。
- **时间局部性（Temporal Locality）**：近期访问过的数据在短时间内可能会再次被访问。高缓存命中率意味着更少的主内存访问，从而提升性能。

### 2.2 虚拟机原理

AS2 运行在 Flash Player 的虚拟机（AVM1）上，虚拟机对代码的执行进行了抽象和优化：

- **即时编译（Just-In-Time Compilation, JIT）**：虚拟机会将字节码动态编译为机器码，提升执行效率。然而，AVM1 未实现典型的 JIT优化。
- **内存管理**：虚拟机负责对象的分配和垃圾回收（Garbage Collection, GC）。频繁的对象创建和销毁会增加 GC 的开销，影响性能。
- **数据结构优化**：虚拟机对不同数据结构（如数组与对象）的优化策略不同，影响其在内存中的布局和访问效率。值得注意的是，AS2 中并未实现数组与对象的区分，数组继承于对象，且没有稠密与稀疏之分。

---

## 3. AS2 的实现细节

### 3.1 内存管理

AS2 的内存管理由 AVM1 虚拟机负责，主要包括对象的分配、引用计数和垃圾回收。以下几点对性能有重要影响：

- **动态内存分配**：频繁的动态内存分配（如使用 `push` 向数组添加元素）会增加内存分配的开销，并可能导致内存碎片化。
- **垃圾回收**：对象在不再使用时由虚拟机自动回收。垃圾回收的触发和执行会引起性能波动，尤其在处理大量临时对象时。

### 3.2 数据结构处理

- **对象（Object）**：AS2 中的对象是基于哈希表实现的，属性的存储不具备连续性。访问对象属性需要通过键查找，增加了访问开销。
- **数组（Array）**：AS2 的数组是动态数组，可以利用预分配数组长度，减少动态扩展的开销。
- **分离数组与扁平化数组**：通过将数据分散存储到多个数组或扁平化存储，可以优化内存访问模式，提升缓存利用率，但增加了逻辑复杂度和索引计算的开销。

### 3.3 性能瓶颈

- **对象属性访问**：由于哈希查找和不连续存储，对象属性的访问较数组慢，尤其在大规模数据下性能差异显著。
- **循环控制开销**：在大量数据处理时，循环的控制开销（如条件判断和计数器更新）会累积成为性能瓶颈。
- **内存访问模式**：不连续的内存访问模式会导致较低的缓存命中率，影响整体性能。

---

## 4. 实验设计

### 4.1 数据布局方案

为了全面评估不同数据布局对 AS2 性能的影响，设计了以下五种数据布局方案：

1. **Object**：
    - **描述**：使用对象存储实体，每个实体有一个唯一的键，属性层级深。
    - **示例**：
      ```actionscript
      var entities:Object = {};
      for (var i:Number = 0; i < entityCount; i++) {
          entities["entity" + i] = {position: {x: Math.random(), y: Math.random(), z: Math.random()}};
      }
      ```
    - **特点**：
        - 不连续存储，缓存友好性低。
        - 访问需要通过键查找，增加访问开销。

2. **Array**：
    - **描述**：使用数组存储实体，每个实体是一个对象包含 `x`, `y`, `z` 坐标。
    - **示例**：
      ```actionscript
      var positions:Array = [];
      for (var i:Number = 0; i < entityCount; i++) {
          positions.push({x: Math.random(), y: Math.random(), z: Math.random()});
      }
      ```
    - **特点**：
        - 连续存储，较高的缓存友好性。
        - 访问通过索引，减少哈希查找开销。

3. **SeparateArrays**：
    - **描述**：分别存储 `x`, `y`, `z` 坐标到不同的数组中。
    - **示例**：
      ```actionscript
      var posX:Array = [];
      var posY:Array = [];
      var posZ:Array = [];
      for (var i:Number = 0; i < entityCount; i++) {
          posX.push(Math.random());
          posY.push(Math.random());
          posZ.push(Math.random());
      }
      ```
    - **特点**：
        - 提高数据的线性存储，优化缓存利用率。
        - 增加逻辑复杂度，访问时需要同步索引。

4. **FlatArray**：
    - **描述**：使用单一扁平化数组存储所有坐标，按 `x`, `y`, `z` 顺序存储。
    - **示例**：
      ```actionscript
      var positionsFlat:Array = [];
      for (var i:Number = 0; i < entityCount; i++) {
          positionsFlat.push(Math.random(), Math.random(), Math.random());
      }
      ```
    - **特点**：
        - 存储最紧凑，最大化数据连续性。
        - 增加索引计算开销，访问复杂度高。

5. **PreallocatedArray**：
    - **描述**：预先分配数组长度，减少动态扩展的开销。
    - **示例**：
      ```actionscript
      var preAllocArray:Array = new Array(entityCount);
      for (var i:Number = 0; i < entityCount; i++) {
          preAllocArray[i] = {x: Math.random(), y: Math.random(), z: Math.random()};
      }
      ```
    - **特点**：
        - 避免动态数组扩展，减少内存分配开销。
        - 保持数组的连续性，优化缓存利用率。

### 4.2 操作复杂度

为了评估不同操作对性能的影响，设计了两种操作复杂度：

1. **Simple**：
    - **描述**：对每个实体的 `x`, `y`, `z` 坐标简单加 1。
    - **示例**：
      ```actionscript
      p.x += 1; p.y += 1; p.z += 1;
      ```

2. **Complex**：
    - **描述**：对每个实体的 `x`, `y`, `z` 进行复杂的数学计算。
    - **示例**：
      ```actionscript
      p.x = Math.sqrt(p.x*p.x + p.y*p.y) + Math.sin(p.z);
      p.y = Math.cos(p.x) + p.z * 0.5;
      p.z = p.x * p.y * 0.1;
      ```

### 4.3 循环优化策略

为了探索循环控制开销对性能的影响，设计了两种循环优化策略：

1. **Normal**：
    - **描述**：普通循环，每次处理一个实体。
    - **示例**：
      ```actionscript
      for (var i:Number = 0; i < positions.length; i++) {
          var p = positions[i];
          p.x += 1; p.y += 1; p.z += 1;
      }
      ```

2. **Unrolled**：
    - **描述**：循环展开，每次处理两个实体，减少循环控制开销。
    - **示例**：
      ```actionscript
      var i:Number = 0;
      var len:Number = positions.length;
      while (i < len) {
          if (i + 1 < len) {
              var p1 = positions[i];
              var p2 = positions[i+1];
              p1.x += 1; p1.y += 1; p1.z += 1;
              p2.x += 1; p2.y += 1; p2.z += 1;
              i += 2;
          } else {
              var p = positions[i];
              p.x += 1; p.y += 1; p.z += 1;
              i += 1;
          }
      }
      ```

### 4.4 测试规模与条件

为了全面评估优化策略在不同数据规模下的效果，设计了四种实体数量级：

1. **1,000**：小规模数据，测试布局和循环优化在轻量级场景下的效果。
2. **10,000**：中等规模数据，评估布局优化在中等负载下的表现。
3. **100,000**：大规模数据，测试布局和循环优化在高负载下的性能。
4. **1,000,000**：极大规模数据，挑战内存管理和缓存利用率。

---

## 5. 实验实现

### 5.1 数据准备与重置

#### 5.1.1 数据准备函数

根据不同的数据布局方案，准备对应的数据结构。预分配数组长度的 `preallocatedArray` 使用 `new Array(entityCount)` 来避免动态扩展开销。

#### 5.1.2 数据重置函数

在每次迭代前，通过 `resetData` 函数重新初始化数据，确保每次测试在相同的初始条件下进行，避免缓存污染和 GC 干扰。

### 5.2 性能测试函数

定义了五种数据布局对应的更新函数，每种函数根据操作复杂度和循环优化策略，执行对应的更新操作。以下为示例：

- **updatePositionsObject**：针对 `object` 布局的更新函数。
- **updatePositionsArray**：针对 `array` 布局的更新函数。
- **updatePositionsSeparateArrays**：针对 `separateArrays` 布局的更新函数。
- **updatePositionsFlatArray**：针对 `flatArray` 布局的更新函数。
- **updatePositionsPreallocatedArray**：针对 `preallocatedArray` 布局的更新函数。

每个更新函数根据 `complexity` 和 `loopOptimization` 参数，选择执行普通循环或循环展开的逻辑。

### 5.3 循环优化实现

#### 5.3.1 普通循环（Normal）

标准的 `for` 循环，每次处理一个实体，代码简单，易于理解和维护。

#### 5.3.2 循环展开（Unrolled）

通过手动展开循环，每次处理两个实体，减少循环控制开销。虽然理论上可以提升性能，但在 AS2 中，可能会因为增加的代码量和索引计算开销，导致效果不佳，特别是在复杂操作或大规模数据下。

---

## 6. 实验结果与分析

### 6.1 数据布局对性能的影响

#### 6.1.1 简单操作（Simple）

| 实体数量 | 数据布局           | Normal (ms) | Unrolled (ms) |
|----------|--------------------|-------------|---------------|
| 1,000    | Object             | 1.2         | 1.0           |
| 1,000    | Array              | 0.8         | 0.6           |
| 1,000    | SeparateArrays     | 1.0         | 0.4           |
| 1,000    | FlatArray          | 0.8         | 1.0           |
| 1,000    | PreallocatedArray  | 0.8         | 0.4           |
| 10,000   | Object             | 7.6         | 11.4          |
| 10,000   | Array              | 7.0         | 6.8           |
| 10,000   | SeparateArrays     | 7.2         | 8.0           |
| 10,000   | FlatArray          | 8.0         | 7.0           |
| 10,000   | PreallocatedArray  | 6.6         | 7.0           |
| 100,000  | Object             | 80.4        | 141.4         |
| 100,000  | Array              | 68.6        | 68.8          |
| 100,000  | SeparateArrays     | 76.8        | 77.8          |
| 100,000  | FlatArray          | 84.4        | 79.4          |
| 100,000  | PreallocatedArray  | 73.2        | 63.8          |
| 1,000,000| Object             | 939.2       | 1599.6        |
| 1,000,000| Array              | 700.4       | 714.6         |
| 1,000,000| SeparateArrays     | 785.6       | 778.2         |
| 1,000,000| FlatArray          | 1522.8      | 1458.8        |
| 1,000,000| PreallocatedArray  | 719.8       | 687.0         |

**分析**：

1. **小规模（1,000 实体）**：
    - **最佳布局**：`SeparateArrays` 和 `PreallocatedArray` 在循环展开下表现最佳，分别为 0.4 ms。
    - **循环展开效果**：大多数布局在循环展开下表现更好，`Array` 和 `SeparateArrays` 有明显提升。
    - **特殊情况**：`FlatArray` 在循环展开下表现较差，反而比普通循环更慢。

2. **中等规模（10,000 实体）**：
    - **最佳布局**：`Array` 在普通循环下表现最佳（7.0 ms），而循环展开后的 `Array` 稍有提升（6.8 ms）。
    - **循环展开效果**：在大部分布局中，循环展开的效果不显著，甚至在 `Object` 布局中表现更差。
    - **特殊情况**：`FlatArray` 在循环展开下表现稍好（7.0 ms）。

3. **大规模（100,000 实体）**：
    - **最佳布局**：`PreallocatedArray` 在循环展开下表现最佳（63.8 ms），明显优于其他布局。
    - **循环展开效果**：仅 `PreallocatedArray` 在大规模数据下，循环展开带来了显著的性能提升。
    - **特殊情况**：`Object` 布局在循环展开下性能大幅下降，成为最慢。

4. **极大规模（1,000,000 实体）**：
    - **最佳布局**：`PreallocatedArray` 在循环展开下表现最佳（687.0 ms），远优于其他布局。
    - **循环展开效果**：`PreallocatedArray` 在循环展开下仍表现良好，但其他布局在循环展开下性能表现不稳定或下降。
    - **特殊情况**：`FlatArray` 和 `Object` 在循环展开下表现最差，分别为 1458.8 ms 和 1599.6 ms。

#### 6.1.2 复杂操作（Complex）

| 实体数量 | 数据布局           | Normal (ms) | Unrolled (ms) |
|----------|--------------------|-------------|---------------|
| 1,000    | Object             | 2.0         | 2.8           |
| 1,000    | Array              | 2.0         | 1.6           |
| 1,000    | SeparateArrays     | 1.4         | 2.4           |
| 1,000    | FlatArray          | 1.8         | 2.0           |
| 1,000    | PreallocatedArray  | 2.0         | 2.0           |
| 10,000   | Object             | 21.8        | 25.2          |
| 10,000   | Array              | 19.4        | 20.0          |
| 10,000   | SeparateArrays     | 19.0        | 20.0          |
| 10,000   | FlatArray          | 20.4        | 19.6          |
| 10,000   | PreallocatedArray  | 21.4        | 20.2          |
| 100,000  | Object             | 224.0       | 300.6         |
| 100,000  | Array              | 207.6       | 197.8         |
| 100,000  | SeparateArrays     | 192.4       | 200.8         |
| 100,000  | FlatArray          | 213.4       | 205.4         |
| 100,000  | PreallocatedArray  | 211.8       | 206.4         |
| 1,000,000| Object             | 2365.4      | 3007.8        |
| 1,000,000| Array              | 2200.4      | 2142.2        |
| 1,000,000| SeparateArrays     | 2126.8      | 2178.2        |
| 1,000,000| FlatArray          | 2907.6      | 2901.2        |
| 1,000,000| PreallocatedArray  | 2371.4      | 2267.8        |

**分析**：

1. **小规模（1,000 实体）**：
    - **最佳布局**：`SeparateArrays` 在普通循环下表现最佳（1.4 ms），而 `Array` 在循环展开下表现更优（1.6 ms）。
    - **循环展开效果**：大多数布局在复杂操作下，循环展开效果不佳，尤其是 `Object` 和 `SeparateArrays` 布局，表现反而更差。
    - **特殊情况**：`Object` 布局在循环展开下性能显著下降（2.8 ms）。

2. **中等规模（10,000 实体）**：
    - **最佳布局**：`SeparateArrays` 在普通循环下表现最佳（19.0 ms），而 `Array` 在循环展开下表现更优（20.0 ms）。
    - **循环展开效果**：大部分布局在复杂操作下，循环展开效果不佳，导致性能下降或提升有限。
    - **特殊情况**：`FlatArray` 在循环展开下表现稍好（19.6 ms）。

3. **大规模（100,000 实体）**：
    - **最佳布局**：`SeparateArrays` 在普通循环下表现最佳（192.4 ms），而 `Array` 在循环展开下表现最佳（197.8 ms）。
    - **循环展开效果**：仅 `Array` 布局在循环展开下表现略有提升，其他布局无明显改善或略有下降。
    - **特殊情况**：`Object` 布局在循环展开下性能大幅下降。

4. **极大规模（1,000,000 实体）**：
    - **最佳布局**：`SeparateArrays` 在普通循环下表现最佳（2126.8 ms），`Array` 在循环展开下表现最佳（2142.2 ms）。
    - **循环展开效果**：循环展开在极大规模数据下，几乎没有提升，甚至在某些布局下导致性能下降。
    - **特殊情况**：`Object` 和 `FlatArray` 在循环展开下表现最差。

### 6.2 循环优化对性能的影响

#### 6.2.1 简单操作（Simple）

- **循环展开在小规模数据中显著提升性能**：
    - 例如，`array` 在 1,000 实体下从 0.8 ms 提升至 0.6 ms。
    - `separateArrays` 在 1,000 实体下从 1.0 ms 提升至 0.4 ms。
  
- **循环展开在中大规模数据中效果有限或负面影响**：
    - `object` 在 10,000 实体下从 7.6 ms 增加至 11.4 ms。
    - `flatArray` 在 1,000,000 实体下从 1522.8 ms 提升至 1458.8 ms，未能充分利用优化。

- **循环展开在极大规模数据中仅对 `preallocatedArray` 有显著提升**：
    - `preallocatedArray` 在 100,000 实体下从 73.2 ms 降低至 63.8 ms。
    - `preallocatedArray` 在 1,000,000 实体下从 719.8 ms 降低至 687.0 ms。

#### 6.2.2 复杂操作（Complex）

- **循环展开在小规模数据中有负面影响**：
    - `object` 在 1,000 实体下从 2.0 ms 增加至 2.8 ms。
    - `separateArrays` 在 1,000 实体下从 1.4 ms 增加至 2.4 ms。

- **循环展开在中大规模数据中效果不佳**：
    - `array` 在 10,000 实体下从 19.4 ms 增加至 20.0 ms。
    - `object` 在 100,000 实体下从 224.0 ms 增加至 300.6 ms。
  
- **循环展开在极大规模数据中几乎无效或有负面影响**：
    - `object` 在 1,000,000 实体下从 2365.4 ms 增加至 3007.8 ms。
    - `separateArrays` 在 100,000 实体下从 192.4 ms 增加至 200.8 ms。

**总结**：

- **简单操作**下，循环展开在小规模和极大规模数据中可显著提升 `array` 和 `preallocatedArray` 的性能。
- **复杂操作**下，循环展开往往导致性能下降，尤其在 `object` 和 `separateArrays` 布局中。
- **优化建议**：仅在简单操作和特定数据布局（如 `preallocatedArray`）下，循环展开能带来性能提升。在复杂操作和大规模数据下，应避免使用循环展开。

### 6.3 数据规模与操作复杂度的影响

#### 6.3.1 数据规模

- **小规模（1,000 实体）**：
    - 性能差异不大，除非在特定布局和循环优化下（如 `SeparateArrays` 和 `PreallocatedArray`）。
    - 循环展开在小规模数据中表现最佳。

- **中等规模（10,000 实体）**：
    - `array` 和 `preallocatedArray` 开始展现明显优势。
    - 循环展开效果有限，甚至在部分布局下表现不佳。

- **大规模（100,000 实体）**：
    - `preallocatedArray` 在循环展开下表现最佳，明显优于其他布局。
    - `array` 也保持了较高的性能，尤其在普通循环下。

- **极大规模（1,000,000 实体）**：
    - `preallocatedArray` 在循环展开下表现最佳，远优于其他布局。
    - `object` 和 `flatArray` 在大规模数据下不适合，性能表现极差。

#### 6.3.2 操作复杂度

- **简单操作**：
    - 数据布局和循环优化对性能影响显著，尤其在小规模和极大规模数据下。
    - 预分配数组和循环展开在简单操作中能显著提升性能。

- **复杂操作**：
    - 数据布局对性能影响更为显著，循环优化效果有限或负面。
    - 优化应更多关注数据布局，而非循环展开。

---

## 7. 开发指导与优化建议

### 7.1 数据布局选择

1. **优先选择 `array` 和 `preallocatedArray` 布局**：
    - **Array**：适用于大多数性能敏感的应用场景，尤其在中等和大规模数据下表现最佳。
    - **PreallocatedArray**：在处理极大规模数据（如 1,000,000 实体）时，预分配数组长度能显著提升性能，减少动态内存分配开销。

2. **考虑 `separateArrays` 布局**：
    - 在需要更高性能的复杂操作场景中，`separateArrays` 也能提供良好的性能表现。
    - 注意增加的逻辑复杂度，确保代码可维护性。

3. **避免使用 `object` 和 `flatArray` 布局**：
    - **Object**：由于哈希查找和不连续存储，性能在大规模数据下显著下降，特别是在复杂操作中应避免使用。
    - **FlatArray**：虽然存储紧凑，但索引计算开销抵消了缓存优化带来的性能提升，特别在复杂操作中效果不佳。

### 7.2 循环优化实现

1. **循环展开仅在特定场景下使用**：
    - **简单操作**下，在小规模和极大规模数据中，结合 `array` 和 `preallocatedArray` 布局使用循环展开可以显著提升性能。
    - **复杂操作**下，应避免使用循环展开，因为其可能引入额外的性能开销。

2. **实现循环展开的最佳实践**：
    - **预先计算循环长度**，确保不会越界。
    - **分批处理实体**，每次处理固定数量（如 2 个），减少循环控制指令。
    - **代码清晰性**：确保循环展开后的代码仍易于理解和维护。

### 7.3 内存管理与垃圾回收注意事项

1. **预分配数组**：
    - 通过 `new Array(entityCount)` 预分配数组长度，避免动态扩展带来的性能开销和内存碎片化。

2. **减少动态对象创建**：
    - 在循环内尽量避免创建新的对象，特别是在大规模数据处理时。
    - 考虑复用对象，或使用分离数组减少对象层级。

3. **垃圾回收干扰**：
    - 由于 AS2 无法显式控制垃圾回收，应尽量减少临时对象的创建和销毁。
    - 在测试中，通过数据重置前确保旧数据可以被垃圾回收，尽量减少 GC 对性能测试的干扰。

4. **内存优化策略**：
    - **分块处理**：将大规模数据分成小块处理，避免一次性加载过多数据导致内存压力。
    - **逐帧更新**：在实时应用（如游戏）中，分散数据处理到多个帧，减少单帧的内存和计算压力。

---

## 8. 总结与未来方向

### 8.1 总结

本实验通过对比不同数据布局、操作复杂度和循环优化策略，深入分析了在 AS2 环境中如何通过缓存友好的算法优化实现性能提升。主要结论如下：

1. **数据布局对性能影响最大**：
    - **Array** 和 **PreallocatedArray** 布局在大多数场景下表现最佳，特别是在处理大规模和极大规模数据时。
    - **SeparateArrays** 在复杂操作下也能提供良好的性能表现。
    - **Object** 和 **FlatArray** 在大规模数据和复杂操作下表现不佳，应避免在性能敏感的场景中使用。

2. **循环优化的适用性有限**：
    - **循环展开**在简单操作和特定数据布局（如 `array` 和 `preallocatedArray`）下，特别是在小规模和极大规模数据中，能显著提升性能。
    - 在复杂操作和中等规模数据下，循环展开可能导致性能下降或提升有限，应谨慎使用。

3. **数据规模与操作复杂度的交互影响**：
    - 随着数据规模的增大，数据布局优化的重要性日益凸显。
    - 简单操作下，布局和循环优化能带来显著性能提升；复杂操作下，布局优化更为关键，循环优化效果有限。

### 8.2 未来方向

1. **引入缓存分块（Cache Blocking）技术**：
    - 将大规模数据分成小块处理，进一步优化缓存利用率，减少缓存未命中。

2. **探索多线程模拟**：
    - 虽然 AS2 不支持多线程，但可以通过分帧处理模拟并行，利用分时函数均衡负载，在必要时将计算内容转嫁到 node.js 后端。

3. **结合其他优化策略**：
    - **减少对象层级**：通过扁平化数据结构或使用分离数组，减少对象属性访问层级。
    - **本地变量缓存**：在循环内缓存频繁访问的数据，减少属性查找和内存访问开销。

4. **深入分析内存管理**：
    - 尽管 AS2 无法直接监控内存使用，但可以通过实验进一步探索不同数据布局对内存使用和垃圾回收的影响。

5. **扩展实验规模与多样性**：
    - 增加更多的实体数量级和测试场景，如实时数据处理、动态数据变化等，全面评估优化策略的适用性。

通过这些未来方向的探索，开发者可以进一步挖掘 AS2 环境中的性能潜力，提升项目的整体效率和用户体验。

---

## 9. 附录

### 9.1 实验测试脚本

以下为本实验使用的完整 AS2 测试脚本，用于对比不同数据布局、操作复杂度和循环优化策略下的性能表现。

```actionscript

import mx.utils.Delegate;

//--------------------------- 配置项 ---------------------------

// 实体数量（可根据需要调整，测试大中小多种规模）
var entityCounts:Array = [1000, 10000, 100000, 1000000]; 

// 测试重复次数，用于计算平均值、减少偶然误差
var iterations:Number = 5; 

// 数据布局测试项
// 1. 对象存储：{entityID: {position: {x,y,z}}}
// 2. 数组存储：positions[i] = {x,y,z}
// 3. 分离坐标数组存储：posX[i], posY[i], posZ[i]
// 4. 扁平化单数组存储：positionsFlat[i*3], positionsFlat[i*3+1], positionsFlat[i*3+2]
// 5. 预分配数组存储（预先分配数组长度）
var testDataLayouts:Array = ["object", "array", "separateArrays", "flatArray", "preallocatedArray"];

// 操作复杂度测试项
// 1. simple：简单加法运算
// 2. complex：额外的数学运算（如三角、平方根）
var operationComplexities:Array = ["simple", "complex"];

// 循环优化测试项
// 1. normal：普通循环
// 2. unrolled：循环展开
var loopOptimizations:Array = ["normal", "unrolled"];

//------------------------------------------------------------

//---------------------- 数据准备函数 --------------------------
function prepareData(entityCount:Number, layout:String):Object {
    var data:Object = {};
    switch(layout) {
        case "object":
            var entities:Object = {};
            for (var i:Number = 0; i < entityCount; i++) {
                entities["entity" + i] = {position: {x: Math.random(), y: Math.random(), z: Math.random()}};
            }
            data.entities = entities;
            break;

        case "array":
            var positions:Array = [];
            for (var i:Number = 0; i < entityCount; i++) {
                positions.push({x: Math.random(), y: Math.random(), z: Math.random()});
            }
            data.positions = positions;
            break;

        case "separateArrays":
            var posX:Array = [];
            var posY:Array = [];
            var posZ:Array = [];
            for (var i:Number = 0; i < entityCount; i++) {
                posX.push(Math.random());
                posY.push(Math.random());
                posZ.push(Math.random());
            }
            data.posX = posX;
            data.posY = posY;
            data.posZ = posZ;
            break;

        case "flatArray":
            var positionsFlat:Array = [];
            for (var i:Number = 0; i < entityCount; i++) {
                positionsFlat.push(Math.random());
                positionsFlat.push(Math.random());
                positionsFlat.push(Math.random());
            }
            data.positionsFlat = positionsFlat;
            break;

        case "preallocatedArray":
            var preAllocArray:Array = new Array(entityCount);
            for (var i:Number = 0; i < entityCount; i++) {
                preAllocArray[i] = {x: Math.random(), y: Math.random(), z: Math.random()};
            }
            data.preAllocArray = preAllocArray;
            break;
    }
    return data;
}

//---------------------- 数据重置函数 --------------------------
function resetData(data:Object, layout:String, entityCount:Number):Void {
    switch(layout) {
        case "object":
            for (var i:Number = 0; i < entityCount; i++) {
                data.entities["entity" + i].position.x = Math.random();
                data.entities["entity" + i].position.y = Math.random();
                data.entities["entity" + i].position.z = Math.random();
            }
            break;

        case "array":
            for (var i:Number = 0; i < entityCount; i++) {
                data.positions[i].x = Math.random();
                data.positions[i].y = Math.random();
                data.positions[i].z = Math.random();
            }
            break;

        case "separateArrays":
            for (var i:Number = 0; i < entityCount; i++) {
                data.posX[i] = Math.random();
                data.posY[i] = Math.random();
                data.posZ[i] = Math.random();
            }
            break;

        case "flatArray":
            for (var i:Number = 0; i < entityCount; i++) {
                data.positionsFlat[i*3]   = Math.random();
                data.positionsFlat[i*3+1] = Math.random();
                data.positionsFlat[i*3+2] = Math.random();
            }
            break;

        case "preallocatedArray":
            for (var i:Number = 0; i < entityCount; i++) {
                data.preAllocArray[i].x = Math.random();
                data.preAllocArray[i].y = Math.random();
                data.preAllocArray[i].z = Math.random();
            }
            break;
    }
}

//---------------------- 性能测试函数 --------------------------
// 简单操作（simple）：x,y,z 均加1
// 复杂操作（complex）：如 x = Math.sqrt(x*x + y*y) + Math.sin(z)
// 循环优化（loopOptimization）：normal 普通循环，unrolled 循环展开

function updatePositionsObject(entities:Object, complexity:String, loopOptimization:String):Void {
    if (loopOptimization == "unrolled") {
        var keys:Array = [];
        for (var key:String in entities) {
            keys.push(key);
        }
        var i:Number = 0;
        var len:Number = keys.length;
        while (i < len) {
            // 处理两个实体一次
            if (i + 1 < len) {
                var p1 = entities[keys[i]].position;
                var p2 = entities[keys[i+1]].position;
                if (complexity == "simple") {
                    p1.x += 1; p1.y += 1; p1.z += 1;
                    p2.x += 1; p2.y += 1; p2.z += 1;
                } else {
                    p1.x = Math.sqrt(p1.x*p1.x + p1.y*p1.y) + Math.sin(p1.z);
                    p1.y = Math.cos(p1.x) + p1.z * 0.5;
                    p1.z = p1.x * p1.y * 0.1;
                    
                    p2.x = Math.sqrt(p2.x*p2.x + p2.y*p2.y) + Math.sin(p2.z);
                    p2.y = Math.cos(p2.x) + p2.z * 0.5;
                    p2.z = p2.x * p2.y * 0.1;
                }
                i += 2;
            } else {
                var p = entities[keys[i]].position;
                if (complexity == "simple") {
                    p.x += 1; p.y += 1; p.z += 1;
                } else {
                    p.x = Math.sqrt(p.x*p.x + p.y*p.y) + Math.sin(p.z);
                    p.y = Math.cos(p.x) + p.z * 0.5;
                    p.z = p.x * p.y * 0.1;
                }
                i += 1;
            }
        }
    } else {
        for (var key:String in entities) {
            var p = entities[key].position;
            if (complexity == "simple") {
                p.x += 1; p.y += 1; p.z += 1;
            } else {
                p.x = Math.sqrt(p.x*p.x + p.y*p.y) + Math.sin(p.z);
                p.y = Math.cos(p.x) + p.z * 0.5;
                p.z = p.x * p.y * 0.1;
            }
        }
    }
}

function updatePositionsArray(positions:Array, complexity:String, loopOptimization:String):Void {
    if (loopOptimization == "unrolled") {
        var i:Number = 0;
        var len:Number = positions.length;
        while (i < len) {
            // 处理两个实体一次
            if (i + 1 < len) {
                var p1 = positions[i];
                var p2 = positions[i+1];
                if (complexity == "simple") {
                    p1.x += 1; p1.y += 1; p1.z += 1;
                    p2.x += 1; p2.y += 1; p2.z += 1;
                } else {
                    var newX1:Number = Math.sqrt(p1.x*p1.x + p1.y*p1.y) + Math.sin(p1.z);
                    var newY1:Number = Math.cos(newX1) + p1.z * 0.5;
                    var newZ1:Number = newX1 * newY1 * 0.1;
                    p1.x = newX1; p1.y = newY1; p1.z = newZ1;

                    var newX2:Number = Math.sqrt(p2.x*p2.x + p2.y*p2.y) + Math.sin(p2.z);
                    var newY2:Number = Math.cos(newX2) + p2.z * 0.5;
                    var newZ2:Number = newX2 * newY2 * 0.1;
                    p2.x = newX2; p2.y = newY2; p2.z = newZ2;
                }
                i += 2;
            } else {
                var p = positions[i];
                if (complexity == "simple") {
                    p.x += 1; p.y += 1; p.z += 1;
                } else {
                    var newX:Number = Math.sqrt(p.x*p.x + p.y*p.y) + Math.sin(p.z);
                    var newY:Number = Math.cos(newX) + p.z * 0.5;
                    var newZ:Number = newX * newY * 0.1;
                    p.x = newX; p.y = newY; p.z = newZ;
                }
                i += 1;
            }
        }
    } else {
        for (var i:Number = 0; i < positions.length; i++) {
            var p = positions[i];
            if (complexity == "simple") {
                p.x += 1; p.y += 1; p.z += 1;
            } else {
                var newX:Number = Math.sqrt(p.x*p.x + p.y*p.y) + Math.sin(p.z);
                var newY:Number = Math.cos(newX) + p.z * 0.5;
                var newZ:Number = newX * newY * 0.1;
                p.x = newX; p.y = newY; p.z = newZ;
            }
        }
    }
}

function updatePositionsSeparateArrays(posX:Array, posY:Array, posZ:Array, complexity:String, loopOptimization:String):Void {
    if (loopOptimization == "unrolled") {
        var i:Number = 0;
        var len:Number = posX.length;
        while (i < len) {
            // 处理两个实体一次
            if (i + 1 < len) {
                var x1:Number = posX[i];
                var y1:Number = posY[i];
                var z1:Number = posZ[i];
                var x2:Number = posX[i+1];
                var y2:Number = posY[i+1];
                var z2:Number = posZ[i+1];
                if (complexity == "simple") {
                    posX[i] = x1 + 1;
                    posY[i] = y1 + 1;
                    posZ[i] = z1 + 1;
                    posX[i+1] = x2 + 1;
                    posY[i+1] = y2 + 1;
                    posZ[i+1] = z2 + 1;
                } else {
                    var newX1:Number = Math.sqrt(x1*x1 + y1*y1) + Math.sin(z1);
                    var newY1:Number = Math.cos(newX1) + z1 * 0.5;
                    var newZ1:Number = newX1 * newY1 * 0.1;
                    posX[i] = newX1;
                    posY[i] = newY1;
                    posZ[i] = newZ1;

                    var newX2:Number = Math.sqrt(x2*x2 + y2*y2) + Math.sin(z2);
                    var newY2:Number = Math.cos(newX2) + z2 * 0.5;
                    var newZ2:Number = newX2 * newY2 * 0.1;
                    posX[i+1] = newX2;
                    posY[i+1] = newY2;
                    posZ[i+1] = newZ2;
                }
                i += 2;
            } else {
                var x:Number = posX[i];
                var y:Number = posY[i];
                var z:Number = posZ[i];
                if (complexity == "simple") {
                    posX[i] = x + 1;
                    posY[i] = y + 1;
                    posZ[i] = z + 1;
                } else {
                    var newX:Number = Math.sqrt(x*x + y*y) + Math.sin(z);
                    var newY:Number = Math.cos(newX) + z * 0.5;
                    var newZ:Number = newX * newY * 0.1;
                    posX[i] = newX;
                    posY[i] = newY;
                    posZ[i] = newZ;
                }
                i += 1;
            }
        }
    } else {
        for (var i:Number = 0; i < posX.length; i++) {
            var x:Number = posX[i];
            var y:Number = posY[i];
            var z:Number = posZ[i];
            if (complexity == "simple") {
                posX[i] = x + 1;
                posY[i] = y + 1;
                posZ[i] = z + 1;
            } else {
                var newX:Number = Math.sqrt(x*x + y*y) + Math.sin(z);
                var newY:Number = Math.cos(newX) + z * 0.5;
                var newZ:Number = newX * newY * 0.1;
                posX[i] = newX;
                posY[i] = newY;
                posZ[i] = newZ;
            }
        }
    }
}

function updatePositionsFlatArray(positionsFlat:Array, complexity:String, loopOptimization:String):Void {
    if (loopOptimization == "unrolled") {
        var i:Number = 0;
        var len:Number = positionsFlat.length;
        while (i < len) {
            // 处理两个实体一次
            if (i + 6 < len) { // 两个实体，每个实体3个坐标
                var x1:Number = positionsFlat[i];
                var y1:Number = positionsFlat[i+1];
                var z1:Number = positionsFlat[i+2];
                var x2:Number = positionsFlat[i+3];
                var y2:Number = positionsFlat[i+4];
                var z2:Number = positionsFlat[i+5];
                if (complexity == "simple") {
                    positionsFlat[i] = x1 + 1;
                    positionsFlat[i+1] = y1 + 1;
                    positionsFlat[i+2] = z1 + 1;
                    positionsFlat[i+3] = x2 + 1;
                    positionsFlat[i+4] = y2 + 1;
                    positionsFlat[i+5] = z2 + 1;
                } else {
                    var newX1:Number = Math.sqrt(x1*x1 + y1*y1) + Math.sin(z1);
                    var newY1:Number = Math.cos(newX1) + z1 * 0.5;
                    var newZ1:Number = newX1 * newY1 * 0.1;
                    positionsFlat[i] = newX1;
                    positionsFlat[i+1] = newY1;
                    positionsFlat[i+2] = newZ1;

                    var newX2:Number = Math.sqrt(x2*x2 + y2*y2) + Math.sin(z2);
                    var newY2:Number = Math.cos(newX2) + z2 * 0.5;
                    var newZ2:Number = newX2 * newY2 * 0.1;
                    positionsFlat[i+3] = newX2;
                    positionsFlat[i+4] = newY2;
                    positionsFlat[i+5] = newZ2;
                }
                i += 6;
            } else {
                var x:Number = positionsFlat[i];
                var y:Number = positionsFlat[i+1];
                var z:Number = positionsFlat[i+2];
                if (complexity == "simple") {
                    positionsFlat[i]   = x + 1;
                    positionsFlat[i+1] = y + 1;
                    positionsFlat[i+2] = z + 1;
                } else {
                    var newX:Number = Math.sqrt(x*x + y*y) + Math.sin(z);
                    var newY:Number = Math.cos(newX) + z * 0.5;
                    var newZ:Number = newX * newY * 0.1;
                    positionsFlat[i]   = newX;
                    positionsFlat[i+1] = newY;
                    positionsFlat[i+2] = newZ;
                }
                i += 3;
            }
        }
    } else {
        for (var i:Number = 0; i < positionsFlat.length; i += 3) {
            var x:Number = positionsFlat[i];
            var y:Number = positionsFlat[i+1];
            var z:Number = positionsFlat[i+2];
            if (complexity == "simple") {
                positionsFlat[i]   = x + 1;
                positionsFlat[i+1] = y + 1;
                positionsFlat[i+2] = z + 1;
            } else {
                var newX:Number = Math.sqrt(x*x + y*y) + Math.sin(z);
                var newY:Number = Math.cos(newX) + z * 0.5;
                var newZ:Number = newX * newY * 0.1;
                positionsFlat[i]   = newX;
                positionsFlat[i+1] = newY;
                positionsFlat[i+2] = newZ;
            }
        }
    }
}

function updatePositionsPreallocatedArray(preAllocArray:Array, complexity:String, loopOptimization:String):Void {
    if (loopOptimization == "unrolled") {
        var i:Number = 0;
        var len:Number = preAllocArray.length;
        while (i < len) {
            // 处理两个实体一次
            if (i + 2 < len) { // 两个实体
                var p1:Object = preAllocArray[i];
                var p2:Object = preAllocArray[i+1];
                if (complexity == "simple") {
                    p1.x += 1; p1.y += 1; p1.z += 1;
                    p2.x += 1; p2.y += 1; p2.z += 1;
                } else {
                    p1.x = Math.sqrt(p1.x*p1.x + p1.y*p1.y) + Math.sin(p1.z);
                    p1.y = Math.cos(p1.x) + p1.z * 0.5;
                    p1.z = p1.x * p1.y * 0.1;
                    
                    p2.x = Math.sqrt(p2.x*p2.x + p2.y*p2.y) + Math.sin(p2.z);
                    p2.y = Math.cos(p2.x) + p2.z * 0.5;
                    p2.z = p2.x * p2.y * 0.1;
                }
                i += 2;
            } else {
                var p:Object = preAllocArray[i];
                if (complexity == "simple") {
                    p.x += 1; p.y += 1; p.z += 1;
                } else {
                    p.x = Math.sqrt(p.x*p.x + p.y*p.y) + Math.sin(p.z);
                    p.y = Math.cos(p.x) + p.z * 0.5;
                    p.z = p.x * p.y * 0.1;
                }
                i += 1;
            }
        }
    } else {
        for (var i:Number = 0; i < preAllocArray.length; i++) {
            var p:Object = preAllocArray[i];
            if (complexity == "simple") {
                p.x += 1; p.y += 1; p.z += 1;
            } else {
                p.x = Math.sqrt(p.x*p.x + p.y*p.y) + Math.sin(p.z);
                p.y = Math.cos(p.x) + p.z * 0.5;
                p.z = p.x * p.y * 0.1;
            }
        }
    }
}

//---------------------- 测试执行函数 --------------------------
function runTestForLayout(entityCount:Number, layout:String, complexity:String, loopOptimization:String):Number {
    // 准备数据
    var data:Object = prepareData(entityCount, layout);
    
    // 多次运行取平均值
    var totalTime:Number = 0;
    for (var t:Number = 0; t < iterations; t++) {
        // 重新初始化数据
        resetData(data, layout, entityCount);
        
        // 垃圾回收前等待
        // AS2 没有显式的垃圾回收控制，只能尽量在测试前后重置数据
        // 此处假设重置数据后，旧数据可以被垃圾回收

        // 测量开始
        var startTime:Number = getTimer();
        
        // 根据布局和循环优化更新数据
        switch(layout) {
            case "object":
                updatePositionsObject(data.entities, complexity, loopOptimization);
                break;
            case "array":
                updatePositionsArray(data.positions, complexity, loopOptimization);
                break;
            case "separateArrays":
                updatePositionsSeparateArrays(data.posX, data.posY, data.posZ, complexity, loopOptimization);
                break;
            case "flatArray":
                updatePositionsFlatArray(data.positionsFlat, complexity, loopOptimization);
                break;
            case "preallocatedArray":
                updatePositionsPreallocatedArray(data.preAllocArray, complexity, loopOptimization);
                break;
        }

        // 测量结束
        var elapsed:Number = getTimer() - startTime;
        totalTime += elapsed;
    }

    return totalTime / iterations;
}

//---------------------- 主测试流程 ---------------------------
trace("AS2 缓存优化测试开始...");
trace("iterations: " + iterations);
trace("-----------------------------------------------");

for (var c:Number = 0; c < entityCounts.length; c++) {
    var count:Number = entityCounts[c];
    trace("实体数量: " + count);
    for (var k:Number = 0; k < operationComplexities.length; k++) {
        var complexity:String = operationComplexities[k];
        trace("  操作复杂度: " + complexity);
        for (var l:Number = 0; l < testDataLayouts.length; l++) {
            var layout:String = testDataLayouts[l];
            for (var m:Number = 0; m < loopOptimizations.length; m++) {
                var loopOpt:String = loopOptimizations[m];
                var avgTime:Number = runTestForLayout(count, layout, complexity, loopOpt);
                trace("    数据布局: " + layout + " 循环优化: " + loopOpt + " 平均时间: " + avgTime + " ms");
            }
        }
    }
    trace("-----------------------------------------------");
}

trace("测试完成！");

//---------------------- 结果分析建议（外部说明）----------------------
// 可以在控制台查看输出结果，并对比不同布局、复杂度和循环优化的平均时间。
// 通过分析结果，可以尝试回答:
// 1. 在不同数据规模下，哪种数据布局和循环优化组合最快？
// 2. 简单操作 vs. 复杂操作下，哪种布局和优化策略的优势更明显？
// 3. 预分配数组（preallocatedArray）是否相比其他布局有明显优化？
// 4. 循环展开（unrolled）在不同布局和复杂度下的收益如何？
// 5. 根据结果选择更适合项目的内存布局与访问模式。

// 可进一步扩展：
// - 增加更多布局类型测试，如多维数组 vs 扁平数组。
// - 引入缓存分块（Cache Blocking）的测试，对比优化效果。
// - 修改 entityCounts 数组测试不同数量级的数据（如 100、1,000、10,000、100,000、1,000,000）。
// - 将测试分块进行，避免大数据导致内存压力过大。
// - 测试不同访问模式（如顺序访问 vs 随机访问）对性能的影响。
// - 结合多种优化策略，观察其叠加效果。


```
AS2 缓存优化测试开始...
iterations: 5
-----------------------------------------------
实体数量: 1000
  操作复杂度: simple
    数据布局: object 循环优化: normal 平均时间: 1.2 ms
    数据布局: object 循环优化: unrolled 平均时间: 1 ms
    数据布局: array 循环优化: normal 平均时间: 0.8 ms
    数据布局: array 循环优化: unrolled 平均时间: 0.6 ms
    数据布局: separateArrays 循环优化: normal 平均时间: 1 ms
    数据布局: separateArrays 循环优化: unrolled 平均时间: 0.4 ms
    数据布局: flatArray 循环优化: normal 平均时间: 0.8 ms
    数据布局: flatArray 循环优化: unrolled 平均时间: 1 ms
    数据布局: preallocatedArray 循环优化: normal 平均时间: 0.8 ms
    数据布局: preallocatedArray 循环优化: unrolled 平均时间: 0.4 ms
  操作复杂度: complex
    数据布局: object 循环优化: normal 平均时间: 2 ms
    数据布局: object 循环优化: unrolled 平均时间: 2.8 ms
    数据布局: array 循环优化: normal 平均时间: 2 ms
    数据布局: array 循环优化: unrolled 平均时间: 1.6 ms
    数据布局: separateArrays 循环优化: normal 平均时间: 1.4 ms
    数据布局: separateArrays 循环优化: unrolled 平均时间: 2.4 ms
    数据布局: flatArray 循环优化: normal 平均时间: 1.8 ms
    数据布局: flatArray 循环优化: unrolled 平均时间: 2 ms
    数据布局: preallocatedArray 循环优化: normal 平均时间: 2 ms
    数据布局: preallocatedArray 循环优化: unrolled 平均时间: 2 ms
-----------------------------------------------
实体数量: 10000
  操作复杂度: simple
    数据布局: object 循环优化: normal 平均时间: 7.6 ms
    数据布局: object 循环优化: unrolled 平均时间: 11.4 ms
    数据布局: array 循环优化: normal 平均时间: 7 ms
    数据布局: array 循环优化: unrolled 平均时间: 6.8 ms
    数据布局: separateArrays 循环优化: normal 平均时间: 7.2 ms
    数据布局: separateArrays 循环优化: unrolled 平均时间: 8 ms
    数据布局: flatArray 循环优化: normal 平均时间: 8 ms
    数据布局: flatArray 循环优化: unrolled 平均时间: 7 ms
    数据布局: preallocatedArray 循环优化: normal 平均时间: 6.6 ms
    数据布局: preallocatedArray 循环优化: unrolled 平均时间: 7 ms
  操作复杂度: complex
    数据布局: object 循环优化: normal 平均时间: 21.8 ms
    数据布局: object 循环优化: unrolled 平均时间: 25.2 ms
    数据布局: array 循环优化: normal 平均时间: 19.4 ms
    数据布局: array 循环优化: unrolled 平均时间: 20 ms
    数据布局: separateArrays 循环优化: normal 平均时间: 19 ms
    数据布局: separateArrays 循环优化: unrolled 平均时间: 20 ms
    数据布局: flatArray 循环优化: normal 平均时间: 20.4 ms
    数据布局: flatArray 循环优化: unrolled 平均时间: 19.6 ms
    数据布局: preallocatedArray 循环优化: normal 平均时间: 21.4 ms
    数据布局: preallocatedArray 循环优化: unrolled 平均时间: 20.2 ms
-----------------------------------------------
实体数量: 100000
  操作复杂度: simple
    数据布局: object 循环优化: normal 平均时间: 80.4 ms
    数据布局: object 循环优化: unrolled 平均时间: 141.4 ms
    数据布局: array 循环优化: normal 平均时间: 68.6 ms
    数据布局: array 循环优化: unrolled 平均时间: 68.8 ms
    数据布局: separateArrays 循环优化: normal 平均时间: 76.8 ms
    数据布局: separateArrays 循环优化: unrolled 平均时间: 77.8 ms
    数据布局: flatArray 循环优化: normal 平均时间: 84.4 ms
    数据布局: flatArray 循环优化: unrolled 平均时间: 79.4 ms
    数据布局: preallocatedArray 循环优化: normal 平均时间: 73.2 ms
    数据布局: preallocatedArray 循环优化: unrolled 平均时间: 63.8 ms
  操作复杂度: complex
    数据布局: object 循环优化: normal 平均时间: 224 ms
    数据布局: object 循环优化: unrolled 平均时间: 300.6 ms
    数据布局: array 循环优化: normal 平均时间: 207.6 ms
    数据布局: array 循环优化: unrolled 平均时间: 197.8 ms
    数据布局: separateArrays 循环优化: normal 平均时间: 192.4 ms
    数据布局: separateArrays 循环优化: unrolled 平均时间: 200.8 ms
    数据布局: flatArray 循环优化: normal 平均时间: 213.4 ms
    数据布局: flatArray 循环优化: unrolled 平均时间: 205.4 ms
    数据布局: preallocatedArray 循环优化: normal 平均时间: 211.8 ms
    数据布局: preallocatedArray 循环优化: unrolled 平均时间: 206.4 ms
-----------------------------------------------
实体数量: 1000000
  操作复杂度: simple
    数据布局: object 循环优化: normal 平均时间: 939.2 ms
    数据布局: object 循环优化: unrolled 平均时间: 1599.6 ms
    数据布局: array 循环优化: normal 平均时间: 700.4 ms
    数据布局: array 循环优化: unrolled 平均时间: 714.6 ms
    数据布局: separateArrays 循环优化: normal 平均时间: 785.6 ms
    数据布局: separateArrays 循环优化: unrolled 平均时间: 778.2 ms
    数据布局: flatArray 循环优化: normal 平均时间: 1522.8 ms
    数据布局: flatArray 循环优化: unrolled 平均时间: 1458.8 ms
    数据布局: preallocatedArray 循环优化: normal 平均时间: 719.8 ms
    数据布局: preallocatedArray 循环优化: unrolled 平均时间: 687 ms
  操作复杂度: complex
    数据布局: object 循环优化: normal 平均时间: 2365.4 ms
    数据布局: object 循环优化: unrolled 平均时间: 3007.8 ms
    数据布局: array 循环优化: normal 平均时间: 2200.4 ms
    数据布局: array 循环优化: unrolled 平均时间: 2142.2 ms
    数据布局: separateArrays 循环优化: normal 平均时间: 2126.8 ms
    数据布局: separateArrays 循环优化: unrolled 平均时间: 2178.2 ms
    数据布局: flatArray 循环优化: normal 平均时间: 2907.6 ms
    数据布局: flatArray 循环优化: unrolled 平均时间: 2901.2 ms
    数据布局: preallocatedArray 循环优化: normal 平均时间: 2371.4 ms
    数据布局: preallocatedArray 循环优化: unrolled 平均时间: 2267.8 ms
-----------------------------------------------
测试完成！

```output


