# **ActionScript 2 虚拟机性能优化实验报告**

---

## **一、引言**

### **1.1 背景与意义**

ActionScript 2（AS2）是一种基于堆栈式虚拟机的脚本语言，以操作数堆栈为核心，通过一系列指令操作堆栈，实现程序的执行。AS2 的特性，如动态类型、作用域链、变量提升等，都对虚拟机的性能有着深刻影响。通过对这些特性的深入分析，可以找到优化代码的有效策略，从而提高 AS2 应用的运行效率。

### **1.2 实验目的**

本实验旨在：

1. **深入分析 AS2 虚拟机的性能特性**，揭示影响性能的核心因素。
2. **通过实验验证堆栈操作、堆栈深度、指令复杂度、数组访问、作用域管理等对性能的影响**。
3. **基于堆栈式虚拟机的实现原理，提出有针对性的代码优化建议**，帮助开发者编写高效代码。

---

## **二、实验设计与方法**

### **2.1 实验方案概述**

根据 AS2 虚拟机的特性，设计了以下 10 个实验方案：

1. **评估额外堆栈操作的成本**：比较最少堆栈操作与额外堆栈操作的性能差异。
2. **评估堆栈深度对性能的影响**：分析浅堆栈深度与深堆栈深度对性能的影响。
3. **评估堆栈操作指令的性能**：比较简单堆栈指令与复杂堆栈指令的性能。
4. **评估 `[]` 解引用操作的性能**：测试数组简单访问与在索引中使用副作用操作的性能差异。
5. **评估在 `[]` 中嵌入副作用操作的优化效果**：比较分离副作用操作与嵌入副作用操作的性能。
6. **复杂表达式和数组操作的结合**：分析传统方式与优化方式的复杂操作性能。
7. **全局变量与局部变量的访问性能**：比较访问全局变量与局部变量的性能。
8. **深层嵌套作用域对变量访问性能的影响**：评估浅层作用域访问与深层作用域访问的性能差异。
9. **变量提升的性能影响**：比较使用 `var` 声明变量与不使用 `var` 声明变量的性能。
10. **作用域链长度对变量访问性能的影响**：分析不同作用域链长度对变量访问性能的影响。

### **2.2 实验环境**

- **编程语言**：ActionScript 2
- **运行环境**：Adobe Flash Player 及支持 AS2 的开发环境
- **硬件环境**：标准 PC，确保实验结果的稳定性
- **测试工具**：使用 AS2 的 `getTimer()` 函数精确测量执行时间
- **实验次数**：每个测试用例执行 **100,000** 次，取平均值以消除偶然误差

### **2.3 实验方法**

1. **代码实现**：为每个实验方案编写对应的测试代码，确保代码简洁、可控，避免其他因素干扰。
2. **数据收集**：运行测试代码，记录每个用例的执行时间，累加并计算平均值。
3. **数据分析**：根据实验数据，结合 AS2 虚拟机的底层实现原理，深入分析不同因素对性能的影响程度。
4. **提出优化策略**：基于分析结果，提出针对性的性能优化建议。

---

## **三、实验结果与分析**

### **3.1 实验结果汇总**

以下是各测试方案的平均执行时间：

#### **测试方案 1：评估额外堆栈操作的成本**

- **案例 A - 最少堆栈操作**：0.00658 ms
- **案例 B - 额外的堆栈操作**：0.00569 ms

#### **测试方案 2：评估堆栈深度对性能的影响**

- **案例 A - 浅堆栈深度**：0.00512 ms
- **案例 B - 深堆栈深度**：0.01269 ms

#### **测试方案 3：评估堆栈操作指令的性能**

- **案例 A - 使用简单堆栈指令**：0.00513 ms
- **案例 B - 使用复杂堆栈指令**：0.00714 ms

#### **测试方案 4：评估 `[]` 解引用操作的性能**

- **案例 A - 简单的数组访问**：0.00987 ms
- **案例 B - 索引中使用副作用操作**：0.01039 ms

#### **测试方案 5：评估在 `[]` 中嵌入副作用操作的优化效果**

- **案例 A - 分离的副作用操作**：0.00790 ms
- **案例 B - 嵌入的副作用操作**：0.00766 ms

#### **测试方案 6：复杂表达式和数组操作的结合**

- **案例 A - 传统方式的复杂操作**：0.00740 ms
- **案例 B - 优化的复杂操作**：0.00752 ms

#### **测试方案 7：全局变量与局部变量的访问性能**

- **案例 A - 访问全局变量**：0.01193 ms
- **案例 B - 访问局部变量**：0.00505 ms

#### **测试方案 8：深层嵌套作用域对变量访问性能的影响**

- **案例 A - 浅层作用域访问**：0.00490 ms
- **案例 B - 深层作用域访问**：0.02682 ms

#### **测试方案 9：变量提升的性能影响**

- **案例 A - 使用 `var` 声明变量**：0.00466 ms
- **案例 B - 不使用 `var` 声明变量**：0.01058 ms

#### **测试方案 10：作用域链长度对变量访问性能的影响**

- **案例 A - 作用域链长度为 2**：0.01900 ms
- **案例 B - 作用域链长度为 5**：0.04029 ms

### **3.2 实验结果分析**

#### **3.2.1 堆栈操作的成本分析**

**现象**：

- **案例 B**（额外的堆栈操作）的性能略优于**案例 A**（最少堆栈操作），性能提升约 **13.5%**。

**分析**：

- **指令优化**：堆栈式虚拟机可能对分离的简单指令进行了优化，将多个简单操作合并，减少了指令调度和堆栈操作的开销。
- **自增操作的开销**：`b++` 操作需要先读取 `b` 的值，再进行加一，最后存储，涉及更多的堆栈操作和临时变量。
- **流水线效应**：分离的操作可能更符合虚拟机的指令流水线，减少了指令间的依赖，提高了执行效率。

**结论**：

- 在 AS2 中，分解复杂操作为简单指令有助于提高性能。

**优化建议**：

- **分解复杂操作**：将复杂的表达式拆解为简单的操作，减少堆栈操作次数。
- **避免使用自增/自减**：在性能敏感的简单逻辑区域，尽量避免使用 `b++`、`b--` 等自增/自减操作，改用 `b = b + 1`。

---

#### **3.2.2 堆栈深度对性能的影响**

**现象**：

- **案例 B**（深堆栈深度）的性能比**案例 A**（浅堆栈深度）差约 **147.9%**。

**分析**：

- **堆栈帧开销**：每次函数调用都会创建新的堆栈帧，保存局部变量、返回地址等信息，增加了内存分配和管理的开销。
- **函数调用开销**：深层函数调用增加了指令跳转和返回的次数，增加了指令执行时间。
- **缓存局部性降低**：深层嵌套可能导致局部变量在内存中的位置分散，降低了缓存命中率，增加了内存访问时间。

**结论**：

- 堆栈深度对性能有显著影响，应尽量避免深层函数嵌套。

**优化建议**：

- **减少函数嵌套层次**：优化代码结构，尽可能将深层嵌套的函数展开或合并。
- **使用迭代替代递归**：在可能的情况下，将递归调用转换为迭代，以减少堆栈深度。

---

#### **3.2.3 堆栈操作指令的性能分析**

**现象**：

- **案例 B**（使用复杂堆栈指令）的性能比**案例 A**（使用简单堆栈指令）差约 **39.2%**。

**分析**：

- **指令复杂度增加**：复杂的表达式需要更多的堆栈操作，包括多个 `push` 和 `pop`，增加了指令执行时间。
- **中间结果的存储**：复杂指令生成的中间结果需要在堆栈中保存，增加了堆栈的压力和内存访问次数。
- **指令解码开销**：复杂指令可能增加了虚拟机的指令解码和执行开销。

**结论**：

- 简单的堆栈指令更易于虚拟机优化，执行效率更高。

**优化建议**：

- **简化表达式**：将复杂的表达式拆分为多个简单的操作，减少堆栈操作和中间结果的存储。
- **使用局部变量**：存储中间结果，减少对堆栈的依赖。

---

#### **3.2.4 数组访问的性能评估**

**现象**：

- **案例 B**（索引中使用副作用操作）的性能比**案例 A**（简单的数组访问）差约 **5.3%**。

**分析**：

- **索引计算的额外开销**：在数组索引中使用副作用操作（如 `++index`）增加了计算复杂度，需要更多的指令和堆栈操作。
- **动态解析**：虚拟机需要在运行时解析复杂的索引表达式，增加了解析时间。

**结论**：

- 在数组索引中使用副作用操作会降低性能，应尽量避免。

**优化建议**：

- **提前计算索引值**：在数组访问之前，先计算并存储索引值，避免在索引中进行复杂操作。
- **避免副作用操作**：简单业务环境下，尽量避免在数组索引中使用自增、自减等副作用操作。

---

#### **3.2.5 在 `[]` 中嵌入副作用操作的优化效果**

**现象**：

- **案例 B**（嵌入的副作用操作）的性能略优于**案例 A**（分离的副作用操作），性能提升约 **3%**。

**分析**：

- **指令合并**：将副作用操作嵌入索引中，可能减少了指令数量和堆栈操作次数。
- **减少变量访问**：嵌入操作可能减少了对变量的多次访问，提高了局部性。

**结论**：

- 在某些情况下，嵌入副作用操作可以略微提高性能。

**优化建议**：

- **谨慎使用嵌入操作**：在性能提升有限的情况下，应优先考虑代码的可读性和可维护性。
- **权衡利弊**：在确定嵌入操作确实带来性能提升的前提下，再进行优化。

---

#### **3.2.6 复杂表达式和数组操作的结合**

**现象**：

- **案例 B**（优化的复杂操作）的性能比**案例 A**（传统方式的复杂操作）略差，性能下降约 **1.6%**。

**分析**：

- **表达式复杂度增加**：优化方式可能增加了表达式的复杂度，导致虚拟机需要更多的指令和堆栈操作。
- **优化效果有限**：对于复杂操作，优化的方式未能显著减少指令数量，反而可能增加了解析和执行开销。

**结论**：

- 复杂表达式的优化需要谨慎，未必能带来性能提升。

**优化建议**：

- **保持代码简洁**：优先采用简单、直观的实现方式，避免过度优化。
- **实际测试验证**：在优化前，进行测试验证，确保优化确实有效。

---

#### **3.2.7 全局变量与局部变量的访问性能**

**现象**：

- **案例 A**（访问全局变量）的性能比**案例 B**（访问局部变量）差约 **136.3%**。

**分析**：

- **作用域链查找**：访问全局变量需要遍历整个作用域链，增加了查找时间。
- **命名空间冲突**：全局命名空间可能存在大量变量，增加了查找的复杂度。

**结论**：

- 使用局部变量可以显著提高变量访问的性能。

**优化建议**：

- **优先使用局部变量**：在函数内部定义和使用变量，避免全局变量的性能开销。
- **缓存全局变量**：如果必须使用全局变量，可在局部作用域中缓存其引用。

---

#### **3.2.8 深层嵌套作用域对变量访问性能的影响**

**现象**：

- **案例 B**（深层作用域访问）的性能比**案例 A**（浅层作用域访问）差约 **447%**。

**分析**：

- **作用域链长度**：深层嵌套增加了作用域链的长度，变量查找需要更多的时间。
- **函数调用开销**：深层嵌套的函数调用也增加了指令执行时间。

**结论**：

- 深层嵌套的作用域对变量访问性能有显著影响，应尽量避免。

**优化建议**：

- **减少嵌套层次**：优化代码结构，减少不必要的函数嵌套。
- **提升变量作用域**：将频繁访问的变量提升到较浅的作用域。

---

#### **3.2.9 变量提升的性能影响**

**现象**：

- **案例 B**（不使用 `var` 声明变量）的性能比**案例 A**（使用 `var` 声明变量）差约 **127%**。

**分析**：

- **隐式全局变量**：未使用 `var` 声明的变量会被提升为全局变量，增加了作用域链查找时间。
- **内存管理问题**：隐式全局变量可能导致内存泄漏和命名冲突。

**结论**：

- 始终使用 `var` 声明变量，有助于提高性能并避免潜在问题。

**优化建议**：

- **严格遵守变量声明规范**：始终使用 `var` 声明变量，避免隐式全局变量。
- **代码检查**：使用工具或严格模式，防止遗漏变量声明。

---

#### **3.2.10 作用域链长度对变量访问性能的影响**

**现象**：

- **案例 B**（作用域链长度为 5）的性能比**案例 A**（作用域链长度为 2）差约 **112%**。

**分析**：

- **作用域链遍历**：更长的作用域链需要更多的时间来查找变量。
- **命名冲突风险**：更长的作用域链可能增加命名冲突的风险，影响查找效率。

**结论**：

- 作用域链长度对变量访问性能有显著影响，应尽量减少作用域链的长度。

**优化建议**：

- **优化作用域结构**：减少不必要的函数嵌套，简化作用域层次。
- **就近使用变量**：在需要的最小作用域内定义和使用变量。

---

## **四、基于底层实现特性的优化策略**

### **4.1 理解 AS2 虚拟机的堆栈机制**

- **堆栈操作成本**：频繁的堆栈读写会增加指令执行时间，应尽量减少不必要的堆栈操作。
- **堆栈深度管理**：深层的函数调用会增加堆栈帧的创建和销毁开销，影响性能。

### **4.2 作用域管理与变量使用**

- **作用域链查找**：变量查找依赖于作用域链，链越长，查找耗时越多。
- **变量提升的影响**：未声明的变量会被提升为全局变量，增加作用域链查找时间。

### **4.3 指令优化**

- **指令复杂度**：复杂指令需要更多的解码和执行时间，应尽量使用简单指令。
- **表达式优化**：分解复杂表达式，减少堆栈操作和中间结果的存储。

### **4.4 数组与对象的访问**

- **数组索引优化**：避免在数组索引中使用副作用操作，提前计算索引值。
- **简化访问路径**：使用简单的属性访问方式，减少动态解析的开销。

---

## **五、结论与展望**

### **5.1 实验结论**

通过本次实验，我们发现：

- **堆栈操作和堆栈深度**对 AS2 虚拟机的性能有显著影响，需优化堆栈使用。
- **作用域管理**是影响性能的关键因素，应优化作用域链和变量声明。
- **指令复杂度和数组访问方式**会直接影响指令执行效率，需要谨慎处理。

### **5.2 性能优化建议**

- **简化指令和表达式**：分解复杂操作，使用简单指令，提高指令执行效率。
- **优化堆栈使用**：减少堆栈深度和不必要的堆栈操作。
- **严格变量声明**：始终使用 `var` 声明变量，避免隐式全局变量。
- **控制作用域链长度**：优化代码结构，减少函数嵌套层次。
- **优化数组访问**：提前计算索引值，避免在索引中使用副作用操作。

### **5.3 未来工作**

- **深入研究内存管理机制**：如垃圾回收和对象分配对性能的影响。
- **评估高级特性的性能**：如闭包、高阶函数等对性能的影响。
- **实践应用**：将优化策略应用于实际项目，验证其有效性和可行性。

---

## **六、参考文献**

1. **ActionScript 2.0 语言参考手册**，Adobe Systems。
2. **堆栈式虚拟机原理与实现**，深入理解堆栈式虚拟机的工作机制。
3. **编译原理与程序优化**，指导代码优化的通用原则和方法。

---

**附录：实验代码**

// AS2 完整性能测试脚本

// 获取当前时间的函数
function getCurrentTime():Number {
    return getTimer();
}

// ================================
// 测试方案 1：评估额外堆栈操作的成本
// ================================

// 案例 A：最少堆栈操作
function testMinimalStackOps() {
    var a:Number = 0;
    var b:Number = 0;
    // 展开操作，避免循环开销
    a = b++;
    a = b++;
    a = b++;
    a = b++;
    a = b++;
    a = b++;
    a = b++;
    a = b++;
    a = b++;
    a = b++;
    a = b++;
    a = b++;
    a = b++;
    a = b++;
    a = b++;
    a = b++;
    a = b++;
    a = b++;
    a = b++;
    a = b++;
}

// 案例 B：额外的堆栈操作
function testExtraStackOps() {
    var a:Number = 0;
    var b:Number = 0;
    // 展开操作，避免循环开销
    a = b;
    b = b + 1;
    a = b;
    b = b + 1;
    a = b;
    b = b + 1;
    a = b;
    b = b + 1;
    a = b;
    b = b + 1;
    a = b;
    b = b + 1;
    a = b;
    b = b + 1;
    a = b;
    b = b + 1;
    a = b;
    b = b + 1;
    a = b;
    b = b + 1;
    a = b;
    b = b + 1;
}

// ================================
// 测试方案 2：评估堆栈深度对性能的影响
// ================================

// 案例 A：浅堆栈深度
function shallowStack() {
    var a:Number = 0;
    var b:Number = 0;
    // 展开操作，避免循环开销
    a = b + 1;
    b = a + 1;
    a = b + 1;
    b = a + 1;
    a = b + 1;
    b = a + 1;
    a = b + 1;
    b = a + 1;
    a = b + 1;
    b = a + 1;
}

// 案例 B：深堆栈深度
function deepStackLevel1() {
    deepStackLevel2();
}

function deepStackLevel2() {
    deepStackLevel3();
}

function deepStackLevel3() {
    deepStackLevel4();
}

function deepStackLevel4() {
    var a:Number = 0;
    var b:Number = 0;
    // 展开操作，避免循环开销
    a = b + 1;
    b = a + 1;
    a = b + 1;
    b = a + 1;
    a = b + 1;
    b = a + 1;
    a = b + 1;
    b = a + 1;
    a = b + 1;
    b = a + 1;
}

// ================================
// 测试方案 3：评估堆栈操作指令的性能
// ================================

// 案例 A：使用简单堆栈指令
function testSimpleStackOps() {
    var a:Number = 0;
    var b:Number = 0;
    // 展开操作，避免循环开销
    a = b + 1;
    b = a + 1;
    a = b + 1;
    b = a + 1;
    a = b + 1;
    b = a + 1;
    a = b + 1;
    b = a + 1;
    a = b + 1;
    b = a + 1;
}

// 案例 B：使用复杂堆栈指令
function testComplexStackOps() {
    var a:Number = 0;
    var b:Number = 0;
    // 展开操作，避免循环开销
    a = ((b + 1) * 2) - (b + 1);
    b = ((a + 1) * 2) - (a + 1);
    a = ((b + 1) * 2) - (b + 1);
    b = ((a + 1) * 2) - (a + 1);
    a = ((b + 1) * 2) - (b + 1);
    b = ((a + 1) * 2) - (a + 1);
    a = ((b + 1) * 2) - (b + 1);
    b = ((a + 1) * 2) - (a + 1);
    a = ((b + 1) * 2) - (b + 1);
    b = ((a + 1) * 2) - (a + 1);
}

// ================================
// 测试方案 4：评估 `[]` 解引用操作的性能
// ================================

// 案例 A：简单的数组访问
function testSimpleArrayAccess() {
    var array:Array = [];
    var value:Number = 0;
    // 展开操作，避免循环开销
    array[0] = value;
    array[1] = value;
    array[2] = value;
    array[3] = value;
    array[4] = value;
    array[5] = value;
    array[6] = value;
    array[7] = value;
    array[8] = value;
    array[9] = value;
}

// 案例 B：在索引中使用副作用操作
function testArrayAccessWithSideEffect() {
    var array:Array = [];
    var index:Number = 0;
    var value:Number = 0;
    // 展开操作，避免循环开销
    array[++index] = value;
    array[++index] = value;
    array[++index] = value;
    array[++index] = value;
    array[++index] = value;
    array[++index] = value;
    array[++index] = value;
    array[++index] = value;
    array[++index] = value;
    array[++index] = value;
}

// ================================
// 测试方案 5：评估在 `[]` 中嵌入副作用操作的优化效果
// ================================

// 案例 A：分离的副作用操作
function testSeparatedSideEffects() {
    var array:Array = [];
    var index:Number = 0;
    var value:Number = 0;
    // 展开操作，避免循环开销
    index = index + 1;
    array[index] = value;
    index = index + 1;
    array[index] = value;
    index = index + 1;
    array[index] = value;
    index = index + 1;
    array[index] = value;
    index = index + 1;
    array[index] = value;
}

// 案例 B：将副作用操作嵌入到 `[]` 索引中
function testEmbeddedSideEffects() {
    var array:Array = [];
    var index:Number = 0;
    var value:Number = 0;
    // 展开操作，避免循环开销
    array[index = index + 1] = value;
    array[index = index + 1] = value;
    array[index = index + 1] = value;
    array[index = index + 1] = value;
    array[index = index + 1] = value;
}

// ================================
// 测试方案 6：复杂表达式和数组操作的结合
// ================================

// 案例 A：传统方式的复杂操作
function testComplexArrayOperations() {
    var array:Array = [];
    var a:Number = 0;
    var b:Number = 0;
    // 展开操作，避免循环开销
    a = b + 1;
    array[a] = b;
    b = a + 1;
    array[b] = a;
    a = b + 1;
    array[a] = b;
    b = a + 1;
    array[b] = a;
}

// 案例 B：利用 `[]` 索引优化的复杂操作
function testOptimizedArrayOperations() {
    var array:Array = [];
    var a:Number = 0;
    var b:Number = 0;
    // 展开操作，避免循环开销
    array[a = b + 1] = b;
    array[b = a + 1] = a;
    array[a = b + 1] = b;
    array[b = a + 1] = a;
}

// ================================
// 测试方案 7：全局变量与局部变量的访问性能
// ================================

// 全局变量
var globalVar:Number = 0;

function testGlobalVariableAccess() {
    // 展开操作，避免循环开销
    globalVar = globalVar + 1;
    globalVar = globalVar + 1;
    globalVar = globalVar + 1;
    globalVar = globalVar + 1;
    globalVar = globalVar + 1;
    globalVar = globalVar + 1;
    globalVar = globalVar + 1;
    globalVar = globalVar + 1;
    globalVar = globalVar + 1;
    globalVar = globalVar + 1;
}

function testLocalVariableAccess() {
    var localVar:Number = 0;
    // 展开操作，避免循环开销
    localVar = localVar + 1;
    localVar = localVar + 1;
    localVar = localVar + 1;
    localVar = localVar + 1;
    localVar = localVar + 1;
    localVar = localVar + 1;
    localVar = localVar + 1;
    localVar = localVar + 1;
    localVar = localVar + 1;
    localVar = localVar + 1;
}

// ================================
// 测试方案 8：深层嵌套作用域对变量访问性能的影响
// ================================

function testShallowScopeAccess() {
    var a:Number = 0;
    // 展开操作，避免循环开销
    a = a + 1;
    a = a + 1;
    a = a + 1;
    a = a + 1;
    a = a + 1;
    a = a + 1;
    a = a + 1;
    a = a + 1;
    a = a + 1;
    a = a + 1;
}

function testDeepScopeAccess() {
    function outerFunction() {
        var outerVar:Number = 0;

        function middleFunction() {
            var middleVar:Number = 0;

            function innerFunction() {
                var innerVar:Number = 0;
                // 展开操作，避免循环开销
                innerVar = innerVar + 1;
                innerVar = innerVar + 1;
                innerVar = innerVar + 1;
                innerVar = innerVar + 1;
                innerVar = innerVar + 1;
                innerVar = innerVar + 1;
                innerVar = innerVar + 1;
                innerVar = innerVar + 1;
                innerVar = innerVar + 1;
                innerVar = innerVar + 1;
            }

            innerFunction();
        }

        middleFunction();
    }

    outerFunction();
}

// ================================
// 测试方案 9：变量提升的性能影响
// ================================

function testVarDeclaration() {
    // 展开操作，避免循环开销
    var a:Number = 0;
    a = a + 1;
    var b:Number = 0;
    b = b + 1;
    var c:Number = 0;
    c = c + 1;
    var d:Number = 0;
    d = d + 1;
    var e:Number = 0;
    e = e + 1;
}

function testNoVarDeclaration() {
    // 展开操作，避免循环开销
    a = 0;
    a = a + 1;
    b = 0;
    b = b + 1;
    c = 0;
    c = c + 1;
    d = 0;
    d = d + 1;
    e = 0;
    e = e + 1;
}

// ================================
// 测试方案 10：作用域链长度对变量访问性能的影响
// ================================

function testScopeChainLength2() {
    function level1() {
        var var1:Number = 1;

        function level2() {
            var var2:Number = 2;
            // 访问 level1 的变量
            var temp:Number = var1;
            // 展开操作
            temp = temp + 1;
            temp = temp + 1;
            temp = temp + 1;
            temp = temp + 1;
            temp = temp + 1;
        }

        level2();
    }

    level1();
}

function testScopeChainLength5() {
    function level1() {
        var var1:Number = 1;

        function level2() {
            var var2:Number = 2;

            function level3() {
                var var3:Number = 3;

                function level4() {
                    var var4:Number = 4;

                    function level5() {
                        var var5:Number = 5;
                        // 访问 level1 的变量
                        var temp:Number = var1;
                        // 展开操作
                        temp = temp + 1;
                        temp = temp + 1;
                        temp = temp + 1;
                        temp = temp + 1;
                        temp = temp + 1;
                    }

                    level5();
                }

                level4();
            }

            level3();
        }

        level2();
    }

    level1();
}

// ================================
// 测试执行和结果记录
// ================================

// 测试次数
var testRuns:Number = 100000;

// 存储测试结果
var results:Object = {
    // 测试方案 1
    testMinimalStackOps: 0,
    testExtraStackOps: 0,

    // 测试方案 2
    shallowStack: 0,
    deepStack: 0,

    // 测试方案 3
    testSimpleStackOps: 0,
    testComplexStackOps: 0,

    // 测试方案 4
    testSimpleArrayAccess: 0,
    testArrayAccessWithSideEffect: 0,

    // 测试方案 5
    testSeparatedSideEffects: 0,
    testEmbeddedSideEffects: 0,

    // 测试方案 6
    testComplexArrayOperations: 0,
    testOptimizedArrayOperations: 0,

    // 测试方案 7
    testGlobalVariableAccess: 0,
    testLocalVariableAccess: 0,

    // 测试方案 8
    testShallowScopeAccess: 0,
    testDeepScopeAccess: 0,

    // 测试方案 9
    testVarDeclaration: 0,
    testNoVarDeclaration: 0,

    // 测试方案 10
    testScopeChainLength2: 0,
    testScopeChainLength5: 0
};

// 测试运行次数
for (var run:Number = 0; run < testRuns; run++) {
    // 测试方案 1
    var startTime:Number = getCurrentTime();
    testMinimalStackOps();
    var endTime:Number = getCurrentTime();
    results.testMinimalStackOps += (endTime - startTime);

    startTime = getCurrentTime();
    testExtraStackOps();
    endTime = getCurrentTime();
    results.testExtraStackOps += (endTime - startTime);

    // 测试方案 2
    startTime = getCurrentTime();
    shallowStack();
    endTime = getCurrentTime();
    results.shallowStack += (endTime - startTime);

    startTime = getCurrentTime();
    deepStackLevel1();
    endTime = getCurrentTime();
    results.deepStack += (endTime - startTime);

    // 测试方案 3
    startTime = getCurrentTime();
    testSimpleStackOps();
    endTime = getCurrentTime();
    results.testSimpleStackOps += (endTime - startTime);

    startTime = getCurrentTime();
    testComplexStackOps();
    endTime = getCurrentTime();
    results.testComplexStackOps += (endTime - startTime);

    // 测试方案 4
    startTime = getCurrentTime();
    testSimpleArrayAccess();
    endTime = getCurrentTime();
    results.testSimpleArrayAccess += (endTime - startTime);

    startTime = getCurrentTime();
    testArrayAccessWithSideEffect();
    endTime = getCurrentTime();
    results.testArrayAccessWithSideEffect += (endTime - startTime);

    // 测试方案 5
    startTime = getCurrentTime();
    testSeparatedSideEffects();
    endTime = getCurrentTime();
    results.testSeparatedSideEffects += (endTime - startTime);

    startTime = getCurrentTime();
    testEmbeddedSideEffects();
    endTime = getCurrentTime();
    results.testEmbeddedSideEffects += (endTime - startTime);

    // 测试方案 6
    startTime = getCurrentTime();
    testComplexArrayOperations();
    endTime = getCurrentTime();
    results.testComplexArrayOperations += (endTime - startTime);

    startTime = getCurrentTime();
    testOptimizedArrayOperations();
    endTime = getCurrentTime();
    results.testOptimizedArrayOperations += (endTime - startTime);

    // 测试方案 7
    startTime = getCurrentTime();
    testGlobalVariableAccess();
    endTime = getCurrentTime();
    results.testGlobalVariableAccess += (endTime - startTime);

    startTime = getCurrentTime();
    testLocalVariableAccess();
    endTime = getCurrentTime();
    results.testLocalVariableAccess += (endTime - startTime);

    // 测试方案 8
    startTime = getCurrentTime();
    testShallowScopeAccess();
    endTime = getCurrentTime();
    results.testShallowScopeAccess += (endTime - startTime);

    startTime = getCurrentTime();
    testDeepScopeAccess();
    endTime = getCurrentTime();
    results.testDeepScopeAccess += (endTime - startTime);

    // 测试方案 9
    startTime = getCurrentTime();
    testVarDeclaration();
    endTime = getCurrentTime();
    results.testVarDeclaration += (endTime - startTime);

    startTime = getCurrentTime();
    testNoVarDeclaration();
    endTime = getCurrentTime();
    results.testNoVarDeclaration += (endTime - startTime);

    // 测试方案 10
    startTime = getCurrentTime();
    testScopeChainLength2();
    endTime = getCurrentTime();
    results.testScopeChainLength2 += (endTime - startTime);

    startTime = getCurrentTime();
    testScopeChainLength5();
    endTime = getCurrentTime();
    results.testScopeChainLength5 += (endTime - startTime);
}

// 计算平均时间
for (var key:String in results) {
    results[key] = results[key] / testRuns;
}

// 输出测试结果
trace("=== AS2 虚拟机性能测试结果 ===");
trace("测试次数: " + testRuns);
trace("-----------------------------------");

// 测试方案 1
trace("测试方案 1：评估额外堆栈操作的成本");
trace("  案例 A - 最少堆栈操作: " + results.testMinimalStackOps + " ms");
trace("  案例 B - 额外的堆栈操作: " + results.testExtraStackOps + " ms");
trace("-----------------------------------");

// 测试方案 2
trace("测试方案 2：评估堆栈深度对性能的影响");
trace("  案例 A - 浅堆栈深度: " + results.shallowStack + " ms");
trace("  案例 B - 深堆栈深度: " + results.deepStack + " ms");
trace("-----------------------------------");

// 测试方案 3
trace("测试方案 3：评估堆栈操作指令的性能");
trace("  案例 A - 使用简单堆栈指令: " + results.testSimpleStackOps + " ms");
trace("  案例 B - 使用复杂堆栈指令: " + results.testComplexStackOps + " ms");
trace("-----------------------------------");

// 测试方案 4
trace("测试方案 4：评估 `[]` 解引用操作的性能");
trace("  案例 A - 简单的数组访问: " + results.testSimpleArrayAccess + " ms");
trace("  案例 B - 索引中使用副作用操作: " + results.testArrayAccessWithSideEffect + " ms");
trace("-----------------------------------");

// 测试方案 5
trace("测试方案 5：评估在 `[]` 中嵌入副作用操作的优化效果");
trace("  案例 A - 分离的副作用操作: " + results.testSeparatedSideEffects + " ms");
trace("  案例 B - 嵌入的副作用操作: " + results.testEmbeddedSideEffects + " ms");
trace("-----------------------------------");

// 测试方案 6
trace("测试方案 6：复杂表达式和数组操作的结合");
trace("  案例 A - 传统方式的复杂操作: " + results.testComplexArrayOperations + " ms");
trace("  案例 B - 优化的复杂操作: " + results.testOptimizedArrayOperations + " ms");
trace("-----------------------------------");

// 测试方案 7
trace("测试方案 7：全局变量与局部变量的访问性能");
trace("  案例 A - 访问全局变量: " + results.testGlobalVariableAccess + " ms");
trace("  案例 B - 访问局部变量: " + results.testLocalVariableAccess + " ms");
trace("-----------------------------------");

// 测试方案 8
trace("测试方案 8：深层嵌套作用域对变量访问性能的影响");
trace("  案例 A - 浅层作用域访问: " + results.testShallowScopeAccess + " ms");
trace("  案例 B - 深层作用域访问: " + results.testDeepScopeAccess + " ms");
trace("-----------------------------------");

// 测试方案 9
trace("测试方案 9：变量提升的性能影响");
trace("  案例 A - 使用 var 声明变量: " + results.testVarDeclaration + " ms");
trace("  案例 B - 不使用 var 声明变量: " + results.testNoVarDeclaration + " ms");
trace("-----------------------------------");

// 测试方案 10
trace("测试方案 10：作用域链长度对变量访问性能的影响");
trace("  案例 A - 作用域链长度为 2: " + results.testScopeChainLength2 + " ms");
trace("  案例 B - 作用域链长度为 5: " + results.testScopeChainLength5 + " ms");
trace("===================================");

---

=== AS2 虚拟机性能测试结果 ===
测试次数: 100000
-----------------------------------
测试方案 1：评估额外堆栈操作的成本
  案例 A - 最少堆栈操作: 0.00658 ms
  案例 B - 额外的堆栈操作: 0.00569 ms
-----------------------------------
测试方案 2：评估堆栈深度对性能的影响
  案例 A - 浅堆栈深度: 0.00512 ms
  案例 B - 深堆栈深度: 0.01269 ms
-----------------------------------
测试方案 3：评估堆栈操作指令的性能
  案例 A - 使用简单堆栈指令: 0.00513 ms
  案例 B - 使用复杂堆栈指令: 0.00714 ms
-----------------------------------
测试方案 4：评估 `[]` 解引用操作的性能
  案例 A - 简单的数组访问: 0.00987 ms
  案例 B - 索引中使用副作用操作: 0.01039 ms
-----------------------------------
测试方案 5：评估在 `[]` 中嵌入副作用操作的优化效果
  案例 A - 分离的副作用操作: 0.0079 ms
  案例 B - 嵌入的副作用操作: 0.00766 ms
-----------------------------------
测试方案 6：复杂表达式和数组操作的结合
  案例 A - 传统方式的复杂操作: 0.0074 ms
  案例 B - 优化的复杂操作: 0.00752 ms
-----------------------------------
测试方案 7：全局变量与局部变量的访问性能
  案例 A - 访问全局变量: 0.01193 ms
  案例 B - 访问局部变量: 0.00505 ms
-----------------------------------
测试方案 8：深层嵌套作用域对变量访问性能的影响
  案例 A - 浅层作用域访问: 0.0049 ms
  案例 B - 深层作用域访问: 0.02682 ms
-----------------------------------
测试方案 9：变量提升的性能影响
  案例 A - 使用 var 声明变量: 0.00466 ms
  案例 B - 不使用 var 声明变量: 0.01058 ms
-----------------------------------
测试方案 10：作用域链长度对变量访问性能的影响
  案例 A - 作用域链长度为 2: 0.019 ms
  案例 B - 作用域链长度为 5: 0.04029 ms
===================================
