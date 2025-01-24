// 文件路径: org/flashNight/gesh/symbol/SymbolTest.as

import org.flashNight.gesh.symbol.*;

class org.flashNight.gesh.symbol.SymbolTest {
    
    public function SymbolTest() {
        trace("开始运行 Symbol 类的测试...\n");
        testCreateSymbols();
        testSymbolUniqueness();
        testGlobalRegistry();
        testDeleteSymbol();
        testEquals();
        testToString();
        testPrivateProperty();
        testEdgeCases();
        testMemoryManagement();
        testUUIDFormat();
        testTypeSafety();
        stressTest();
        trace("\n所有测试已完成。");
    }

    private function testCreateSymbols(): Void {
        trace("测试 1: 创建 Symbol 实例");
        var sym1:Symbol = Symbol.create("test");
        var sym2:Symbol = Symbol.create("test");
        var sym3:Symbol = Symbol.create("anotherTest");

        trace("sym1:" + sym1.getKey() + " " + sym1.getDescription());
        trace("sym2:" + sym2.getKey() + " " + sym2.getDescription());
        trace("sym3:" + sym3.getKey() + " " + sym3.getDescription());
        
        if (sym1 instanceof Symbol && sym2 instanceof Symbol && sym3 instanceof Symbol) {
            trace("  ✅ 创建 Symbol 实例成功。");
        } else {
            trace("  ❌ 创建 Symbol 实例失败。");
        }
    }

    private function testSymbolUniqueness(): Void {
        trace("测试 2: 验证 Symbol 的唯一性");
        var sym1:Symbol = Symbol.create("unique");
        var sym2:Symbol = Symbol.create("unique");

        trace("sym1:" + sym1.getKey() + " " + sym1.getDescription());
        trace("sym2:" + sym2.getKey() + " " + sym2.getDescription()); 

        if (!sym1.equals(sym2)) {
            trace("  ✅ 不同创建的 Symbol 实例具有唯一性。");
        } else {
            trace("  ❌ Symbol 实例不唯一。");
        }
    }

    private function testGlobalRegistry(): Void {
        trace("测试 3: 全局注册表的 forKey 方法");
        var key:String = "globalTestKey";
        var sym1:Symbol = Symbol.forKey(key, "globalSymbol");
        var sym2:Symbol = Symbol.forKey(key, "globalSymbol");

        trace("sym1:" + sym1.getKey() + " " + sym1.getDescription());
        trace("sym2:" + sym2.getKey() + " " + sym2.getDescription());
        
        if (sym1.equals(sym2)) {
            trace("  ✅ forKey 方法返回相同的 Symbol 实例。");
        } else {
            trace("  ❌ forKey 方法未返回相同的 Symbol 实例。");
        }
        
        // 描述符冲突测试
        var errorOccurred:Boolean = false;
        try {
            Symbol.forKey(key, "differentDesc");
        } catch (e:Error) {
            errorOccurred = true;
            trace("  ✅ 检测到描述符冲突: " + e.message);
        }
        if (!errorOccurred) {
            trace("  ❌ 未检测到描述符冲突");
        }
    }

    private function testDeleteSymbol(): Void {
        trace("测试 4: 删除全局注册的 Symbol");
        var key:String = "deleteTestKey";
        Symbol.forKey(key, "toBeDeleted");
        trace("sym1_old:" + sym1.getKey() + " " + sym1.getDescription());
        
        var deleted:Boolean = Symbol.deleteSymbol(key);
        
        if (deleted) {
            trace("  ✅ Symbol 删除成功。");
        } else {
            trace("  ❌ Symbol 删除失败。");
        }
        
    
        // 重新注册验证
        var sym1:Symbol = Symbol.forKey(key, "newSymbol");
        var sym2:Symbol = Symbol.forKey(key, "newSymbol");

        trace("sym1:" + sym1.getKey() + " " + sym1.getDescription());
        trace("sym2:" + sym2.getKey() + " " + sym2.getDescription());

        if (sym1.equals(sym2)) {
            trace("  ✅ 删除后重新注册返回相同的 Symbol 实例。");
        } else {
            trace("  ❌ 删除后重新注册未返回相同的 Symbol 实例。");
        }
    }

    private function testEquals(): Void {
        trace("测试 5: Symbol 的 equals 方法");
        var sym1:Symbol = Symbol.create("equalsTest");
        var sym2:Symbol = Symbol.create("equalsTest");
        var sym3:Symbol = sym1;
        
        trace("sym1:" + sym1.getKey() + " " + sym1.getDescription());
        trace("sym2:" + sym2.getKey() + " " + sym2.getDescription());
        trace("sym3:" + sym3.getKey() + " " + sym3.getDescription());

        if (!sym1.equals(sym2) && sym1.equals(sym3)) {
            trace("  ✅ equals 方法正确区分不同实例并识别相同实例。");
        } else {
            trace("  ❌ equals 方法存在问题。");
        }
    }

    private function testToString(): Void {
        trace("测试 6: Symbol 的 toString 方法");
        var description:String = "toStringTest";
        var sym:Symbol = Symbol.create(description);
        var str:String = sym.toString();
        
        var expectedStart:String = "Symbol(" + description + ")";
        if (str.substring(0, expectedStart.length) == expectedStart) {
            trace("  ✅ toString 方法输出正确。");
        } else {
            trace("  ❌ toString 方法输出不正确。");
        }
    }

    private function testPrivateProperty(): Void {
        trace("测试 7: 使用 Symbol 作为私有属性键");
        var privateKey:Symbol = Symbol.create("privateProperty");
        var obj:Object = {};
        obj[privateKey] = "Secret Data";
        
        // 字符串访问测试
        var stringAccessSuccess:Boolean = true;
        for (var prop:String in obj) {
            if (prop == "privateProperty") {
                stringAccessSuccess = false;
                break;
            }
        }
        if (stringAccessSuccess) {
            trace("  ✅ 通过字符串无法访问私有属性。");
        } else {
            trace("  ❌ 通过字符串可以访问私有属性。");
        }
        
        // Symbol访问测试
        if (obj[privateKey] === "Secret Data") {
            trace("  ✅ 通过 Symbol 可以正确访问私有属性。");
        } else {
            trace("  ❌ 通过 Symbol 访问私有属性失败。");
        }
    }

    private function testEdgeCases(): Void {
        trace("测试 8: 边界条件测试");
        // 空描述符测试
        var symEmpty:Symbol = Symbol.create("");
        if (symEmpty.getDescription() === "") {
            trace("  ✅ 空描述符创建 Symbol 成功。");
        } else {
            trace("  ❌ 空描述符创建 Symbol 失败。");
        }
        
        // 特殊字符测试
        var specialDesc:String = "!@#$%^&*()_+";
        var symSpecial:Symbol = Symbol.create(specialDesc);
        if (symSpecial.getDescription() === specialDesc) {
            trace("  ✅ 特殊字符描述符创建 Symbol 成功。");
        } else {
            trace("  ❌ 特殊字符描述符创建 Symbol 失败。");
        }
    }

    private function testMemoryManagement(): Void {
        trace("测试 9: 内存管理与资源清理");
        var key:String = "memoryTestKey";
        Symbol.forKey(key, "memorySymbol");
        var firstDelete:Boolean = Symbol.deleteSymbol(key);
        var secondDelete:Boolean = Symbol.deleteSymbol(key);
        
        if (firstDelete && !secondDelete) {
            trace("  ✅ Symbol 删除后无法再次删除，内存管理正常。");
        } else {
            trace("  ❌ Symbol 删除后存在问题。");
        }
    }

    private function testUUIDFormat(): Void {
        trace("测试 10: UUID格式验证");
        var sym:Symbol = Symbol.create("uuidTest");
        var keyParts:Array = sym.getKey().split(":");
        
        // 验证基础结构
        if (keyParts.length != 2 || keyParts[0].indexOf("Symbol(uuidTest)") != 0) {
            trace("  ❌ UUID基础格式错误: " + sym.getKey());
            return;
        }
        
        // 分解UUID部分
        var uuidParts:Array = keyParts[1].split("-");
        if (uuidParts.length != 5) {
            trace("  ❌ UUID段落数量错误: " + keyParts[1]);
            return;
        }
        
        // 验证各段长度（使用标准逻辑运算符）
        var valid:Boolean = true;
        valid = valid && (uuidParts[0].length == 8);
        valid = valid && (uuidParts[1].length == 4);
        valid = valid && (uuidParts[2].length == 4);
        valid = valid && (uuidParts[3].length == 4);
        valid = valid && (uuidParts[4].length == 12);
        
        // 验证版本标识位
        if (valid) {
            valid = valid && (parseInt(uuidParts[2].substr(0,1), 16) == 4);
            valid = valid && (parseInt(uuidParts[3].substr(0,1), 16) >= 8);
        }
        
        if (valid) {
            trace("  ✅ UUID格式符合规范");
        } else {
            trace("  ❌ UUID格式异常: " + sym.getKey());
        }
    }

    private function testTypeSafety(): Void {
        trace("测试 11: 类型安全验证");
        var errorCount:Number = 0;
        
        // 测试1: 数字类型key
        try {
            // 使用动态类型强制绕过编译检查
            var invalidKey:Object = 123;
            Symbol["forKey"](invalidKey, "numberKey");
        } catch (e:Error) {
            errorCount++;
        }
        
        // 测试2: 对象类型删除操作
        try {
            var invalidKeyObj:Object = { key: "test" };
            Symbol["deleteSymbol"](invalidKeyObj);
        } catch (e:Error) {
            errorCount++;
        }
        
        // 测试3: 非法比较操作（使用动态调用）
        try {
            var validSym:Symbol = Symbol.create("valid");
            var invalidCompare:Object = "not_a_symbol";
            validSym["equals"](invalidCompare); // 动态方法调用
        } catch (e:Error) {
            errorCount++;
        }
        
        if (errorCount === 3) {
            trace("  ✅ 类型检查正常");
        } else {
            trace("  ❌ 类型检查存在漏洞，预期3个错误，实际捕获：" + errorCount);
        }
    }

    private function stressTest(): Void {
        trace("测试 12: 压力测试（创建500个Symbol）");
        var symbolMap:Object = {};
        var collision:Boolean = false;
        var duplicateKey:String = "";
        
        for (var i:Number = 0; i < 500; i++) {
            var newSym:Symbol = Symbol.create("stress_" + i);
            if (symbolMap[newSym.getKey()] !== undefined) {
                collision = true;
                duplicateKey = newSym.getKey();
                break;
            }
            symbolMap[newSym.getKey()] = true;
        }
        
        if (!collision) {
            trace("  ✅ 500次创建无冲突");
        } else {
            trace("  ❌ 检测到唯一性冲突，重复key: " + duplicateKey);
        }
    }

    public static function run(): Void {
        new SymbolTest();
    }
}