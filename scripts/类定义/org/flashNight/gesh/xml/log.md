new org.flashNight.gesh.xml.XMLParser_Benchmark();


╔══════════════════════════════════════════════════╗
║       XMLParser 性能基准测试                     ║
╚══════════════════════════════════════════════════╝

========== 负载自校验 ==========

--- 负载自校验 ---
[PASS] 生成 XML 变体数量 (expected=4, actual=4)
[PASS] 相邻 XML 变体字符串不同
[PASS] 非相邻 XML 变体字符串不同
[PASS] 变体 0 解析不为 null
[PASS] 变体 0 metadata.seed (expected=0, actual=0)
[PASS] 变体 0 metadata.count (expected=6, actual=6)
[PASS] 变体 0 item 为数组
[PASS] 变体 0 item 长度 (expected=6, actual=6)
[PASS] 变体 0 首项 id (expected=0, actual=0)
[PASS] 变体 0 首项有 tags
[PASS] 变体 1 metadata.seed (expected=1, actual=1)
[PASS] 变体 1 首项 id (expected=1, actual=1)
[PASS] 预解析节点数量 (expected=4, actual=4)
[PASS] 预解析节点 0 不为 null
[PASS] 预解析后重新 parseXMLNode 的 seed (expected=0, actual=0)
[PASS] 首项有 Description
[PASS] Description 严格解码验证 (expected=<p>Desc 0</p>, actual=<p>Desc 0</p>)
[PASS] convertDataType 值数组长度 (expected=12, actual=12)
[PASS] 值数组元素为字符串
[PASS] decodeHTML 字符串数组长度 (expected=6, actual=6)
[PASS] 含实体的 HTML 字符串正确
[PASS] 无实体的纯文本字符串正确
[PASS] collectElementNodes: 元素节点数 > item 数 (实际=29)
[PASS] collectElementNodes: 首节点为元素节点
[PASS] 密集 Description XML 解析成功
[PASS] 密集 Description: item 为数组
[PASS] 密集 Description 首项解码 (expected=<p>Desc & detail 0</p>, actual=<p>Desc & detail 0</p>)
[PASS] Description 子节点收集数量 (expected=4, actual=4)
[PASS] 数组提升 pairs 长度 (expected=4, actual=4)
[PASS] 真实结构 XML 解析成功
[PASS] 真实结构: item 为数组
[PASS] 真实结构 item 长度 (expected=3, actual=3)
[PASS] 真实结构首项 name (expected=weapon_0, actual=weapon_0)
[PASS] 真实结构首项有 data
[PASS] 真实结构首项 data.bullet (expected=普通子弹, actual=普通子弹)
[PASS] 真实结构首项 data.power (expected=30, actual=30)
[PASS] 防具结构 XML 解析成功
[PASS] 防具结构: item 为数组
[PASS] 防具结构 item 长度 (expected=6, actual=6)
[PASS] 防具结构首项 name (expected=armor_0, actual=armor_0)
[PASS] 防具结构首项有 skill（i%3==0）
[PASS] 防具结构首项 skill.skillname (expected=技能_0, actual=技能_0)
[PASS] 防具结构首项有 data
[PASS] 防具结构首项 data.defence (expected=10, actual=10)
[PASS] 防具结构首项有 data_2（i%2==0）
[PASS] 防具结构首项有 data_3（i%3==0）
[PASS] 防具结构首项有 data_4（i%6==0）
[PASS] 防具结构第2项无 skill（i%3!=0）
[PASS] 防具结构第2项无 data_2（i%2!=0）
[PASS] 深层嵌套 XML 解析成功
[PASS] 深层嵌套 XML parseXMLNode 成功
[PASS] null 节点 → 返回 null
[PASS] 空 XML 字符串 → 返回 null
[PASS] 纯空白 XML → 返回 null
[PASS] 畸形 XML 不崩溃 (结果=partial)
[PASS] convertDataType: 'true' → true
[PASS] convertDataType: 'True' → true
[PASS] convertDataType: 'TRUE' → true
[PASS] convertDataType: 'false' → false
[PASS] convertDataType: 'False' → false
[PASS] convertDataType: 'FALSE' → false
[PASS] convertDataType: 'tRue' → 保留字符串
[PASS] convertDataType: 'FALSE ' → 尾空格保留字符串
[PASS] convertDataType: '42' → 42
[PASS] convertDataType: '' → 空字符串
[PASS] convertDataType: 'hello' → 原字符串

---------- 自校验汇总 ----------
通过: 66 / 66  失败: 0

========== 性能基准 ==========

--- 分相分解（50 项） ---
  说明: 将全流水线拆为「原生 XML.parseXML」与「XMLParser.parseXMLNode」两阶段
        独立度量，定位时间到底花在 C++ 还是 AS2。

  50 项 | 6007 字符
    全流水线:      3.109 ms/次 | 64 次/轮 | 中位总 199.00 ms | 1.84 MB/s | 波动 1.04x
    原生 parseXML: 0.146 ms/次 | 512 次/轮 | 中位总 75.00 ms | 39.11 MB/s | 波动 1.27x
    parseXMLNode:  2.594 ms/次 | 64 次/轮 | 中位总 166.00 ms | 2.21 MB/s | 波动 1.03x
    --
    原生占全流水线: 5% (0.146 / 3.109 ms)
    parseXMLNode 占全流水线: 83% (2.594 / 3.109 ms)
    分相加总 vs 全流水线偏差: 12% (正常应 <10%)

--- parseXMLNode 多规模基准（变体冷路径 + 基线扣除） ---
  说明: 使用不同 seed 的 XML 变体轮转，避免 AVM 内部可能的字符串缓存。
        分别度量全流水线与纯 parseXMLNode 阶段。

  小(10项) | 1283 字符 | 64 变体
    全流水线(冷):   0.658 ms/次 | 16 批/轮 x32 = 512 次 | 中位总 337.00 ms | 1.86 MB/s | 波动 1.05x
    parseXMLNode(冷): 0.539 ms/次 | 16 批/轮 x32 = 512 次 | 中位总 276.00 ms | 2.27 MB/s | 波动 1.03x
    parseXMLNode(热): 0.535 ms/次 | 256 次/轮 | 中位总 137.00 ms | 2.29 MB/s | 波动 1.09x
    --
    parseXMLNode 占全流水线: 82% (0.539 / 0.658 ms)
    parseXMLNode 冷/热 = 1.01x

  中(50项) | 6007 字符 | 64 变体
    全流水线(冷):   3.133 ms/次 | 4 批/轮 x32 = 128 次 | 中位总 401.00 ms | 1.83 MB/s | 波动 1.05x
    parseXMLNode(冷): 2.734 ms/次 | 4 批/轮 x32 = 128 次 | 中位总 350.00 ms | 2.10 MB/s | 波动 1.04x
    parseXMLNode(热): 2.750 ms/次 | 48 次/轮 | 中位总 132.00 ms | 2.08 MB/s | 波动 1.06x
    --
    parseXMLNode 占全流水线: 87% (2.734 / 3.133 ms)
    parseXMLNode 冷/热 = 0.99x

  大(200项) | 24176 字符 | 32 变体
    全流水线(冷):   12.469 ms/次 | 2 批/轮 x16 = 32 次 | 中位总 399.00 ms | 1.85 MB/s | 波动 1.03x
    parseXMLNode(冷): 11.500 ms/次 | 2 批/轮 x16 = 32 次 | 中位总 368.00 ms | 2.00 MB/s | 波动 1.02x
    parseXMLNode(热): 11.563 ms/次 | 16 次/轮 | 中位总 185.00 ms | 1.99 MB/s | 波动 1.06x
    --
    parseXMLNode 占全流水线: 92% (11.500 / 12.469 ms)
    parseXMLNode 冷/热 = 0.99x

--- 热点剖析（微基准） ---
  说明: 对 parseXMLNodeInner 内部各热点独立计时，定位时间分布。
        Phase 1 优化后，isValidXML 已从递归中移除，Description 已改为单次解码。

  属性迭代（50 项 XML 的 item 节点，每节点 4 属性）
    item 节点数: 50
    属性迭代:         13.65 us/次 | 192 批/轮 x50 = 9600 次 | 中位总 131.00 ms | 波动 1.05x

  同名节点数组提升（展平全树碰撞模式）
    模式: 根层 50 item 碰撞 + 50 item 各含 tags/Description +
          50 tags 各含 2 tag 碰撞。展平为单次循环测量总工作量。
    pairs 数: 212
    数组提升:         0.186 ms/次 | 1024 次/轮 | 中位总 190.00 ms | 波动 1.04x

  Description 单次解码路径（密集模式：每项都有 Description）
    当前路径: getInnerTextDecoded(node) 拼接子文本 + 单次 decodeHTML。
    Phase 1 已修复双重解码问题。
    Description 节点数: 50
    Description(当前): 0.102 ms/次 | 24 批/轮 x50 = 1200 次 | 中位总 122.00 ms | 波动 1.09x
    单独 decodeHTML:  0.116 ms/次 | 40 批/轮 x50 = 2000 次 | 中位总 232.00 ms | 波动 1.03x
    当前路径 / 单独 decodeHTML = 0.88x

  convertDataType（240 值轮转）
    convertDataType:  2.82 us/次 | 768 批/轮 x60 = 46080 次 | 中位总 130.00 ms | 波动 1.05x

  --- 各热点占 parseXMLNode 总耗时占比（当前实现） ---
    parseXMLNode(参照): 2.531 ms/次 | 64 次/轮 | 中位总 162.00 ms | 波动 1.04x
    属性迭代:          1% (0.014 / 2.531 ms)
    数组提升:          7% (0.186 / 2.531 ms)
    Description(当前): 4% (0.102 / 2.531 ms)
    convertDataType:   0% (0.003 / 2.531 ms)
    已解释: 12% | 未解释（递归/对象创建/childNodes访问等）: 88%

  --- 历史参考：Phase 1 前的旧热点 ---
    以下度量的是优化前的代码路径，供与 Phase 1 前基线对比。
    当前 parseXMLNodeInner 已不再调用 isValidXML，Description 已改为单次解码。

  isValidXML 累积成本（历史参考，50 项）
    旧行为: parseXMLNode 每层递归入口调用 isValidXML(node) → O(N^2)。
    当前: 已消除，内联 nodeName 检查 O(1)。
    元素节点数: 213
    isValidXML(累积,历史): 2.078 ms/次 | 64 次/轮 | 中位总 133.00 ms | 波动 1.06x
    旧 isValidXML 占当前 parseXMLNode: 82% (2.078 / 2.531 ms)

  Description 双重解码路径（历史参考）
    旧行为: getInnerText(node) 内调 decodeHTML → 外层再调 decodeHTML。
    当前: getInnerTextDecoded 单次解码。
    Description(旧双重): 0.201 ms/次 | 24 批/轮 x50 = 1200 次 | 中位总 241.00 ms | 波动 1.01x
    旧双重 / 当前单次 = 1.98x

--- 解析器 CPU 基准（启动语料分布） ---
  说明: 度量 parseXML + parseXMLNode 的纯 CPU 成本，不含 IO/路径解析/回调/日志。
        使用合成 XML 模拟 data/items/ 下 50 文件的真实分布。
        武器类用 weapon 生成器（~25 节点/item），防具类用 armor 生成器（~35 节点/item）。
        结果为「解析器内部先改哪里」的依据，不等于端到端初始化耗时。

  极小(2项) | 1215 字符 | 模拟 7 个文件
    全流水线:  0.348 ms/次 | 256 次/轮 | 中位总 89.00 ms | 3.33 MB/s | 波动 1.01x

  小(10项) | 6037 字符 | 模拟 17 个文件
    全流水线:  1.700 ms/次 | 80 次/轮 | 中位总 136.00 ms | 3.39 MB/s | 波动 1.04x

  中(22项) | 13348 字符 | 模拟 15 个文件
    全流水线:  3.750 ms/次 | 32 次/轮 | 中位总 120.00 ms | 3.39 MB/s | 波动 1.08x

  大(48项) | 29232 字符 | 模拟 5 个文件
    全流水线:  8.250 ms/次 | 16 次/轮 | 中位总 132.00 ms | 3.38 MB/s | 波动 1.06x

  超大(96项,武器类) | 58567 字符 | 模拟 2 个文件
    全流水线:  16.375 ms/次 | 8 次/轮 | 中位总 131.00 ms | 3.41 MB/s | 波动 1.09x

  超大(96项,防具类) | 47640 字符 | 模拟 2 个文件
    全流水线:  15.125 ms/次 | 8 次/轮 | 中位总 121.00 ms | 3.00 MB/s | 波动 1.09x

  巨型(217项,防具类) | 109308 字符 | 模拟 2 个文件
    全流水线:  34.750 ms/次 | 4 次/轮 | 中位总 139.00 ms | 3.00 MB/s | 波动 1.07x

  Array.concat 累积合并（50 文件, 1572 总物品）
    concat累积: 2.813 ms/次 | 48 次/轮 | 中位总 135.00 ms | 波动 1.07x

  --- 解析器 CPU 时间估算 ---
    注意: 仅含 parseXML + parseXMLNode，不含 IO/PathManager/日志/回调开销。
    真实初始化耗时 = 本值 + IO等待 + BaseXMLLoader开销 + ItemDataLoader串行调度。
    极小(2项) x7: 0.35 ms/文件 x7 = 2.43 ms
    小(10项) x17: 1.70 ms/文件 x17 = 28.90 ms
    中(22项) x15: 3.75 ms/文件 x15 = 56.25 ms
    大(48项) x5: 8.25 ms/文件 x5 = 41.25 ms
    超大(96项,武器类) x2: 16.38 ms/文件 x2 = 32.75 ms
    超大(96项,防具类) x2: 15.13 ms/文件 x2 = 30.25 ms
    巨型(217项,防具类) x2: 34.75 ms/文件 x2 = 69.50 ms
    concat: 2.81 ms
    --
    解析器纯 CPU 合计: 264.15 ms（不含 IO 及框架开销）

========== 测试结束 ==========
