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

---------- 正确性汇总 ----------
通过: 295 / 295  失败: 0

========== 性能基准 ==========

--- parse 性能基准（等价路径 + 基线扣除） ---
  说明: FastJSON 热路径代表缓存命中后的查表成本，不等于真实重新 parse。
  冷路径: 使用有限变体循环，变体耗尽后重建 FastJSON 实例，并按批次聚合多次冷操作以提高计时置信度。

  小(10项) | 895 字符
    JSON:         3.350 ms/次 | 40 次/轮 | 中位总 134.00 ms | 0.25 MB/s | 波动 1.05x
    LiteJSON:     0.992 ms/次 | 128 次/轮 | 中位总 127.00 ms | 0.86 MB/s | 波动 1.03x
    FastJSON(冷): 2.94 us/次 | 2560 批/轮 x32 = 81920 次 | 中位总 241.00 ms | 290.13 MB/s | 波动 1.02x
    FastJSON(热): 3.28 us/次 | 50000 次/轮 | 中位总 164.00 ms | 260.23 MB/s | 波动 1.04x
    --
    JSON / LiteJSON = 3.38x
    LiteJSON / FastJSON(冷) = 337.26x
    FastJSON 冷 / 热 = 0.90x

  中(50项) | 4035 字符
    JSON:         15.000 ms/次 | 8 次/轮 | 中位总 120.00 ms | 0.26 MB/s | 波动 1.05x
    LiteJSON:     4.500 ms/次 | 32 次/轮 | 中位总 144.00 ms | 0.86 MB/s | 波动 1.04x
    FastJSON(冷): 7.26 us/次 | 768 批/轮 x64 = 49152 次 | 中位总 357.00 ms | 529.81 MB/s | 波动 1.03x
    FastJSON(热): 9.00 us/次 | 14336 次/轮 | 中位总 129.00 ms | 427.64 MB/s | 波动 1.02x
    --
    JSON / LiteJSON = 3.33x
    LiteJSON / FastJSON(冷) = 619.56x
    FastJSON 冷 / 热 = 0.81x

  大(200项) | 16244 字符
    JSON:         62.000 ms/次 | 2 次/轮 | 中位总 124.00 ms | 0.25 MB/s | 波动 1.03x
    LiteJSON:     18.000 ms/次 | 8 次/轮 | 中位总 144.00 ms | 0.86 MB/s | 波动 1.07x
    FastJSON(冷): 23.93 us/次 | 256 批/轮 x64 = 16384 次 | 中位总 392.00 ms | 647.48 MB/s | 波动 1.03x
    FastJSON(热): 31.25 us/次 | 4096 次/轮 | 中位总 128.00 ms | 495.73 MB/s | 波动 1.03x
    --
    JSON / LiteJSON = 3.44x
    LiteJSON / FastJSON(冷) = 752.33x
    FastJSON 冷 / 热 = 0.77x

--- stringify 性能基准（等价路径 + 基线扣除） ---
  说明: FastJSON 热路径代表对象身份缓存命中，不反映对象变更后的重序列化。
  冷路径: 使用有限对象变体循环，变体耗尽后重建 FastJSON 实例，并按批次聚合多次冷操作以提高计时置信度。

  小(10项) | 约 895 输出字符
    JSON:         0.871 ms/次 | 256 次/轮 | 中位总 223.00 ms | 0.98 MB/s | 波动 1.02x
    LiteJSON:     1.016 ms/次 | 128 次/轮 | 中位总 130.00 ms | 0.84 MB/s | 波动 1.10x
    FastJSON(冷): 2.89 us/次 | 3072 批/轮 x32 = 98304 次 | 中位总 284.00 ms | 295.44 MB/s | 波动 1.09x
    FastJSON(热): 2.76 us/次 | 50000 次/轮 | 中位总 138.00 ms | 309.25 MB/s | 波动 1.19x
    --
    JSON / LiteJSON = 0.86x
    LiteJSON / FastJSON(冷) = 351.55x
    FastJSON 冷 / 热 = 1.05x

  中(50项) | 约 4035 输出字符
    JSON:         4.094 ms/次 | 32 次/轮 | 中位总 131.00 ms | 0.94 MB/s | 波动 1.06x
    LiteJSON:     4.531 ms/次 | 32 次/轮 | 中位总 145.00 ms | 0.85 MB/s | 波动 1.09x
    FastJSON(冷): 2.90 us/次 | 1536 批/轮 x64 = 98304 次 | 中位总 285.00 ms | 1327.30 MB/s | 波动 1.05x
    FastJSON(热): 2.73 us/次 | 30000 次/轮 | 中位总 82.00 ms | 1407.83 MB/s | 波动 1.09x
    --
    JSON / LiteJSON = 0.90x
    LiteJSON / FastJSON(冷) = 1562.95x
    FastJSON 冷 / 热 = 1.06x

  大(200项) | 约 16244 输出字符
    JSON:         16.000 ms/次 | 8 次/轮 | 中位总 128.00 ms | 0.97 MB/s | 波动 1.12x
    LiteJSON:     17.625 ms/次 | 8 次/轮 | 中位总 141.00 ms | 0.88 MB/s | 波动 1.10x
    FastJSON(冷): 3.02 us/次 | 1024 批/轮 x64 = 65536 次 | 中位总 198.00 ms | 5127.53 MB/s | 波动 1.11x
    FastJSON(热): 2.75 us/次 | 12000 次/轮 | 中位总 33.00 ms | 5633.27 MB/s | 波动 1.10x
    --
    JSON / LiteJSON = 0.91x
    LiteJSON / FastJSON(冷) = 5833.70x
    FastJSON 冷 / 热 = 1.10x

--- FastJSON 缓存专项（中规模） ---
  说明: parse 热 = 同字符串同实例；stringify 热 = 同对象同实例。
  风险: parse 热共享对象引用；stringify 热可能返回旧缓存字符串。
  parse
    冷: 9.37 us/次 | 512 批/轮 x64 = 32768 次 | 中位总 307.00 ms | 410.73 MB/s | 波动 1.03x
    热: 9.14 us/次 | 14336 次/轮 | 中位总 131.00 ms | 421.11 MB/s | 波动 1.03x
    冷 / 热 = 1.03x
  stringify
    冷: 2.94 us/次 | 1536 批/轮 x64 = 98304 次 | 中位总 289.00 ms | 1308.93 MB/s | 波动 1.07x
    热: 2.73 us/次 | 30000 次/轮 | 中位总 82.00 ms | 1407.83 MB/s | 波动 1.16x
    冷 / 热 = 1.08x

========== 测试结束 ==========
