// 文件路径: org/flashNight/gesh/symbol/SymbolTest.as

import org.flashNight.gesh.symbol.Symbol;

class org.flashNight.gesh.symbol.SymbolTest {
    
    /**
     * 构造函数
     * 自动运行所有测试
     */
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
        trace("\n所有测试已完成。");
    }
    
    /**
     * 测试 Symbol 的创建
     */
    private function testCreateSymbols(): Void {
        trace("测试 1: 创建 Symbol 实例");
        var sym1:Symbol = Symbol.create("test");
        var sym2:Symbol = Symbol.create("test");
        var sym3:Symbol = Symbol.create("anotherTest");
        
        if (sym1 instanceof Symbol && sym2 instanceof Symbol && sym3 instanceof Symbol) {
            trace("  ✅ 创建 Symbol 实例成功。");
        } else {
            trace("  ❌ 创建 Symbol 实例失败。");
        }
    }
    
    /**
     * 测试 Symbol 的唯一性
     */
    private function testSymbolUniqueness(): Void {
        trace("测试 2: 验证 Symbol 的唯一性");
        var sym1:Symbol = Symbol.create("unique");
        var sym2:Symbol = Symbol.create("unique");
        
        if (!sym1.equals(sym2)) {
            trace("  ✅ 不同创建的 Symbol 实例具有唯一性。");
        } else {
            trace("  ❌ Symbol 实例不唯一。");
        }
    }
    
    /**
     * 测试全局注册表的功能
     */
    private function testGlobalRegistry(): Void {
        trace("测试 3: 全局注册表的 forKey 方法");
        var key:String = "globalTestKey";
        var sym1:Symbol = Symbol.forKey(key, "globalSymbol");
        var sym2:Symbol = Symbol.forKey(key, "globalSymbol");
        
        if (sym1.equals(sym2)) {
            trace("  ✅ forKey 方法返回相同的 Symbol 实例。");
        } else {
            trace("  ❌ forKey 方法未返回相同的 Symbol 实例。");
        }
    }
    
    /**
     * 测试删除全局注册的 Symbol
     */
    private function testDeleteSymbol(): Void {
        trace("测试 4: 删除全局注册的 Symbol");
        var key:String = "deleteTestKey";
        Symbol.forKey(key, "toBeDeleted");
        var deleted:Boolean = Symbol.deleteSymbol(key);
        
        if (deleted) {
            trace("  ✅ Symbol 删除成功。");
        } else {
            trace("  ❌ Symbol 删除失败。");
        }
        
        // 尝试重新注册，确保已删除
        var sym1:Symbol = Symbol.forKey(key, "newSymbol");
        var sym2:Symbol = Symbol.forKey(key, "newSymbol");
        
        if (sym1.equals(sym2)) {
            trace("  ✅ 删除后重新注册返回相同的 Symbol 实例。");
        } else {
            trace("  ❌ 删除后重新注册未返回相同的 Symbol 实例。");
        }
    }
    
    /**
     * 测试 Symbol 的 equals 方法
     */
    private function testEquals(): Void {
        trace("测试 5: Symbol 的 equals 方法");
        var sym1:Symbol = Symbol.create("equalsTest");
        var sym2:Symbol = Symbol.create("equalsTest");
        var sym3:Symbol = sym1;
        
        if (!sym1.equals(sym2) && sym1.equals(sym3)) {
            trace("  ✅ equals 方法正确区分不同实例并识别相同实例。");
        } else {
            trace("  ❌ equals 方法存在问题。");
        }
    }
    
    /**
     * 测试 Symbol 的 toString 方法
     */
    private function testToString(): Void {
        trace("测试 6: Symbol 的 toString 方法");
        var description:String = "toStringTest";
        var sym:Symbol = Symbol.create(description);
        var str:String = sym.toString();
        
        var expectedStart:String = "Symbol(" + description + ")";
        if (str.indexOf(expectedStart) === 0) {
            trace("  ✅ toString 方法输出正确。");
        } else {
            trace("  ❌ toString 方法输出不正确。");
        }
    }
    
    /**
     * 测试使用 Symbol 作为对象的私有属性键
     */
    private function testPrivateProperty(): Void {
        trace("测试 7: 使用 Symbol 作为私有属性键");
        var privateKey:Symbol = Symbol.create("privateProperty");
        var obj:Object = {};
        obj[privateKey] = "Secret Data";
        
        // 尝试通过字符串访问
        if (obj["privateProperty"] === undefined) {
            trace("  ✅ 通过字符串无法访问私有属性。");
        } else {
            trace("  ❌ 通过字符串可以访问私有属性。");
        }
        
        // 通过 Symbol 访问
        if (obj[privateKey] === "Secret Data") {
            trace("  ✅ 通过 Symbol 可以正确访问私有属性。");
        } else {
            trace("  ❌ 通过 Symbol 访问私有属性失败。");
        }
    }
    
    /**
     * 测试边界条件，如空描述符和特殊字符描述符
     */
    private function testEdgeCases(): Void {
        trace("测试 8: 边界条件测试");
        
        // 测试空描述符
        var symEmpty:Symbol = Symbol.create("");
        if (symEmpty.getDescription() === "") {
            trace("  ✅ 空描述符创建 Symbol 成功。");
        } else {
            trace("  ❌ 空描述符创建 Symbol 失败。");
        }
        
        // 测试特殊字符描述符
        var specialDesc:String = "特殊字符!@#$%^&*()_+";
        var symSpecial:Symbol = Symbol.create(specialDesc);
        if (symSpecial.getDescription() === specialDesc) {
            trace("  ✅ 特殊字符描述符创建 Symbol 成功。");
        } else {
            trace("  ❌ 特殊字符描述符创建 Symbol 失败。");
        }
    }
    
    /**
     * 测试内存管理功能，确保删除 Symbol 后不再保留
     */
    private function testMemoryManagement(): Void {
        trace("测试 9: 内存管理与资源清理");
        var key:String = "memoryTestKey";
        Symbol.forKey(key, "memorySymbol");
        var deleted:Boolean = Symbol.deleteSymbol(key);
        
        if (deleted && Symbol.deleteSymbol(key) === false) {
            trace("  ✅ Symbol 删除后无法再次删除，内存管理正常。");
        } else {
            trace("  ❌ Symbol 删除后存在问题。");
        }
    }
    
    /**
     * 运行所有测试
     */
    public static function run(): Void {
        new SymbolTest();
    }
}
