# StringUtilsPerfTest

StringUtils 性能测试套件

## 快速启动

**一句话启动代码**（复制到 TestLoader.as）：

```actionscript
import org.flashNight.gesh.string.StringUtilsPerfTest;
var tester = new StringUtilsPerfTest();
tester.run();
```

或直接使用内联测试代码（推荐，见 `scripts/TestLoader.as`）

## 典型日志输出

```
===== StringUtilsPerfTest =====
>>> str.length: 147ms
>>> length(str): 76ms
>>> Speedup: 1.93x

>>> Function Tests
(3/3 PASS)

>>> Method Performance
trim: 466ms (20000 ops)
endsWith: 51ms (20000 ops)

===== Test Complete =====
```

## 测试内容

1. **基础性能对比**: `str.length` vs `length(str)` (100000次循环)
2. **功能验证**: trim, startsWith, endsWith
3. **方法性能**: trim, endsWith (各20000次调用)

## 文件位置

| 文件 | 路径 |
|------|------|
| 测试类 | `scripts/类定义/org/flashNight/gesh/string/StringUtilsPerfTest.as` |
| 说明文档 | `scripts/类定义/org/flashNight/gesh/string/StringUtilsPerfTest.md` |
| 当前测试 | `scripts/TestLoader.as` |

## 验证历史

- **2026-03-10**: `length(str)` 比 `str.length` 快 ~1.93x
  - Flash CS6 + Flash Player 20
  - 100000次循环测试
  - StringUtils 功能正常 (3/3 PASS)
