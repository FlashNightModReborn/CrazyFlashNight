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
[PASS] 深层嵌套 XML 解析成功
[PASS] 深层嵌套 XML parseXMLNode 成功

---------- 自校验汇总 ----------
通过: 31 / 31  失败: 0

========== 性能基准 ==========

--- 分相分解（50 项） ---
  说明: 将全流水线拆为「原生 XML.parseXML」与「XMLParser.parseXMLNode」两阶段
        独立度量，定位时间到底花在 C++ 还是 AS2。

  50 项 | 6007 字符
    全流水线:      11.083 ms/次 | 12 次/轮 | 中位总 133.00 ms | 0.52 MB/s | 波动 1.07x
    原生 parseXML: 0.223 ms/次 | 512 次/轮 | 中位总 114.00 ms | 25.73 MB/s | 波动 1.03x
    parseXMLNode:  11.083 ms/次 | 12 次/轮 | 中位总 133.00 ms | 0.52 MB/s | 波动 1.02x
    --
    原生占全流水线: 2% (0.223 / 11.083 ms)
    parseXMLNode 占全流水线: 100% (11.083 / 11.083 ms)
    分相加总 vs 全流水线偏差: -2% (正常应 <10%)

--- parseXMLNode 多规模基准（变体冷路径 + 基线扣除） ---
  说明: 使用不同 seed 的 XML 变体轮转，避免 AVM 内部可能的字符串缓存。
        分别度量全流水线与纯 parseXMLNode 阶段。

  小(10项) | 1283 字符 | 64 变体
    全流水线(冷):   2.492 ms/次 | 8 批/轮 x32 = 256 次 | 中位总 638.00 ms | 0.49 MB/s | 波动 1.05x
    parseXMLNode(冷): 2.227 ms/次 | 8 批/轮 x32 = 256 次 | 中位总 570.00 ms | 0.55 MB/s | 波动 1.06x
    parseXMLNode(热): 2.297 ms/次 | 64 次/轮 | 中位总 147.00 ms | 0.53 MB/s | 波动 1.11x
    --
    parseXMLNode 占全流水线: 89% (2.227 / 2.492 ms)
    parseXMLNode 冷/热 = 0.97x

  中(50项) | 6007 字符 | 64 变体
    全流水线(冷):   12.031 ms/次 | 4 批/轮 x32 = 128 次 | 中位总 1540.00 ms | 0.48 MB/s | 波动 1.01x
    parseXMLNode(冷): 11.563 ms/次 | 4 批/轮 x32 = 128 次 | 中位总 1480.00 ms | 0.50 MB/s | 波动 1.01x
    parseXMLNode(热): 11.500 ms/次 | 16 次/轮 | 中位总 184.00 ms | 0.50 MB/s | 波动 1.07x
    --
    parseXMLNode 占全流水线: 96% (11.563 / 12.031 ms)
    parseXMLNode 冷/热 = 1.01x

  大(200项) | 24176 字符 | 32 变体
    全流水线(冷):   47.969 ms/次 | 2 批/轮 x16 = 32 次 | 中位总 1535.00 ms | 0.48 MB/s | 波动 1.07x
    parseXMLNode(冷): 45.969 ms/次 | 2 批/轮 x16 = 32 次 | 中位总 1471.00 ms | 0.50 MB/s | 波动 1.02x
    parseXMLNode(热): 46.875 ms/次 | 8 次/轮 | 中位总 375.00 ms | 0.49 MB/s | 波动 1.04x
    --
    parseXMLNode 占全流水线: 96% (45.969 / 47.969 ms)
    parseXMLNode 冷/热 = 0.98x

--- 热点剖析（微基准） ---
  说明: 对 parseXMLNode 内部各热点独立计时，定位时间分布。
        isValidXML 使用累积模式（模拟递归中每层都调用的真实 O(N^2) 行为）。

  isValidXML 累积成本（50 项，模拟递归调用模式）
    真实行为: parseXMLNode 每层递归入口调用 isValidXML(node)，
    而 isValidXML 自身递归验证整个子树 → 总复杂度 O(N^2)。
    元素节点数: 213
    isValidXML(累积): 4.250 ms/次 | 32 次/轮 | 中位总 136.00 ms | 波动 1.10x
    parseXMLNode:     10.750 ms/次 | 12 次/轮 | 中位总 129.00 ms | 波动 1.13x
    isValidXML 累积占 parseXMLNode: 40% (4.250 / 10.750 ms)

  属性迭代（50 项 XML 的 item 节点，每节点 4 属性）
    item 节点数: 50
    属性迭代:         19.22 us/次 | 128 批/轮 x50 = 6400 次 | 中位总 123.00 ms | 波动 1.05x

  同名节点数组提升（模拟 50 项 XML 的碰撞模式）
    模式: 50 个 item 同名 + tags/tag 同名 + 少量单出现节点。
    pairs 数: 52
    数组提升:         83.33 us/次 | 1536 次/轮 | 中位总 128.00 ms | 波动 1.03x

  Description 完整路径（密集模式：每项都有 Description）
    真实路径: getInnerText(node) 内调 decodeHTML → 外层再调 decodeHTML（双重解码）。
    Description 节点数: 50
    Description全路径: 0.365 ms/次 | 8 批/轮 x50 = 400 次 | 中位总 146.00 ms | 波动 1.06x
    单独 decodeHTML:  0.207 ms/次 | 12 批/轮 x50 = 600 次 | 中位总 124.00 ms | 波动 1.04x
    完整路径 / 单独 decodeHTML = 1.77x

  convertDataType（240 值轮转）
    convertDataType:  3.91 us/次 | 768 批/轮 x60 = 46080 次 | 中位总 180.00 ms | 波动 1.10x

  --- 各热点占 parseXMLNode 总耗时占比 ---
    parseXMLNode(参照): 10.750 ms/次 | 12 次/轮 | 中位总 129.00 ms | 波动 1.13x
    isValidXML(累积):  40% (4.250 / 10.750 ms)
    属性迭代:          0% (0.019 / 10.750 ms)
    数组提升:          1% (0.083 / 10.750 ms)
    Description全路径: 3% (0.365 / 10.750 ms)
    convertDataType:   0% (0.004 / 10.750 ms)
    已解释: 40% | 未解释（递归/对象创建/childNodes访问等）: 60%

========== 测试结束 ==========
