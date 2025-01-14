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
            "testConvolution", // 已修改以使用 3x3 卷积核
            "testTransformations", // 修正期望旋转结果
            "testHasConverged", // 改大 A/B 差异
            "testUpdateWeights",
            "testPerformance",
            "testMeanSquaredError"];

        var passCount:Number = 0;
        var failCount:Number = 0;

        for (var i:Number = 0; i < testMethods.length; i++) {
            var methodName:String = testMethods[i];
            trace("\n运行测试: " + methodName);

            try {
                this[methodName](); // 反射调用
                trace("测试 " + methodName + " : 通过。");
                passCount++;
            } catch (e:Error) {
                trace("测试 " + methodName + " : 失败 => " + e.message);
                failCount++;
            }
        }

        trace("\n测试完成: 通过 " + passCount + " 个，失败 " + failCount + " 个。");
    }

    /**
     * 简单断言方法
     * @param condition 布尔条件
     * @param message 错误消息
     */
    private function assert(condition:Boolean, message:String):Void {
        if (!condition) {
            throw new Error("断言失败: " + message);
        }
    }

    /**
     * 测试构造函数和初始化方法
     */
    private function testConstructors():Void {
        trace("测试构造函数和初始化方法...");

        // 测试 init 方法
        var data:Array = [1, 2, 3, 4];
        var matrix:AdvancedMatrix = new AdvancedMatrix(data).init(2, 2);
        assert(matrix.getRows() == 2, "初始化行数错误");
        assert(matrix.getCols() == 2, "初始化列数错误");
        assert(matrix.getElement(0, 0) == 1, "元素 [0,0] 错误");
        assert(matrix.getElement(1, 1) == 4, "元素 [1,1] 错误");

        // 测试 initFromMultiDimensionalArray 方法
        var multiArray:Array = [[5, 6], [7, 8]];
        var matrix2:AdvancedMatrix = new AdvancedMatrix([]).initFromMultiDimensionalArray(multiArray);
        assert(matrix2.getRows() == 2, "多维数组初始化行数错误");
        assert(matrix2.getCols() == 2, "多维数组初始化列数错误");
        assert(matrix2.getElement(0, 0) == 5, "元素 [0,0] 错误");
        assert(matrix2.getElement(1, 1) == 8, "元素 [1,1] 错误");

        // 测试 clone 方法
        var matrixClone:AdvancedMatrix = matrix.clone();
        assert(matrixClone.getRows() == matrix.getRows(), "克隆矩阵行数不匹配");
        assert(matrixClone.getCols() == matrix.getCols(), "克隆矩阵列数不匹配");
        assert(matrixClone.getElement(0, 0) == matrix.getElement(0, 0), "克隆矩阵元素 [0,0] 不匹配");

        trace("构造函数和初始化方法测试通过。");
    }

    /**
     * 测试矩阵加法
     */
    private function testAddition():Void {
        trace("测试矩阵加法...");

        var A:AdvancedMatrix = new AdvancedMatrix([1, 2, 3, 4]).init(2, 2);
        var B:AdvancedMatrix = new AdvancedMatrix([5, 6, 7, 8]).init(2, 2);
        var C:AdvancedMatrix = new AdvancedMatrix([0, 0, 0, 0]).init(2, 2);

        // 使用 add 方法
        var D:AdvancedMatrix = A.add(B, null);
        assert(D.getElement(0, 0) == 6, "加法元素 [0,0] 错误");
        assert(D.getElement(1, 1) == 12, "加法元素 [1,1] 错误");

        // 使用 addInPlace 方法
        var A_copy:AdvancedMatrix = A.clone(); // 克隆以避免修改原始 A
        A_copy.addInPlace(B);
        assert(A_copy.getElement(0, 0) == 6, "原地加法元素 [0,0] 错误");
        assert(A_copy.getElement(1, 1) == 12, "原地加法元素 [1,1] 错误");

        // 使用 add 方法并指定结果矩阵
        A_copy = new AdvancedMatrix([1, 2, 3, 4]).init(2, 2);
        A_copy.add(B, C);
        assert(C.getElement(0, 0) == 6, "指定结果加法元素 [0,0] 错误");
        assert(C.getElement(1, 1) == 12, "指定结果加法元素 [1,1] 错误");

        trace("矩阵加法测试通过。");
    }

    /**
     * 测试矩阵减法
     */
    private function testSubtraction():Void {
        trace("测试矩阵减法...");

        var A:AdvancedMatrix = new AdvancedMatrix([5, 6, 7, 8]).init(2, 2);
        var B:AdvancedMatrix = new AdvancedMatrix([1, 2, 3, 4]).init(2, 2);
        var C:AdvancedMatrix = new AdvancedMatrix([0, 0, 0, 0]).init(2, 2);

        // 使用 subtract 方法
        var D:AdvancedMatrix = A.subtract(B, null);
        assert(D.getElement(0, 0) == 4, "减法元素 [0,0] 错误");
        assert(D.getElement(1, 1) == 4, "减法元素 [1,1] 错误");

        // 使用 subtractInPlace 方法
        var A_copy:AdvancedMatrix = A.clone(); // 克隆以避免修改原始 A
        A_copy.subtractInPlace(B);
        assert(A_copy.getElement(0, 0) == 4, "原地减法元素 [0,0] 错误");
        assert(A_copy.getElement(1, 1) == 4, "原地减法元素 [1,1] 错误");

        // 使用 subtract 方法并指定结果矩阵
        A_copy = new AdvancedMatrix([5, 6, 7, 8]).init(2, 2);
        A_copy.subtract(B, C);
        assert(C.getElement(0, 0) == 4, "指定结果减法元素 [0,0] 错误");
        assert(C.getElement(1, 1) == 4, "指定结果减法元素 [1,1] 错误");

        trace("矩阵减法测试通过。");
    }

    /**
     * 测试矩阵数乘
     */
    private function testScalarMultiplication():Void {
        trace("测试矩阵数乘...");

        var A:AdvancedMatrix = new AdvancedMatrix([1, 2, 3, 4]).init(2, 2);
        var C:AdvancedMatrix = new AdvancedMatrix([0, 0, 0, 0]).init(2, 2);

        // 使用 scalarMultiply 方法
        var D:AdvancedMatrix = A.scalarMultiply(2, null);
        assert(D.getElement(0, 0) == 2, "数乘元素 [0,0] 错误");
        assert(D.getElement(1, 1) == 8, "数乘元素 [1,1] 错误");

        // 使用 scalarMultiplyInPlace 方法
        var A_copy:AdvancedMatrix = A.clone(); // 克隆以避免修改原始 A
        A_copy.scalarMultiplyInPlace(3);
        assert(A_copy.getElement(0, 0) == 3, "原地数乘元素 [0,0] 错误");
        assert(A_copy.getElement(1, 1) == 12, "原地数乘元素 [1,1] 错误");

        // 使用 scalarMultiply 方法并指定结果矩阵
        A_copy = new AdvancedMatrix([1, 2, 3, 4]).init(2, 2);
        A_copy.scalarMultiply(4, C);
        assert(C.getElement(0, 0) == 4, "指定结果数乘元素 [0,0] 错误");
        assert(C.getElement(1, 1) == 16, "指定结果数乘元素 [1,1] 错误");

        trace("矩阵数乘测试通过。");
    }

    /**
     * 测试 Hadamard 乘法
     */
    private function testHadamardMultiplication():Void {
        trace("测试 Hadamard 乘法...");

        var A:AdvancedMatrix = new AdvancedMatrix([1, 2, 3, 4]).init(2, 2);
        var B:AdvancedMatrix = new AdvancedMatrix([5, 6, 7, 8]).init(2, 2);
        var C:AdvancedMatrix = new AdvancedMatrix([0, 0, 0, 0]).init(2, 2);

        // 使用 hadamardMultiply 方法
        var D:AdvancedMatrix = A.hadamardMultiply(B, null);
        assert(D.getElement(0, 0) == 5, "Hadamard 乘法元素 [0,0] 错误");
        assert(D.getElement(1, 1) == 32, "Hadamard 乘法元素 [1,1] 错误");

        // 使用 hadamardMultiplyInPlace 方法
        var A_copy:AdvancedMatrix = A.clone(); // 克隆以避免修改原始 A
        A_copy.hadamardMultiplyInPlace(B);
        assert(A_copy.getElement(0, 0) == 5, "原地 Hadamard 乘法元素 [0,0] 错误");
        assert(A_copy.getElement(1, 1) == 32, "原地 Hadamard 乘法元素 [1,1] 错误");

        // 使用 hadamardMultiply 方法并指定结果矩阵
        A_copy = new AdvancedMatrix([1, 2, 3, 4]).init(2, 2);
        A_copy.hadamardMultiply(B, C);
        assert(C.getElement(0, 0) == 5, "指定结果 Hadamard 乘法元素 [0,0] 错误");
        assert(C.getElement(1, 1) == 32, "指定结果 Hadamard 乘法元素 [1,1] 错误");

        trace("Hadamard 乘法测试通过。");
    }

    /**
     * 测试矩阵乘法
     */
    private function testMultiplication():Void {
        trace("测试矩阵乘法...");

        var A:AdvancedMatrix = new AdvancedMatrix([1, 2, 3, 4]).init(2, 2);
        var B:AdvancedMatrix = new AdvancedMatrix([5, 6, 7, 8]).init(2, 2);
        var C:AdvancedMatrix = new AdvancedMatrix([0, 0, 0, 0]).init(2, 2);

        // 使用 multiply 方法
        var D:AdvancedMatrix = A.multiply(B, null);
        assert(D.getElement(0, 0) == 19, "乘法元素 [0,0] 错误");
        assert(D.getElement(0, 1) == 22, "乘法元素 [0,1] 错误");
        assert(D.getElement(1, 0) == 43, "乘法元素 [1,0] 错误");
        assert(D.getElement(1, 1) == 50, "乘法元素 [1,1] 错误");

        // 使用 multiply 方法并指定结果矩阵
        A = new AdvancedMatrix([1, 2, 3, 4]).init(2, 2);
        A.multiply(B, C);
        assert(C.getElement(0, 0) == 19, "指定结果乘法元素 [0,0] 错误");
        assert(C.getElement(0, 1) == 22, "指定结果乘法元素 [0,1] 错误");
        assert(C.getElement(1, 0) == 43, "指定结果乘法元素 [1,0] 错误");
        assert(C.getElement(1, 1) == 50, "指定结果乘法元素 [1,1] 错误");

        trace("矩阵乘法测试通过。");
    }

    /**
     * 测试矩阵转置
     */
    private function testTranspose():Void {
        trace("测试矩阵转置...");

        var A:AdvancedMatrix = new AdvancedMatrix([1, 2, 3, 4, 5, 6]).init(2, 3);
        var B:AdvancedMatrix = new AdvancedMatrix([0, 0, 0, 0, 0, 0]).init(3, 2);

        // 使用 transpose 方法
        var C:AdvancedMatrix = A.transpose(null);
        assert(C.getRows() == 3, "转置后行数错误");
        assert(C.getCols() == 2, "转置后列数错误");
        assert(C.getElement(0, 0) == 1, "转置元素 [0,0] 错误");
        assert(C.getElement(2, 1) == 6, "转置元素 [2,1] 错误");

        // 使用 transpose 方法并指定结果矩阵
        A.transpose(B);
        assert(B.getRows() == 3, "指定结果转置后行数错误");
        assert(B.getCols() == 2, "指定结果转置后列数错误");
        assert(B.getElement(0, 0) == 1, "指定结果转置元素 [0,0] 错误");
        assert(B.getElement(2, 1) == 6, "指定结果转置元素 [2,1] 错误");

        trace("矩阵转置测试通过。");
    }

    /**
     * 测试矩阵行列式和逆矩阵
     */
    private function testDeterminantAndInverse():Void {
        trace("测试矩阵行列式和逆矩阵...");

        // 2x2 矩阵
        var A:AdvancedMatrix = new AdvancedMatrix([4, 7, 2, 6]).init(2, 2);
        var det:Number = A.determinant();
        assert(det == 10, "行列式计算错误");

        var A_inv:AdvancedMatrix = A.inverse();
        // 逆矩阵应为 (1/det) * [[6, -7], [-2, 4]]
        assert(Math.abs(A_inv.getElement(0, 0) - 0.6) < 1e-6, "逆矩阵元素 [0,0] 错误");
        assert(Math.abs(A_inv.getElement(0, 1) - (-0.7)) < 1e-6, "逆矩阵元素 [0,1] 错误");
        assert(Math.abs(A_inv.getElement(1, 0) - (-0.2)) < 1e-6, "逆矩阵元素 [1,0] 错误");
        assert(Math.abs(A_inv.getElement(1, 1) - 0.4) < 1e-6, "逆矩阵元素 [1,1] 错误");

        // 3x3 矩阵
        A = new AdvancedMatrix([1, 2, 3,
            0, 1, 4,
            5, 6, 0]).init(3, 3);
        det = A.determinant();
        assert(det == 1, "3x3 行列式计算错误");

        A_inv = A.inverse();
        // 逆矩阵应为:
        // [-24, 18, 5]
        // [20, -15, -4]
        // [-5, 4, 1]
        assert(Math.abs(A_inv.getElement(0, 0) - (-24)) < 1e-6, "3x3 逆矩阵元素 [0,0] 错误");
        assert(Math.abs(A_inv.getElement(0, 1) - 18) < 1e-6, "3x3 逆矩阵元素 [0,1] 错误");
        assert(Math.abs(A_inv.getElement(0, 2) - 5) < 1e-6, "3x3 逆矩阵元素 [0,2] 错误");
        assert(Math.abs(A_inv.getElement(1, 0) - 20) < 1e-6, "3x3 逆矩阵元素 [1,0] 错误");
        assert(Math.abs(A_inv.getElement(1, 1) - (-15)) < 1e-6, "3x3 逆矩阵元素 [1,1] 错误");
        assert(Math.abs(A_inv.getElement(1, 2) - (-4)) < 1e-6, "3x3 逆矩阵元素 [1,2] 错误");
        assert(Math.abs(A_inv.getElement(2, 0) - (-5)) < 1e-6, "3x3 逆矩阵元素 [2,0] 错误");
        assert(Math.abs(A_inv.getElement(2, 1) - 4) < 1e-6, "3x3 逆矩阵元素 [2,1] 错误");
        assert(Math.abs(A_inv.getElement(2, 2) - 1) < 1e-6, "3x3 逆矩阵元素 [2,2] 错误");

        trace("矩阵行列式和逆矩阵测试通过。");
    }

    /**
     * 测试矩阵归一化
     */
    private function testNormalization():Void {
        trace("测试矩阵归一化...");

        var A:AdvancedMatrix = new AdvancedMatrix([2, 4, 6, 8]).init(2, 2);
        var B:AdvancedMatrix = new AdvancedMatrix([0, 0, 0, 0]).init(2, 2);

        // 使用 normalize 方法
        var C:AdvancedMatrix = A.normalize();
        // 归一化: (x - min) / (max - min) = (x - 2) / 6
        // [0, (4-2)/6=0.333333..., (6-2)/6=0.666666..., 1]
        assert(Math.abs(C.getElement(0, 0) - 0) < 1e-6, "归一化元素 [0,0] 错误");
        assert(Math.abs(C.getElement(0, 1) - (4 - 2) / 6) < 1e-6, "归一化元素 [0,1] 错误");
        assert(Math.abs(C.getElement(1, 1) - 1) < 1e-6, "归一化元素 [1,1] 错误");

        // 使用 normalizeRows 方法
        A = new AdvancedMatrix([1, 2, 3, 4]).init(2, 2);
        A.normalizeRows(null);
        // 每行之和: [3, 7]
        // 归一化后: [1/3, 2/3, 3/7, 4/7]
        assert(Math.abs(A.getElement(0, 0) - (1 / 3)) < 1e-6, "行归一化元素 [0,0] 错误");
        assert(Math.abs(A.getElement(0, 1) - (2 / 3)) < 1e-6, "行归一化元素 [0,1] 错误");
        assert(Math.abs(A.getElement(1, 0) - (3 / 7)) < 1e-6, "行归一化元素 [1,0] 错误");
        assert(Math.abs(A.getElement(1, 1) - (4 / 7)) < 1e-6, "行归一化元素 [1,1] 错误");

        // 使用 normalizeRows 方法并指定结果矩阵
        A = new AdvancedMatrix([2, 4, 6, 8]).init(2, 2);
        A.normalizeRows(B);
        // 每行之和: [6, 14]
        // 归一化后: [2/6=0.333333..., 4/6=0.666666..., 6/14≈0.428571, 8/14≈0.571428]
        assert(Math.abs(B.getElement(0, 0) - (2 / 6)) < 1e-6, "指定结果行归一化元素 [0,0] 错误");
        assert(Math.abs(B.getElement(0, 1) - (4 / 6)) < 1e-6, "指定结果行归一化元素 [0,1] 错误");
        assert(Math.abs(B.getElement(1, 0) - (6 / 14)) < 1e-6, "指定结果行归一化元素 [1,0] 错误");
        assert(Math.abs(B.getElement(1, 1) - (8 / 14)) < 1e-6, "指定结果行归一化元素 [1,1] 错误");

        trace("矩阵归一化测试通过。");
    }

    /**
     * 测试应用激活函数
     */
    private function testApplyActivation():Void {
        trace("测试应用激活函数...");

        var A:AdvancedMatrix = new AdvancedMatrix([-1, 0, 1, 2]).init(2, 2);
        var B:AdvancedMatrix = new AdvancedMatrix([0, 0, 0, 0]).init(2, 2);

        // 测试 sigmoid
        var C:AdvancedMatrix = A.applyActivation("sigmoid", null);
        assert(Math.abs(C.getElement(0, 0) - 0.26894142137) < 1e-6, "Sigmoid 元素 [0,0] 错误");
        assert(Math.abs(C.getElement(1, 1) - 0.8807970779778823) < 1e-6, "Sigmoid 元素 [1,1] 错误");

        // 测试 ReLU
        C = A.applyActivation("relu", null);
        assert(C.getElement(0, 0) == 0, "ReLU 元素 [0,0] 错误");
        assert(C.getElement(1, 1) == 2, "ReLU 元素 [1,1] 错误");

        // 测试 tanh
        A = new AdvancedMatrix([-1, 0, 1, 2]).init(2, 2);
        C = A.applyActivation("tanh", null);
        assert(Math.abs(C.getElement(0, 0) - (-0.7615941559557649)) < 1e-6, "tanh 元素 [0,0] 错误");
        assert(Math.abs(C.getElement(1, 1) - 0.9640275800758169) < 1e-6, "tanh 元素 [1,1] 错误");

        // 使用 applyActivation 方法并指定结果矩阵
        A = new AdvancedMatrix([1, 2, 3, 4]).init(2, 2);
        A.applyActivation("relu", B);
        assert(B.getElement(0, 0) == 1, "指定结果 ReLU 元素 [0,0] 错误");
        assert(B.getElement(1, 1) == 4, "指定结果 ReLU 元素 [1,1] 错误");

        trace("应用激活函数测试通过。");
    }

    /**
     * 测试矩阵卷积
     */
    private function testConvolution():Void {
        trace("测试矩阵卷积...");

        // 使用 3x3 图像和 3x3 卷积核
        var image:AdvancedMatrix = new AdvancedMatrix([1, 2, 3,
            4, 5, 6,
            7, 8, 9]).init(3, 3);
        var kernel:AdvancedMatrix = new AdvancedMatrix([0, 1, 0,
            1, -4, 1,
            0, 1, 0]).init(3, 3);

        // 设置 padding=0，stride=1
        var convResult:AdvancedMatrix = image.convolve(kernel, 0, 1);

        // 期望结果为 [0]
        assert(convResult.getRows() == 1, "卷积结果行数错误");
        assert(convResult.getCols() == 1, "卷积结果列数错误");
        assert(Math.abs(convResult.getElement(0, 0) - 0) < 1e-6, "卷积元素 [0,0] 应为 0");

        trace("矩阵卷积测试通过。");
    }

    /**
     * 测试仿射变换（旋转、缩放、平移）
     */
    private function testTransformations():Void {
        trace("测试仿射变换...");

        // 创建一个简单的图像矩阵
        var image:AdvancedMatrix = new AdvancedMatrix([1, 2,
            3, 4]).init(2, 2);

        // 旋转 90 度（逆时针）
        var rotation:AdvancedMatrix = AdvancedMatrix.rotationMatrix(90);
        var rotatedImage:AdvancedMatrix = image.applyTransformation(rotation, null);

        // 期望旋转后的图像为:
        // [ [2,4],
        //   [1,3] ]
        assert(rotatedImage.getRows() == 2, "旋转后图像行数错误");
        assert(rotatedImage.getCols() == 2, "旋转后图像列数错误");
        assert(Math.abs(rotatedImage.getElement(0, 0) - 2) < 1e-6, "旋转元素 [0,0] 错误");
        assert(Math.abs(rotatedImage.getElement(0, 1) - 4) < 1e-6, "旋转元素 [0,1] 错误");
        assert(Math.abs(rotatedImage.getElement(1, 0) - 1) < 1e-6, "旋转元素 [1,0] 错误");
        assert(Math.abs(rotatedImage.getElement(1, 1) - 3) < 1e-6, "旋转元素 [1,1] 错误");

        // 缩放 2x
        var scaling:AdvancedMatrix = AdvancedMatrix.scalingMatrix(2, 2);
        var scaledImage:AdvancedMatrix = image.applyTransformation(scaling, null);

        // 期望缩放后的图像为:
        // 使用最近邻插值，输出尺寸与输入相同
        // [1,4]
        // [3,0]
        assert(scaledImage.getRows() == 2, "缩放后图像行数错误");
        assert(scaledImage.getCols() == 2, "缩放后图像列数错误");
        assert(Math.abs(scaledImage.getElement(0, 0) - 1) < 1e-6, "缩放元素 [0,0] 错误");
        assert(Math.abs(scaledImage.getElement(0, 1) - 4) < 1e-6, "缩放元素 [0,1] 错误");
        assert(Math.abs(scaledImage.getElement(1, 0) - 3) < 1e-6, "缩放元素 [1,0] 错误");
        assert(Math.abs(scaledImage.getElement(1, 1) - 0) < 1e-6, "缩放元素 [1,1] 错误");

        // 平移 (1, 1)
        var translation:AdvancedMatrix = AdvancedMatrix.translationMatrix(1, 1);
        var translatedImage:AdvancedMatrix = image.applyTransformation(translation, null);

        // 期望平移后的图像为:
        // 使用最近邻插值，输出尺寸与输入相同
        // [0, 0]
        // [2, 4]
        assert(translatedImage.getRows() == 2, "平移后图像行数错误");
        assert(translatedImage.getCols() == 2, "平移后图像列数错误");
        assert(Math.abs(translatedImage.getElement(0, 0) - 0) < 1e-6, "平移元素 [0,0] 错误");
        assert(Math.abs(translatedImage.getElement(0, 1) - 0) < 1e-6, "平移元素 [0,1] 错误");
        assert(Math.abs(translatedImage.getElement(1, 0) - 2) < 1e-6, "平移元素 [1,0] 错误");
        assert(Math.abs(translatedImage.getElement(1, 1) - 4) < 1e-6, "平移元素 [1,1] 错误");

        trace("仿射变换测试通过。");
    }

    /**
     * 测试均方误差和其导数
     */
    private function testMeanSquaredError():Void {
        trace("测试均方误差和其导数...");

        var output:AdvancedMatrix = new AdvancedMatrix([1, 2, 3, 4]).init(2, 2);
        var target:AdvancedMatrix = new AdvancedMatrix([2, 2, 2, 2]).init(2, 2);

        // 计算均方误差
        var mse:Number = AdvancedMatrix.meanSquaredError(output, target);
        // MSE = ((1-2)^2 + (2-2)^2 + (3-2)^2 + (4-2)^2) / 4 = (1 + 0 + 1 + 4) / 4 = 6 / 4 = 1.5
        assert(Math.abs(mse - 1.5) < 1e-6, "均方误差计算错误");

        // 计算均方误差的导数
        var derivative:AdvancedMatrix = AdvancedMatrix.meanSquaredErrorDerivative(output, target, null);
        // 导数 = 2 * (output - target) / 4 = [2*(1-2)/4, 2*(2-2)/4, 2*(3-2)/4, 2*(4-2)/4] = [-0.5, 0, 0.5, 1]
        assert(Math.abs(derivative.getElement(0, 0) - (-0.5)) < 1e-6, "MSE 导数元素 [0,0] 错误");
        assert(Math.abs(derivative.getElement(0, 1) - 0) < 1e-6, "MSE 导数元素 [0,1] 错误");
        assert(Math.abs(derivative.getElement(1, 0) - 0.5) < 1e-6, "MSE 导数元素 [1,0] 错误");
        assert(Math.abs(derivative.getElement(1, 1) - 1) < 1e-6, "MSE 导数元素 [1,1] 错误");

        trace("均方误差和其导数测试通过。");
    }

    /**
     * 测试权重更新
     */
    private function testUpdateWeights():Void {
        trace("测试权重更新...");

        var weights:AdvancedMatrix = new AdvancedMatrix([1, 2, 3, 4]).init(2, 2);
        var gradients:AdvancedMatrix = new AdvancedMatrix([0.1, 0.2, 0.3, 0.4]).init(2, 2);
        var learningRate:Number = 0.5;

        // 使用 updateWeights 方法
        var updatedWeights:AdvancedMatrix = weights.updateWeights(gradients, learningRate, null);
        // 更新后 weights = weights - 0.5 * gradients = [1 - 0.05, 2 - 0.1, 3 - 0.15, 4 - 0.2] = [0.95, 1.9, 2.85, 3.8]
        assert(Math.abs(updatedWeights.getElement(0, 0) - 0.95) < 1e-6, "权重更新元素 [0,0] 错误");
        assert(Math.abs(updatedWeights.getElement(1, 1) - 3.8) < 1e-6, "权重更新元素 [1,1] 错误");

        // 使用 updateWeights 方法并指定结果矩阵
        var C:AdvancedMatrix = new AdvancedMatrix([0, 0, 0, 0]).init(2, 2);
        weights = new AdvancedMatrix([1, 2, 3, 4]).init(2, 2); // 重置 weights
        weights.updateWeights(gradients, learningRate, C);
        assert(Math.abs(C.getElement(0, 0) - 0.95) < 1e-6, "指定结果权重更新元素 [0,0] 错误");
        assert(Math.abs(C.getElement(1, 1) - 3.8) < 1e-6, "指定结果权重更新元素 [1,1] 错误");

        trace("权重更新测试通过。");
    }

    /**
     * 测试矩阵的收敛判断
     */
    private function testHasConverged():Void {
        trace("测试矩阵收敛判断...");

        var A:AdvancedMatrix = new AdvancedMatrix([1, 2, 3, 4]).init(2, 2);
        // 调整 B 的第一个元素，使其与 A 的差异为 0.1 > 0.001
        var B:AdvancedMatrix = new AdvancedMatrix([1.1, 2, 3, 4]).init(2, 2);
        var threshold:Number = 0.001;

        // A 与 B 的差异 = 0.1 > 0.001 => 应未收敛
        var converged:Boolean = A.hasConverged(B, threshold);
        assert(converged == false, "收敛判断错误：应未收敛");

        // 再定义一个 C，和 B 相同 => 应收敛
        var C:AdvancedMatrix = new AdvancedMatrix([1.1, 2, 3, 4]).init(2, 2);
        var converged2:Boolean = B.hasConverged(C, threshold);
        assert(converged2 == true, "收敛判断错误：应已收敛");

        trace("矩阵收敛判断测试通过。");
    }

    /**
     * 性能测试部分
     */
    private function testPerformance():Void {
        trace("开始性能测试...");

        var size:Number = 500; // 大尺寸矩阵
        var dataA:Array = [];
        var dataB:Array = [];
        for (var i:Number = 0; i < size * size; i++) {
            dataA.push(Math.random());
            dataB.push(Math.random());
        }
        var A:AdvancedMatrix = new AdvancedMatrix(dataA).init(size, size);
        var B:AdvancedMatrix = new AdvancedMatrix(dataB).init(size, size);
        var C:AdvancedMatrix = new AdvancedMatrix(new Array(size * size)).init(size, size);

        // 测试加法
        var startTime:Number = getTimer();
        A.add(B, null);
        var endTime:Number = getTimer();
        trace("加法耗时: " + (endTime - startTime) + " 毫秒");

        // 测试原地加法
        A.addInPlace(B);
        trace("原地加法完成。");

        // 测试乘法
        startTime = getTimer();
        A.multiply(B, null);
        endTime = getTimer();
        trace("乘法耗时: " + (endTime - startTime) + " 毫秒");

        // 测试转置
        startTime = getTimer();
        A.transpose(null);
        endTime = getTimer();
        trace("转置耗时: " + (endTime - startTime) + " 毫秒");

        // 测试逆矩阵（较小矩阵）
        var smallA:AdvancedMatrix = new AdvancedMatrix([4, 7, 2, 6]).init(2, 2);
        startTime = getTimer();
        var smallInv:AdvancedMatrix = smallA.inverse();
        endTime = getTimer();
        trace("逆矩阵（2x2）耗时: " + (endTime - startTime) + " 毫秒");

        trace("性能测试完成。");
    }
}

