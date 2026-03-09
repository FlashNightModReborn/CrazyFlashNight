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
[PASS] 深层嵌套 XML 解析成功
[PASS] 深层嵌套 XML parseXMLNode 成功

---------- 自校验汇总 ----------
通过: 38 / 38  失败: 0

========== 性能基准 ==========

--- 分相分解（50 项） ---
  说明: 将全流水线拆为「原生 XML.parseXML」与「XMLParser.parseXMLNode」两阶段
        独立度量，定位时间到底花在 C++ 还是 AS2。

  50 项 | 6007 字符
    全流水线:      12.917 ms/次 | 12 次/轮 | 中位总 155.00 ms | 0.44 MB/s | 波动 1.07x
    原生 parseXML: 0.240 ms/次 | 512 次/轮 | 中位总 123.00 ms | 23.85 MB/s | 波动 1.10x
    parseXMLNode:  11.500 ms/次 | 12 次/轮 | 中位总 138.00 ms | 0.50 MB/s | 波动 1.06x
    --
    原生占全流水线: 2% (0.240 / 12.917 ms)
    parseXMLNode 占全流水线: 89% (11.500 / 12.917 ms)
    分相加总 vs 全流水线偏差: 9% (正常应 <10%)

--- parseXMLNode 多规模基准（变体冷路径 + 基线扣除） ---
  说明: 使用不同 seed 的 XML 变体轮转，避免 AVM 内部可能的字符串缓存。
        分别度量全流水线与纯 parseXMLNode 阶段。

  小(10项) | 1283 字符 | 64 变体
    全流水线(冷):   2.605 ms/次 | 8 批/轮 x32 = 256 次 | 中位总 667.00 ms | 0.47 MB/s | 波动 1.12x
    parseXMLNode(冷): 2.402 ms/次 | 8 批/轮 x32 = 256 次 | 中位总 615.00 ms | 0.51 MB/s | 波动 1.11x
    parseXMLNode(热): 2.484 ms/次 | 64 次/轮 | 中位总 159.00 ms | 0.49 MB/s | 波动 1.12x
    --
    parseXMLNode 占全流水线: 92% (2.402 / 2.605 ms)
    parseXMLNode 冷/热 = 0.97x

  中(50项) | 6007 字符 | 64 变体
    全流水线(冷):   12.445 ms/次 | 4 批/轮 x32 = 128 次 | 中位总 1593.00 ms | 0.46 MB/s | 波动 1.03x
    parseXMLNode(冷): 12.203 ms/次 | 4 批/轮 x32 = 128 次 | 中位总 1562.00 ms | 0.47 MB/s | 波动 1.06x
    parseXMLNode(热): 12.563 ms/次 | 16 次/轮 | 中位总 201.00 ms | 0.46 MB/s | 波动 1.05x
    --
    parseXMLNode 占全流水线: 98% (12.203 / 12.445 ms)
    parseXMLNode 冷/热 = 0.97x

  大(200项) | 24176 字符 | 32 变体
    全流水线(冷):   49.188 ms/次 | 2 批/轮 x16 = 32 次 | 中位总 1574.00 ms | 0.47 MB/s | 波动 1.17x
    parseXMLNode(冷): 46.469 ms/次 | 2 批/轮 x16 = 32 次 | 中位总 1487.00 ms | 0.50 MB/s | 波动 1.06x
    parseXMLNode(热): 48.125 ms/次 | 8 次/轮 | 中位总 385.00 ms | 0.48 MB/s | 波动 1.12x
    --
    parseXMLNode 占全流水线: 94% (46.469 / 49.188 ms)
    parseXMLNode 冷/热 = 0.97x

--- 热点剖析（微基准） ---
  说明: 对 parseXMLNode 内部各热点独立计时，定位时间分布。
        isValidXML 使用累积模式（模拟递归中每层都调用的真实 O(N^2) 行为）。

  isValidXML 累积成本（50 项，模拟递归调用模式）
    真实行为: parseXMLNode 每层递归入口调用 isValidXML(node)，
    而 isValidXML 自身递归验证整个子树 → 总复杂度 O(N^2)。
    元素节点数: 213
    isValidXML(累积): 4.188 ms/次 | 32 次/轮 | 中位总 134.00 ms | 波动 1.06x
    parseXMLNode:     10.917 ms/次 | 12 次/轮 | 中位总 131.00 ms | 波动 1.04x
    isValidXML 累积占 parseXMLNode: 38% (4.188 / 10.917 ms)

  属性迭代（50 项 XML 的 item 节点，每节点 4 属性）
    item 节点数: 50
    属性迭代:         19.69 us/次 | 128 批/轮 x50 = 6400 次 | 中位总 126.00 ms | 波动 1.07x

  同名节点数组提升（展平全树碰撞模式）
    模式: 根层 50 item 碰撞 + 50 item 各含 tags/Description +
          50 tags 各含 2 tag 碰撞。展平为单次循环测量总工作量。
    pairs 数: 212
    数组提升:         0.352 ms/次 | 384 次/轮 | 中位总 135.00 ms | 波动 1.10x

  Description 完整路径（密集模式：每项都有 Description）
    真实路径: getInnerText(node) 内调 decodeHTML → 外层再调 decodeHTML（双重解码）。
    Description 节点数: 50
    Description全路径: 0.393 ms/次 | 8 批/轮 x50 = 400 次 | 中位总 157.00 ms | 波动 1.06x
    单独 decodeHTML:  0.213 ms/次 | 12 批/轮 x50 = 600 次 | 中位总 128.00 ms | 波动 1.08x
    完整路径 / 单独 decodeHTML = 1.84x

  convertDataType（240 值轮转）
    convertDataType:  3.75 us/次 | 768 批/轮 x60 = 46080 次 | 中位总 173.00 ms | 波动 1.04x

  --- 各热点占 parseXMLNode 总耗时占比 ---
    parseXMLNode(参照): 10.917 ms/次 | 12 次/轮 | 中位总 131.00 ms | 波动 1.04x
    isValidXML(累积):  38% (4.188 / 10.917 ms)
    属性迭代:          0% (0.020 / 10.917 ms)
    数组提升:          3% (0.352 / 10.917 ms)
    Description全路径: 4% (0.393 / 10.917 ms)
    convertDataType:   0% (0.004 / 10.917 ms)
    已解释: 45% | 未解释（递归/对象创建/childNodes访问等）: 55%

--- 启动语料基准（模拟真实初始化加载链路） ---
  说明: 使用匹配真实 data/items/*.xml 结构的合成 XML，
        模拟 51 文件的 parseXML + parseXMLNode + concat 全流程。
        不含 IO/网络等待，仅度量 CPU 部分。

  小(5项) | 3021 字符 | 模拟 15 个文件
    全流水线:  4.438 ms/次 | 32 次/轮 | 中位总 142.00 ms | 0.65 MB/s | 波动 1.04x

  中(20项) | 12125 字符 | 模拟 25 个文件
    全流水线:  18.625 ms/次 | 8 次/轮 | 中位总 149.00 ms | 0.62 MB/s | 波动 1.11x

  大(50项) | 30449 字符 | 模拟 8 个文件
    全流水线:  45.250 ms/次 | 4 次/轮 | 中位总 181.00 ms | 0.64 MB/s | 波动 1.02x

  超大(100项) | 61026 字符 | 模拟 3 个文件
    全流水线:  92.000 ms/次 | 2 次/轮 | 中位总 184.00 ms | 0.63 MB/s | 波动 1.06x

  Array.concat 累积合并（51 文件, 1275 总物品）
    concat累积: 5.094 ms/次 | 32 次/轮 | 中位总 163.00 ms | 波动 1.09x

  --- 启动期 CPU 时间估算（不含 IO） ---
    小(5项) x15: 4.44 ms/文件 x15 = 66.56 ms
    中(20项) x25: 18.63 ms/文件 x25 = 465.63 ms
    大(50项) x8: 45.25 ms/文件 x8 = 362.00 ms
    超大(100项) x3: 92.00 ms/文件 x3 = 276.00 ms
    concat: 5.09 ms
    --
    估算启动期总 CPU: 1175.28 ms（纯解析+合并，不含IO）

========== 测试结束 ==========
