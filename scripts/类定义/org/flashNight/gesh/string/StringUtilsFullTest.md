# StringUtilsFullTest

StringUtils 全覆盖测试套件

## 快速启动

```actionscript
import org.flashNight.gesh.string.StringUtilsFullTest;
var tester = new StringUtilsFullTest();
tester.run();
```

## 典型日志输出

```
===== StringUtilsFullTest =====
[PERF] Baseline: str.length=116ms, length(str)=48ms (2.42x)

[FUNC] Running tests...
[FUNC] 20/20 tests passed

[PERF] Method performance (20000 ops):
  trim: 268ms
  endsWith: 47ms
  replaceAll: 206ms
  reverse: 332ms

[SUMMARY] 20/20 PASS
===== Test Complete =====
```

## 测试覆盖

### 功能测试 (20项)

| 类别 | 方法 |
|------|------|
| 查询 | includes, startsWith, endsWith, isEmpty, countOccurrences |
| 修剪 | trim, trimLeft, trimRight |
| 填充 | padStart, padEnd, repeat |
| 转换 | replaceAll, reverse, capitalize, remove |
| HTML | escapeHTML, unescapeHTML, decodeHTMLFast |
| 数字 | toFixed, formatNumber |

### 性能测试 (4项高频方法)

- trim, endsWith, replaceAll, reverse

## 文件位置

| 文件 | 路径 |
|------|------|
| 测试类 | `scripts/类定义/org/flashNight/gesh/string/StringUtilsFullTest.as` |
| 说明文档 | `scripts/类定义/org/flashNight/gesh/string/StringUtilsFullTest.md` |
| 当前测试 | `scripts/TestLoader.as` |

## 验证历史

- **2026-03-11**: 20/20 功能测试通过，trimLeft/trimRight 优化后重测
  - `length(str)` 比 `str.length` 快 **2.42x**
  - trim: 437ms → 268ms（-39%，消除循环内重复 length() 和 substring）
  - Flash CS6 + Flash Player 20
  - 100000次循环测试
- **2026-03-10**: 初始基准，20/20 通过
  - `length(str)` 比 `str.length` 快 **1.92x**
