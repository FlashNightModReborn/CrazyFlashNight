

/**
 * AdvancedMatrix 类
 * 提供各种高级矩阵操作，包括加法、减法、乘法、转置、逆矩阵、卷积、仿射变换等。
 */
class org.flashNight.naki.DataStructures.AdvancedMatrix {


    private var data:Array; // 用于存储矩阵数据的一维数组
    private var rows:Number; // 矩阵的行数
    private var cols:Number; // 矩阵的列数

    /**
     * 构造函数
     * @param inputData 一维数组
     */
    public function AdvancedMatrix(inputData:Array) {
        this.data = inputData.concat(); // 创建数组的副本，防止外部修改
        this.rows = 0;
        this.cols = 0;
    }

    /**
     * 初始化矩阵维度
     * @param numRows 行数
     * @param numCols 列数
     * @return 当前 AdvancedMatrix 实例（支持链式调用）
     */
    public function init(numRows:Number, numCols:Number):AdvancedMatrix {
        if (this.data.length != numRows * numCols) {
            throw new Error("init 错误: 输入数据长度(" + this.data.length + ")与指定矩阵尺寸(" + numRows + "x" + numCols + ")不匹配.\n" + "期望: " + (numRows * numCols) + ", 实际: " + this.data.length);
        }
        this.rows = numRows;
        this.cols = numCols;
        return this;
    }

    /**
     * 通过传入新数组重置矩阵数据
     */
    public function reset(inputData:Array):AdvancedMatrix {
        this.data = inputData.concat(); // 创建新的数组副本
        this.rows = 0;
        this.cols = 0;
        return this;
    }

    /**
     * 从多维数组初始化矩阵
     * @param multiArray 二维数组, 外层为行, 内层为列
     */
    public function initFromMultiDimensionalArray(multiArray:Array):AdvancedMatrix {
        var newData:Array = [];
        var numRows:Number = multiArray.length;
        var numCols:Number = multiArray[0].length;

        for (var i:Number = 0; i < numRows; i++) {
            if (multiArray[i].length != numCols) {
                throw new Error("initFromMultiDimensionalArray 错误：每一行的列数必须相同。");
            }
            for (var j:Number = 0; j < numCols; j++) {
                newData.push(multiArray[i][j]);
            }
        }

        this.data = newData;
        this.rows = numRows;
        this.cols = numCols;
        return this;
    }

    /**
     * 获取矩阵中特定位置的元素
     */
    public function getElement(row:Number, col:Number):Number {
        if (row < 0 || row >= this.rows) {
            throw new Error("getElement 错误：行索引 " + row + " 超出范围(0 ~ " + (this.rows - 1) + ").");
        }
        if (col < 0 || col >= this.cols) {
            throw new Error("getElement 错误：列索引 " + col + " 超出范围(0 ~ " + (this.cols - 1) + ").");
        }
        return this.data[row * this.cols + col];
    }

    /**
     * 设置矩阵中特定位置的元素
     */
    public function setElement(row:Number, col:Number, value:Number):Void {
        if (row < 0 || row >= this.rows) {
            throw new Error("setElement 错误：行索引 " + row + " 超出范围(0 ~ " + (this.rows - 1) + ").");
        }
        if (col < 0 || col >= this.cols) {
            throw new Error("setElement 错误：列索引 " + col + " 超出范围(0 ~ " + (this.cols - 1) + ").");
        }
        this.data[row * this.cols + col] = value;
    }

    /** 获取矩阵的行数 */
    public function getRows():Number {
        return this.rows;
    }

    /** 获取矩阵的列数 */
    public function getCols():Number {
        return this.cols;
    }

    // -------------------- 原地操作方法 --------------------

    /** 原地矩阵加法 */
    public function addInPlace(matrix:AdvancedMatrix):Void {
        if (this.rows != matrix.getRows() || this.cols != matrix.getCols()) {
            throw new Error("addInPlace 错误：矩阵尺寸不匹配，无法相加。");
        }
        for (var i:Number = 0; i < this.data.length; i++) {
            this.data[i] += matrix.data[i];
        }
    }

    /** 原地矩阵减法 */
    public function subtractInPlace(matrix:AdvancedMatrix):Void {
        if (this.rows != matrix.getRows() || this.cols != matrix.getCols()) {
            throw new Error("subtractInPlace 错误：矩阵尺寸不匹配，无法相减。");
        }
        for (var i:Number = 0; i < this.data.length; i++) {
            this.data[i] -= matrix.data[i];
        }
    }

    /** 原地矩阵数乘 */
    public function scalarMultiplyInPlace(scalar:Number):Void {
        for (var i:Number = 0; i < this.data.length; i++) {
            this.data[i] *= scalar;
        }
    }

    /** 原地矩阵元素级乘法（Hadamard 乘法） */
    public function hadamardMultiplyInPlace(matrix:AdvancedMatrix):Void {
        if (this.rows != matrix.getRows() || this.cols != matrix.getCols()) {
            throw new Error("hadamardMultiplyInPlace 错误：矩阵尺寸不匹配，无法逐元素相乘。");
        }
        for (var i:Number = 0; i < this.data.length; i++) {
            this.data[i] *= matrix.data[i];
        }
    }

    /** 将另一个矩阵的值赋给当前矩阵 */
    public function assign(source:AdvancedMatrix):Void {
        if (this.rows != source.getRows() || this.cols != source.getCols()) {
            throw new Error("assign 错误：矩阵尺寸不匹配。");
        }
        for (var i:Number = 0; i < this.data.length; i++) {
            this.data[i] = source.data[i];
        }
    }

    // -------------------- 非原地矩阵运算 --------------------

    /** 矩阵加法 */
    public function add(matrix:AdvancedMatrix, result:AdvancedMatrix):AdvancedMatrix {
        var hasResult:Boolean = (arguments.length >= 2) && (result != undefined);
        if (this.rows != matrix.getRows() || this.cols != matrix.getCols()) {
            throw new Error("add 错误：矩阵尺寸不匹配。");
        }
        if (hasResult) {
            if (result.getRows() != this.rows || result.getCols() != this.cols) {
                throw new Error("add 错误：结果矩阵尺寸不匹配。");
            }
        } else {
            result = new AdvancedMatrix(new Array(this.rows * this.cols));
            result.init(this.rows, this.cols);
        }

        for (var i:Number = 0; i < this.data.length; i++) {
            result.data[i] = this.data[i] + matrix.data[i];
        }
        return result;
    }

    /** 矩阵减法 */
    public function subtract(matrix:AdvancedMatrix, result:AdvancedMatrix):AdvancedMatrix {
        var hasResult:Boolean = (arguments.length >= 2) && (result != undefined);
        if (this.rows != matrix.getRows() || this.cols != matrix.getCols()) {
            throw new Error("subtract 错误：矩阵尺寸不匹配。");
        }
        if (hasResult) {
            if (result.getRows() != this.rows || result.getCols() != this.cols) {
                throw new Error("subtract 错误：结果矩阵尺寸不匹配。");
            }
        } else {
            result = new AdvancedMatrix(new Array(this.rows * this.cols));
            result.init(this.rows, this.cols);
        }

        for (var i:Number = 0; i < this.data.length; i++) {
            result.data[i] = this.data[i] - matrix.data[i];
        }
        return result;
    }

    /** 矩阵数乘 */
    public function scalarMultiply(scalar:Number, result:AdvancedMatrix):AdvancedMatrix {
        var hasResult:Boolean = (arguments.length >= 2) && (result != undefined);
        if (hasResult) {
            if (result.getRows() != this.rows || result.getCols() != this.cols) {
                throw new Error("scalarMultiply 错误：结果矩阵尺寸不匹配。");
            }
        } else {
            result = new AdvancedMatrix(new Array(this.rows * this.cols));
            result.init(this.rows, this.cols);
        }

        for (var i:Number = 0; i < this.data.length; i++) {
            result.data[i] = this.data[i] * scalar;
        }
        return result;
    }

    /** Hadamard 乘法（逐元素乘法） */
    public function hadamardMultiply(matrix:AdvancedMatrix, result:AdvancedMatrix):AdvancedMatrix {
        var hasResult:Boolean = (arguments.length >= 2) && (result != undefined);
        if (this.rows != matrix.getRows() || this.cols != matrix.getCols()) {
            throw new Error("hadamardMultiply 错误：矩阵尺寸不匹配。");
        }
        if (hasResult) {
            if (result.getRows() != this.rows || result.getCols() != this.cols) {
                throw new Error("hadamardMultiply 错误：结果矩阵尺寸不匹配。");
            }
        } else {
            result = new AdvancedMatrix(new Array(this.rows * this.cols));
            result.init(this.rows, this.cols);
        }

        for (var i:Number = 0; i < this.data.length; i++) {
            result.data[i] = this.data[i] * matrix.data[i];
        }
        return result;
    }

    /** 矩阵乘法 (自动判断是否使用 Strassen) */
    public function multiply(matrix:AdvancedMatrix, result:AdvancedMatrix):AdvancedMatrix {
        if (this.cols != matrix.getRows()) {
            throw new Error("multiply 错误：第一个矩阵的列数需等于第二个矩阵的行数。");
        }

        var hasResult:Boolean = (arguments.length >= 2) && (result != undefined);
        if (hasResult) {
            if (result.getRows() != this.rows || result.getCols() != matrix.getCols()) {
                throw new Error("multiply 错误：结果矩阵尺寸不匹配。");
            }
            // 先清零
            for (var i:Number = 0; i < result.data.length; i++) {
                result.data[i] = 0;
            }
        } else {
            // 如果不传 result，先判断维度，决定是直接乘法还是 Strassen
            if (this.rows != this.cols || matrix.getRows() != matrix.getCols() || this.rows != matrix.getRows() || this.rows <= 64) {
                // 小尺寸或非方阵 => 直接乘法
                return multiplyDirect(matrix, null);
            }
            // 如果是大方阵 => Strassen
            var size:Number = this.rows;
            if (!isPowerOfTwo(size)) {
                var newSize:Number = nextPowerOfTwo(size);
                var A_padded:AdvancedMatrix = this.padMatrix(newSize);
                var B_padded:AdvancedMatrix = matrix.padMatrix(newSize);
                var C_padded:AdvancedMatrix = A_padded.strassenMultiply(B_padded, null);
                return C_padded.unpadMatrix(this.rows, matrix.getCols(), null);
            } else {
                return strassenMultiply(matrix, null);
            }
        }

        // 判断是否直接乘法或 Strassen
        if (this.rows != this.cols || matrix.getRows() != matrix.getCols() || this.rows != matrix.getRows() || this.rows <= 64) {
            return multiplyDirect(matrix, result);
        }

        var size2:Number = this.rows;
        if (!isPowerOfTwo(size2)) {
            var newSize2:Number = nextPowerOfTwo(size2);
            var A_padded2:AdvancedMatrix = this.padMatrix(newSize2);
            var B_padded2:AdvancedMatrix = matrix.padMatrix(newSize2);
            var C_padded2:AdvancedMatrix = A_padded2.strassenMultiply(B_padded2, null);
            return C_padded2.unpadMatrix(this.rows, matrix.getCols(), result);
        } else {
            return strassenMultiply(matrix, result);
        }
    }

    /** 标准直接矩阵乘法 */
    private function multiplyDirect(matrix:AdvancedMatrix, result:AdvancedMatrix):AdvancedMatrix {
        var r:Number;
        var c:Number;
        var k:Number;

        if (result == undefined) {
            result = new AdvancedMatrix(new Array(this.rows * matrix.getCols()));
            result.init(this.rows, matrix.getCols());
            // 初始化为0
            for (var i:Number = 0; i < result.data.length; i++) {
                result.data[i] = 0;
            }
        } else {
            if (result.getRows() != this.rows || result.getCols() != matrix.getCols()) {
                throw new Error("multiplyDirect 错误：结果矩阵尺寸不匹配。");
            }
            for (k = 0; k < result.data.length; k++) {
                result.data[k] = 0;
            }
        }

        for (r = 0; r < this.rows; r++) {
            for (c = 0; c < matrix.getCols(); c++) {
                var sum:Number = 0;
                for (k = 0; k < this.cols; k++) {
                    sum += this.data[r * this.cols + k] * matrix.data[k * matrix.getCols() + c];
                }
                result.data[r * matrix.getCols() + c] = sum;
            }
        }
        return result;
    }

    /** Strassen 乘法 (包装函数) */
    private function strassenMultiply(matrix:AdvancedMatrix, result:AdvancedMatrix):AdvancedMatrix {
        var n:Number = this.rows;
        if (n <= 64) {
            return this.multiplyDirect(matrix, result);
        }

        var newSize:Number = Math.ceil(n / 2) * 2;
        // 分割
        var A11:AdvancedMatrix = this.getSubMatrix(0, 0, Math.floor(newSize / 2), Math.floor(newSize / 2), null);
        var A12:AdvancedMatrix = this.getSubMatrix(0, Math.floor(newSize / 2), Math.floor(newSize / 2), Math.floor(newSize / 2), null);
        var A21:AdvancedMatrix = this.getSubMatrix(Math.floor(newSize / 2), 0, Math.floor(newSize / 2), Math.floor(newSize / 2), null);
        var A22:AdvancedMatrix = this.getSubMatrix(Math.floor(newSize / 2), Math.floor(newSize / 2), Math.floor(newSize / 2), Math.floor(newSize / 2), null);

        var B11:AdvancedMatrix = matrix.getSubMatrix(0, 0, Math.floor(newSize / 2), Math.floor(newSize / 2), null);
        var B12:AdvancedMatrix = matrix.getSubMatrix(0, Math.floor(newSize / 2), Math.floor(newSize / 2), Math.floor(newSize / 2), null);
        var B21:AdvancedMatrix = matrix.getSubMatrix(Math.floor(newSize / 2), 0, Math.floor(newSize / 2), Math.floor(newSize / 2), null);
        var B22:AdvancedMatrix = matrix.getSubMatrix(Math.floor(newSize / 2), Math.floor(newSize / 2), Math.floor(newSize / 2), Math.floor(newSize / 2), null);

        // M1..M7
        var M1:AdvancedMatrix = (A11.add(A22, null)).strassenMultiply(B11.add(B22, null), null);
        var M2:AdvancedMatrix = (A21.add(A22, null)).strassenMultiply(B11, null);
        var M3:AdvancedMatrix = A11.strassenMultiply(B12.subtract(B22, null), null);
        var M4:AdvancedMatrix = A22.strassenMultiply(B21.subtract(B11, null), null);
        var M5:AdvancedMatrix = (A11.add(A12, null)).strassenMultiply(B22, null);
        var M6:AdvancedMatrix = (A21.subtract(A11, null)).strassenMultiply(B11.add(B12, null), null);
        var M7:AdvancedMatrix = (A12.subtract(A22, null)).strassenMultiply(B21.add(B22, null), null);

        var C11:AdvancedMatrix = M1.add(M4, null).subtract(M5, null).add(M7, null);
        var C12:AdvancedMatrix = M3.add(M5, null);
        var C21:AdvancedMatrix = M2.add(M4, null);
        var C22:AdvancedMatrix = M1.subtract(M2, null).add(M3, null).add(M6, null);

        if (result == undefined) {
            return C11.combineSubMatrices(C12, C21, C22, null);
        } else {
            C11.combineSubMatrices(C12, C21, C22, result);
            return result;
        }
    }

    /** 合并子矩阵 */
    private function combineSubMatrices(C12:AdvancedMatrix, C21:AdvancedMatrix, C22:AdvancedMatrix, result:AdvancedMatrix):AdvancedMatrix {
        var C11:AdvancedMatrix = this; // 当前对象就是C11
        var newRows:Number = C11.getRows() + C21.getRows();
        var newCols:Number = C11.getCols() + C12.getCols();

        if (result == undefined) {
            result = new AdvancedMatrix(new Array(newRows * newCols));
            result.init(newRows, newCols);
            // 初始化为0
            for (var m:Number = 0; m < result.data.length; m++) {
                result.data[m] = 0;
            }
        } else {
            if (result.getRows() != newRows || result.getCols() != newCols) {
                throw new Error("combineSubMatrices 错误：结果矩阵尺寸不匹配。");
            }
        }

        for (var i:Number = 0; i < C11.getRows(); i++) {
            for (var j:Number = 0; j < C11.getCols(); j++) {
                // C11
                result.data[i * newCols + j] = C11.getElement(i, j);
                // C12
                result.data[i * newCols + (j + C11.getCols())] = C12.getElement(i, j);
                // C21
                result.data[(i + C11.getRows()) * newCols + j] = C21.getElement(i, j);
                // C22
                result.data[(i + C11.getRows()) * newCols + (j + C11.getCols())] = C22.getElement(i, j);
            }
        }
        return result;
    }

    /** 判断是否是 2 的幂 */
    private function isPowerOfTwo(num:Number):Boolean {
        return (num & (num - 1)) == 0;
    }

    /** 计算下一个 2 的幂 */
    private function nextPowerOfTwo(n:Number):Number {
        var power:Number = 1;
        while (power < n) {
            power *= 2;
        }
        return power;
    }

    // -------------------- 其他重要方法 --------------------

    /** 矩阵转置 */
    public function transpose(result:AdvancedMatrix):AdvancedMatrix {
        var hasResult:Boolean = (arguments.length >= 1) && (result != undefined);
        if (hasResult) {
            if (result.getRows() != this.cols || result.getCols() != this.rows) {
                throw new Error("transpose 错误：结果矩阵尺寸不匹配。");
            }
        } else {
            result = new AdvancedMatrix(new Array(this.cols * this.rows));
            result.init(this.cols, this.rows);
        }

        for (var r:Number = 0; r < this.rows; r++) {
            for (var c:Number = 0; c < this.cols; c++) {
                result.data[c * this.rows + r] = this.data[r * this.cols + c];
            }
        }
        return result;
    }

    /** LU 分解 (用于行列式和逆矩阵) */
    private function luDecomposition():Object {
        if (this.rows != this.cols) {
            throw new Error("luDecomposition 错误：仅适用于方阵。");
        }

        var n:Number = this.rows;
        var A:Array = this.data.concat(); // 拷贝一份做分解
        var L:Array = [];
        var U:Array = [];
        var P:Array = [];
        var pivot:Number;
        var rowSwapCount:Number = 0;

        // 初始化 P
        for (var i:Number = 0; i < n; i++) {
            P[i] = i;
        }

        for (var k:Number = 0; k < n; k++) {
            // 选主元(最大绝对值)
            pivot = k;
            var maxVal:Number = Math.abs(A[k * n + k]);
            for (var i2:Number = k + 1; i2 < n; i2++) {
                var val:Number = Math.abs(A[i2 * n + k]);
                if (val > maxVal) {
                    maxVal = val;
                    pivot = i2;
                }
            }
            if (maxVal == 0) {
                throw new Error("LU 分解错误：矩阵奇异，无法分解。");
            }
            // 若 pivot != k, 则交换行
            if (pivot != k) {
                for (var col:Number = 0; col < n; col++) {
                    var temp:Number = A[k * n + col];
                    A[k * n + col] = A[pivot * n + col];
                    A[pivot * n + col] = temp;
                }
                // 更新 P
                var tempP:Number = P[k];
                P[k] = P[pivot];
                P[pivot] = tempP;
                rowSwapCount++;
            }
            // 消去
            for (var r2:Number = k + 1; r2 < n; r2++) {
                A[r2 * n + k] /= A[k * n + k];
                for (var c2:Number = k + 1; c2 < n; c2++) {
                    A[r2 * n + c2] -= A[r2 * n + k] * A[k * n + c2];
                }
            }
        }

        // 提取 L & U
        for (var r3:Number = 0; r3 < n; r3++) {
            L[r3] = [];
            U[r3] = [];
            for (var c3:Number = 0; c3 < n; c3++) {
                if (r3 > c3) {
                    L[r3][c3] = A[r3 * n + c3];
                    U[r3][c3] = 0;
                } else if (r3 == c3) {
                    L[r3][c3] = 1;
                    U[r3][c3] = A[r3 * n + c3];
                } else {
                    L[r3][c3] = 0;
                    U[r3][c3] = A[r3 * n + c3];
                }
            }
        }

        return {L: L,
                U: U,
                P: P,
                rowSwapCount: rowSwapCount};
    }

    /** 行列式 */
    public function determinant():Number {
        if (this.rows != this.cols) {
            throw new Error("determinant 错误：仅适用于方阵。");
        }
        var lu:Object = this.luDecomposition();
        var L:Array = lu.L;
        var U:Array = lu.U;
        var P:Array = lu.P;
        var n:Number = this.rows;
        var detVal:Number = 1;
        for (var i:Number = 0; i < n; i++) {
            detVal *= U[i][i];
        }
        // 考虑行交换
        if (lu.rowSwapCount % 2 != 0) {
            detVal = -detVal;
        }
        // 为防止浮点误差太大，适度四舍五入
        detVal = Math.round(detVal * 1000000) / 1000000;
        return detVal;
    }

    /** 矩阵求逆 */
    public function inverse():AdvancedMatrix {
        if (this.rows != this.cols) {
            throw new Error("inverse 错误：仅适用于方阵。");
        }

        var n:Number = this.rows;
        var lu:Object = this.luDecomposition();
        var L:Array = lu.L;
        var U:Array = lu.U;
        var P:Array = lu.P;
        var invData:Array = new Array(n * n);

        for (var col:Number = 0; col < n; col++) {
            // 构建 e 向量, 其中 e[P[i]] = 1 表示在 P 后的位置
            var e:Array = [];
            for (var i:Number = 0; i < n; i++) {
                if (P[i] == col) {
                    e[i] = 1;
                } else {
                    e[i] = 0;
                }
            }
            // 前向替代 (Ly = e)
            var y:Array = [];
            for (var r:Number = 0; r < n; r++) {
                var sum:Number = 0;
                for (var c:Number = 0; c < r; c++) {
                    sum += L[r][c] * y[c];
                }
                y[r] = e[r] - sum;
            }
            // 回代 (Ux = y)
            var x:Array = [];
            for (var rr:Number = n - 1; rr >= 0; rr--) {
                var sum2:Number = 0;
                for (var cc:Number = rr + 1; cc < n; cc++) {
                    sum2 += U[rr][cc] * x[cc];
                }
                if (Math.abs(U[rr][rr]) < 1e-14) {
                    throw new Error("inverse 错误：矩阵奇异或接近奇异。");
                }
                x[rr] = (y[rr] - sum2) / U[rr][rr];
            }
            // 写入 invData
            for (var r2:Number = 0; r2 < n; r2++) {
                invData[r2 * n + col] = x[r2];
            }
        }

        return new AdvancedMatrix(invData).init(n, n);
    }

    /**
     * 卷积操作
     */
    public function convolve(kernel:AdvancedMatrix, padding:Number, stride:Number):AdvancedMatrix {
        if (kernel.getRows() % 2 == 0 || kernel.getCols() % 2 == 0) {
            throw new Error("convolve 错误：卷积核维度必须为奇数。");
        }
        var kernelRows:Number = kernel.getRows();
        var kernelCols:Number = kernel.getCols();
        var padRows:Number = padding;
        var padCols:Number = padding;
        var outputRows:Number = Math.floor((this.rows + 2 * padRows - kernelRows) / stride) + 1;
        var outputCols:Number = Math.floor((this.cols + 2 * padCols - kernelCols) / stride) + 1;

        var outputData:Array = new Array(outputRows * outputCols);
        var paddedMatrix:AdvancedMatrix = this.padMatrixForConvolution(padRows, padCols);

        for (var i:Number = 0; i < outputRows; i++) {
            for (var j:Number = 0; j < outputCols; j++) {
                var sumVal:Number = 0;
                for (var m:Number = 0; m < kernelRows; m++) {
                    for (var n:Number = 0; n < kernelCols; n++) {
                        var rowIndex:Number = i * stride + m;
                        var colIndex:Number = j * stride + n;
                        var imageValue:Number = paddedMatrix.getElement(rowIndex, colIndex);
                        var kernelValue:Number = kernel.getElement(kernelRows - 1 - m, kernelCols - 1 - n);
                        sumVal += imageValue * kernelValue;
                    }
                }
                outputData[i * outputCols + j] = sumVal;
            }
        }
        return new AdvancedMatrix(outputData).init(outputRows, outputCols);
    }

    /** 为卷积填充矩阵 */
    private function padMatrixForConvolution(padRows:Number, padCols:Number):AdvancedMatrix {
        var newRows:Number = this.rows + 2 * padRows;
        var newCols:Number = this.cols + 2 * padCols;
        var paddedData:Array = new Array(newRows * newCols);

        for (var i:Number = 0; i < newRows; i++) {
            for (var j:Number = 0; j < newCols; j++) {
                if (i >= padRows && i < padRows + this.rows && j >= padCols && j < padCols + this.cols) {
                    paddedData[i * newCols + j] = this.getElement(i - padRows, j - padCols);
                } else {
                    paddedData[i * newCols + j] = 0;
                }
            }
        }
        return new AdvancedMatrix(paddedData).init(newRows, newCols);
    }

    /**
     * 应用仿射变换
     * 注意：内部会先对 transformationMatrix 求 inverse，然后再乘以目标像素坐标
     */
    public function applyTransformation(transformationMatrix:AdvancedMatrix, result:AdvancedMatrix):AdvancedMatrix {
        if (transformationMatrix.getRows() != 3 || transformationMatrix.getCols() != 3) {
            throw new Error("applyTransformation 错误：变换矩阵必须是 3x3。");
        }
        var inverseTransform:AdvancedMatrix = transformationMatrix.inverse();
        var outputRows:Number = this.rows;
        var outputCols:Number = this.cols;
        var newData:Array = [];

        for (var i:Number = 0; i < outputRows; i++) {
            for (var j:Number = 0; j < outputCols; j++) {
                // 目标坐标
                var destCoord:AdvancedMatrix = new AdvancedMatrix([j, i, 1]).init(3, 1);
                // srcCoord = inverseTransform * destCoord
                var srcCoord:AdvancedMatrix = inverseTransform.multiply(destCoord, null);
                var x:Number = srcCoord.getElement(0, 0);
                var y:Number = srcCoord.getElement(1, 0);

                var x0:Number = Math.round(x);
                var y0:Number = Math.round(y);

                if (x0 >= 0 && x0 < this.cols && y0 >= 0 && y0 < this.rows) {
                    var value:Number = this.getElement(y0, x0);
                    newData.push(value);
                } else {
                    newData.push(0);
                }
            }
        }
        if (result == undefined) {
            result = new AdvancedMatrix(newData).init(outputRows, outputCols);
        } else {
            if (result.getRows() != outputRows || result.getCols() != outputCols) {
                throw new Error("applyTransformation 错误：结果矩阵尺寸不匹配。");
            }
            for (var idx:Number = 0; idx < newData.length; idx++) {
                result.data[idx] = newData[idx];
            }
        }
        return result;
    }

    // -------------------- 静态方法: 生成常用仿射矩阵 --------------------

    /**
     * 生成旋转矩阵（angle>0 => 最终效果顺时针旋转）
     */
    public static function rotationMatrix(angle:Number):AdvancedMatrix {
        var rad:Number = angle * Math.PI / 180;
        var cosA:Number = Math.cos(rad);
        var sinA:Number = Math.sin(rad);

        // 如果希望 angle>0 是顺时针，则此处应把原本 -sinA 改为 +sinA
        // 并把 sinA 行那一行改为 -sinA
        // 这样在 applyTransformation 内部再做 inverse()，就会得到与测试期望一致的效果
        var data:Array = [cosA, sinA, 0,
            -sinA, cosA, 0,
            0, 0, 1];
        return new AdvancedMatrix(data).init(3, 3);
    }

    /** 生成缩放矩阵 */
    public static function scalingMatrix(sx:Number, sy:Number):AdvancedMatrix {
        var data:Array = [sx, 0, 0,
            0, sy, 0,
            0, 0, 1];
        return new AdvancedMatrix(data).init(3, 3);
    }

    /** 生成平移矩阵 */
    public static function translationMatrix(tx:Number, ty:Number):AdvancedMatrix {
        var data:Array = [1, 0, tx,
            0, 1, ty,
            0, 0, 1];
        return new AdvancedMatrix(data).init(3, 3);
    }

    // -------------------- 其他实用方法 --------------------

    /** 矩阵归一化 [0,1] */
    public function normalize():AdvancedMatrix {
        var maxVal:Number = getMax(this.data);
        var minVal:Number = getMin(this.data);
        var range:Number = maxVal - minVal;
        if (range == 0) {
            throw new Error("normalize 错误：矩阵中所有元素相同，无法归一化。");
        }
        var result:Array = new Array(this.rows * this.cols);
        for (var i:Number = 0; i < this.data.length; i++) {
            result[i] = (this.data[i] - minVal) / range;
        }
        return new AdvancedMatrix(result).init(this.rows, this.cols);
    }

    /** 行归一化（每行和=1） */
    public function normalizeRows(result:AdvancedMatrix):AdvancedMatrix {
        var hasResult:Boolean = (arguments.length >= 1) && (result != undefined);
        if (hasResult) {
            if (result.getRows() != this.rows || result.getCols() != this.cols) {
                throw new Error("normalizeRows 错误：结果矩阵尺寸不匹配。");
            }
        } else {
            result = new AdvancedMatrix(new Array(this.rows * this.cols));
            result.init(this.rows, this.cols);
        }
        for (var r:Number = 0; r < this.rows; r++) {
            var rowSum:Number = 0;
            for (var c:Number = 0; c < this.cols; c++) {
                rowSum += this.data[r * this.cols + c];
            }
            if (rowSum == 0) {
                throw new Error("normalizeRows 错误：第 " + r + " 行元素和为0，无法归一化。");
            }
            for (c = 0; c < this.cols; c++) {
                result.data[r * this.cols + c] = this.data[r * this.cols + c] / rowSum;
            }
        }
        return result;
    }

    /** 判断是否收敛 */
    public function hasConverged(previousState:AdvancedMatrix, threshold:Number):Boolean {
        if (this.rows != previousState.rows || this.cols != previousState.cols) {
            throw new Error("hasConverged 错误：矩阵尺寸不匹配。");
        }
        var diff:AdvancedMatrix = this.subtract(previousState, null);
        for (var i:Number = 0; i < diff.data.length; i++) {
            if (Math.abs(diff.data[i]) > threshold) {
                return false;
            }
        }
        return true;
    }

    /** 用特定值填充矩阵(原地) */
    public function fill(value:Number):AdvancedMatrix {
        for (var i:Number = 0; i < this.data.length; i++) {
            this.data[i] = value;
        }
        return this;
    }

    /** 用随机数填充矩阵(原地) */
    public function randomize(min:Number, max:Number):AdvancedMatrix {
        for (var i:Number = 0; i < this.data.length; i++) {
            this.data[i] = Math.random() * (max - min) + min;
        }
        return this;
    }

    /** 去除填充(主要用于 Strassen 或者其他补零后的情况) */
    private function unpadMatrix(originalRows:Number, originalCols:Number, result:AdvancedMatrix):AdvancedMatrix {
        if (result == undefined) {
            result = new AdvancedMatrix(new Array(originalRows * originalCols));
            result.init(originalRows, originalCols);
        } else {
            if (result.getRows() != originalRows || result.getCols() != originalCols) {
                throw new Error("unpadMatrix 错误：结果矩阵维度不匹配。");
            }
        }
        for (var i:Number = 0; i < originalRows; i++) {
            for (var j:Number = 0; j < originalCols; j++) {
                result.data[i * originalCols + j] = this.data[i * this.cols + j];
            }
        }
        return result;
    }

    /** 扩展(填充)到指定大小(方阵)，用于 Strassen */
    private function padMatrix(newSize:Number):AdvancedMatrix {
        var paddedData:Array = [];
        for (var i:Number = 0; i < newSize; i++) {
            for (var j:Number = 0; j < newSize; j++) {
                if (i < this.rows && j < this.cols) {
                    paddedData.push(this.data[i * this.cols + j]);
                } else {
                    paddedData.push(0);
                }
            }
        }
        return new AdvancedMatrix(paddedData).init(newSize, newSize);
    }

    /** 提取子矩阵 */
    public function getSubMatrix(startRow:Number, startCol:Number, numRows:Number, numCols:Number, result:AdvancedMatrix):AdvancedMatrix {
        var hasResult:Boolean = (arguments.length >= 5) && (result != undefined);
        if (hasResult) {
            if (result.getRows() != numRows || result.getCols() != numCols) {
                throw new Error("getSubMatrix 错误：结果矩阵维度不匹配。");
            }
        } else {
            result = new AdvancedMatrix(new Array(numRows * numCols));
            result.init(numRows, numCols);
            // 默认先填充0
            for (var z:Number = 0; z < result.data.length; z++) {
                result.data[z] = 0;
            }
        }
        for (var i:Number = 0; i < numRows; i++) {
            for (var j:Number = 0; j < numCols; j++) {
                var srcRow:Number = startRow + i;
                var srcCol:Number = startCol + j;
                if (srcRow < this.rows && srcCol < this.cols) {
                    result.data[i * numCols + j] = this.data[srcRow * this.cols + srcCol];
                } else {
                    result.data[i * numCols + j] = 0;
                }
            }
        }
        return result;
    }

    /** 克隆到一维数组 */
    public function toArray():Array {
        return this.data.concat();
    }

    /** 克隆矩阵 */
    public function clone():AdvancedMatrix {
        return new AdvancedMatrix(this.data).init(this.rows, this.cols);
    }

    /** 计算方阵的迹(trace) */
    public function trace():Number {
        if (this.rows != this.cols) {
            throw new Error("trace 错误：仅适用于方阵。");
        }
        var sum:Number = 0;
        for (var i:Number = 0; i < this.rows; i++) {
            sum += this.data[i * this.cols + i];
        }
        return sum;
    }

    /** 重写 toString */
    public function toString():String {
        var s:String = "";
        for (var r:Number = 0; r < this.rows; r++) {
            for (var c:Number = 0; c < this.cols; c++) {
                s += this.data[r * this.cols + c] + "\t";
            }
            s += "\n";
        }
        return s;
    }

    /** 打印矩阵（AS2下用 trace） */
    public function printMatrix():Void {
        trace(this.toString());
    }

    /** 获取数组最大值 */
    private function getMax(arr:Array):Number {
        var mx:Number = arr[0];
        for (var i:Number = 1; i < arr.length; i++) {
            if (arr[i] > mx) {
                mx = arr[i];
            }
        }
        return mx;
    }

    /** 获取数组最小值 */
    private function getMin(arr:Array):Number {
        var mn:Number = arr[0];
        for (var i:Number = 1; i < arr.length; i++) {
            if (arr[i] < mn) {
                mn = arr[i];
            }
        }
        return mn;
    }

    // -------------------- 常用的静态方法(损失函数等) --------------------

    /** 应用激活函数: sigmoid、tanh、relu */
    public function applyActivation(functionName:String, result:AdvancedMatrix):AdvancedMatrix {
        var hasResult:Boolean = (arguments.length >= 2) && (result != undefined);
        if (hasResult) {
            if (result.getRows() != this.rows || result.getCols() != this.cols) {
                throw new Error("applyActivation 错误：结果矩阵尺寸不匹配。");
            }
        } else {
            result = new AdvancedMatrix(new Array(this.rows * this.cols));
            result.init(this.rows, this.cols);
        }
        for (var i:Number = 0; i < this.data.length; i++) {
            var value:Number = this.data[i];
            switch (functionName.toLowerCase()) {
                case "sigmoid":
                    result.data[i] = 1 / (1 + Math.exp(-value));
                    break;
                case "tanh":
                    result.data[i] = tanh(value);
                    break;
                case "relu":
                    result.data[i] = (value > 0) ? value : 0;
                    break;
                default:
                    throw new Error("applyActivation 错误：不支持激活函数 '" + functionName + "'.");
            }
        }
        return result;
    }

    private static function tanh(x:Number):Number {
        var ePos:Number = Math.exp(x);
        var eNeg:Number = Math.exp(-x);
        return (ePos - eNeg) / (ePos + eNeg);
    }

    /** 均方误差 (MSE) */
    public static function meanSquaredError(output:AdvancedMatrix, target:AdvancedMatrix):Number {
        if (output.getRows() != target.getRows() || output.getCols() != target.getCols()) {
            throw new Error("meanSquaredError 错误：输出和目标尺寸不匹配。");
        }
        var sum:Number = 0;
        for (var i:Number = 0; i < output.data.length; i++) {
            var diff:Number = output.data[i] - target.data[i];
            sum += diff * diff;
        }
        return sum / output.data.length;
    }

    /** MSE 的导数 => d/dOutput */
    public static function meanSquaredErrorDerivative(output:AdvancedMatrix, target:AdvancedMatrix, result:AdvancedMatrix):AdvancedMatrix {
        if (output.getRows() != target.getRows() || output.getCols() != target.getCols()) {
            throw new Error("meanSquaredErrorDerivative 错误：输出和目标尺寸不匹配。");
        }
        var hasResult:Boolean = (arguments.length >= 3) && (result != undefined);
        if (hasResult) {
            if (result.getRows() != output.getRows() || result.getCols() != output.getCols()) {
                throw new Error("meanSquaredErrorDerivative 错误：结果矩阵尺寸不匹配。");
            }
        } else {
            result = new AdvancedMatrix(new Array(output.getRows() * output.getCols()));
            result.init(output.getRows(), output.getCols());
        }
        for (var idx:Number = 0; idx < output.data.length; idx++) {
            result.data[idx] = 2 * (output.data[idx] - target.data[idx]) / output.data.length;
        }
        return result;
    }

    /** 用梯度下降更新权重矩阵 */
    public function updateWeights(gradient:AdvancedMatrix, learningRate:Number, result:AdvancedMatrix):AdvancedMatrix {
        if (this.rows != gradient.getRows() || this.cols != gradient.getCols()) {
            throw new Error("updateWeights 错误：权重矩阵和梯度矩阵尺寸不匹配。");
        }
        var hasResult:Boolean = (arguments.length >= 3) && (result != undefined);
        if (hasResult) {
            if (result.getRows() != this.rows || result.getCols() != this.cols) {
                throw new Error("updateWeights 错误：结果矩阵尺寸不匹配。");
            }
        } else {
            result = new AdvancedMatrix(new Array(this.rows * this.cols));
            result.init(this.rows, this.cols);
        }
        for (var i:Number = 0; i < this.data.length; i++) {
            result.data[i] = this.data[i] - learningRate * gradient.data[i];
        }
        return result;
    }
}
