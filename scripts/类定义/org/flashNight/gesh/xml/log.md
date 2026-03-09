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
    全流水线:      2.141 ms/次 | 64 次/轮 | 中位总 137.00 ms | 2.68 MB/s | 波动 1.02x
    原生 parseXML: 0.141 ms/次 | 512 次/轮 | 中位总 72.00 ms | 40.74 MB/s | 波动 1.07x
    parseXMLNode:  1.573 ms/次 | 96 次/轮 | 中位总 151.00 ms | 3.64 MB/s | 波动 1.09x
    --
    原生占全流水线: 7% (0.141 / 2.141 ms)
    parseXMLNode 占全流水线: 73% (1.573 / 2.141 ms)
    分相加总 vs 全流水线偏差: 20% (偏高：含XML对象创建/GC等固定开销，绝对值参考趋势)

--- parseXMLNode 多规模基准（变体冷路径 + 基线扣除） ---
  说明: 使用不同 seed 的 XML 变体轮转，避免 AVM 内部可能的字符串缓存。
        分别度量全流水线与纯 parseXMLNode 阶段。

  小(10项) | 1283 字符 | 64 变体
    全流水线(冷):   0.461 ms/次 | 32 批/轮 x32 = 1024 次 | 中位总 472.00 ms | 2.65 MB/s | 波动 1.05x
    parseXMLNode(冷): 0.339 ms/次 | 24 批/轮 x32 = 768 次 | 中位总 260.00 ms | 3.61 MB/s | 波动 1.03x
    parseXMLNode(热): 0.334 ms/次 | 512 次/轮 | 中位总 171.00 ms | 3.66 MB/s | 波动 1.04x
    --
    parseXMLNode 占全流水线: 73% (0.339 / 0.461 ms)
    parseXMLNode 冷/热 = 1.01x

  中(50项) | 6007 字符 | 64 变体
    全流水线(冷):   2.164 ms/次 | 4 批/轮 x32 = 128 次 | 中位总 277.00 ms | 2.65 MB/s | 波动 1.05x
    parseXMLNode(冷): 1.680 ms/次 | 8 批/轮 x32 = 256 次 | 中位总 430.00 ms | 3.41 MB/s | 波动 1.04x
    parseXMLNode(热): 1.638 ms/次 | 80 次/轮 | 中位总 131.00 ms | 3.50 MB/s | 波动 1.08x
    --
    parseXMLNode 占全流水线: 78% (1.680 / 2.164 ms)
    parseXMLNode 冷/热 = 1.03x

  大(200项) | 24176 字符 | 32 变体
    全流水线(冷):   8.594 ms/次 | 2 批/轮 x16 = 32 次 | 中位总 275.00 ms | 2.68 MB/s | 波动 1.05x
    parseXMLNode(冷): 6.844 ms/次 | 4 批/轮 x16 = 64 次 | 中位总 438.00 ms | 3.37 MB/s | 波动 1.08x
    parseXMLNode(热): 6.958 ms/次 | 24 次/轮 | 中位总 167.00 ms | 3.31 MB/s | 波动 1.11x
    --
    parseXMLNode 占全流水线: 80% (6.844 / 8.594 ms)
    parseXMLNode 冷/热 = 0.98x

--- 热点剖析（微基准） ---
  说明: 对 parseXMLNodeInner 内部各热点独立计时，定位时间分布。
        Phase 1 优化后，isValidXML 已从递归中移除，Description 已改为单次解码。

  属性迭代（50 项 XML 的 item 节点，每节点 4 属性）
    item 节点数: 50
    属性迭代:         13.75 us/次 | 192 批/轮 x50 = 9600 次 | 中位总 132.00 ms | 波动 1.05x

  同名节点数组提升（展平全树碰撞模式）
    模式: 根层 50 item 碰撞 + 50 item 各含 tags/Description +
          50 tags 各含 2 tag 碰撞。展平为单次循环测量总工作量。
    pairs 数: 212
    数组提升:         0.188 ms/次 | 1024 次/轮 | 中位总 193.00 ms | 波动 1.06x

  Description 单次解码路径（密集模式：每项都有 Description）
    当前路径: getInnerTextDecoded(node) 拼接子文本 + 单次 decodeHTML。
    Phase 1 已修复双重解码问题。
    Description 节点数: 50
    Description(当前): 32.08 us/次 | 96 批/轮 x50 = 4800 次 | 中位总 154.00 ms | 波动 1.01x
    decodeHTML(DOM文本):29.38 us/次 | 96 批/轮 x50 = 4800 次 | 中位总 141.00 ms | 波动 1.03x
    注意: DOM 文本不含实体，decodeHTML 近似 no-op；仅反映函数调用开销。

  decodeHTML 真实实体对比（含 &lt;/&gt;/&amp; 的字符串 x50）
    对比 decodeHTMLFast（单次扫描 O(L)）与旧 unescapeHTML（O(L×30)）。
    decodeHTMLFast:   61.56 us/次 | 64 批/轮 x50 = 3200 次 | 中位总 197.00 ms | 波动 1.05x
    unescapeHTML(旧):  0.118 ms/次 | 40 批/轮 x50 = 2000 次 | 中位总 235.00 ms | 波动 1.02x
    旧 / 新 = 1.91x

  convertDataType（240 值轮转）
    convertDataType:  2.84 us/次 | 768 批/轮 x60 = 46080 次 | 中位总 131.00 ms | 波动 1.03x

  --- 各热点占 parseXMLNode 总耗时占比（当前实现） ---
    parseXMLNode(参照): 1.552 ms/次 | 96 次/轮 | 中位总 149.00 ms | 波动 1.03x
    属性迭代:          1% (0.014 / 1.552 ms)
    数组提升:          12% (0.188 / 1.552 ms)
    Description(当前): 2% (0.032 / 1.552 ms)
    convertDataType:   0% (0.003 / 1.552 ms)
    已解释: 15% | 未解释（递归/对象创建/childNodes访问等）: 85%

  --- 历史参考：Phase 1 前的旧热点 ---
    以下度量的是优化前的代码路径，供与 Phase 1 前基线对比。
    当前 parseXMLNodeInner 已不再调用 isValidXML，Description 已改为单次解码。

  isValidXML 累积成本（历史参考，50 项）
    旧行为: parseXMLNode 每层递归入口调用 isValidXML(node) → O(N^2)。
    当前: 已消除，内联 nodeName 检查 O(1)。
    元素节点数: 213
    isValidXML(累积,历史): 2.141 ms/次 | 64 次/轮 | 中位总 137.00 ms | 波动 1.05x
    旧 isValidXML 占当前 parseXMLNode: 138% (2.141 / 1.552 ms)

  Description 双重解码路径（历史参考）
    旧行为: getInnerText(node) 内调 decodeHTML → 外层再调 decodeHTML。
    当前: getInnerTextDecoded 单次解码。
    Description(旧双重): 62.19 us/次 | 64 批/轮 x50 = 3200 次 | 中位总 199.00 ms | 波动 1.02x
    旧双重 / 当前单次 = 1.94x

--- 解析器 CPU 基准（启动语料分布） ---
  说明: 度量 parseXML + parseXMLNode 的纯 CPU 成本，不含 IO/路径解析/回调/日志。
        使用合成 XML 模拟 data/items/ 下 50 文件的真实分布。
        武器类用 weapon 生成器（~25 节点/item），防具类用 armor 生成器（~35 节点/item）。
        结果为「解析器内部先改哪里」的依据，不等于端到端初始化耗时。

  极小(2项) | 1215 字符 | 模拟 7 个文件
    全流水线:  0.359 ms/次 | 256 次/轮 | 中位总 92.00 ms | 3.22 MB/s | 波动 1.07x

  小(10项) | 6037 字符 | 模拟 17 个文件
    全流水线:  1.788 ms/次 | 80 次/轮 | 中位总 143.00 ms | 3.22 MB/s | 波动 1.04x

  中(22项) | 13348 字符 | 模拟 15 个文件
    全流水线:  3.750 ms/次 | 32 次/轮 | 中位总 120.00 ms | 3.39 MB/s | 波动 1.08x

  大(48项) | 29232 字符 | 模拟 5 个文件
    全流水线:  8.188 ms/次 | 16 次/轮 | 中位总 131.00 ms | 3.40 MB/s | 波动 1.05x

  超大(96项,武器类) | 58567 字符 | 模拟 2 个文件
    全流水线:  16.375 ms/次 | 8 次/轮 | 中位总 131.00 ms | 3.41 MB/s | 波动 1.05x

  超大(96项,防具类) | 47640 字符 | 模拟 2 个文件
    全流水线:  15.600 ms/次 | 10 次/轮 | 中位总 156.00 ms | 2.91 MB/s | 波动 1.09x

  巨型(217项,防具类) | 109308 字符 | 模拟 2 个文件
    全流水线:  36.000 ms/次 | 4 次/轮 | 中位总 144.00 ms | 2.90 MB/s | 波动 1.01x

  Array.concat 累积合并（50 文件, 1572 总物品）
    concat累积: 2.833 ms/次 | 48 次/轮 | 中位总 136.00 ms | 波动 1.04x

  --- 解析器 CPU 时间估算 ---
    注意: 仅含 parseXML + parseXMLNode，不含 IO/PathManager/日志/回调开销。
    真实初始化耗时 = 本值 + IO等待 + BaseXMLLoader开销 + ItemDataLoader串行调度。
    极小(2项) x7: 0.36 ms/文件 x7 = 2.52 ms
    小(10项) x17: 1.79 ms/文件 x17 = 30.39 ms
    中(22项) x15: 3.75 ms/文件 x15 = 56.25 ms
    大(48项) x5: 8.19 ms/文件 x5 = 40.94 ms
    超大(96项,武器类) x2: 16.38 ms/文件 x2 = 32.75 ms
    超大(96项,防具类) x2: 15.60 ms/文件 x2 = 31.20 ms
    巨型(217项,防具类) x2: 36.00 ms/文件 x2 = 72.00 ms
    concat: 2.83 ms
    --
    解析器纯 CPU 合计: 268.87 ms（不含 IO 及框架开销）

========== 测试结束 ==========
