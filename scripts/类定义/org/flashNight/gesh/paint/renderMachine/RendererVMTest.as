import org.flashNight.gesh.paint.renderMachine.*;

class org.flashNight.gesh.paint.renderMachine.RendererVMTest {
    private var vm:RendererVM;
    private var testMC:MovieClip;

    public function RendererVMTest() {
        // 创建测试用的 MovieClip
        testMC = _root.createEmptyMovieClip("testMC", _root.getNextHighestDepth());
        // 使用测试 MovieClip 实例化 RendererVM
        vm = new RendererVM(testMC);
    }

    public function runTests():Void {
        testBasicDrawing();
        testStylingInstructions();
        testColorAndAlphaHandling();
        testBlendModes();
        testColorTransforms();
        testErrorHandling();
        testPerformance();
    }

    // 测试基本绘图操作
    private function testBasicDrawing():Void {
        trace("Testing Basic Drawing Operations");

        // moveTo 和 lineTo
        var commandStream:String = "M 100 100; L 200 200;";
        vm.executeCommandStream(commandStream);
        trace("moveTo and lineTo test completed.");

        // 绘制矩形
        commandStream = "R 50 50 150 100;";
        vm.executeCommandStream(commandStream);
        trace("drawRect test completed.");

        // 绘制圆形
        commandStream = "O 300 200 50;";
        vm.executeCommandStream(commandStream);
        trace("drawCircle test completed.");

        // 绘制圆角矩形
        commandStream = "A 400 100 120 80 15 15;";
        vm.executeCommandStream(commandStream);
        trace("drawRoundRect test completed.");

        // 绘制多边形
        commandStream = "P 500 200 40 6;";
        vm.executeCommandStream(commandStream);
        trace("drawPolygon test completed.");
    }

    // 测试样式指令
    private function testStylingInstructions():Void {
        trace("Testing Styling Instructions");

        // 设置线条样式
        var commandStream:String = "S 3 Aa 80; M 100 300; L 200 400;";
        vm.executeCommandStream(commandStream);
        trace("lineStyle test completed.");

        // 填充并结束填充
        commandStream = "F Bb 60; R 250 300 100 100; E;";
        vm.executeCommandStream(commandStream);
        trace("beginFill and endFill test completed.");

        // 渐变填充
        commandStream = "G linear AaBb CcDd EeFf 0,128,255; R 400 300 150 100; E;";
        vm.executeCommandStream(commandStream);
        trace("beginGradientFill test completed.");

        // 位图填充 (假设位图 'pattern' 已导出为 MovieClip)
        commandStream = "B pattern; R 600 300 100 100; E;";
        vm.executeCommandStream(commandStream);
        trace("beginBitmapFill test completed.");
    }

    // 测试颜色和透明度处理
    private function testColorAndAlphaHandling():Void {
        trace("Testing Color and Alpha Handling");

        // 测试颜色解码
        var colorCode:String = "Aa";
        var color:Number = vm.utils.decodeColor(colorCode);
        trace("Decoded color for 'Aa': " + color.toString(16));

        // 测试透明度解码
        var alphaCode:String = "Bb";
        var alphaArray:Array = vm.utils.decodeAlphas(alphaCode);
        trace("Decoded alpha for 'Bb': " + alphaArray[0]);

        // 测试指定颜色和透明度的绘图
        var commandStream:String = "F " + colorCode + " " + alphaArray[0] + "; O 200 500 50; E;";
        vm.executeCommandStream(commandStream);
        trace("Drawing with specific color and alpha completed.");
    }

    // 测试混合模式
    private function testBlendModes():Void {
        trace("Testing Blend Modes");

        // 设置为 normal 混合模式
        var commandStream:String = "N; F Aa 100; R 50 550 100 100; E;";
        vm.executeCommandStream(commandStream);
        trace("Blend mode set to 'normal'.");

        // 设置为 multiply 混合模式
        commandStream = "X; F Bb 100; R 100 600 100 100; E;";
        vm.executeCommandStream(commandStream);
        trace("Blend mode set to 'multiply'.");

        // 设置为 add 混合模式
        commandStream = "D; F Cc 100; R 150 650 100 100; E;";
        vm.executeCommandStream(commandStream);
        trace("Blend mode set to 'add'.");

        // 设置为 subtract 混合模式
        commandStream = "U; F Dd 100; R 200 700 100 100; E;";
        vm.executeCommandStream(commandStream);
        trace("Blend mode set to 'subtract'.");
    }

    // 测试颜色变换
    private function testColorTransforms():Void {
        trace("Testing Color Transforms");

        // 应用颜色变换
        var commandStream:String = "T 1 0.5 0.5 0 0 0 1 0; R 300 550 100 100;";
        vm.executeCommandStream(commandStream);
        trace("Applied color transform.");

        // 重置颜色变换
        commandStream = "T 1 1 1 0 0 0 1 0;";
        vm.executeCommandStream(commandStream);
        trace("Reset color transform.");
    }

    // 测试错误处理
    private function testErrorHandling():Void {
        trace("Testing Error Handling");

        // 使用无效的指令
        var commandStream:String = "Z 100 100;";
        vm.executeCommandStream(commandStream);
        trace("Tested error handling with invalid command.");

        // 缺少参数
        commandStream = "M 100;";
        vm.executeCommandStream(commandStream);
        trace("Tested error handling with missing parameters.");
    }

    // 测试性能
    private function testPerformance():Void {
        trace("Testing Performance");

        var startTime:Number = getTimer();
        var commandStream:String = "";
        for (var i:Number = 0; i < 1000; i++) {
            var x1:Number = Math.random() * 800;
            var y1:Number = Math.random() * 600;
            var x2:Number = Math.random() * 800;
            var y2:Number = Math.random() * 600;
            commandStream += "M " + x1 + " " + y1 + "; L " + x2 + " " + y2 + ";";
        }
        vm.executeCommandStream(commandStream);
        var endTime:Number = getTimer();
        trace("Performance test completed in " + (endTime - startTime) + " ms.");
    }
}
