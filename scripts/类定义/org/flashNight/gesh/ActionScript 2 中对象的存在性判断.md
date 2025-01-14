# ActionScript 2 中对象的存在性判断 #

在 ActionScript 2 中，对象的存在性判断主要通过三种方法。
- 对象是否与 undefined 不等
- 对象是否与 null 不等
- 对象能否通过 if 语句
以下是一个用于测试这三种方法性质的函数及其结果。

## 测试代码
ActionScript 2 与 JavaScript 拥有非常相近的语法。以下代码实际上作为 ActionScript 2 语言在 flash 中运行。
```javascript
function isnil(key,val){
    var r1 = val != undefined;
    var r2 = val != null;
    var r3 = false;
    if(val) r3 = true;
    str1 += "\n测试 " + key + " 性质\n ①!=undefined: "+r1+" ②!=null: "+r2+" ③if: "+r3;
    
    var r1 = key != undefined;
    var r2 = key != null;
    var r3 = false;
    if(key) r3 = true;
    str2 += '\n测试字符串 "' + key + '" 性质\n ①!=undefined: '+r1+" ②!=null: "+r2+" ③if: "+r3;
}

str1 = "";
str2 = "";

isnil("undefined",undefined);
isnil("null",null);
isnil("true",true);
isnil("false",false);
isnil("1",1);
isnil("0",0);
isnil("{}",{});
isnil("[]",[]);
isnil("[0]",[0]);
isnil("[[]]",[[]]);
isnil('""',"");

trace(str1);
trace(str2);
```

## 测试结果
以下是各项测试的输出结果：

### 测试 undefined
* !=undefined: false
* !=null: false
* if: false

### 测试 null
* !=undefined: false
* !=null: false
* if: false

### 测试布尔值 true
* !=undefined: true
* !=null: true
* if: true

### 测试布尔值 false
* !=undefined: true
* !=null: true
* if: false

### 测试数字 1
* !=undefined: true
* !=null: true
* if: true

### 测试数字 0
* !=undefined: true
* !=null: true
* if: false

### 测试对象 {}
* !=undefined: true
* !=null: true
* if: true

### 测试数组 []
* !=undefined: true
* !=null: true
* if: true

### 测试数组 [0]
* !=undefined: true
* !=null: true
* if: true

### 测试数组 [[]]
* !=undefined: true
* !=null: true
* if: true

### 测试字符串 ""
* !=undefined: true
* !=null: true
* if: false

### 测试字符串 "undefined"
* !=undefined: true
* !=null: true
* if: true

### 测试字符串 "null"
* !=undefined: true
* !=null: true
* if: true

### 测试字符串 "true"
* !=undefined: true
* !=null: true
* if: true

### 测试字符串 "false"
* !=undefined: true
* !=null: true
* if: true

### 测试字符串 "1"
* !=undefined: true
* !=null: true
* if: true

### 测试字符串 "0"
* !=undefined: true
* !=null: true
* if: true

### 测试字符串 "{}"
* !=undefined: true
* !=null: true
* if: true

### 测试字符串 "[]"
* !=undefined: true
* !=null: true
* if: true

## 结论
通过以上测试，我们可以得出以下结论。

### 是否与undefined与null不等
* undefined 和 null 判断 !=undefined 与 !=null 均返回 false。
* 任何对象在 if 判断 !=undefined 与 !=null 的结果均为 true，包括空对象 {}，空数组 []，空字符串 ""，布尔值 false。

### 能否通过if条件
* undefined 和 null 在 if 语句中视为假值。
* 空字符串 ""，布尔值 false 和数字 0 在 if 中被视为假值。
* 任何非空字符串均被视为真值。
* 任何其他对象在 if 中均为真值，包括空对象 {} 与空数组 []。

### 方法对比
* !=undefined 与 !=null 在逻辑上是完全等价的，且可以精准判断对象是否存在。这一点与 JavaScript 非常不同。
* if 语句对空字符串 ""，布尔值 false 和数字 0 视为假值，除此之外的对象均可以直接进入 if 语句判断存在性。

这些结果对于理解 ActionScript 2 中相等性和条件判断的行为非常重要。