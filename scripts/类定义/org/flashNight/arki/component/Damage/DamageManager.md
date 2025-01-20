
import org.flashNight.arki.component.Damage.*;
// 运行 DamageManager 测试
DamageManagerTest.runTests();



// 伤害管理器工厂中的策略函数生成代码

var generatedCode:String = "";

for (var i:Number = 1; i <= 32; i++) {
    var funcName:String = "getDamageManager" + i;
    generatedCode += "public function " + funcName + "(bullet:Object):DamageManager {\n";
    generatedCode += "    var bitmask:Number = this._skipCheckBitmask;\n";
    generatedCode += "    var handles:Array = this._handles;\n";
    generatedCode += "    var conditionalIndices:Array = this._conditionalHandlerIndices;\n";
	generatedCode += "    var index:Number;\n";
    generatedCode += "\n";

    for (var j:Number = 0; j < i; j++) {
        generatedCode += "    index = conditionalIndices[" + j + "];\n";
        generatedCode += "    if (handles[index].canHandle(bullet)) bitmask |= (1 << index);\n";

    }

    generatedCode += "\n    return DamageManager(this._managerCache.get(bitmask));\n";
    generatedCode += "}\n";
    generatedCode += "\n";
}
