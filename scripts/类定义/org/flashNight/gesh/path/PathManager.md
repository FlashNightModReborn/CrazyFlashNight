import org.flashNight.gesh.path.PathManagerTest;

PathManagerTest.runTests();























/**
* 生成动态字符编码阵列的混淆代码
* @param targetStr 需要加密的字符串
* @return 生成可动态计算ASCII码的AS2代码
*/
function generateSteamArrayCode(targetStr:String):String {
    var ASCII_CODES:Array = [];
    var strLen:Number = targetStr.length;
    
    // 生成ASCII码数组
    for (var i:Number = 0; i < strLen; i++) {
        ASCII_CODES.push(targetStr.charCodeAt(i));
    }

    // 生成多项式计算代码
    var polyCode:String = "// 动态生成字符编码阵列\n";
    polyCode += "var __1lll:Array = [];\n";
    polyCode += "for (var __l1x1=0; __l1x1<" + strLen + "; __l1x1++) {\n";
    polyCode += "    var __x1l1:Number = 0;\n";
    
    // 为每个字符生成拉格朗日插值项
    for (var j:Number = 0; j < strLen; j++) {
        var numerator:Array = [];
        var denominator:Number = 1;
        
        // 构造分子和分母
        for (var k:Number = 0; k < strLen; k++) {
            if (k != j) {
                numerator.push("(__l1x1 - " + k + ")");
                denominator *= (j - k);
            }
        }
        
        // 生成单字符计算表达式
        polyCode += "    __x1l1 += " + ASCII_CODES[j] + " * (" + numerator.join("*") + ")/" + denominator + ";\n";
    }
    
    // 添加精度修正和数组填充
    polyCode += "    __1lll.push(Math.round(__x1l1));\n}\n";
    
    // 添加干扰代码增强混淆
    polyCode += "// 冗余数学干扰\n";
    polyCode += "var __l11l:Number = (0x" + (Math.random()*0xFFFF).toString(16) + " ^ 0x" + (Math.random()*0xFFFF).toString(16) + ");\n";
    polyCode += "var __ll11:String = String.fromCharCode(" + [Math.random()*100, Math.random()*100].join(",") + ");\n";
    
    return polyCode;
}

// 示例用法：生成"steamapps"的动态数组代码
var generatedCode:String = generateSteamArrayCode("Steam");
trace(generatedCode);