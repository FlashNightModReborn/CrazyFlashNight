import org.flashNight.gesh.pratt.*;

PrattToken_TestSuite.runAllTests();

========== PrattToken 100%覆盖测试开始 ==========

--- 测试分组1：构造函数基础功能 ---
  ✅ 基础构造：type应该正确设置
  ✅ 基础构造：text应该正确设置
  ✅ 基础构造：line应该正确设置
  ✅ 基础构造：column应该正确设置
  ✅ 所有Token类型构造：EOF应该正确设置
  ✅ 所有Token类型构造：NUMBER应该正确设置
  ✅ 所有Token类型构造：IDENTIFIER应该正确设置
  ✅ 所有Token类型构造：STRING应该正确设置
  ✅ 所有Token类型构造：BOOLEAN应该正确设置
  ✅ 所有Token类型构造：NULL应该正确设置
  ✅ 所有Token类型构造：UNDEFINED应该正确设置
  ✅ 所有Token类型构造：OPERATOR应该正确设置
  ✅ 所有Token类型构造：LPAREN应该正确设置
  ✅ 所有Token类型构造：RPAREN应该正确设置
  ✅ 所有Token类型构造：COMMA应该正确设置
  ✅ 所有Token类型构造：DOT应该正确设置

--- 测试分组2：值的自动转换逻辑 ---
  ✅ T_NUMBER整数：value应该转换为数字123
  ✅ T_NUMBER整数：value类型应该是number
  ✅ T_NUMBER浮点数：value应该转换为123.45
  ✅ T_NUMBER浮点数：value类型应该是number
  ✅ T_NUMBER零：value应该转换为0
  ✅ T_NUMBER负数：value应该转换为-42
  ✅ T_BOOLEAN真值：value应该转换为true
  ✅ T_BOOLEAN真值：value类型应该是boolean
  ✅ T_BOOLEAN假值：value应该转换为false
  ✅ T_BOOLEAN假值：value类型应该是boolean
  ✅ T_NULL：value应该转换为null
  ✅ T_UNDEFINED：value应该转换为undefined
  ✅ T_IDENTIFIER：value应该等于text
  ✅ T_OPERATOR：value应该等于text

--- 测试分组3：手动值覆盖 ---
  ✅ 手动值覆盖：显式传入的value应该覆盖自动转换
  ✅ 手动值覆盖：即使是布尔类型也应该被覆盖
  ✅ 手动值覆盖：显式传入null应该保留
  ✅ 手动值覆盖：显式传入undefined应该保留
  ✅ 手动值覆盖：显式传入0应该保留

--- 测试分组4：位置跟踪 ---
  ✅ 位置默认值：line应该默认为0
  ✅ 位置默认值：column应该默认为0
  ✅ 位置跟踪：line=1应该正确设置
  ✅ 位置跟踪：column=1应该正确设置
  ✅ 位置跟踪：line=999应该正确设置
  ✅ 位置跟踪：column=999应该正确设置
  ✅ 位置跟踪：line=0应该正确设置
  ✅ 位置跟踪：column=0应该正确设置
  ✅ 位置跟踪：line=-1应该正确设置
  ✅ 位置跟踪：column=-1应该正确设置

--- 测试分组5：类型检查方法 ---
  ✅ is()方法：应该正确识别匹配的类型
  ✅ is()方法：应该正确识别不匹配的类型
  ✅ is()方法：应该正确处理不存在的类型
  ✅ isLiteral()方法：NUMBER应该被识别为字面量
  ✅ isLiteral()方法：STRING应该被识别为字面量
  ✅ isLiteral()方法：BOOLEAN应该被识别为字面量
  ✅ isLiteral()方法：NULL应该被识别为字面量
  ✅ isLiteral()方法：UNDEFINED应该被识别为字面量
  ✅ isLiteral()方法：IDENTIFIER不应该被识别为字面量
  ✅ isLiteral()方法：OPERATOR不应该被识别为字面量
  ✅ isLiteral()方法：LPAREN不应该被识别为字面量
  ✅ isLiteral()方法：EOF不应该被识别为字面量
  ✅ isLiteral()方法：COMMA不应该被识别为字面量

--- 测试分组6：值获取方法 ---
  ✅ getNumberValue()正确：应该返回正确的数字值
  ✅ getNumberValue()正确：返回值类型应该是number
  ✅ getNumberValue()错误：错误信息应该包含类型提示
  ✅ getNumberValue()错误：非数字Token应该抛出错误
  ✅ getStringValue()正确：应该返回正确的字符串值
  ✅ getStringValue()正确：返回值类型应该是string
  ✅ getStringValue()错误：错误信息应该包含类型提示
  ✅ getStringValue()错误：非字符串Token应该抛出错误
  ✅ getBooleanValue()正确：应该返回正确的布尔值
  ✅ getBooleanValue()正确：返回值类型应该是boolean
  ✅ getBooleanValue()错误：错误信息应该包含类型提示
  ✅ getBooleanValue()错误：非布尔Token应该抛出错误

--- 测试分组7：错误处理和消息格式 ---
  ✅ createError()格式：应该包含错误消息
  ✅ createError()格式：应该包含行号
  ✅ createError()格式：应该包含列号
  ✅ createError()格式：应该包含token文本
  ✅ createError()边界：应该正确处理0位置
  ✅ createError()边界：应该正确处理大位置值
  ✅ createError()空消息：即使消息为空也应该包含位置信息

--- 测试分组8：字符串表示 ---
  ✅ toString()基础：应该包含类型
  ✅ toString()基础：应该包含文本
  ✅ toString()基础：应该包含位置信息
  ✅ toString()值转换：应该包含原始文本
  ✅ toString()值转换：应该显示转换后的值
  ✅ toString()null：应该包含NULL类型
  ✅ toString()无位置：应该包含类型
  ✅ toString()无位置：应该包含文本
  ✅ toString()复杂：应该包含类型
  ✅ toString()复杂：应该包含原始文本
  ✅ toString()复杂：应该显示实际值
  ✅ toString()复杂：应该包含位置

--- 测试分组9：边界条件和异常情况 ---
  ✅ 边界条件：应该正确处理空字符串
  ✅ 边界条件：空字符串的value应该也是空字符串
  ✅ 边界条件：应该正确处理特殊字符
  ✅ 边界条件：应该正确处理超长字符串
  ✅ 边界条件：超大数字应该仍然是number类型
  ✅ 边界条件：应该正确处理科学计数法
  ✅ 边界条件：应该接受undefined作为text
  ✅ 边界条件：空字符串类型检查应该返回false
  ✅ 边界条件：null类型检查应该返回false
  ✅ 边界条件：undefined类型检查应该返回false

========== PrattToken 测试结果 ==========
总计: 99 个测试
通过: 99 个
失败: 0 个
覆盖率: 100%
✅ PrattToken 所有测试通过！
==========================================
