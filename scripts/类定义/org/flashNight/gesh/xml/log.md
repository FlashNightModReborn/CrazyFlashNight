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
[PASS] Description 含已解码或原始 HTML
[PASS] convertDataType 值数组长度 (expected=12, actual=12)
[PASS] 值数组元素为字符串
[PASS] decodeHTML 字符串数组长度 (expected=6, actual=6)
[PASS] 含实体的 HTML 字符串正确
[PASS] 无实体的纯文本字符串正确
[PASS] 深层嵌套 XML 解析成功
[PASS] 深层嵌套 XML parseXMLNode 成功

---------- 自校验汇总 ----------
通过: 24 / 24  失败: 0

========== 性能基准 ==========

--- 分相分解（50 项） ---
  说明: 将全流水线拆为「原生 XML.parseXML」与「XMLParser.parseXMLNode」两阶段
        独立度量，定位时间到底花在 C++ 还是 AS2。

  50 项 | 6007 字符
    全流水线:      12.667 ms/次 | 12 次/轮 | 中位总 152.00 ms | 0.45 MB/s | 波动 1.09x
    原生 parseXML: 0.250 ms/次 | 512 次/轮 | 中位总 128.00 ms | 22.91 MB/s | 波动 1.07x
    parseXMLNode:  11.750 ms/次 | 12 次/轮 | 中位总 141.00 ms | 0.49 MB/s | 波动 1.04x
    --
    原生占全流水线: 2% (0.250 / 12.667 ms)
    parseXMLNode 占全流水线: 93% (11.750 / 12.667 ms)
    分相加总 vs 全流水线偏差: 5% (正常应 <10%)

--- parseXMLNode 多规模基准（变体冷路径 + 基线扣除） ---
  说明: 使用不同 seed 的 XML 变体轮转，避免 AVM 内部可能的字符串缓存。
        分别度量全流水线与纯 parseXMLNode 阶段。

  小(10项) | 1283 字符 | 64 变体
    全流水线(冷):   2.539 ms/次 | 8 批/轮 x32 = 256 次 | 中位总 650.00 ms | 0.48 MB/s | 波动 1.06x
    parseXMLNode(冷): 2.422 ms/次 | 8 批/轮 x32 = 256 次 | 中位总 620.00 ms | 0.51 MB/s | 波动 1.08x
    parseXMLNode(热): 2.469 ms/次 | 64 次/轮 | 中位总 158.00 ms | 0.50 MB/s | 波动 1.09x
    --
    parseXMLNode 占全流水线: 95% (2.422 / 2.539 ms)
    parseXMLNode 冷/热 = 0.98x

  中(50项) | 6007 字符 | 64 变体
    全流水线(冷):   12.516 ms/次 | 4 批/轮 x32 = 128 次 | 中位总 1602.00 ms | 0.46 MB/s | 波动 1.03x
    parseXMLNode(冷): 11.672 ms/次 | 4 批/轮 x32 = 128 次 | 中位总 1494.00 ms | 0.49 MB/s | 波动 1.05x
    parseXMLNode(热): 11.500 ms/次 | 16 次/轮 | 中位总 184.00 ms | 0.50 MB/s | 波动 1.08x
    --
    parseXMLNode 占全流水线: 93% (11.672 / 12.516 ms)
    parseXMLNode 冷/热 = 1.01x

  大(200项) | 24176 字符 | 32 变体
    全流水线(冷):   48.344 ms/次 | 2 批/轮 x16 = 32 次 | 中位总 1547.00 ms | 0.48 MB/s | 波动 1.04x
    parseXMLNode(冷): 49.219 ms/次 | 2 批/轮 x16 = 32 次 | 中位总 1575.00 ms | 0.47 MB/s | 波动 1.06x
    parseXMLNode(热): 48.875 ms/次 | 8 次/轮 | 中位总 391.00 ms | 0.47 MB/s | 波动 1.07x
    --
    parseXMLNode 占全流水线: 102% (49.219 / 48.344 ms)
    parseXMLNode 冷/热 = 1.01x

--- 热点剖析（微基准） ---
  说明: 对 isValidXML / convertDataType / decodeHTML 独立计时，
        定位 parseXMLNode 内部的时间分布。

  isValidXML（50 项 XML 的根节点）
    isValidXML:     1.391 ms/次 | 128 次/轮 | 中位总 178.00 ms | 波动 1.22x
    parseXMLNode:   11.167 ms/次 | 12 次/轮 | 中位总 134.00 ms | 波动 1.07x
    isValidXML 占 parseXMLNode: 12% (1.391 / 11.167 ms)

  convertDataType（240 值轮转）
    convertDataType: 3.91 us/次 | 1024 批/轮 x60 = 61440 次 | 中位总 240.00 ms | 波动 1.12x

  StringUtils.decodeHTML（90 字符串轮转）
    decodeHTML(混合): 0.197 ms/次 | 24 批/轮 x30 = 720 次 | 中位总 142.00 ms | 波动 1.11x
    decodeHTML(纯实体): 0.210 ms/次 | 20 批/轮 x30 = 600 次 | 中位总 126.00 ms | 波动 1.05x
    decodeHTML(纯文本): 0.185 ms/次 | 24 批/轮 x30 = 720 次 | 中位总 133.00 ms | 波动 1.12x
    --
    纯实体 / 纯文本 = 1.14x
    （若比值 >> 1 则说明短路优化有价值）

========== 测试结束 ==========
