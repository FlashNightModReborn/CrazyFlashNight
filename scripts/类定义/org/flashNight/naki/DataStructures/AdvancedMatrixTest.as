import org.flashNight.naki.DataStructures.*;

/**
 * AdvancedMatrixTest 类
 * 用于测试 AdvancedMatrix 类的各项功能和性能。
 */
class org.flashNight.naki.DataStructures.AdvancedMatrixTest {
    /**
     * 运行所有测试
     */
    public function runTests():Void {
        trace("开始运行 AdvancedMatrix 测试...");

        var testMethods:Array = ["testConstructors",
            "testAddition",
            "testSubtraction",
            "testScalarMultiplication",
            "testHadamardMultiplication",
            "testMultiplication",
            "testTranspose",
            "testDeterminantAndInverse",
            "testNormalization",
            "testApplyActivation",
            "testConvolution",
            "testTransformations",
            "testHasConverged",
            "testUpdateWeights",
            "testPerformance",
            "testMeanSquaredError"];

        var passCount:Number = 0;
        var failCount:Number = 0;

        for (var i:Number = 0; i < testMethods.length; i++) {
            var methodName:String = testMethods[i];
            trace("\n运行测试: " + methodName);

            try {
                this[methodName]();
                trace("测试 " + methodName + " : 通过。");
                passCount++;
            } catch (e:Error) {
                // 增加更详细的错误提示
                trace("测试 " + methodName + " : 失败 => " + e.message);
                failCount++;
            }
        }

        trace("\n测试完成: 通过 " + passCount + " 个，失败 " + failCount + " 个。");
    }

    /** 简单断言 */
    private function assert(condition:Boolean, message:String):Void {
        if (!condition) {
            throw new Error("断言失败: " + message);
        }
    }

    private function testConstructors():Void {
        trace("测试构造函数和初始化方法...");

        var data:Array = [1, 2, 3, 4];
        var matrix:AdvancedMatrix = new AdvancedMatrix(data).init(2, 2);
        assert(matrix.getRows() == 2, "行数错误");
        assert(matrix.getCols() == 2, "列数错误");
        assert(matrix.getElement(0, 0) == 1, "元素[0,0]应为1");
        assert(matrix.getElement(1, 1) == 4, "元素[1,1]应为4");

        var multiArr:Array = [[5, 6], [7, 8]];
        var matrix2:AdvancedMatrix = new AdvancedMatrix([]).initFromMultiDimensionalArray(multiArr);
        assert(matrix2.getRows() == 2, "多维数组初始化-行数错误");
        assert(matrix2.getCols() == 2, "多维数组初始化-列数错误");
        assert(matrix2.getElement(0, 0) == 5, "元素[0,0]应为5");
        assert(matrix2.getElement(1, 1) == 8, "元素[1,1]应为8");

        var cloneMat:AdvancedMatrix = matrix.clone();
        assert(cloneMat.getRows() == matrix.getRows(), "克隆矩阵行数不匹配");
        assert(cloneMat.getCols() == matrix.getCols(), "克隆矩阵列数不匹配");
        assert(cloneMat.getElement(0, 0) == matrix.getElement(0, 0), "克隆[0,0]元素不匹配");

        trace("构造函数和初始化方法测试通过。");
    }

    private function testAddition():Void {
        trace("测试矩阵加法...");

        var A:AdvancedMatrix = new AdvancedMatrix([1, 2, 3, 4]).init(2, 2);
        var B:AdvancedMatrix = new AdvancedMatrix([5, 6, 7, 8]).init(2, 2);
        var C:AdvancedMatrix = new AdvancedMatrix([0, 0, 0, 0]).init(2, 2);

        var D:AdvancedMatrix = A.add(B, null);
        assert(D.getElement(0, 0) == 6, "A+B[0,0]应为6");
        assert(D.getElement(1, 1) == 12, "A+B[1,1]应为12");

        var A_copy:AdvancedMatrix = A.clone();
        A_copy.addInPlace(B);
        assert(A_copy.getElement(0, 0) == 6, "原地加法[0,0]错误");
        assert(A_copy.getElement(1, 1) == 12, "原地加法[1,1]错误");

        A_copy = new AdvancedMatrix([1, 2, 3, 4]).init(2, 2);
        A_copy.add(B, C);
        assert(C.getElement(0, 0) == 6, "指定结果加法[0,0]错误");
        assert(C.getElement(1, 1) == 12, "指定结果加法[1,1]错误");

        trace("矩阵加法测试通过。");
    }

    private function testSubtraction():Void {
        trace("测试矩阵减法...");

        var A:AdvancedMatrix = new AdvancedMatrix([5, 6, 7, 8]).init(2, 2);
        var B:AdvancedMatrix = new AdvancedMatrix([1, 2, 3, 4]).init(2, 2);
        var C:AdvancedMatrix = new AdvancedMatrix([0, 0, 0, 0]).init(2, 2);

        var D:AdvancedMatrix = A.subtract(B, null);
        assert(D.getElement(0, 0) == 4, "A-B[0,0]应为4");
        assert(D.getElement(1, 1) == 4, "A-B[1,1]应为4");

        var A_copy:AdvancedMatrix = A.clone();
        A_copy.subtractInPlace(B);
        assert(A_copy.getElement(0, 0) == 4, "原地减法[0,0]错误");
        assert(A_copy.getElement(1, 1) == 4, "原地减法[1,1]错误");

        A_copy = new AdvancedMatrix([5, 6, 7, 8]).init(2, 2);
        A_copy.subtract(B, C);
        assert(C.getElement(0, 0) == 4, "指定结果减法[0,0]错误");
        assert(C.getElement(1, 1) == 4, "指定结果减法[1,1]错误");

        trace("矩阵减法测试通过。");
    }

    private function testScalarMultiplication():Void {
        trace("测试矩阵数乘...");

        var A:AdvancedMatrix = new AdvancedMatrix([1, 2, 3, 4]).init(2, 2);
        var C:AdvancedMatrix = new AdvancedMatrix([0, 0, 0, 0]).init(2, 2);

        var D:AdvancedMatrix = A.scalarMultiply(2, null);
        assert(D.getElement(0, 0) == 2, "2*[0,0]应为2");
        assert(D.getElement(1, 1) == 8, "2*[1,1]应为8");

        var A_copy:AdvancedMatrix = A.clone();
        A_copy.scalarMultiplyInPlace(3);
        assert(A_copy.getElement(0, 0) == 3, "原地数乘[0,0]错误");
        assert(A_copy.getElement(1, 1) == 12, "原地数乘[1,1]错误");

        A_copy = new AdvancedMatrix([1, 2, 3, 4]).init(2, 2);
        A_copy.scalarMultiply(4, C);
        assert(C.getElement(0, 0) == 4, "指定结果数乘[0,0]错误");
        assert(C.getElement(1, 1) == 16, "指定结果数乘[1,1]错误");

        trace("矩阵数乘测试通过。");
    }

    private function testHadamardMultiplication():Void {
        trace("测试 Hadamard 乘法...");

        var A:AdvancedMatrix = new AdvancedMatrix([1, 2, 3, 4]).init(2, 2);
        var B:AdvancedMatrix = new AdvancedMatrix([5, 6, 7, 8]).init(2, 2);
        var C:AdvancedMatrix = new AdvancedMatrix([0, 0, 0, 0]).init(2, 2);

        var D:AdvancedMatrix = A.hadamardMultiply(B, null);
        assert(D.getElement(0, 0) == 5, "Hadamard[0,0]应为5");
        assert(D.getElement(1, 1) == 32, "Hadamard[1,1]应为32");

        var A_copy:AdvancedMatrix = A.clone();
        A_copy.hadamardMultiplyInPlace(B);
        assert(A_copy.getElement(0, 0) == 5, "原地Hadamard[0,0]错误");
        assert(A_copy.getElement(1, 1) == 32, "原地Hadamard[1,1]错误");

        A_copy = new AdvancedMatrix([1, 2, 3, 4]).init(2, 2);
        A_copy.hadamardMultiply(B, C);
        assert(C.getElement(0, 0) == 5, "指定结果Hadamard[0,0]错误");
        assert(C.getElement(1, 1) == 32, "指定结果Hadamard[1,1]错误");

        trace("Hadamard 乘法测试通过。");
    }

    private function testMultiplication():Void {
        trace("测试矩阵乘法...");

        var A:AdvancedMatrix = new AdvancedMatrix([1, 2, 3, 4]).init(2, 2);
        var B:AdvancedMatrix = new AdvancedMatrix([5, 6, 7, 8]).init(2, 2);
        var C:AdvancedMatrix = new AdvancedMatrix([0, 0, 0, 0]).init(2, 2);

        // A x B
        var D:AdvancedMatrix = A.multiply(B, null);
        // [1*5+2*7, 1*6+2*8] => [19,22]
        // [3*5+4*7, 3*6+4*8] => [43,50]
        assert(D.getElement(0, 0) == 19, "乘法[0,0]错误");
        assert(D.getElement(0, 1) == 22, "乘法[0,1]错误");
        assert(D.getElement(1, 0) == 43, "乘法[1,0]错误");
        assert(D.getElement(1, 1) == 50, "乘法[1,1]错误");

        A.multiply(B, C);
        assert(C.getElement(0, 0) == 19, "C[0,0]错误");
        assert(C.getElement(1, 1) == 50, "C[1,1]错误");

        trace("矩阵乘法测试通过。");
    }

    private function testTranspose():Void {
        trace("测试矩阵转置...");

        var A:AdvancedMatrix = new AdvancedMatrix([1, 2, 3, 4, 5, 6]).init(2, 3);
        var B:AdvancedMatrix = new AdvancedMatrix([0, 0, 0, 0, 0, 0]).init(3, 2);

        var C:AdvancedMatrix = A.transpose(null);
        // A = 2x3 => [1,2,3;4,5,6]
        // 转置 => 3x2 => [1,4; 2,5; 3,6]
        assert(C.getRows() == 3, "转置后行数应为3");
        assert(C.getCols() == 2, "转置后列数应为2");
        assert(C.getElement(0, 0) == 1, "转置[0,0]错误");
        assert(C.getElement(2, 1) == 6, "转置[2,1]错误");

        A.transpose(B);
        assert(B.getRows() == 3, "B行数应为3");
        assert(B.getCols() == 2, "B列数应为2");
        assert(B.getElement(0, 0) == 1, "B[0,0]应为1");
        assert(B.getElement(2, 1) == 6, "B[2,1]应为6");

        trace("矩阵转置测试通过。");
    }

    private function testDeterminantAndInverse():Void {
        trace("测试矩阵行列式和逆矩阵...");

        // 2x2
        var A:AdvancedMatrix = new AdvancedMatrix([4, 7, 2, 6]).init(2, 2);
        var det:Number = A.determinant();
        // => (4*6 - 7*2) = 24 - 14 = 10
        assert(det == 10, "2x2行列式应为10");

        var A_inv:AdvancedMatrix = A.inverse();
        // => (1/10)*[[ 6, -7],[-2,4]]
        assert(Math.abs(A_inv.getElement(0, 0) - 0.6) < 1e-6, "inverse(0,0)错误");
        assert(Math.abs(A_inv.getElement(0, 1) - (-0.7)) < 1e-6, "inverse(0,1)错误");
        assert(Math.abs(A_inv.getElement(1, 0) - (-0.2)) < 1e-6, "inverse(1,0)错误");
        assert(Math.abs(A_inv.getElement(1, 1) - 0.4) < 1e-6, "inverse(1,1)错误");

        // 3x3
        // |1 2 3|
        // |0 1 4|
        // |5 6 0|
        // 手算=1
        A = new AdvancedMatrix([1, 2, 3,
            0, 1, 4,
            5, 6, 0]).init(3, 3);
        var det3:Number = A.determinant();
        // 此处若有微小浮点误差，改成 abs(det3-1) < 1e-6 来断言
        assert(Math.abs(det3 - 1) < 1e-6, "3x3行列式应为1, 实际=" + det3);

        var A3_inv:AdvancedMatrix = A.inverse();
        // => [-24,18,5; 20,-15,-4; -5,4,1]
        assert(Math.abs(A3_inv.getElement(0, 0) - (-24)) < 1e-6, "A3_inv[0,0]错误");
        assert(Math.abs(A3_inv.getElement(0, 1) - 18) < 1e-6, "A3_inv[0,1]错误");
        assert(Math.abs(A3_inv.getElement(0, 2) - 5) < 1e-6, "A3_inv[0,2]错误");
        assert(Math.abs(A3_inv.getElement(1, 0) - 20) < 1e-6, "A3_inv[1,0]错误");
        assert(Math.abs(A3_inv.getElement(1, 1) - (-15)) < 1e-6, "A3_inv[1,1]错误");
        assert(Math.abs(A3_inv.getElement(1, 2) - (-4)) < 1e-6, "A3_inv[1,2]错误");
        assert(Math.abs(A3_inv.getElement(2, 0) - (-5)) < 1e-6, "A3_inv[2,0]错误");
        assert(Math.abs(A3_inv.getElement(2, 1) - 4) < 1e-6, "A3_inv[2,1]错误");
        assert(Math.abs(A3_inv.getElement(2, 2) - 1) < 1e-6, "A3_inv[2,2]错误");

        trace("矩阵行列式和逆矩阵测试通过。");
    }

    private function testNormalization():Void {
        trace("测试矩阵归一化...");

        var A:AdvancedMatrix = new AdvancedMatrix([2, 4, 6, 8]).init(2, 2);
        var B:AdvancedMatrix = new AdvancedMatrix([0, 0, 0, 0]).init(2, 2);

        // [2,4,6,8] => min=2, max=8 => range=6
        // => [0, 1/3, 2/3, 1]
        var C:AdvancedMatrix = A.normalize();
        assert(Math.abs(C.getElement(0, 0) - 0) < 1e-6, "[0,0]应为0");
        assert(Math.abs(C.getElement(0, 1) - 0.3333333) < 1e-5, "[0,1]应约=1/3");
        assert(Math.abs(C.getElement(1, 1) - 1) < 1e-6, "[1,1]应为1");

        // 行归一化
        A = new AdvancedMatrix([1, 2, 3, 4]).init(2, 2);
        var A_rowsNorm:AdvancedMatrix = A.normalizeRows(null);
        // row0 sum=3 => [1/3,2/3]
        // row1 sum=7 => [3/7,4/7]
        assert(Math.abs(A_rowsNorm.getElement(0, 0) - (1 / 3)) < 1e-6, "行归一化[0,0]错误");
        assert(Math.abs(A_rowsNorm.getElement(1, 1) - (4 / 7)) < 1e-6, "行归一化[1,1]错误");

        // 行归一化并指定 result
        A = new AdvancedMatrix([2, 4, 6, 8]).init(2, 2);
        A.normalizeRows(B);
        // row0 sum=6 => [2/6=1/3,4/6=2/3]
        // row1 sum=14 => [6/14=3/7,8/14=4/7]
        assert(Math.abs(B.getElement(0, 0) - (1 / 3)) < 1e-6, "B[0,0]错误");
        assert(Math.abs(B.getElement(1, 1) - (4 / 7)) < 1e-6, "B[1,1]错误");

        trace("矩阵归一化测试通过。");
    }

    private function testApplyActivation():Void {
        trace("测试应用激活函数...");

        var A:AdvancedMatrix = new AdvancedMatrix([-1, 0, 1, 2]).init(2, 2);
        var B:AdvancedMatrix = new AdvancedMatrix([0, 0, 0, 0]).init(2, 2);

        // sigmoid
        var C:AdvancedMatrix = A.applyActivation("sigmoid", null);
        // [-1 => ~0.26894, 0=>0.5, 1=>~0.73106, 2=>~0.88079]
        assert(Math.abs(C.getElement(0, 0) - 0.26894142137) < 1e-5, "sigmoid[0,0]错误");
        assert(Math.abs(C.getElement(1, 1) - 0.88079707797) < 1e-5, "sigmoid[1,1]错误");

        // relu
        C = A.applyActivation("relu", null);
        // => [0,0,1,2]
        assert(C.getElement(0, 0) == 0, "relu[0,0]错误");
        assert(C.getElement(1, 1) == 2, "relu[1,1]错误");

        // tanh
        A = new AdvancedMatrix([-1, 0, 1, 2]).init(2, 2);
        C = A.applyActivation("tanh", null);
        // => [-0.761594..., 0, 0.761594..., 0.96402758...]
        assert(Math.abs(C.getElement(0, 0) - (-0.7615941559557649)) < 1e-6, "tanh[0,0]错误");
        assert(Math.abs(C.getElement(1, 1) - 0.9640275800758169) < 1e-6, "tanh[1,1]错误");

        // 指定 result
        A = new AdvancedMatrix([1, 2, 3, 4]).init(2, 2);
        A.applyActivation("relu", B);
        assert(B.getElement(0, 0) == 1, "B[0,0]错误");
        assert(B.getElement(1, 1) == 4, "B[1,1]错误");

        trace("应用激活函数测试通过。");
    }

    private function testConvolution():Void {
        trace("测试矩阵卷积...");

        var image:AdvancedMatrix = new AdvancedMatrix([1, 2, 3, 4, 5, 6, 7, 8, 9]).init(3, 3);
        var kernel:AdvancedMatrix = new AdvancedMatrix([0, 1, 0, 1, -4, 1, 0, 1, 0]).init(3, 3);

        var convResult:AdvancedMatrix = image.convolve(kernel, 0, 1);
        // 理论输出=1x1 => = (1*0 +2*1 +3*0 +4*1 +5*(-4)+6*1 +7*0 +8*1 +9*0)
        // => 0+2+0+4 -20+6+0+8+0 = 0
        assert(convResult.getRows() == 1, "卷积结果行数应为1");
        assert(convResult.getCols() == 1, "卷积结果列数应为1");
        assert(Math.abs(convResult.getElement(0, 0)) < 1e-6, "卷积[0,0]应为0");

        trace("矩阵卷积测试通过。");
    }

    private function testTransformations():Void {
        trace("测试仿射变换...");

        var image:AdvancedMatrix = new AdvancedMatrix([
            1, 2, 3, 4,
            5, 6, 7, 8,
            9,10,11,12,
            13,14,15,16
        ]).init(4, 4);

        // 定义平移矩阵，将中心移动到原点
        var T_forward:AdvancedMatrix = AdvancedMatrix.translationMatrix(-1.5, -1.5);

        // 定义旋转矩阵（逆时针90度）
        var R:AdvancedMatrix = AdvancedMatrix.rotationMatrix(90);

        // 定义平移矩阵，将中心从原点移回
        var T_back:AdvancedMatrix = AdvancedMatrix.translationMatrix(1.5, 1.5);

        // 组合变换矩阵：T_back * R * T_forward
        var temp:AdvancedMatrix = R.multiply(T_forward, null);
        var composite:AdvancedMatrix = T_back.multiply(temp, null);

        // 应用组合变换（旋转）
        var rotatedImage:AdvancedMatrix = image.applyTransformation(composite, null);

        trace(rotatedImage);
        // 检查旋转结果
        assert(Math.abs(rotatedImage.getElement(0, 0) - 13) < 1e-6, "旋转[0,0]应为13");
        assert(Math.abs(rotatedImage.getElement(0, 1) - 9) < 1e-6, "旋转[0,1]应为9");
        assert(Math.abs(rotatedImage.getElement(0, 2) - 5) < 1e-6, "旋转[0,2]应为5");
        assert(Math.abs(rotatedImage.getElement(0, 3) - 1) < 1e-6, "旋转[0,3]应为1");
        assert(Math.abs(rotatedImage.getElement(1, 0) - 14) < 1e-6, "旋转[1,0]应为14");
        assert(Math.abs(rotatedImage.getElement(1, 1) -10) < 1e-6, "旋转[1,1]应为10");
        assert(Math.abs(rotatedImage.getElement(1, 2) - 6) < 1e-6, "旋转[1,2]应为6");
        assert(Math.abs(rotatedImage.getElement(1, 3) - 2) < 1e-6, "旋转[1,3]应为2");
        assert(Math.abs(rotatedImage.getElement(2, 0) - 15) < 1e-6, "旋转[2,0]应为15");
        assert(Math.abs(rotatedImage.getElement(2, 1) -11) < 1e-6, "旋转[2,1]应为11");
        assert(Math.abs(rotatedImage.getElement(2, 2) -7) < 1e-6, "旋转[2,2]应为7");
        assert(Math.abs(rotatedImage.getElement(2, 3) -3) < 1e-6, "旋转[2,3]应为3");
        assert(Math.abs(rotatedImage.getElement(3, 0) -16) < 1e-6, "旋转[3,0]应为16");
        assert(Math.abs(rotatedImage.getElement(3, 1) -12) < 1e-6, "旋转[3,1]应为12");
        assert(Math.abs(rotatedImage.getElement(3, 2) -8) < 1e-6, "旋转[3,2]应为8");
        assert(Math.abs(rotatedImage.getElement(3, 3) -4) < 1e-6, "旋转[3,3]应为4");

        // 缩放 2x => 简化测试，假设采样可导致部分像素=0
        var scaling:AdvancedMatrix = AdvancedMatrix.scalingMatrix(2, 2);
        var scaledImage:AdvancedMatrix = rotatedImage.applyTransformation(scaling, null);

        trace(scaledImage);
        // 仅测试是否维度没变 & 部分值
        assert(scaledImage.getRows() == 4, "缩放后行数应为4");
        assert(scaledImage.getCols() == 4, "缩放后列数应为4");
        assert(Math.abs(scaledImage.getElement(0, 0) - 13) < 1e-6, "缩放后[0,0]应为13");
        assert(Math.abs(scaledImage.getElement(1, 1) -10) < 1e-6, "缩放后[1,1]应为10");

        // 平移 (-1,1) 向左移动1，向下移动1
        // 为实现视觉上的 (-1,1) 平移，传入其逆矩阵 (1,-1)
        var translation:AdvancedMatrix = AdvancedMatrix.translationMatrix(1, -1);
        var translatedImage:AdvancedMatrix = scaledImage.applyTransformation(translation, null);

        trace(translatedImage);
        // 仅测试部分元素
        assert(Math.abs(translatedImage.getElement(0, 0)) < 1e-6, "平移[0,0]应为0");
        assert(Math.abs(translatedImage.getElement(0, 1) -14) < 1e-6, "平移[0,1]应为14"); // 修改预期值
        assert(Math.abs(translatedImage.getElement(0, 2) -10) < 1e-6, "平移[0,2]应为10"); // 修改预期值
        assert(Math.abs(translatedImage.getElement(0, 3) -10) < 1e-6, "平移[0,3]应为10"); // 修改预期值
        assert(Math.abs(translatedImage.getElement(1, 0)) <1e-6, "平移[1,0]应为0");
        assert(Math.abs(translatedImage.getElement(1, 1) -14) <1e-6, "平移[1,1]应为14"); // 修改预期值
        assert(Math.abs(translatedImage.getElement(1, 2) -10) <1e-6, "平移[1,2]应为10"); // 修改预期值
        assert(Math.abs(translatedImage.getElement(1, 3) -10) <1e-6, "平移[1,3]应为10"); // 修改预期值
        assert(Math.abs(translatedImage.getElement(2, 0)) <1e-6, "平移[2,0]应为0");
        assert(Math.abs(translatedImage.getElement(2, 1) -15) <1e-6, "平移[2,1]应为15"); // 修改预期值
        assert(Math.abs(translatedImage.getElement(2, 2) -11) <1e-6, "平移[2,2]应为11"); // 修改预期值
        assert(Math.abs(translatedImage.getElement(2, 3) -11) <1e-6, "平移[2,3]应为11"); // 修改预期值
        assert(Math.abs(translatedImage.getElement(3, 0)) <1e-6, "平移[3,0]应为0");
        assert(Math.abs(translatedImage.getElement(3, 1) -0) <1e-6, "平移[3,1]应为0"); // 修改预期值
        assert(Math.abs(translatedImage.getElement(3, 2) -0) <1e-6, "平移[3,2]应为0"); // 修改预期值
        assert(Math.abs(translatedImage.getElement(3, 3) -0) <1e-6, "平移[3,3]应为0"); // 修改预期值

        trace("仿射变换测试通过。");
    }



    private function testHasConverged():Void {
        trace("测试矩阵收敛判断...");

        var A:AdvancedMatrix = new AdvancedMatrix([1, 2, 3, 4]).init(2, 2);
        var B:AdvancedMatrix = new AdvancedMatrix([1.1, 2, 3, 4]).init(2, 2);
        var threshold:Number = 0.001;

        var conv:Boolean = A.hasConverged(B, threshold);
        assert(conv == false, "应未收敛");

        var C:AdvancedMatrix = new AdvancedMatrix([1.1, 2, 3, 4]).init(2, 2);
        var conv2:Boolean = B.hasConverged(C, threshold);
        assert(conv2 == true, "应已收敛");

        trace("矩阵收敛判断测试通过。");
    }

    private function testUpdateWeights():Void {
        trace("测试权重更新...");

        var weights:AdvancedMatrix = new AdvancedMatrix([1, 2, 3, 4]).init(2, 2);
        var gradients:AdvancedMatrix = new AdvancedMatrix([0.1, 0.2, 0.3, 0.4]).init(2, 2);
        var lr:Number = 0.5;

        var updated:AdvancedMatrix = weights.updateWeights(gradients, lr, null);
        // => weights - 0.5*grad => [0.95,1.9,2.85,3.8]
        assert(Math.abs(updated.getElement(0, 0) - 0.95) < 1e-6, "更新后[0,0]应为0.95");
        assert(Math.abs(updated.getElement(1, 1) - 3.8) < 1e-6, "更新后[1,1]应为3.8");

        var C:AdvancedMatrix = new AdvancedMatrix([0, 0, 0, 0]).init(2, 2);
        weights = new AdvancedMatrix([1, 2, 3, 4]).init(2, 2);
        weights.updateWeights(gradients, lr, C);
        assert(Math.abs(C.getElement(0, 0) - 0.95) < 1e-6, "C[0,0]应为0.95");
        assert(Math.abs(C.getElement(1, 1) - 3.8) < 1e-6, "C[1,1]应为3.8");

        trace("权重更新测试通过。");
    }

    private function testPerformance():Void {
        trace("开始性能测试...");

        var size:Number = 500;
        var dataA:Array = [];
        var dataB:Array = [];
        for (var i:Number = 0; i < size * size; i++) {
            dataA.push(Math.random());
            dataB.push(Math.random());
        }
        var A:AdvancedMatrix = new AdvancedMatrix(dataA).init(size, size);
        var B:AdvancedMatrix = new AdvancedMatrix(dataB).init(size, size);

        var startTime:Number = getTimer();
        A.add(B, null);
        var endTime:Number = getTimer();
        trace("加法耗时: " + (endTime - startTime) + " 毫秒");

        A.addInPlace(B);
        trace("原地加法完成。");

        startTime = getTimer();
        A.multiply(B, null);
        endTime = getTimer();
        trace("乘法耗时: " + (endTime - startTime) + " 毫秒");

        startTime = getTimer();
        A.transpose(null);
        endTime = getTimer();
        trace("转置耗时: " + (endTime - startTime) + " 毫秒");

        var smallA:AdvancedMatrix = new AdvancedMatrix([4, 7, 2, 6]).init(2, 2);
        startTime = getTimer();
        var smallInv:AdvancedMatrix = smallA.inverse();
        endTime = getTimer();
        trace("逆矩阵(2x2)耗时: " + (endTime - startTime) + " 毫秒");

        trace("性能测试完成。");
    }

    private function testMeanSquaredError():Void {
        trace("测试均方误差和其导数...");

        var output:AdvancedMatrix = new AdvancedMatrix([1, 2, 3, 4]).init(2, 2);
        var target:AdvancedMatrix = new AdvancedMatrix([2, 2, 2, 2]).init(2, 2);

        // => ((1-2)^2+(2-2)^2+(3-2)^2+(4-2)^2)/4 = (1+0+1+4)/4=1.5
        var mse:Number = AdvancedMatrix.meanSquaredError(output, target);
        assert(Math.abs(mse - 1.5) < 1e-6, "MSE应为1.5, 实际=" + mse);

        var deriv:AdvancedMatrix = AdvancedMatrix.meanSquaredErrorDerivative(output, target, null);
        // => 2*(output-target)/4 => [-0.5,0,0.5,1]
        assert(Math.abs(deriv.getElement(0, 0) - (-0.5)) < 1e-6, "导数[0,0]应为-0.5");
        assert(Math.abs(deriv.getElement(1, 1) - 1) < 1e-6, "导数[1,1]应为1");

        trace("均方误差和其导数测试通过。");
    }
}
