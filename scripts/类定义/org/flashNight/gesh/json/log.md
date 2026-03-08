╔══════════════════════════════════════════════════╗
║      JSON 解析器正确性、差异行为与性能测试       ║
╚══════════════════════════════════════════════════╝

========== 正确性与差异行为 ==========

--- parse: 基本类型 ---
[PASS] JSON parse null (expected type=null, actual type=null)
[PASS] JSON parse true (expected=true, actual=true)
[PASS] JSON parse false (expected=false, actual=false)
[PASS] JSON parse 整数 42 (expected=42, actual=42)
[PASS] JSON parse 浮点数 3.14 (expected=3.14, actual=3.14)
[PASS] JSON parse 负整数 -7 (expected=-7, actual=-7)
[PASS] JSON parse 零 (expected=0, actual=0)
[PASS] JSON parse 字符串 hello (expected=hello, actual=hello)
[PASS] JSON parse 空字符串 (expected=, actual=)
[PASS] LiteJSON parse null (expected type=null, actual type=null)
[PASS] LiteJSON parse true (expected=true, actual=true)
[PASS] LiteJSON parse false (expected=false, actual=false)
[PASS] LiteJSON parse 整数 42 (expected=42, actual=42)
[PASS] LiteJSON parse 浮点数 3.14 (expected=3.14, actual=3.14)
[PASS] LiteJSON parse 负整数 -7 (expected=-7, actual=-7)
[PASS] LiteJSON parse 零 (expected=0, actual=0)
[PASS] LiteJSON parse 字符串 hello (expected=hello, actual=hello)
[PASS] LiteJSON parse 空字符串 (expected=, actual=)
[PASS] FastJSON parse null (expected type=null, actual type=null)
[PASS] FastJSON parse true (expected=true, actual=true)
[PASS] FastJSON parse false (expected=false, actual=false)
[PASS] FastJSON parse 整数 42 (expected=42, actual=42)
[PASS] FastJSON parse 浮点数 3.14 (expected=3.14, actual=3.14)
[PASS] FastJSON parse 负整数 -7 (expected=-7, actual=-7)
[PASS] FastJSON parse 零 (expected=0, actual=0)
[PASS] FastJSON parse 字符串 hello (expected=hello, actual=hello)
[PASS] FastJSON parse 空字符串 (expected=, actual=)

--- parse: 容器与深层结构 ---
[PASS] JSON parse 空数组
[PASS] JSON parse 数字数组
[PASS] JSON parse 字符串数组
[PASS] JSON parse 混合数组
[PASS] JSON parse 嵌套数组
[PASS] JSON parse 三层空嵌套
[PASS] JSON parse 空对象
[PASS] JSON 对象.name (expected=Alice, actual=Alice)
[PASS] JSON 对象.age (expected=30, actual=30)
[PASS] LiteJSON parse 空数组
[PASS] LiteJSON parse 数字数组
[PASS] LiteJSON parse 字符串数组
[PASS] LiteJSON parse 混合数组
[PASS] LiteJSON parse 嵌套数组
[PASS] LiteJSON parse 三层空嵌套
[PASS] LiteJSON parse 空对象
[PASS] LiteJSON 对象.name (expected=Alice, actual=Alice)
[PASS] LiteJSON 对象.age (expected=30, actual=30)
[PASS] FastJSON parse 空数组
[PASS] FastJSON parse 数字数组
[PASS] FastJSON parse 字符串数组
[PASS] FastJSON parse 混合数组
[PASS] FastJSON parse 嵌套数组
[PASS] FastJSON parse 三层空嵌套
[PASS] FastJSON parse 空对象
[PASS] FastJSON 对象.name (expected=Alice, actual=Alice)
[PASS] FastJSON 对象.age (expected=30, actual=30)
[PASS] JSON 嵌套 user.name (expected=Bob, actual=Bob)
[PASS] JSON 嵌套 user.scores
[PASS] JSON 嵌套 user.address.city (expected=NYC, actual=NYC)
[PASS] LiteJSON 嵌套 user.name (expected=Bob, actual=Bob)
[PASS] LiteJSON 嵌套 user.scores
[PASS] LiteJSON 嵌套 user.address.city (expected=NYC, actual=NYC)
[PASS] FastJSON 嵌套 user.name (expected=Bob, actual=Bob)
[PASS] FastJSON 嵌套 user.scores
[PASS] FastJSON 嵌套 user.address.city (expected=NYC, actual=NYC)
[PASS] JSON 32层深嵌套 (expected=1, actual=1)
[PASS] LiteJSON 32层深嵌套 (expected=1, actual=1)
[PASS] FastJSON 32层深嵌套 (expected=1, actual=1)

--- parse: 转义字符 ---
[PASS] JSON \n\t\r (expected=line1
line2	tab
ret, actual=line1
line2	tab
ret)
[PASS] LiteJSON \n\t\r (expected=line1
line2	tab
ret, actual=line1
line2	tab
ret)
[PASS] FastJSON \n\t\r (expected=line1
line2	tab
ret, actual=line1
line2	tab
ret)
[PASS] JSON 反斜杠 (expected=C:\Users\test, actual=C:\Users\test)
[PASS] JSON 引号转义 (expected=He said "hi", actual=He said "hi")
[PASS] LiteJSON 反斜杠 (expected=C:\Users\test, actual=C:\Users\test)
[PASS] LiteJSON 引号转义 (expected=He said "hi", actual=He said "hi")
[PASS] FastJSON 反斜杠 (expected=C:\Users\test, actual=C:\Users\test)
[PASS] FastJSON 引号转义 (expected=He said "hi", actual=He said "hi")
[PASS] JSON \/ 转义 (expected=http://example.com, actual=http://example.com)
[PASS] LiteJSON \/ 转义 (expected=http://example.com, actual=http://example.com)
[PASS] FastJSON \/ 转义 (expected=http://example.com, actual=http://example.com)
[PASS] JSON Unicode \u002C (expected=Hello,World, actual=Hello,World)
[PASS] FastJSON Unicode \u002C (expected=Hello,World, actual=Hello,World)
[PASS] JSON 连续 Unicode (expected=Hi, actual=Hi)
[PASS] FastJSON 连续 Unicode (expected=Hi, actual=Hi)
[PASS] JSON parse \b\f (expected=, actual=)
[PASS] FastJSON parse \b\f (expected=, actual=)
[PASS] JSON 连续转义序列 (expected=
	
\, actual=
	
\)
[PASS] LiteJSON 连续转义序列 (expected=
	
\, actual=
	
\)
[PASS] FastJSON 连续转义序列 (expected=
	
\, actual=
	
\)

--- parse: 数字与空白 ---
[PASS] JSON parse 零 (expected=0, actual=0)
[PASS] JSON parse 0.5 (expected=0.5, actual=0.5)
[PASS] JSON parse -3.14 (expected=-3.14, actual=-3.14)
[PASS] JSON parse 999 (expected=999, actual=999)
[PASS] JSON parse -0 (expected=0, actual=0)
[PASS] JSON parse 大整数 (expected=123456789, actual=123456789)
[PASS] JSON parse 极小小数 (expected=0.001, actual=0.001)
[PASS] LiteJSON parse 零 (expected=0, actual=0)
[PASS] LiteJSON parse 0.5 (expected=0.5, actual=0.5)
[PASS] LiteJSON parse -3.14 (expected=-3.14, actual=-3.14)
[PASS] LiteJSON parse 999 (expected=999, actual=999)
[PASS] LiteJSON parse -0 (expected=0, actual=0)
[PASS] LiteJSON parse 大整数 (expected=123456789, actual=123456789)
[PASS] LiteJSON parse 极小小数 (expected=0.001, actual=0.001)
[PASS] FastJSON parse 零 (expected=0, actual=0)
[PASS] FastJSON parse 0.5 (expected=0.5, actual=0.5)
[PASS] FastJSON parse -3.14 (expected=-3.14, actual=-3.14)
[PASS] FastJSON parse 999 (expected=999, actual=999)
[PASS] FastJSON parse -0 (expected=0, actual=0)
[PASS] FastJSON parse 大整数 (expected=123456789, actual=123456789)
[PASS] FastJSON parse 极小小数 (expected=0.001, actual=0.001)
[PASS] JSON parse 1e2 (expected=100, actual=100)
[PASS] FastJSON parse 1e2 (expected=100, actual=100)
[PASS] JSON 空白字符 a (expected=1, actual=1)
[PASS] JSON 空白字符 b
[PASS] LiteJSON 空白字符 a (expected=1, actual=1)
[PASS] LiteJSON 空白字符 b
[PASS] FastJSON 空白字符 a (expected=1, actual=1)
[PASS] FastJSON 空白字符 b

--- parse: 边界行为 ---
[PASS] JSON 空白字符串值 (expected=   , actual=   )
[PASS] JSON 字符串含 JSON 语法 (expected={ "a": [1,2] }, actual={ "a": [1,2] })
[PASS] LiteJSON 空白字符串值 (expected=   , actual=   )
[PASS] LiteJSON 字符串含 JSON 语法 (expected={ "a": [1,2] }, actual={ "a": [1,2] })
[PASS] FastJSON 空白字符串值 (expected=   , actual=   )
[PASS] FastJSON 字符串含 JSON 语法 (expected={ "a": [1,2] }, actual={ "a": [1,2] })
[PASS] JSON 长字符串长度 (expected=800, actual=800)
[PASS] JSON 重复键后者覆盖 (expected=2, actual=2)
[PASS] LiteJSON 长字符串长度 (expected=800, actual=800)
[PASS] LiteJSON 重复键后者覆盖 (expected=2, actual=2)
[PASS] FastJSON 长字符串长度 (expected=800, actual=800)
[PASS] FastJSON 重复键后者覆盖 (expected=2, actual=2)
[PASS] JSON 100 元素数组长度 (expected=100, actual=100)
[PASS] JSON 100 元素数组首 (expected=0, actual=0)
[PASS] JSON 100 元素数组末 (expected=99, actual=99)
[PASS] LiteJSON 100 元素数组长度 (expected=100, actual=100)
[PASS] LiteJSON 100 元素数组首 (expected=0, actual=0)
[PASS] LiteJSON 100 元素数组末 (expected=99, actual=99)
[PASS] FastJSON 100 元素数组长度 (expected=100, actual=100)
[PASS] FastJSON 100 元素数组首 (expected=0, actual=0)
[PASS] FastJSON 100 元素数组末 (expected=99, actual=99)

--- stringify: 基本行为 ---
[PASS] JSON stringify null (expected=null, actual=null)
[PASS] JSON stringify true (expected=true, actual=true)
[PASS] JSON stringify false (expected=false, actual=false)
[PASS] JSON stringify 42 (expected=42, actual=42)
[PASS] JSON stringify string (expected="hello", actual="hello")
[PASS] JSON stringify [] (expected=[], actual=[])
[PASS] JSON stringify {} (expected={}, actual={})
[PASS] JSON stringify undefined (expected=null, actual=null)
[PASS] JSON stringify NaN (expected=null, actual=null)
[PASS] JSON stringify Infinity (expected=null, actual=null)
[PASS] JSON stringify -Infinity (expected=null, actual=null)
[PASS] JSON stringify 空串 (expected="", actual="")
[PASS] JSON stringify 0 (expected=0, actual=0)
[PASS] LiteJSON stringify null (expected=null, actual=null)
[PASS] LiteJSON stringify true (expected=true, actual=true)
[PASS] LiteJSON stringify false (expected=false, actual=false)
[PASS] LiteJSON stringify 42 (expected=42, actual=42)
[PASS] LiteJSON stringify string (expected="hello", actual="hello")
[PASS] LiteJSON stringify [] (expected=[], actual=[])
[PASS] LiteJSON stringify {} (expected={}, actual={})
[PASS] LiteJSON stringify undefined (expected=null, actual=null)
[PASS] LiteJSON stringify NaN (expected=null, actual=null)
[PASS] LiteJSON stringify Infinity (expected=null, actual=null)
[PASS] LiteJSON stringify -Infinity (expected=null, actual=null)
[PASS] LiteJSON stringify 空串 (expected="", actual="")
[PASS] LiteJSON stringify 0 (expected=0, actual=0)
[PASS] FastJSON stringify null (expected=null, actual=null)
[PASS] FastJSON stringify true (expected=true, actual=true)
[PASS] FastJSON stringify false (expected=false, actual=false)
[PASS] FastJSON stringify 42 (expected=42, actual=42)
[PASS] FastJSON stringify string (expected="hello", actual="hello")
[PASS] FastJSON stringify [] (expected=[], actual=[])
[PASS] FastJSON stringify {} (expected={}, actual={})
[PASS] FastJSON stringify undefined (expected=null, actual=null)
[PASS] FastJSON stringify NaN (expected=null, actual=null)
[PASS] FastJSON stringify Infinity (expected=null, actual=null)
[PASS] FastJSON stringify -Infinity (expected=null, actual=null)
[PASS] FastJSON stringify 空串 (expected="", actual="")
[PASS] FastJSON stringify 0 (expected=0, actual=0)
[PASS] JSON 特殊键名空格 (expected=1, actual=1)
[PASS] JSON 特殊键名引号 (expected=2, actual=2)
[PASS] LiteJSON 特殊键名空格 (expected=1, actual=1)
[PASS] LiteJSON 特殊键名引号 (expected=2, actual=2)
[PASS] FastJSON 特殊键名空格 (expected=1, actual=1)
[PASS] FastJSON 特殊键名引号 (expected=2, actual=2)

--- stringify: undefined / function 过滤 ---
[PASS] JSON 保留普通属性 (expected=1, actual=1)
[PASS] JSON 跳过 undefined 属性
[PASS] JSON 跳过 function 属性
[PASS] LiteJSON 保留普通属性 (expected=1, actual=1)
[PASS] LiteJSON 跳过 undefined 属性
[PASS] LiteJSON 跳过 function 属性
[PASS] FastJSON 保留普通属性 (expected=1, actual=1)
[PASS] FastJSON 跳过 undefined 属性
[PASS] FastJSON 跳过 function 属性
[PASS] JSON 数组元素 0 (expected=1, actual=1)
[PASS] JSON 数组 undefined -> null (expected type=null, actual type=null)
[PASS] JSON 数组 null 保留 (expected type=null, actual type=null)
[PASS] JSON 数组元素 3 (expected=4, actual=4)
[PASS] LiteJSON 数组元素 0 (expected=1, actual=1)
[PASS] LiteJSON 数组 undefined -> null (expected type=null, actual type=null)
[PASS] LiteJSON 数组 null 保留 (expected type=null, actual type=null)
[PASS] LiteJSON 数组元素 3 (expected=4, actual=4)
[PASS] FastJSON 数组元素 0 (expected=1, actual=1)
[PASS] FastJSON 数组 undefined -> null (expected type=null, actual type=null)
[PASS] FastJSON 数组 null 保留 (expected type=null, actual type=null)
[PASS] FastJSON 数组元素 3 (expected=4, actual=4)

--- stringify: 转义与控制字符 ---
[PASS] JSON stringify 含 \n (needle=\n)
[PASS] JSON stringify 含 \t (needle=\t)
[PASS] JSON stringify 含 \r (needle=\r)
[PASS] JSON stringify 引号转义 (needle=\")
[PASS] JSON stringify 反斜杠转义 (needle=\\)
[PASS] LiteJSON stringify 含 \n (needle=\n)
[PASS] LiteJSON stringify 含 \t (needle=\t)
[PASS] LiteJSON stringify 含 \r (needle=\r)
[PASS] LiteJSON stringify 引号转义 (needle=\")
[PASS] LiteJSON stringify 反斜杠转义 (needle=\\)
[PASS] FastJSON stringify 含 \n (needle=\n)
[PASS] FastJSON stringify 含 \t (needle=\t)
[PASS] FastJSON stringify 含 \r (needle=\r)
[PASS] FastJSON stringify 引号转义 (needle=\")
[PASS] FastJSON stringify 反斜杠转义 (needle=\\)
[PASS] JSON stringify 含 \b (needle=\b)
[PASS] JSON stringify 含 \f (needle=\f)
[PASS] FastJSON stringify 含 \b (needle=\b)
[PASS] FastJSON stringify 含 \f (needle=\f)
[PASS] JSON stringify 控制字符转 \u (needle=\u0001)
[PASS] LiteJSON stringify 控制字符转 \u (needle=\u0001)
[PASS] FastJSON stringify 控制字符转 \u (needle=\u0001)

--- roundtrip: 往返一致性 ---
[PASS] JSON RT name (expected=测试, actual=测试)
[PASS] JSON RT value (expected=3.14, actual=3.14)
[PASS] JSON RT active (expected=true, actual=true)
[PASS] JSON RT tags
[PASS] JSON RT nested
[PASS] JSON RT arr
[PASS] JSON RT nullVal (expected type=null, actual type=null)
[PASS] JSON RT zero (expected=0, actual=0)
[PASS] JSON RT emptyStr (expected=, actual=)
[PASS] JSON RT emptyArr
[PASS] LiteJSON RT name (expected=测试, actual=测试)
[PASS] LiteJSON RT value (expected=3.14, actual=3.14)
[PASS] LiteJSON RT active (expected=true, actual=true)
[PASS] LiteJSON RT tags
[PASS] LiteJSON RT nested
[PASS] LiteJSON RT arr
[PASS] LiteJSON RT nullVal (expected type=null, actual type=null)
[PASS] LiteJSON RT zero (expected=0, actual=0)
[PASS] LiteJSON RT emptyStr (expected=, actual=)
[PASS] LiteJSON RT emptyArr
[PASS] FastJSON RT name (expected=测试, actual=测试)
[PASS] FastJSON RT value (expected=3.14, actual=3.14)
[PASS] FastJSON RT active (expected=true, actual=true)
[PASS] FastJSON RT tags
[PASS] FastJSON RT nested
[PASS] FastJSON RT arr
[PASS] FastJSON RT nullVal (expected type=null, actual type=null)
[PASS] FastJSON RT zero (expected=0, actual=0)
[PASS] FastJSON RT emptyStr (expected=, actual=)
[PASS] FastJSON RT emptyArr

--- 差异: 引用语义与缓存副作用 ---
[PASS] JSON 重复 parse 返回新对象
[PASS] LiteJSON 重复 parse 返回新对象
[PASS] FastJSON 重复 parse 返回同一引用
[PASS] FastJSON parse 缓存共享已修改对象 (expected=99, actual=99)
[PASS] JSON stringify 反映对象变更 (expected={"value":2}, actual={"value":2})
[PASS] LiteJSON stringify 反映对象变更 (expected={"value":2}, actual={"value":2})
[PASS] FastJSON stringify 使用旧缓存结果 (expected={"value":1}, actual={"value":1})

--- 差异: 非法数字 fallback ---
[PASS] JSON 解析不完整指数 1e (expected=1, actual=1)
[PASS] JSON 不完整指数 1e 不记录错误 (expected=0, actual=0)
[PASS] LiteJSON 解析不完整指数 1e (expected=1, actual=1)
[PASS] FastJSON 接受不完整指数 1e
[PASS] FastJSON 解析不完整指数 1e (expected=1, actual=1)

--- 差异: LiteJSON / FastJSON 已知行为 ---
[PASS] LiteJSON 不支持 Unicode 转义 (expected=u0041u4E2D, actual=u0041u4E2D)
[PASS] LiteJSON 不支持 \b\f 还原 (expected=bf, actual=bf)
[PASS] LiteJSON 不支持科学记数法 (expected=1, actual=1)
[PASS] LiteJSON 忽略根值后的 trailing token (expected=1, actual=1)
[PASS] JSON 记录 trailing token 错误 (errors=1)
[PASS] JSON 仍保留已解析根对象 (expected=1, actual=1)
[PASS] FastJSON trailing token 直接抛错
[PASS] LiteJSON stringify 输出 \b\f (expected="\b\f", actual="\b\f")
[PASS] LiteJSON parse 自身 stringify 后无法恢复 \b\f (expected=bf, actual=bf)

--- 错误处理: 非法输入 ---
[PASS] JSON 记录错误: 缺少冒号 (errors=2)
[PASS] FastJSON 抛错: 缺少冒号
[PASS] LiteJSON 尝试容错: 缺少冒号
[PASS] JSON 容错: 对象尾逗号 (expected=0, actual=0)
[PASS] JSON 对象尾逗号仍保留已解析属性 (expected=1, actual=1)
[PASS] FastJSON 容错: 对象尾逗号
[PASS] FastJSON 对象尾逗号仍保留已解析属性 (expected=1, actual=1)
[PASS] LiteJSON 尝试容错: 对象尾逗号
[PASS] JSON 记录错误: 数组未闭合 (errors=1)
[PASS] FastJSON 抛错: 数组未闭合
[INFO] LiteJSON 跳过: 数组未闭合（已知 EOF 死循环风险）
[PASS] JSON 记录错误: 非法 Unicode (errors=1)
[PASS] FastJSON 抛错: 非法 Unicode
[PASS] LiteJSON 尝试容错: 非法 Unicode

--- 跨解析器一致性 ---
[PASS] JSON -> LiteJSON 一致
[PASS] JSON -> FastJSON 一致
[PASS] LiteJSON -> JSON 一致
[PASS] LiteJSON -> FastJSON 一致
[PASS] FastJSON -> JSON 一致
[PASS] FastJSON -> LiteJSON 一致

--- benchmark: 负载自校验 ---
[PASS] 生成 benchmark 变体数量 (expected=4, actual=4)
[PASS] benchmark 相邻字符串变体不同
[PASS] benchmark 对象变体 A seed (expected=0, actual=0)
[PASS] benchmark 对象变体 B seed (expected=1, actual=1)
[PASS] benchmark 对象变体互不共享引用
[PASS] FastJSON 失配路径不复用不同字符串的 parse 引用
[PASS] FastJSON 失配路径保留 A seed (expected=0, actual=0)
[PASS] FastJSON 失配路径保留 B seed (expected=1, actual=1)
[PASS] FastJSON 严格冷启动 parse 不共享引用
[PASS] FastJSON 严格冷启动 stringify 不复用旧缓存

---------- 正确性汇总 ----------
通过: 305 / 305  失败: 0

========== 性能基准 ==========

--- parse 性能基准（等价路径 + 基线扣除） ---
  说明: FastJSON 失配 = 同实例不同 payload；严冷 = 每次操作新建实例；热 = 缓存命中。
  冷路径: 使用有限变体循环并按批次聚合多次冷操作，避免缓存复用同时维持计时置信度。

  小(10项) | 895 字符
    JSON:         3.325 ms/次 | 40 次/轮 | 中位总 133.00 ms | 0.26 MB/s | 波动 1.03x
    LiteJSON:     1.016 ms/次 | 128 次/轮 | 中位总 130.00 ms | 0.84 MB/s | 波动 1.05x
    FastJSON(失配): 1.059 ms/次 | 8 批/轮 x32 = 256 次 | 中位总 271.00 ms | 0.81 MB/s | 波动 1.02x
    FastJSON(严冷): 1.074 ms/次 | 8 批/轮 x32 = 256 次 | 中位总 275.00 ms | 0.79 MB/s | 波动 1.02x
    FastJSON(热): 3.26 us/次 | 50000 次/轮 | 中位总 163.00 ms | 261.82 MB/s | 波动 1.03x
    --
    JSON / LiteJSON = 3.27x
    LiteJSON / FastJSON(严冷) = 0.95x
    FastJSON 严冷 / 失配 = 1.01x
    FastJSON 失配 / 热 = 324.72x
    FastJSON 严冷 / 热 = 329.51x

  中(50项) | 4035 字符
    JSON:         14.800 ms/次 | 10 次/轮 | 中位总 148.00 ms | 0.26 MB/s | 波动 1.03x
    LiteJSON:     4.406 ms/次 | 32 次/轮 | 中位总 141.00 ms | 0.87 MB/s | 波动 1.07x
    FastJSON(失配): 4.734 ms/次 | 4 批/轮 x64 = 256 次 | 中位总 1212.00 ms | 0.81 MB/s | 波动 1.03x
    FastJSON(严冷): 4.695 ms/次 | 4 批/轮 x64 = 256 次 | 中位总 1202.00 ms | 0.82 MB/s | 波动 1.02x
    FastJSON(热): 8.93 us/次 | 14336 次/轮 | 中位总 128.00 ms | 430.98 MB/s | 波动 1.06x
    --
    JSON / LiteJSON = 3.36x
    LiteJSON / FastJSON(严冷) = 0.94x
    FastJSON 严冷 / 失配 = 0.99x
    FastJSON 失配 / 热 = 530.25x
    FastJSON 严冷 / 热 = 525.88x

  大(200项) | 16244 字符
    JSON:         59.000 ms/次 | 4 次/轮 | 中位总 236.00 ms | 0.26 MB/s | 波动 1.06x
    LiteJSON:     18.000 ms/次 | 7 次/轮 | 中位总 126.00 ms | 0.86 MB/s | 波动 1.15x
    FastJSON(失配): 18.523 ms/次 | 2 批/轮 x64 = 128 次 | 中位总 2371.00 ms | 0.84 MB/s | 波动 1.01x
    FastJSON(严冷): 18.500 ms/次 | 2 批/轮 x64 = 128 次 | 中位总 2368.00 ms | 0.84 MB/s | 波动 1.00x
    FastJSON(热): 31.25 us/次 | 4096 次/轮 | 中位总 128.00 ms | 495.73 MB/s | 波动 1.03x
    --
    JSON / LiteJSON = 3.28x
    LiteJSON / FastJSON(严冷) = 0.97x
    FastJSON 严冷 / 失配 = 1.00x
    FastJSON 失配 / 热 = 592.75x
    FastJSON 严冷 / 热 = 592.00x

--- stringify 性能基准（等价路径 + 基线扣除） ---
  说明: FastJSON 失配 = 同实例不同对象；严冷 = 每次操作新建实例；热 = 同对象命中身份缓存。
  冷路径: 使用有限对象变体循环并按批次聚合多次冷操作，避免缓存复用同时维持计时置信度。

  小(10项) | 约 895 输出字符
    JSON:         0.867 ms/次 | 256 次/轮 | 中位总 222.00 ms | 0.98 MB/s | 波动 1.05x
    LiteJSON:     0.984 ms/次 | 128 次/轮 | 中位总 126.00 ms | 0.87 MB/s | 波动 1.06x
    FastJSON(失配): 0.992 ms/次 | 8 批/轮 x32 = 256 次 | 中位总 254.00 ms | 0.86 MB/s | 波动 1.03x
    FastJSON(严冷): 1.004 ms/次 | 8 批/轮 x32 = 256 次 | 中位总 257.00 ms | 0.85 MB/s | 波动 1.04x
    FastJSON(热): 2.82 us/次 | 50000 次/轮 | 中位总 141.00 ms | 302.67 MB/s | 波动 1.04x
    --
    JSON / LiteJSON = 0.88x
    LiteJSON / FastJSON(严冷) = 0.98x
    FastJSON 严冷 / 失配 = 1.01x
    FastJSON 失配 / 热 = 351.84x
    FastJSON 严冷 / 热 = 356.00x

  中(50项) | 约 4035 输出字符
    JSON:         3.844 ms/次 | 32 次/轮 | 中位总 123.00 ms | 1.00 MB/s | 波动 1.02x
    LiteJSON:     4.393 ms/次 | 28 次/轮 | 中位总 123.00 ms | 0.88 MB/s | 波动 1.07x
    FastJSON(失配): 4.352 ms/次 | 4 批/轮 x64 = 256 次 | 中位总 1114.00 ms | 0.88 MB/s | 波动 1.01x
    FastJSON(严冷): 4.363 ms/次 | 4 批/轮 x64 = 256 次 | 中位总 1117.00 ms | 0.88 MB/s | 波动 1.01x
    FastJSON(热): 2.80 us/次 | 30000 次/轮 | 中位总 84.00 ms | 1374.31 MB/s | 波动 1.10x
    --
    JSON / LiteJSON = 0.87x
    LiteJSON / FastJSON(严冷) = 1.01x
    FastJSON 严冷 / 失配 = 1.00x
    FastJSON 失配 / 热 = 1554.13x
    FastJSON 严冷 / 热 = 1558.31x

  大(200项) | 约 16244 输出字符
    JSON:         15.250 ms/次 | 8 次/轮 | 中位总 122.00 ms | 1.02 MB/s | 波动 1.04x
    LiteJSON:     17.125 ms/次 | 8 次/轮 | 中位总 137.00 ms | 0.90 MB/s | 波动 1.03x
    FastJSON(失配): 17.000 ms/次 | 2 批/轮 x64 = 128 次 | 中位总 2176.00 ms | 0.91 MB/s | 波动 1.01x
    FastJSON(严冷): 17.070 ms/次 | 2 批/轮 x64 = 128 次 | 中位总 2185.00 ms | 0.91 MB/s | 波动 1.01x
    FastJSON(热): 2.92 us/次 | 12000 次/轮 | 中位总 35.00 ms | 5311.37 MB/s | 波动 1.12x
    --
    JSON / LiteJSON = 0.89x
    LiteJSON / FastJSON(严冷) = 1.00x
    FastJSON 严冷 / 失配 = 1.00x
    FastJSON 失配 / 热 = 5828.57x
    FastJSON 严冷 / 热 = 5852.68x

--- FastJSON 缓存专项（中规模） ---
  说明: 失配 = 同实例不同 payload；严冷 = 每次新实例；热 = 同 payload / 同对象命中缓存。
  风险: parse 热共享对象引用；stringify 热可能返回旧缓存字符串。
  parse
    失配: 4.785 ms/次 | 4 批/轮 x64 = 256 次 | 中位总 1225.00 ms | 0.80 MB/s | 波动 1.02x
    严冷: 4.766 ms/次 | 4 批/轮 x64 = 256 次 | 中位总 1220.00 ms | 0.81 MB/s | 波动 1.02x
    热: 9.14 us/次 | 14336 次/轮 | 中位总 131.00 ms | 421.11 MB/s | 波动 1.05x
    严冷 / 失配 = 1.00x
    失配 / 热 = 523.66x
    严冷 / 热 = 521.53x
  stringify
    失配: 4.355 ms/次 | 4 批/轮 x64 = 256 次 | 中位总 1115.00 ms | 0.88 MB/s | 波动 1.03x
    严冷: 4.414 ms/次 | 4 批/轮 x64 = 256 次 | 中位总 1130.00 ms | 0.87 MB/s | 波动 1.01x
    热: 2.80 us/次 | 30000 次/轮 | 中位总 84.00 ms | 1374.31 MB/s | 波动 1.07x
    严冷 / 失配 = 1.01x
    失配 / 热 = 1555.52x
    严冷 / 热 = 1576.45x

========== 测试结束 ==========
