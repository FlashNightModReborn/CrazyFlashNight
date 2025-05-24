# 实验报告：分析 ActionScript 2 (AS2) 中对象属性的哈希函数实现

## 目录

1. [引言](#引言)
2. [实验背景与原理](#实验背景与原理)
3. [实验设计与方法](#实验设计与方法)
    - 实验 A：简单碰撞组测试
    - 实验 B：大规模碰撞/接近碰撞词典测试
    - 实验 C：字符串模式测试
    - 实验 D：数值型键 vs. 字符串型键
    - 实验 E：插入大批随机字符串 + 逐个删除 + 再插入
4. [实验结果](#实验结果)
    - 实验 A 结果
    - 实验 B 结果
    - 实验 C 结果
    - 实验 D 结果
    - 实验 E 结果
5. [结果分析与讨论](#结果分析与讨论)
    - 遍历顺序的逆序特征
    - 哈希冲突处理机制
    - 数值键与字符串键的处理
    - 哈希函数的可能性推测
6. [结论](#结论)
7. [未来工作](#未来工作)

---

## 引言

在 ActionScript 2 (AS2) 中，对象属性的存储与遍历顺序受到底层哈希函数和哈希表实现方式的影响。理解 AS2 中对象属性的哈希函数特征，对于优化性能、避免哈希冲突以及进行逆向工程分析具有重要意义。本实验旨在通过一系列有针对性的测试，推测 AS2 使用的哈希函数类型及其特性。

## 实验背景与原理

AS2（基于 AVM1 虚拟机）在处理对象属性时，通常会采用哈希表结构来管理属性键值对。哈希函数的选择与实现方式直接影响到属性的存储效率、遍历顺序以及哈希冲突的处理。本实验通过观察对象属性的插入顺序与 `for...in` 遍历顺序之间的关系，分析 AS2 可能采用的哈希函数特征。

常见的字符串哈希函数包括：

- **djb2**：由 Daniel J. Bernstein 提出，简单高效，广泛应用于早期脚本语言。
- **BKDR Hash**：基于乘法累加的哈希函数，常用于字符串哈希。
- **ELF Hash**：用于 Unix 系统中的 ELF 文件符号表哈希。
- **31/33 乘法哈希**：如 Java 中常用的 `31 * hash + c` 形式。

通过设计不同的测试场景，观察哈希表在不同操作下的行为，能够侧面推测出 AS2 中哈希函数的特性。

## 实验设计与方法

本实验设计了五个子实验（A 至 E），分别针对哈希函数的不同特性进行测试。所有实验均在同一 AS2 环境下运行，结果通过 `trace` 输出并记录。

### 实验 A：简单碰撞组测试

**目的**：插入已知或假设在某些哈希函数下会发生碰撞的字符串对，观察 `for...in` 遍历顺序是否有特定规律。

**方法**：
1. 准备若干对可能在 djb2 或其他哈希函数下产生碰撞的字符串（如 `"Aa"` 与 `"BB"`）。
2. 将这些字符串对依次插入到同一个对象中，并记录插入顺序。
3. 使用 `for...in` 遍历对象属性，记录遍历顺序。
4. 通过比较插入顺序与遍历顺序，分析哈希冲突的处理方式。

### 实验 B：大规模碰撞/接近碰撞词典测试

**目的**：通过插入大量随机字符串，观察遍历顺序的分布和模式，推测哈希函数的特征。

**方法**：
1. 生成大量随机字符串，并插入到对象中（总计 100 个）。
2. 使用 `for...in` 遍历对象属性，记录前 20 个遍历结果。
3. 分析随机字符串的遍历顺序与插入顺序的关系。

### 实验 C：字符串模式测试

**目的**：通过插入具有固定模式（如相同前缀和后缀）的字符串，测试哈希函数对字符串内容和长度的敏感度。

**方法**：
1. 生成一系列具有固定前缀和后缀的字符串（如 `"prefix_0_suffix"` 至 `"prefix_19_suffix"`）。
2. 将这些字符串插入到对象中，并记录插入顺序。
3. 使用 `for...in` 遍历对象属性，记录遍历顺序。
4. 分析字符串模式对遍历顺序的影响。

### 实验 D：数值型键 vs. 字符串型键

**目的**：测试哈希函数是否区分数值型键和字符串型键，以及它们在遍历顺序中的表现。

**方法**：
1. 插入一组数值型键和对应的字符串型键（如 `1` 和 `"1"`，`2` 和 `"2"`）。
2. 使用 `for...in` 遍历对象属性，记录遍历顺序。
3. 分析数值键与字符串键在遍历顺序中的差异。

### 实验 E：插入大批随机字符串 + 逐个删除 + 再插入

**目的**：观察哈希表在删除和再插入属性后的遍历顺序变化，推测哈希桶的处理机制。

**方法**：
1. 插入 100 个随机字符串到对象中。
2. 随机删除其中 50 个属性，并记录被删除的键。
3. 再插入 50 个新的随机字符串。
4. 使用 `for...in` 遍历对象属性，记录前 20 个遍历结果。
5. 分析删除和再插入操作对遍历顺序的影响。

## 实验结果

### 实验 A 结果

```
实验 A：简单碰撞组测试
插入属性顺序：
Aa = A0
BB = B0
Zg = A1
Yh = B1
Cc = A2
DD = B2
Ee = A3
FF = B3
Gg = A4
HH = B4
-----------------------------
for...in 遍历顺序：
遍历到的属性：HH = B4
遍历到的属性：Gg = A4
遍历到的属性：FF = B3
遍历到的属性：Ee = A3
遍历到的属性：DD = B2
遍历到的属性：Cc = A2
遍历到的属性：Yh = B1
遍历到的属性：Zg = A1
遍历到的属性：BB = B0
遍历到的属性：Aa = A0
-----------------------------
```

### 实验 B 结果

```
实验 B：大规模碰撞/接近碰撞词典测试
插入大量随机属性...
插入完成，总计 100 个属性。
-----------------------------
for...in 遍历顺序（前20个）：
key_n05SP = 99
key_BB0Xq = 98
key_4PJFB = 97
key_OzJ62 = 96
key_l1utT = 95
key_l4HMp = 94
key_O4Hdo = 93
key_RTRIg = 92
key_sATmA = 91
key_DaD0I = 90
key_AfRBK = 89
key_oGRXu = 88
key_BgPQO = 87
key_s4nQt = 86
key_ntx5W = 85
key_AY4MN = 84
key_LgUkj = 83
key_ui0YZ = 82
key_uj0mq = 81
key_dzWyI = 80
... (总计 100 个属性)
-----------------------------
```

### 实验 C 结果

```
实验 C：字符串模式测试
插入具有不同模式的属性名称：
prefix_0_suffix = 0
prefix_1_suffix = 1
prefix_2_suffix = 2
prefix_3_suffix = 3
prefix_4_suffix = 4
prefix_5_suffix = 5
prefix_6_suffix = 6
prefix_7_suffix = 7
prefix_8_suffix = 8
prefix_9_suffix = 9
prefix_10_suffix = 10
prefix_11_suffix = 11
prefix_12_suffix = 12
prefix_13_suffix = 13
prefix_14_suffix = 14
prefix_15_suffix = 15
prefix_16_suffix = 16
prefix_17_suffix = 17
prefix_18_suffix = 18
prefix_19_suffix = 19
-----------------------------
for...in 遍历顺序：
遍历到的属性：prefix_19_suffix = 19
遍历到的属性：prefix_18_suffix = 18
遍历到的属性：prefix_17_suffix = 17
遍历到的属性：prefix_16_suffix = 16
遍历到的属性：prefix_15_suffix = 15
遍历到的属性：prefix_14_suffix = 14
遍历到的属性：prefix_13_suffix = 13
遍历到的属性：prefix_12_suffix = 12
遍历到的属性：prefix_11_suffix = 11
遍历到的属性：prefix_10_suffix = 10
遍历到的属性：prefix_9_suffix = 9
遍历到的属性：prefix_8_suffix = 8
遍历到的属性：prefix_7_suffix = 7
遍历到的属性：prefix_6_suffix = 6
遍历到的属性：prefix_5_suffix = 5
遍历到的属性：prefix_4_suffix = 4
遍历到的属性：prefix_3_suffix = 3
遍历到的属性：prefix_2_suffix = 2
遍历到的属性：prefix_1_suffix = 1
遍历到的属性：prefix_0_suffix = 0
-----------------------------
```

### 实验 D 结果

```
实验 D：数值型键 vs. 字符串型键
插入数值型键和字符串型键：
1 (数值键) = number_1
"1" (字符串键) = string_1
2 (数值键) = number_2
"2" (字符串键) = string_2
3 (数值键) = number_3
"3" (字符串键) = string_3
4 (数值键) = number_4
"4" (字符串键) = string_4
5 (数值键) = number_5
"5" (字符串键) = string_5
6 (数值键) = number_6
"6" (字符串键) = string_6
7 (数值键) = number_7
"7" (字符串键) = string_7
8 (数值键) = number_8
"8" (字符串键) = string_8
9 (数值键) = number_9
"9" (字符串键) = string_9
10 (数值键) = number_10
"10" (字符串键) = string_10
-----------------------------
for...in 遍历顺序：
遍历到的属性：10 = string_10
遍历到的属性：9 = string_9
遍历到的属性：8 = string_8
遍历到的属性：7 = string_7
遍历到的属性：6 = string_6
遍历到的属性：5 = string_5
遍历到的属性：4 = string_4
遍历到的属性：3 = string_3
遍历到的属性：2 = string_2
遍历到的属性：1 = string_1
-----------------------------
```

### 实验 E 结果

```
实验 E：插入大批随机字符串 + 逐个删除 + 再插入
插入 100 个随机属性...
插入完成。
-----------------------------
删除 50 个随机属性...
删除属性：init_hTB5v
删除属性：init_bxvDb
删除属性：init_KsyHI
删除属性：init_rYGMq
删除属性：init_rU2Ky
删除属性：init_mTRI6
删除属性：init_AFbJB
删除属性：init_oVAk6
删除属性：init_qxd9f
删除属性：init_GlyGz
删除属性：init_rhUjg
删除属性：init_E9jzr
删除属性：init_E3QtR
删除属性：init_k3Qvd
删除属性：init_4oriL
删除属性：init_8kTdd
删除属性：init_V9ku6
删除属性：init_AOQof
删除属性：init_6GnwC
删除属性：init_vouDP
删除属性：init_QmGks
删除属性：init_GPLph
删除属性：init_gtuzk
删除属性：init_OB9kk
删除属性：init_JrFo5
删除属性：init_fdcFs
删除属性：init_kjjTx
删除属性：init_tvv9t
删除属性：init_PcqCS
删除属性：init_Cf6zi
删除属性：init_89Jru
删除属性：init_aDZtO
删除属性：init_XNw07
删除属性：init_fe0Yi
删除属性：init_HIzZY
删除属性：init_JJQ93
删除属性：init_u3YfQ
删除属性：init_SgL0k
删除属性：init_OAmjU
删除属性：init_dWlqe
删除属性：init_8zZjU
删除属性：init_1qr3x
删除属性：init_QtuIp
删除属性：init_kBR9L
删除属性：init_xiGCv
删除属性：init_5CJKv
删除属性：init_u0nqi
删除属性：init_dS7W5
删除属性：init_1t6B7
删除属性：init_GdjIp
删除完成。
-----------------------------
再插入 50 个新随机属性...
new_EUgFn = 0
new_Dw0zD = 1
new_LaDGi = 2
new_MUU3y = 3
new_qKI4k = 4
new_rqBWz = 5
new_ECo0q = 6
new_RApbG = 7
new_3ckH0 = 8
new_LlaB8 = 9
new_chUgm = 10
new_8q1Px = 11
new_Vuohz = 12
new_tUtkO = 13
new_cEaPu = 14
new_AYdh7 = 15
new_XnvpB = 16
new_G2K8U = 17
new_0PTyr = 18
new_RyWQs = 19
new_LCUDz = 20
new_1fO4C = 21
new_SiUgS = 22
new_Fz4ut = 23
new_BA7Ps = 24
new_Go2ww = 25
new_npE7q = 26
new_qyU8f = 27
new_CU7WU = 28
new_JTBb4 = 29
new_k9Yxp = 30
new_MldGE = 31
new_nqMGw = 32
new_eOrEf = 33
new_ppm9i = 34
new_bIDwp = 35
new_holpF = 36
new_0XhH3 = 37
new_VFSuC = 38
new_AIaFs = 39
new_5wiIE = 40
new_uESs9 = 41
new_tBQ1R = 42
new_HZvlk = 43
new_lSRyy = 44
new_f641u = 45
new_Y5n2g = 46
new_Evlck = 47
new_3QX1X = 48
new_7qz5J = 49
再插入完成。
-----------------------------
for...in 遍历顺序（前20个）：
new_7qz5J = 49
new_3QX1X = 48
new_Evlck = 47
new_Y5n2g = 46
new_f641u = 45
new_lSRyy = 44
new_HZvlk = 43
new_tBQ1R = 42
new_uESs9 = 41
new_5wiIE = 40
new_AIaFs = 39
new_VFSuC = 38
new_0XhH3 = 37
new_holpF = 36
new_bIDwp = 35
new_ppm9i = 34
new_eOrEf = 33
new_nqMGw = 32
new_MldGE = 31
new_k9Yxp = 30
... (总计 100 个属性)
-----------------------------
```

## 结果分析与讨论

### 遍历顺序的逆序特征

在所有实验中，`for...in` 遍历顺序普遍呈现**后插入先遍历**的特征。例如：

- **实验 A**：最后插入的 `HH` 首先被遍历，最先插入的 `Aa` 最后被遍历。
- **实验 C**：插入顺序从 `prefix_0_suffix` 到 `prefix_19_suffix`，遍历时从 `prefix_19_suffix` 倒序至 `prefix_0_suffix`。
- **实验 D**：插入的数值键和字符串键按顺序插入，但遍历时仅遍历字符串键，并按降序排列。
- **实验 E**：再插入的 `new_XXX` 键首先被遍历。

这种逆序特征一致表明，AS2 中对象属性的哈希表实现可能采用**链表头插法**。即，每次新插入的属性被添加到哈希桶链表的头部，导致新插入的属性在遍历时优先出现。

### 哈希冲突处理机制

**实验 A** 中插入了可能在某些哈希函数下发生碰撞的字符串对（如 `"Aa"` 与 `"BB"`）。结果显示，遍历顺序依然遵循后插先遍历的模式，没有明显的分组或打乱顺序现象。这表明：

1. **冲突分辨机制**：AS2 可能采用链表来处理哈希冲突，每个哈希桶对应一个单向链表，新插入的属性位于链表头部。
2. **遍历顺序稳定性**：即使发生哈希冲突，遍历顺序仍保持“后插先出”特性，未出现属性顺序混乱的情况。

### 数值键与字符串键的处理

**实验 D** 插入了数值型键和对应的字符串型键（如 `1` 和 `"1"`）。遍历结果仅显示字符串型键，且按降序排列。这表明：

1. **键类型处理**：AS2 可能将数值型键自动转换为字符串型键进行处理，或在遍历时仅显示字符串型键。
2. **遍历顺序统一**：无论是数值键还是字符串键，遍历顺序都遵循“后插先出”的规律，未见特定优先级差异。

### 哈希函数的可能性推测

通过以上实验，可以推测 AS2 中使用的哈希函数具有以下特征：

1. **简单高效**：哈希函数可能采用简单的乘法或累加方式，如 djb2、BKDR 或 31/33 乘法哈希，这些函数在早期脚本语言中广泛使用。
2. **链表头插法**：哈希表实现可能采用拉链法处理冲突，并通过链表头插法插入新属性，导致遍历时后插入的属性优先出现。
3. **哈希值分布**：由于未观察到明显的哈希冲突分组特征，哈希函数可能具有较好的哈希值分布，减少碰撞的影响。

然而，实验结果未能直接区分具体的哈希函数类型（如 djb2 vs. BKDR）。为进一步推测，需进行更大规模的碰撞测试，并将 AS2 的遍历顺序与不同哈希函数下的哈希值分布进行比对。

## 结论

本实验通过五个子实验，系统性地分析了 AS2 中对象属性的哈希函数特征。主要结论如下：

1. **遍历顺序逆序特征**：所有实验均显示出对象属性遍历顺序遵循“后插入先遍历”模式，强烈暗示 AS2 的哈希表实现采用链表头插法。
2. **哈希冲突处理**：AS2 可能采用拉链法处理哈希冲突，每个哈希桶对应一个单向链表，新属性插入链表头部。
3. **哈希函数类型推测**：虽然未能明确确认具体哈希函数类型，但基于早期脚本语言的常用实践，AS2 可能采用 djb2 或类似的简单高效哈希函数。
4. **键类型处理**：AS2 似乎将数值型键转换为字符串型键进行处理，且遍历顺序对键类型无特定偏好。

总的来说，AS2 中的对象属性哈希实现具有以下特征：

- 使用简单高效的字符串哈希函数（如 djb2 或其变体）。
- 采用链表头插法处理哈希冲突，导致属性遍历顺序呈现逆序插入特性。

## 未来工作

为进一步确认 AS2 中具体使用的哈希函数类型，建议开展以下工作：

1. **大规模碰撞测试**：
    - 制作或收集大量在不同哈希函数下产生碰撞的字符串集。
    - 在 AS2 中插入这些字符串，观察遍历顺序是否与特定哈希函数下的哈希值排序相符。
    
2. **离线哈希值对比**：
    - 使用 Python 或其他编程语言，计算相同字符串集在不同哈希函数（如 djb2、BKDR、ELF Hash 等）下的哈希值。
    - 比较 AS2 的遍历顺序与不同哈希函数下哈希值的排序关系，寻找匹配度最高的哈希函数。

3. **版本比较**：
    - 在不同版本的 Flash Player（如 6、7、8、9）中运行相同实验，观察哈希实现是否存在差异。
    - 分析不同版本中哈希函数的变化趋势，进一步推测哈希函数的演进。

4. **逆向工程**：
    - 通过逆向分析旧版 Flash Player 的二进制文件，直接查看 AS2 对象属性哈希函数的实现细节。
    - 结合静态分析与动态调试，确认哈希函数的具体算法。



```actionscript

// 完整代码：分析 AS2 中对象属性哈希函数的特征

// 实验 A：简单碰撞组测试
function experimentA_collisionGroupTest():Void {
    var collisionPairs:Array = [
        ["Aa", "BB"],
        ["Zg", "Yh"],
        ["Cc", "DD"],
        ["Ee", "FF"],
        ["Gg", "HH"]
        // 可根据需要添加更多已知或假设的碰撞对
    ];
    
    var obj:Object = new Object();
    
    trace("实验 A：简单碰撞组测试");
    trace("插入属性顺序：");
    
    // 插入碰撞对
    for (var i:Number = 0; i < collisionPairs.length; i++) {
        var pair:Array = collisionPairs[i];
        obj[pair[0]] = "A" + i;
        trace(pair[0] + " = " + obj[pair[0]]);
        obj[pair[1]] = "B" + i;
        trace(pair[1] + " = " + obj[pair[1]]);
    }
    trace("-----------------------------");
    
    // 遍历顺序
    trace("for...in 遍历顺序：");
    for (var key in obj) {
        trace("遍历到的属性：" + key + " = " + obj[key]);
    }
    trace("-----------------------------\n\n");
}

// 实验 B：大规模碰撞/接近碰撞词典测试
function experimentB_largeScaleCollisionTest():Void {
    // 注意：由于不知道具体的碰撞字符串，这里使用随机生成的字符串
    // 实际应用中应使用已知在特定哈希函数下碰撞的字符串
    var numPairs:Number = 50; // 可以根据需要调整数量
    var collisionGroups:Array = [];
    var obj:Object = new Object();
    
    // 生成随机字符串
    function generateRandomString(length:Number):String {
        var chars:String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
        var str:String = "";
        for (var i:Number = 0; i < length; i++) {
            str += chars.charAt(Math.floor(Math.random() * chars.length));
        }
        return str;
    }
    
    // 插入大量随机字符串
    trace("实验 B：大规模碰撞/接近碰撞词典测试");
    trace("插入大量随机属性...");
    for (var i:Number = 0; i < numPairs * 2; i++) {
        var key:String = "key_" + generateRandomString(5);
        obj[key] = i;
        collisionGroups.push(key);
    }
    trace("插入完成，总计 " + (numPairs * 2) + " 个属性。");
    trace("-----------------------------");
    
    // 遍历顺序记录
    var traversalOrder:Array = [];
    for (var key in obj) {
        traversalOrder.push(key + " = " + obj[key]);
    }
    
    trace("for...in 遍历顺序（前20个）：");
    for (var j:Number = 0; j < Math.min(20, traversalOrder.length); j++) {
        trace(traversalOrder[j]);
    }
    trace("... (总计 " + traversalOrder.length + " 个属性)");
    trace("-----------------------------\n\n");
}

// 实验 C：字符串模式测试
function experimentC_stringPatternTest():Void {
    var obj:Object = new Object();
    var prefix:String = "prefix_";
    var suffix:String = "_suffix";
    var numKeys:Number = 20;
    
    // 生成具有不同模式的字符串
    function generatePatternedKeys():Array {
        var keys:Array = [];
        for (var i:Number = 0; i < numKeys; i++) {
            var key:String = prefix + i + suffix;
            keys.push(key);
        }
        return keys;
    }
    
    var patternedKeys:Array = generatePatternedKeys();
    
    trace("实验 C：字符串模式测试");
    trace("插入具有不同模式的属性名称：");
    for (var i:Number = 0; i < patternedKeys.length; i++) {
        var key:String = patternedKeys[i];
        obj[key] = i;
        trace(key + " = " + obj[key]);
    }
    trace("-----------------------------");
    
    // 遍历顺序
    trace("for...in 遍历顺序：");
    for (var key in obj) {
        trace("遍历到的属性：" + key + " = " + obj[key]);
    }
    trace("-----------------------------\n\n");
}

// 实验 D：数值型键 vs. 字符串型键
function experimentD_numericVsStringKeysTest():Void {
    var obj:Object = new Object();
    
    trace("实验 D：数值型键 vs. 字符串型键");
    trace("插入数值型键和字符串型键：");
    
    // 插入数值型键和对应的字符串型键
    for (var i:Number = 1; i <= 10; i++) {
        obj[i] = "number_" + i;
        trace(i + " (数值键) = " + obj[i]);
        obj[String(i)] = "string_" + i;
        trace("\"" + i + "\" (字符串键) = " + obj[String(i)]);
    }
    trace("-----------------------------");
    
    // 遍历顺序
    trace("for...in 遍历顺序：");
    for (var key in obj) {
        trace("遍历到的属性：" + key + " = " + obj[key]);
    }
    trace("-----------------------------\n\n");
}

// 实验 E：插入大批随机字符串 + 逐个删除 + 再插入
function experimentE_insertDeleteReinsertTest():Void {
    var obj:Object = new Object();
    var initialCount:Number = 100;
    var deleteCount:Number = 50;
    var reinsertCount:Number = 50;
    var allKeys:Array = [];
    
    // 生成随机字符串
    function generateRandomString(length:Number):String {
        var chars:String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
        var str:String = "";
        for (var i:Number = 0; i < length; i++) {
            str += chars.charAt(Math.floor(Math.random() * chars.length));
        }
        return str;
    }
    
    // 插入初始属性
    trace("实验 E：插入大批随机字符串 + 逐个删除 + 再插入");
    trace("插入 " + initialCount + " 个随机属性...");
    for (var i:Number = 0; i < initialCount; i++) {
        var key:String = "init_" + generateRandomString(5);
        obj[key] = i;
        allKeys.push(key);
    }
    trace("插入完成。");
    trace("-----------------------------");
    
    // 随机删除部分属性
    trace("删除 " + deleteCount + " 个随机属性...");
    for (var j:Number = 0; j < deleteCount; j++) {
        var delIndex:Number = Math.floor(Math.random() * allKeys.length);
        var delKey:String = allKeys.splice(delIndex, 1)[0];
        delete obj[delKey];
        trace("删除属性：" + delKey);
    }
    trace("删除完成。");
    trace("-----------------------------");
    
    // 再插入新属性
    trace("再插入 " + reinsertCount + " 个新随机属性...");
    for (var k:Number = 0; k < reinsertCount; k++) {
        var newKey:String = "new_" + generateRandomString(5);
        obj[newKey] = k;
        allKeys.push(newKey);
        trace(newKey + " = " + obj[newKey]);
    }
    trace("再插入完成。");
    trace("-----------------------------");
    
    // 遍历顺序
    var traversalOrder:Array = [];
    for (var key in obj) {
        traversalOrder.push(key + " = " + obj[key]);
    }
    
    trace("for...in 遍历顺序（前20个）：");
    for (var m:Number = 0; m < Math.min(20, traversalOrder.length); m++) {
        trace(traversalOrder[m]);
    }
    trace("... (总计 " + traversalOrder.length + " 个属性)");
    trace("-----------------------------\n\n");
}

// 清空输出框
output_txt.text = "";

// 运行所有实验
trace("开始实验\n\n");
experimentA_collisionGroupTest();
experimentB_largeScaleCollisionTest();
experimentC_stringPatternTest();
experimentD_numericVsStringKeysTest();
experimentE_insertDeleteReinsertTest();
trace("实验完成\n\n");

```


```output

开始实验


实验 A：简单碰撞组测试
插入属性顺序：
Aa = A0
BB = B0
Zg = A1
Yh = B1
Cc = A2
DD = B2
Ee = A3
FF = B3
Gg = A4
HH = B4
-----------------------------
for...in 遍历顺序：
遍历到的属性：HH = B4
遍历到的属性：Gg = A4
遍历到的属性：FF = B3
遍历到的属性：Ee = A3
遍历到的属性：DD = B2
遍历到的属性：Cc = A2
遍历到的属性：Yh = B1
遍历到的属性：Zg = A1
遍历到的属性：BB = B0
遍历到的属性：Aa = A0
-----------------------------


实验 B：大规模碰撞/接近碰撞词典测试
插入大量随机属性...
插入完成，总计 100 个属性。
-----------------------------
for...in 遍历顺序（前20个）：
key_n05SP = 99
key_BB0Xq = 98
key_4PJFB = 97
key_OzJ62 = 96
key_l1utT = 95
key_l4HMp = 94
key_O4Hdo = 93
key_RTRIg = 92
key_sATmA = 91
key_DaD0I = 90
key_AfRBK = 89
key_oGRXu = 88
key_BgPQO = 87
key_s4nQt = 86
key_ntx5W = 85
key_AY4MN = 84
key_LgUkj = 83
key_ui0YZ = 82
key_uj0mq = 81
key_dzWyI = 80
... (总计 100 个属性)
-----------------------------


实验 C：字符串模式测试
插入具有不同模式的属性名称：
prefix_0_suffix = 0
prefix_1_suffix = 1
prefix_2_suffix = 2
prefix_3_suffix = 3
prefix_4_suffix = 4
prefix_5_suffix = 5
prefix_6_suffix = 6
prefix_7_suffix = 7
prefix_8_suffix = 8
prefix_9_suffix = 9
prefix_10_suffix = 10
prefix_11_suffix = 11
prefix_12_suffix = 12
prefix_13_suffix = 13
prefix_14_suffix = 14
prefix_15_suffix = 15
prefix_16_suffix = 16
prefix_17_suffix = 17
prefix_18_suffix = 18
prefix_19_suffix = 19
-----------------------------
for...in 遍历顺序：
遍历到的属性：prefix_19_suffix = 19
遍历到的属性：prefix_18_suffix = 18
遍历到的属性：prefix_17_suffix = 17
遍历到的属性：prefix_16_suffix = 16
遍历到的属性：prefix_15_suffix = 15
遍历到的属性：prefix_14_suffix = 14
遍历到的属性：prefix_13_suffix = 13
遍历到的属性：prefix_12_suffix = 12
遍历到的属性：prefix_11_suffix = 11
遍历到的属性：prefix_10_suffix = 10
遍历到的属性：prefix_9_suffix = 9
遍历到的属性：prefix_8_suffix = 8
遍历到的属性：prefix_7_suffix = 7
遍历到的属性：prefix_6_suffix = 6
遍历到的属性：prefix_5_suffix = 5
遍历到的属性：prefix_4_suffix = 4
遍历到的属性：prefix_3_suffix = 3
遍历到的属性：prefix_2_suffix = 2
遍历到的属性：prefix_1_suffix = 1
遍历到的属性：prefix_0_suffix = 0
-----------------------------


实验 D：数值型键 vs. 字符串型键
插入数值型键和字符串型键：
1 (数值键) = number_1
"1" (字符串键) = string_1
2 (数值键) = number_2
"2" (字符串键) = string_2
3 (数值键) = number_3
"3" (字符串键) = string_3
4 (数值键) = number_4
"4" (字符串键) = string_4
5 (数值键) = number_5
"5" (字符串键) = string_5
6 (数值键) = number_6
"6" (字符串键) = string_6
7 (数值键) = number_7
"7" (字符串键) = string_7
8 (数值键) = number_8
"8" (字符串键) = string_8
9 (数值键) = number_9
"9" (字符串键) = string_9
10 (数值键) = number_10
"10" (字符串键) = string_10
-----------------------------
for...in 遍历顺序：
遍历到的属性：10 = string_10
遍历到的属性：9 = string_9
遍历到的属性：8 = string_8
遍历到的属性：7 = string_7
遍历到的属性：6 = string_6
遍历到的属性：5 = string_5
遍历到的属性：4 = string_4
遍历到的属性：3 = string_3
遍历到的属性：2 = string_2
遍历到的属性：1 = string_1
-----------------------------


实验 E：插入大批随机字符串 + 逐个删除 + 再插入
插入 100 个随机属性...
插入完成。
-----------------------------
删除 50 个随机属性...
删除属性：init_hTB5v
删除属性：init_bxvDb
删除属性：init_KsyHI
删除属性：init_rYGMq
删除属性：init_rU2Ky
删除属性：init_mTRI6
删除属性：init_AFbJB
删除属性：init_oVAk6
删除属性：init_qxd9f
删除属性：init_GlyGz
删除属性：init_rhUjg
删除属性：init_E9jzr
删除属性：init_E3QtR
删除属性：init_k3Qvd
删除属性：init_4oriL
删除属性：init_8kTdd
删除属性：init_V9ku6
删除属性：init_AOQof
删除属性：init_6GnwC
删除属性：init_vouDP
删除属性：init_QmGks
删除属性：init_GPLph
删除属性：init_gtuzk
删除属性：init_OB9kk
删除属性：init_JrFo5
删除属性：init_fdcFs
删除属性：init_kjjTx
删除属性：init_tvv9t
删除属性：init_PcqCS
删除属性：init_Cf6zi
删除属性：init_89Jru
删除属性：init_aDZtO
删除属性：init_XNw07
删除属性：init_fe0Yi
删除属性：init_HIzZY
删除属性：init_JJQ93
删除属性：init_u3YfQ
删除属性：init_SgL0k
删除属性：init_OAmjU
删除属性：init_dWlqe
删除属性：init_8zZjU
删除属性：init_1qr3x
删除属性：init_QtuIp
删除属性：init_kBR9L
删除属性：init_xiGCv
删除属性：init_5CJKv
删除属性：init_u0nqi
删除属性：init_dS7W5
删除属性：init_1t6B7
删除属性：init_GdjIp
删除完成。
-----------------------------
再插入 50 个新随机属性...
new_EUgFn = 0
new_Dw0zD = 1
new_LaDGi = 2
new_MUU3y = 3
new_qKI4k = 4
new_rqBWz = 5
new_ECo0q = 6
new_RApbG = 7
new_3ckH0 = 8
new_LlaB8 = 9
new_chUgm = 10
new_8q1Px = 11
new_Vuohz = 12
new_tUtkO = 13
new_cEaPu = 14
new_AYdh7 = 15
new_XnvpB = 16
new_G2K8U = 17
new_0PTyr = 18
new_RyWQs = 19
new_LCUDz = 20
new_1fO4C = 21
new_SiUgS = 22
new_Fz4ut = 23
new_BA7Ps = 24
new_Go2ww = 25
new_npE7q = 26
new_qyU8f = 27
new_CU7WU = 28
new_JTBb4 = 29
new_k9Yxp = 30
new_MldGE = 31
new_nqMGw = 32
new_eOrEf = 33
new_ppm9i = 34
new_bIDwp = 35
new_holpF = 36
new_0XhH3 = 37
new_VFSuC = 38
new_AIaFs = 39
new_5wiIE = 40
new_uESs9 = 41
new_tBQ1R = 42
new_HZvlk = 43
new_lSRyy = 44
new_f641u = 45
new_Y5n2g = 46
new_Evlck = 47
new_3QX1X = 48
new_7qz5J = 49
再插入完成。
-----------------------------
for...in 遍历顺序（前20个）：
new_7qz5J = 49
new_3QX1X = 48
new_Evlck = 47
new_Y5n2g = 46
new_f641u = 45
new_lSRyy = 44
new_HZvlk = 43
new_tBQ1R = 42
new_uESs9 = 41
new_5wiIE = 40
new_AIaFs = 39
new_VFSuC = 38
new_0XhH3 = 37
new_holpF = 36
new_bIDwp = 35
new_ppm9i = 34
new_eOrEf = 33
new_nqMGw = 32
new_MldGE = 31
new_k9Yxp = 30
... (总计 100 个属性)
-----------------------------


实验完成


```