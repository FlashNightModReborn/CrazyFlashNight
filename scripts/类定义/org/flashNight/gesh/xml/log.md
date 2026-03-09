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

---------- 自校验汇总 ----------
通过: 55 / 55  失败: 0

========== 性能基准 ==========

--- 分相分解（50 项） ---
  说明: 将全流水线拆为「原生 XML.parseXML」与「XMLParser.parseXMLNode」两阶段
        独立度量，定位时间到底花在 C++ 还是 AS2。

  50 项 | 6007 字符
    全流水线:      3.063 ms/次 | 64 次/轮 | 中位总 196.00 ms | 1.87 MB/s | 波动 1.05x
    原生 parseXML: 0.146 ms/次 | 512 次/轮 | 中位总 75.00 ms | 39.11 MB/s | 波动 1.16x
    parseXMLNode:  2.531 ms/次 | 64 次/轮 | 中位总 162.00 ms | 2.26 MB/s | 波动 1.04x
    --
    原生占全流水线: 5% (0.146 / 3.063 ms)
    parseXMLNode 占全流水线: 83% (2.531 / 3.063 ms)
    分相加总 vs 全流水线偏差: 13% (正常应 <10%)

--- parseXMLNode 多规模基准（变体冷路径 + 基线扣除） ---
  说明: 使用不同 seed 的 XML 变体轮转，避免 AVM 内部可能的字符串缓存。
        分别度量全流水线与纯 parseXMLNode 阶段。

  小(10项) | 1283 字符 | 64 变体
    全流水线(冷):   0.672 ms/次 | 16 批/轮 x32 = 512 次 | 中位总 344.00 ms | 1.82 MB/s | 波动 1.03x
    parseXMLNode(冷): 0.549 ms/次 | 16 批/轮 x32 = 512 次 | 中位总 281.00 ms | 2.23 MB/s | 波动 1.03x
    parseXMLNode(热): 0.531 ms/次 | 256 次/轮 | 中位总 136.00 ms | 2.30 MB/s | 波动 1.02x
    --
    parseXMLNode 占全流水线: 82% (0.549 / 0.672 ms)
    parseXMLNode 冷/热 = 1.03x

  中(50项) | 6007 字符 | 64 变体
    全流水线(冷):   3.156 ms/次 | 4 批/轮 x32 = 128 次 | 中位总 404.00 ms | 1.82 MB/s | 波动 1.02x
    parseXMLNode(冷): 2.711 ms/次 | 4 批/轮 x32 = 128 次 | 中位总 347.00 ms | 2.11 MB/s | 波动 1.03x
    parseXMLNode(热): 2.708 ms/次 | 48 次/轮 | 中位总 130.00 ms | 2.12 MB/s | 波动 1.12x
    --
    parseXMLNode 占全流水线: 86% (2.711 / 3.156 ms)
    parseXMLNode 冷/热 = 1.00x

  大(200项) | 24176 字符 | 32 变体
    全流水线(冷):   12.625 ms/次 | 2 批/轮 x16 = 32 次 | 中位总 404.00 ms | 1.83 MB/s | 波动 1.02x
    parseXMLNode(冷): 11.781 ms/次 | 2 批/轮 x16 = 32 次 | 中位总 377.00 ms | 1.96 MB/s | 波动 1.04x
    parseXMLNode(热): 11.563 ms/次 | 16 次/轮 | 中位总 185.00 ms | 1.99 MB/s | 波动 1.12x
    --
    parseXMLNode 占全流水线: 93% (11.781 / 12.625 ms)
    parseXMLNode 冷/热 = 1.02x

--- 热点剖析（微基准） ---
  说明: 对 parseXMLNode 内部各热点独立计时，定位时间分布。
        isValidXML 使用累积模式（模拟递归中每层都调用的真实 O(N^2) 行为）。

  isValidXML 累积成本（50 项，模拟递归调用模式）
    真实行为: parseXMLNode 每层递归入口调用 isValidXML(node)，
    而 isValidXML 自身递归验证整个子树 → 总复杂度 O(N^2)。
    元素节点数: 213
    isValidXML(累积): 2.188 ms/次 | 64 次/轮 | 中位总 140.00 ms | 波动 1.06x
    parseXMLNode:     2.609 ms/次 | 64 次/轮 | 中位总 167.00 ms | 波动 1.04x
    isValidXML 累积占 parseXMLNode: 84% (2.188 / 2.609 ms)

  属性迭代（50 项 XML 的 item 节点，每节点 4 属性）
    item 节点数: 50
    属性迭代:         13.85 us/次 | 192 批/轮 x50 = 9600 次 | 中位总 133.00 ms | 波动 1.12x

  同名节点数组提升（展平全树碰撞模式）
    模式: 根层 50 item 碰撞 + 50 item 各含 tags/Description +
          50 tags 各含 2 tag 碰撞。展平为单次循环测量总工作量。
    pairs 数: 212
    数组提升:         0.188 ms/次 | 1024 次/轮 | 中位总 192.00 ms | 波动 1.02x

  Description 完整路径（密集模式：每项都有 Description）
    真实路径: getInnerText(node) 内调 decodeHTML → 外层再调 decodeHTML（双重解码）。
    Description 节点数: 50
    Description全路径: 0.203 ms/次 | 12 批/轮 x50 = 600 次 | 中位总 122.00 ms | 波动 1.02x
    单独 decodeHTML:  0.119 ms/次 | 40 批/轮 x50 = 2000 次 | 中位总 238.00 ms | 波动 1.05x
    完整路径 / 单独 decodeHTML = 1.71x

  convertDataType（240 值轮转）
    convertDataType:  2.80 us/次 | 768 批/轮 x60 = 46080 次 | 中位总 129.00 ms | 波动 1.05x

  --- 各热点占 parseXMLNode 总耗时占比 ---
    parseXMLNode(参照): 2.609 ms/次 | 64 次/轮 | 中位总 167.00 ms | 波动 1.04x
    isValidXML(累积):  84% (2.188 / 2.609 ms)
    属性迭代:          1% (0.014 / 2.609 ms)
    数组提升:          7% (0.188 / 2.609 ms)
    Description全路径: 8% (0.203 / 2.609 ms)
    convertDataType:   0% (0.003 / 2.609 ms)
    已解释: 99% | 未解释（递归/对象创建/childNodes访问等）: 1%

--- 解析器 CPU 基准（启动语料分布） ---
  说明: 度量 parseXML + parseXMLNode 的纯 CPU 成本，不含 IO/路径解析/回调/日志。
        使用合成 XML 模拟 data/items/ 下 50 文件的真实分布。
        武器类用 weapon 生成器（~25 节点/item），防具类用 armor 生成器（~35 节点/item）。
        结果为「解析器内部先改哪里」的依据，不等于端到端初始化耗时。

  极小(2项) | 1215 字符 | 模拟 7 个文件
    全流水线:  0.359 ms/次 | 256 次/轮 | 中位总 92.00 ms | 3.22 MB/s | 波动 1.07x

  小(10项) | 6037 字符 | 模拟 17 个文件
    全流水线:  1.775 ms/次 | 80 次/轮 | 中位总 142.00 ms | 3.24 MB/s | 波动 1.07x

  中(22项) | 13348 字符 | 模拟 15 个文件
    全流水线:  3.813 ms/次 | 32 次/轮 | 中位总 122.00 ms | 3.34 MB/s | 波动 1.02x

  大(48项) | 29232 字符 | 模拟 5 个文件
    全流水线:  8.375 ms/次 | 16 次/轮 | 中位总 134.00 ms | 3.33 MB/s | 波动 1.15x

  超大(96项,武器类) | 58567 字符 | 模拟 2 个文件
    全流水线:  16.625 ms/次 | 8 次/轮 | 中位总 133.00 ms | 3.36 MB/s | 波动 1.02x

  超大(96项,防具类) | 47640 字符 | 模拟 2 个文件
    全流水线:  15.800 ms/次 | 10 次/轮 | 中位总 158.00 ms | 2.88 MB/s | 波动 1.17x

  巨型(217项,防具类) | 109308 字符 | 模拟 2 个文件
    全流水线:  36.500 ms/次 | 4 次/轮 | 中位总 146.00 ms | 2.86 MB/s | 波动 1.16x

  Array.concat 累积合并（50 文件, 1572 总物品）
    concat累积: 2.917 ms/次 | 48 次/轮 | 中位总 140.00 ms | 波动 1.06x

  --- 解析器 CPU 时间估算 ---
    注意: 仅含 parseXML + parseXMLNode，不含 IO/PathManager/日志/回调开销。
    真实初始化耗时 = 本值 + IO等待 + BaseXMLLoader开销 + ItemDataLoader串行调度。
    极小(2项) x7: 0.36 ms/文件 x7 = 2.52 ms
    小(10项) x17: 1.78 ms/文件 x17 = 30.17 ms
    中(22项) x15: 3.81 ms/文件 x15 = 57.19 ms
    大(48项) x5: 8.38 ms/文件 x5 = 41.88 ms
    超大(96项,武器类) x2: 16.63 ms/文件 x2 = 33.25 ms
    超大(96项,防具类) x2: 15.80 ms/文件 x2 = 31.60 ms
    巨型(217项,防具类) x2: 36.50 ms/文件 x2 = 73.00 ms
    concat: 2.92 ms
    --
    解析器纯 CPU 合计: 272.52 ms（不含 IO 及框架开销）

========== 测试结束 ==========
