import org.flashNight.gesh.pratt.*;
// 运行完整的表达式求值测试
PrattExpression_TestSuite.runAllTests();


========== PrattExpression 100%覆盖测试开始 ==========

--- 测试分组0：表达式类型常量验证 ---
  ✅ 表达式类型常量：BINARY应该正确定义
  ✅ 表达式类型常量：UNARY应该正确定义
  ✅ 表达式类型常量：TERNARY应该正确定义
  ✅ 表达式类型常量：LITERAL应该正确定义
  ✅ 表达式类型常量：IDENTIFIER应该正确定义
  ✅ 表达式类型常量：FUNCTION_CALL应该正确定义
  ✅ 表达式类型常量：PROPERTY_ACCESS应该正确定义
  ✅ 表达式类型常量：ARRAY_ACCESS应该正确定义
  ✅ 表达式类型常量：ARRAY_LITERAL应该正确定义
  ✅ 表达式类型常量：所有类型常量应该是唯一的
  ✅ 工厂方法：literal()应该创建LITERAL类型
  ✅ 工厂方法：identifier()应该创建IDENTIFIER类型
  ✅ 工厂方法：binary()应该创建BINARY类型
  ✅ 工厂方法：unary()应该创建UNARY类型
  ✅ 工厂方法：ternary()应该创建TERNARY类型
  ✅ 工厂方法：functionCall()应该创建FUNCTION_CALL类型
  ✅ 工厂方法：propertyAccess()应该创建PROPERTY_ACCESS类型
  ✅ 工厂方法：arrayAccess()应该创建ARRAY_ACCESS类型
  ✅ 工厂方法：arrayLiteral()应该创建ARRAY_LITERAL类型

--- 测试分组1：字面量表达式 ---
  ✅ 数字字面量：类型应该是LITERAL
  ✅ 数字字面量：求值应该返回42
  ✅ 浮点字面量：求值应该返回3.14
  ✅ 零字面量：求值应该返回0
  ✅ 负数字面量：求值应该返回-123
  ✅ 字符串字面量：求值应该返回hello
  ✅ 空字符串字面量：求值应该返回空字符串
  ✅ 特殊字符串字面量：应该保持原样
  ✅ 真值字面量：求值应该返回true
  ✅ 假值字面量：求值应该返回false
  ✅ null字面量：求值应该返回null
  ✅ undefined字面量：求值应该返回undefined
  ✅ 对象字面量：求值应该返回完整对象
  ✅ 数组字面量：求值应该返回完整数组

--- 测试分组2：标识符表达式 ---
  ✅ 数字标识符：类型应该是IDENTIFIER
  ✅ 数字标识符：求值应该返回123
  ✅ 字符串标识符：求值应该返回hello
  ✅ 布尔标识符：求值应该返回true
  ✅ null标识符：求值应该返回null
  ✅ undefined标识符：求值应该返回undefined
  ✅ 零标识符：求值应该返回0
  ✅ 空字符串标识符：求值应该返回空字符串
  ✅ 对象标识符：求值应该返回完整对象
  ✅ 数组标识符：求值应该返回完整数组
  ✅ 下划线标识符：应该正确求值
  ✅ 美元符号标识符：应该正确求值
  ✅ 混合标识符：应该正确求值
  ✅ 未定义标识符错误：应该抛出错误

--- 测试分组3：一元表达式 ---
  ✅ 正号表达式：类型应该是UNARY
  ✅ 正号表达式：+42应该等于42
  ✅ 正号字符串：+'123'应该转换为123
  ✅ 正号变量：+num应该等于42
  ✅ 负号表达式：-42应该等于-42
  ✅ 负号负数：-(-17)应该等于17
  ✅ 负号零：-0应该等于0
  ✅ 负号变量：-negNum应该等于17
  ✅ 逻辑非真：!true应该等于false
  ✅ 逻辑非假：!false应该等于true
  ✅ 逻辑非数字：!42应该等于false
  ✅ 逻辑非零：!0应该等于true
  ✅ 逻辑非字符串：!'hello'应该等于false
  ✅ 逻辑非空字符串：!''应该等于true
  ✅ 逻辑非null：!null应该等于true
  ✅ 逻辑非undefined：!undefined应该等于true
  ✅ 逻辑非变量：!bool应该等于false
  ✅ typeof数字：typeof 42应该等于'number'
  ✅ typeof字符串：typeof 'hello'应该等于'string'
  ✅ typeof布尔：typeof true应该等于'boolean'
  ✅ typeof null：typeof null应该等于'object'
  ✅ typeof undefined：typeof undefined应该等于'undefined'
  ✅ 双重负号：--42应该等于42
  ✅ 双重逻辑非：!!true应该等于true
  ✅ 混合一元：!(-42)应该等于false

--- 测试分组4：二元表达式 ---
  ✅ 加法表达式：类型应该是BINARY
  ✅ 加法表达式：5 + 3应该等于8
  ✅ 变量加法：a + b应该等于13
  ✅ 加零：42 + 0应该等于42
  ✅ 减法表达式：10 - 3应该等于7
  ✅ 减负数：5 - (-3)应该等于8
  ✅ 变量减法：a - b应该等于7
  ✅ 乘法表达式：6 * 7应该等于42
  ✅ 乘零：42 * 0应该等于0
  ✅ 负数乘法：-4 * 3应该等于-12
  ✅ 变量乘法：a * b应该等于30
  ✅ 除法表达式：15 / 3应该等于5
  ✅ 浮点除法：10 / 3应该约等于3.333
  ✅ 变量除法：a / b应该约等于3.333
  ✅ 取模表达式：10 % 3应该等于1
  ✅ 取模零结果：15 % 5应该等于0
  ✅ 变量取模：a % b应该等于1
  ✅ 幂运算表达式：2 ** 3应该等于8
  ✅ 零次幂：5 ** 0应该等于1
  ✅ 一次幂：42 ** 1应该等于42
  ✅ 变量幂运算：b ** 2应该等于9
  ✅ 数字相等：5 == 5应该为true
  ✅ 数字字符串相等：5 == '5'应该为true
  ✅ 变量相等：a == 10应该为true
  ✅ 不等于：5 != 3应该为true
  ✅ 相等不等于：5 != 5应该为false
  ✅ 严格相等：5 === 5应该为true
  ✅ 严格不等：5 === '5'应该为false
  ✅ 严格不等于：5 !== '5'应该为true
  ✅ 严格相等不等于：5 !== 5应该为false
  ✅ 小于：3 < 5应该为true
  ✅ 不小于：5 < 3应该为false
  ✅ 等于不小于：5 < 5应该为false
  ✅ 大于：5 > 3应该为true
  ✅ 不大于：3 > 5应该为false
  ✅ 小于等于：3 <= 5应该为true
  ✅ 等于小于等于：5 <= 5应该为true
  ✅ 不小于等于：5 <= 3应该为false
  ✅ 大于等于：5 >= 3应该为true
  ✅ 等于大于等于：5 >= 5应该为true
  ✅ 不大于等于：3 >= 5应该为false
  ✅ 逻辑与真：true && true应该为true
  ✅ 逻辑与假：true && false应该为false
  ✅ 逻辑与都假：false && false应该为false
  ✅ 逻辑与真值：1 && 'hello'应该返回'hello'
  ✅ 逻辑与假值：0 && 'hello'应该返回0
  ✅ 逻辑或真：true || false应该为true
  ✅ 逻辑或都真：true || true应该为true
  ✅ 逻辑或都假：false || false应该为false
  ✅ 逻辑或真值：'hello' || 'world'应该返回'hello'
  ✅ 逻辑或假值：null || 'default'应该返回'default'
  ✅ 空值合并null：null ?? 'default'应该返回'default'
  ✅ 空值合并undefined：undefined ?? 'default'应该返回'default'
  ✅ 空值合并有值：'value' ?? 'default'应该返回'value'
  ✅ 空值合并零：0 ?? 'default'应该返回0
  ✅ 空值合并空字符串：'' ?? 'default'应该返回''
  ✅ 空值合并false：false ?? 'default'应该返回false

--- 测试分组5：三元表达式 ---
  ✅ 基础三元：类型应该是TERNARY
  ✅ 基础三元真：true ? 'yes' : 'no'应该返回'yes'
  ✅ 基础三元假：false ? 'yes' : 'no'应该返回'no'
  ✅ 变量三元真：isTrue ? x : y应该返回10
  ✅ 变量三元假：isFalse ? x : y应该返回5
  ✅ 比较三元：x > y ? 'x is greater' : 'y is greater or equal'应该返回'x is greater'
  ✅ 真值三元：1 ? 'truthy' : 'falsy'应该返回'truthy'
  ✅ 假值零三元：0 ? 'truthy' : 'falsy'应该返回'falsy'
  ✅ 假值空字符串三元：'' ? 'truthy' : 'falsy'应该返回'falsy'
  ✅ 假值null三元：null ? 'truthy' : 'falsy'应该返回'falsy'
  ✅ 假值undefined三元：undefined ? 'truthy' : 'falsy'应该返回'falsy'
  ✅ 嵌套三元：x ? (x > 20 ? 'very big' : 'medium') : 'small'应该返回'medium'
  ✅ 复杂三元：(x > y * 2) ? (x + y) : (x - y)应该返回5

--- 测试分组6：函数调用表达式 ---
  ✅ 无参函数调用：类型应该是FUNCTION_CALL
  ✅ 无参函数调用：noArgs()应该返回'no arguments'
  ✅ 单参函数调用：greet('Alice')应该返回'Hello, Alice'
  ✅ 单参变量函数调用：greet(name)应该返回'Hello, World'
  ✅ 多参函数调用：add(3, 7)应该返回10
  ✅ 多参变量函数调用：multiply(x, y)应该返回50
  ✅ 表达式参数函数调用：add(2 * 3, 10 / 2)应该返回11
  ✅ 对象方法调用：Math.max(5, 10, 3)应该返回10
  ✅ 对象方法变量调用：Math.min(x, y)应该返回5
  ✅ 对象方法绝对值：Math.abs(-42)应该返回42
  ✅ 嵌套函数调用：add(multiply(2, 3), 4)应该返回10
  ✅ 三元函数调用：x > y ? add(x, y) : multiply(x, y)应该返回15

--- 测试分组7：属性访问表达式 ---
  ✅ 基础属性访问：类型应该是PROPERTY_ACCESS
  ✅ 基础属性访问：user.name应该返回'Alice'
  ✅ 数字属性访问：user.age应该返回25
  ✅ 布尔属性访问：config.debug应该返回false
  ✅ 嵌套属性访问：user.profile.email应该返回'alice@example.com'
  ✅ 深度嵌套属性访问：user.profile.settings.theme应该返回'dark'
  ✅ 深度嵌套布尔属性：config.features.newUI应该返回true
  ✅ 不存在属性访问：user.nonexistent应该返回undefined
  ✅ 空对象属性访问：emptyObj.anything应该返回undefined
  ✅ 属性访问二元表达式：user.age + 5应该返回30
  ✅ 属性访问三元表达式：config.debug ? 'debug mode' : 'production mode'应该返回'production mode'
  ✅ 属性访问作为参数：greet(user.name)应该返回'Hello, Alice'

--- 测试分组8：数组访问表达式 ---
  ✅ 基础数组访问：类型应该是ARRAY_ACCESS
  ✅ 基础数组访问：numbers[0]应该返回1
  ✅ 数组访问：numbers[2]应该返回3
  ✅ 数组访问最后：numbers[4]应该返回5
  ✅ 字符串数组访问：strings[1]应该返回'world'
  ✅ 混合数组数字：mixed[0]应该返回1
  ✅ 混合数组字符串：mixed[1]应该返回'two'
  ✅ 混合数组布尔：mixed[2]应该返回true
  ✅ 混合数组null：mixed[3]应该返回null
  ✅ 混合数组undefined：mixed[4]应该返回undefined
  ✅ 变量索引：numbers[index1]应该返回2
  ✅ 变量索引字符串：strings[index2]应该返回'test'
  ✅ 表达式索引：numbers[1 + 1]应该返回3
  ✅ 复杂表达式索引：numbers[2 * 2 - 1]应该返回4
  ✅ 嵌套数组访问：nested[0][1]应该返回2
  ✅ 嵌套数组访问2：nested[2][0]应该返回5
  ✅ 对象数组属性访问：objects[0].name应该返回'Alice'
  ✅ 对象数组属性访问2：objects[1].age应该返回30
  ✅ 越界访问：numbers[10]应该返回undefined
  ✅ 负索引访问：numbers[-1]应该返回undefined
  ✅ 空数组访问：emptyArray[0]应该返回undefined
  ✅ 数组访问二元表达式：numbers[0] + numbers[1]应该返回3

--- 测试分组9：数组字面量表达式 ---
  ✅ 空数组字面量：类型应该是ARRAY_LITERAL
  ✅ 空数组字面量：求值应该返回空数组
  ✅ 单元素数组字面量：应该包含一个元素42
  ✅ 多元素数组字面量：应该包含[1, 2, 3]
  ✅ 混合类型数组字面量：应该包含不同类型的元素
  ✅ 标识符数组字面量：应该求值为[10, 5, 'Alice']
  ✅ 表达式数组字面量：应该求值为[15, 50, -42]
  ✅ 嵌套数组字面量：应该正确创建二维数组
  ✅ 数组字面量属性访问：['a', 'b', 'c'].length应该返回3
  ✅ 数组字面量索引访问：['first', 'second', 'third'][1]应该返回'second'
  ✅ 数组字面量作为参数：join(['a', 'b', 'c'], '-')应该返回'a-b-c'
  ✅ 数组字面量三元表达式：x > y ? ['x', 'is', 'greater'] : ['y', 'is', 'greater']应该返回第一个数组
  ✅ 复杂数组字面量：应该正确求值包含属性访问、函数调用和二元表达式的数组

--- 测试分组10：复杂嵌套表达式 ---
  ✅ 复杂访问：users[0].scores[1]应该返回90
  ✅ 嵌套函数访问：avg(users[currentUserIndex].scores)应该约等于84.33
  ✅ 复杂三元表达式应该约等于100.83
  ✅ 多层嵌套二元表达式：(max(users[0].scores[0], users[0].scores[1]) + config.passing.bonus) > config.passing.grade应该为true
  ✅ 超复杂表达式应该返回'Needs improvement: Alice'
  ✅ 深度嵌套一元表达式：!!(avg(users[1].scores) > 90)应该为true
  ✅ 数组字面量复杂表达式：avg([users[0].scores[0], users[1].scores[0], users[2].scores[0]])应该返回85
  ✅ 数组字面量三元表达式：(currentUserIndex == 0 ? ['first', 'user', 'data'] : ['other', 'user', 'data'])[1]应该返回'user'

--- 测试分组11：错误处理 ---
  ✅ 未定义变量错误：应该抛出错误
  ✅ 除零错误：应该抛出错误
  ✅ 直接除零错误：应该抛出错误
  ✅ null属性访问错误：应该抛出错误
  ✅ undefined属性访问错误：应该抛出错误
  ✅ null数组访问错误：应该抛出错误
  ✅ undefined数组访问错误：应该抛出错误
  ✅ 未定义函数错误：应该抛出错误
  ✅ 非函数调用错误：应该抛出错误
  ✅ 不存在方法调用错误：应该抛出错误
  ✅ 方法非函数错误：调用非函数属性应该抛出错误
  ✅ 未知二元运算符错误：应该抛出错误
  ✅ 未知一元运算符错误：应该抛出错误
  ✅ 未知表达式类型错误：应该抛出错误
  ✅ Arguments关键字测试：函数应该正确处理多个参数
  ✅ 数组字面量元素错误：包含未定义变量的数组字面量应该抛出错误
  ✅ 数组字面量计算错误：包含除零操作的数组字面量应该抛出错误

--- 测试分组12：toString方法 ---
  ✅ 字面量toString：应该包含Literal和值
  ✅ 标识符toString：应该包含Identifier和名称
  ✅ 二元表达式toString：应该包含Binary、运算符和操作数
  ✅ 一元表达式toString：应该包含Unary、运算符和操作数
  ✅ 三元表达式toString：应该包含Ternary、?和:
  ✅ 函数调用toString：应该包含FunctionCall和函数名
  ✅ 属性访问toString：应该包含PropertyAccess、对象和属性名
  ✅ 数组访问toString：应该包含ArrayAccess和数组名
  ✅ 数组字面量toString：应该包含ArrayLiteral和数组元素
  ✅ 复杂嵌套toString：应该包含所有表达式类型
  ✅ 嵌套二元toString：应该显示嵌套的二元表达式结构
  ✅ 复杂数组字面量toString：应该包含FunctionCall、ArrayLiteral和Binary

--- 测试分组13：边界条件 ---
  ✅ 极大数值运算：结果应该仍然是数字类型
  ✅ 无穷大运算：结果应该仍然是正无穷
  ✅ 负无穷运算：-(-∞)应该是正无穷
  ✅ NaN运算：NaN + 42应该仍然是NaN
  ✅ NaN比较：NaN == NaN应该为false
  ✅ 极小数值运算：结果应该仍然是数字类型
  ✅ 空字符串运算：'' + 'test'应该等于'test'
  ✅ 超长字符串运算：应该正确处理长字符串连接
  ✅ 特殊字符处理：特殊字符字符串长度应该正确
  ✅ 空数组访问：空数组长度应该为0
  ✅ 单元素数组：应该正确访问唯一元素
  ✅ 大数组处理：大数组长度应该正确
  ✅ 深度嵌套对象：应该能访问深层属性
  ✅ 无参数函数调用：应该返回null
  ✅ 单参数函数调用：应该返回该参数
  ✅ 类型转换：字符串数字应该正确转换并相加
  ✅ 字符串数字比较：'10' == 10应该为true
  ✅ 严格字符串数字比较：'10' === 10应该为false
  ✅ Falsy值测试：!false应该为true
  ✅ Falsy值测试：!0应该为true
  ✅ Falsy值测试：!应该为true
  ✅ Falsy值测试：!null应该为true
  ✅ Falsy值测试：!undefined应该为true
  ✅ Truthy值测试：!true应该为false
  ✅ Truthy值测试：!1应该为false
  ✅ Truthy值测试：!hello应该为false
  ✅ Truthy值测试：!应该为false
  ✅ Truthy值测试：![object Object]应该为false
  ✅ 零值比较：0应该等于-0
  ✅ 大索引访问：访问超大索引应该返回undefined
  ✅ 空数组字面量长度：应该为0
  ✅ 大型数组字面量：应该正确处理100个元素的数组
  ✅ 深度嵌套数组字面量：应该正确访问深层元素
  ✅ 特殊值数组字面量：应该正确处理各种特殊值

========== PrattExpression 测试结果 ==========
总计: 272 个测试
通过: 272 个
失败: 0 个
覆盖率: 100%
✅ PrattExpression 所有测试通过！
==========================================