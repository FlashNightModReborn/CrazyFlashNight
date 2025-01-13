class org.flashNight.naki.DataStructures.AdvancedMatrix {
    private var data:Array; // 用于存储矩阵数据的数组
    private var rows:Number; // 矩阵的行数
    private var cols:Number; // 矩阵的列数

    // 构造函数，接受一个数组并复制输入数组的数据
    // inputData 是一维数组，表示矩阵的所有元素，按行优先顺序存储
    public function AdvancedMatrix(inputData:Array) {
        this.data = inputData.concat(); // 创建数组的副本，防止外部修改
        this.rows = 0;
        this.cols = 0;
    }

    // 初始化矩阵维度，返回自身以支持链式调用
    // 通过传入的行数和列数初始化矩阵大小
    // numRows: 矩阵的行数
    // numCols: 矩阵的列数
    // 该方法检查传入的数组长度是否与指定的矩阵尺寸匹配
    public function init(numRows:Number, numCols:Number):AdvancedMatrix {
        // 检查输入数据的长度是否与指定的行数和列数匹配
        if (this.data.length != numRows * numCols) {
            // 抛出错误时，输出更多调试信息
            throw new Error(
                "输入数据的大小与指定的矩阵尺寸不匹配。\n" +
                "输入数据的长度: " + this.data.length + "\n" +
                "指定的行数: " + numRows + "\n" +
                "指定的列数: " + numCols + "\n" +
                "期望的数据长度: " + (numRows * numCols) + "\n" +
                "实际的数据: " + this.data.toString()
            );
        }
        this.rows = numRows;
        this.cols = numCols;
        return this;
    }

    // 通过传入新数组重置矩阵数据
    // 该方法会将矩阵的行数和列数重置为0，之后需要重新初始化
    public function reset(inputData:Array):AdvancedMatrix {
        this.data = inputData.concat(); // 创建新的数组副本
        this.rows = 0;
        this.cols = 0;
        return this;
    }

    // 从多维数组初始化矩阵
    // multiArray: 二维数组，外层数组表示行，内层数组表示列
    // 该方法会将二维数组转换为一维数组存储，并更新矩阵的行数和列数
    public function initFromMultiDimensionalArray(multiArray:Array):AdvancedMatrix {
        var newData:Array = [];
        var numRows:Number = multiArray.length;
        var numCols:Number = multiArray[0].length;

        for (var i:Number = 0; i < numRows; i++) {
            if (multiArray[i].length != numCols) {
                throw new Error("输入数组的每一行必须具有相同的列数。");
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

    // 获取矩阵中特定位置的元素
    // row: 行索引，从0开始
    // col: 列索引，从0开始
    // 返回矩阵中指定位置的元素
    public function getElement(row:Number, col:Number):Number {
        if (row < 0 || row >= this.rows) {
            throw new Error("getElement 错误：行索引 " + row + " 超出范围。矩阵有 " + this.rows + " 行。");
        }
        if (col < 0 || col >= this.cols) {
            throw new Error("getElement 错误：列索引 " + col + " 超出范围。矩阵有 " + this.cols + " 列。");
        }
        return this.data[row * this.cols + col];
    }

    // 设置矩阵中特定位置的元素
    // row: 行索引，从0开始
    // col: 列索引，从0开始
    // value: 要设置的值
    public function setElement(row:Number, col:Number, value:Number):Void {
        if (row < 0 || row >= this.rows) {
            throw new Error("setElement 错误：行索引 " + row + " 超出范围。矩阵有 " + this.rows + " 行。");
        }
        if (col < 0 || col >= this.cols) {
            throw new Error("setElement 错误：列索引 " + col + " 超出范围。矩阵有 " + this.cols + " 列。");
        }
        this.data[row * this.cols + col] = value;
    }

    // 获取矩阵的行数
    // 返回当前矩阵的行数
    public function getRows():Number {
        return this.rows;
    }

    // 获取矩阵的列数
    // 返回当前矩阵的列数
    public function getCols():Number {
        return this.cols;
    }

    // 矩阵加法
    // 将当前矩阵与另一个矩阵的对应元素相加
    // matrix: 另一个 AdvancedMatrix 对象，维度必须与当前矩阵相同
    // 返回一个新的 AdvancedMatrix 对象，包含加法的结果
    public function add(matrix:AdvancedMatrix):AdvancedMatrix {
        // 检查两个矩阵的维度是否相同
        if (this.rows != matrix.getRows() || this.cols != matrix.getCols()) {
            throw new Error("矩阵加法错误：矩阵的维度不匹配，无法进行加法运算。");
        }

        // 创建一个数组存储结果矩阵的数据
        var result:Array = new Array(this.rows * this.cols);
        // 遍历矩阵中的每一个元素，将对应元素相加
        for (var i:Number = 0; i < this.data.length; i++) {
            result[i] = this.data[i] + matrix.data[i];
        }
        // 返回新的矩阵对象
        return new AdvancedMatrix(result).init(this.rows, this.cols);
    }

    // 矩阵减法
    // 将当前矩阵与另一个矩阵的对应元素相减
    // matrix: 另一个 AdvancedMatrix 对象，维度必须与当前矩阵相同
    // 返回一个新的 AdvancedMatrix 对象，包含减法的结果
    public function subtract(matrix:AdvancedMatrix):AdvancedMatrix {
        // 检查两个矩阵的维度是否相同
        if (this.rows != matrix.getRows() || this.cols != matrix.getCols()) {
            throw new Error("矩阵减法错误：矩阵的维度不匹配，无法进行减法运算。");
        }

        // 创建一个数组存储结果矩阵的数据
        var result:Array = new Array(this.rows * this.cols);
        // 遍历矩阵中的每一个元素，将对应元素相减
        for (var i:Number = 0; i < this.data.length; i++) {
            result[i] = this.data[i] - matrix.data[i];
        }
        // 返回新的矩阵对象
        return new AdvancedMatrix(result).init(this.rows, this.cols);
    }

    // 矩阵数乘
    // 将矩阵的每个元素与一个标量相乘
    // scalar: 用于乘法运算的标量
    // 返回一个新的 AdvancedMatrix 对象，包含数乘的结果
    public function scalarMultiply(scalar:Number):AdvancedMatrix {
        // 创建一个数组存储结果矩阵的数据
        var result:Array = new Array(this.rows * this.cols);
        // 遍历矩阵中的每一个元素，与标量相乘
        for (var i:Number = 0; i < this.data.length; i++) {
            result[i] = this.data[i] * scalar;
        }
        // 返回新的矩阵对象
        return new AdvancedMatrix(result).init(this.rows, this.cols);
    }

    // 矩阵元素级乘法（Hadamard 乘法）
    // 对两个矩阵的对应元素进行乘法运算
    // matrix: 另一个 AdvancedMatrix 对象，维度必须与当前矩阵相同
    // 返回一个新的 AdvancedMatrix 对象，包含元素级乘法的结果
    public function hadamardMultiply(matrix:AdvancedMatrix):AdvancedMatrix {
        // 检查两个矩阵的维度是否相同
        if (this.rows != matrix.getRows() || this.cols != matrix.getCols()) {
            throw new Error("Hadamard 乘法错误：矩阵的维度不匹配，无法进行元素级乘法运算。");
        }

        // 创建一个数组存储结果矩阵的数据
        var result:Array = new Array(this.rows * this.cols);
        // 遍历矩阵中的每一个元素，进行对应元素的乘法
        for (var i:Number = 0; i < this.data.length; i++) {
            result[i] = this.data[i] * matrix.data[i];
        }
        // 返回新的矩阵对象
        return new AdvancedMatrix(result).init(this.rows, this.cols);
    }

    // 矩阵乘法
    // 当前矩阵与另一个矩阵进行乘法运算
    // matrix: 另一个 AdvancedMatrix 对象，列数必须等于当前矩阵的行数
    // 返回一个新的 AdvancedMatrix 对象，包含乘法的结果
    public function multiply(matrix:AdvancedMatrix):AdvancedMatrix {
        if (this.cols != matrix.getRows()) {
            throw new Error("乘法错误：第一个矩阵的列数必须等于第二个矩阵的行数。");
        }

        // 对于非方阵或尺寸较小的矩阵，使用直接乘法
        if (this.rows != this.cols || matrix.getRows() != matrix.getCols() || this.rows != matrix.getRows() || this.rows <= 64) {
            return this.multiplyDirect(matrix);
        }

        // 如果矩阵是方阵且尺寸较大，使用 Strassen 算法
        var size:Number = this.rows;
        if (!isPowerOfTwo(size)) {
            var newSize:Number = nextPowerOfTwo(size);
            var A_padded:AdvancedMatrix = this.padMatrix(newSize);
            var B_padded:AdvancedMatrix = matrix.padMatrix(newSize);
            var C_padded:AdvancedMatrix = A_padded.strassenMultiply(B_padded);
            return C_padded.unpadMatrix(this.rows, matrix.getCols());
        } else {
            return this.strassenMultiply(matrix);
        }
    }

    // 标准直接矩阵乘法，适用于小尺寸矩阵
    // matrix: 另一个 AdvancedMatrix 对象
    // 返回一个新的 AdvancedMatrix 对象，包含乘法的结果
    private function multiplyDirect(matrix:AdvancedMatrix):AdvancedMatrix {
        var result:Array = new Array(this.rows * matrix.getCols());
        for (var i:Number = 0; i < this.rows; i++) {
            for (var j:Number = 0; j < matrix.getCols(); j++) {
                var sum:Number = 0;
                for (var k:Number = 0; k < this.cols; k++) {
                    sum += this.data[i * this.cols + k] * matrix.data[k * matrix.getCols() + j];
                }
                result[i * matrix.getCols() + j] = sum;
            }
        }
        return new AdvancedMatrix(result).init(this.rows, matrix.getCols());
    }

    // Strassen 乘法的实际实现
    // 用于大尺寸的方阵乘法，通过递归分治法提高效率
    // matrix: 另一个 AdvancedMatrix 对象
    // 返回一个新的 AdvancedMatrix 对象，包含乘法的结果
    private function strassenMultiply(matrix:AdvancedMatrix):AdvancedMatrix {
        var n:Number = this.rows;
        
        // 基本情况，直接使用标准乘法
        if (n <= 64) {
            return this.multiplyDirect(matrix);
        }
        
        var newSize:Number = n / 2;
        
        // 分割矩阵为四个子矩阵
        var A11:AdvancedMatrix = this.getSubMatrix(0, 0, newSize, newSize);
        var A12:AdvancedMatrix = this.getSubMatrix(0, newSize, newSize, newSize);
        var A21:AdvancedMatrix = this.getSubMatrix(newSize, 0, newSize, newSize);
        var A22:AdvancedMatrix = this.getSubMatrix(newSize, newSize, newSize, newSize);
        
        var B11:AdvancedMatrix = matrix.getSubMatrix(0, 0, newSize, newSize);
        var B12:AdvancedMatrix = matrix.getSubMatrix(0, newSize, newSize, newSize);
        var B21:AdvancedMatrix = matrix.getSubMatrix(newSize, 0, newSize, newSize);
        var B22:AdvancedMatrix = matrix.getSubMatrix(newSize, newSize, newSize, newSize);
        
        // 计算 M1 到 M7
        var M1:AdvancedMatrix = (A11.add(A22)).strassenMultiply(B11.add(B22));
        var M2:AdvancedMatrix = (A21.add(A22)).strassenMultiply(B11);
        var M3:AdvancedMatrix = A11.strassenMultiply(B12.subtract(B22));
        var M4:AdvancedMatrix = A22.strassenMultiply(B21.subtract(B11));
        var M5:AdvancedMatrix = (A11.add(A12)).strassenMultiply(B22);
        var M6:AdvancedMatrix = (A21.subtract(A11)).strassenMultiply(B11.add(B12));
        var M7:AdvancedMatrix = (A12.subtract(A22)).strassenMultiply(B21.add(B22));
        
        // 计算 C11, C12, C21, C22
        var C11:AdvancedMatrix = M1.add(M4).subtract(M5).add(M7);
        var C12:AdvancedMatrix = M3.add(M5);
        var C21:AdvancedMatrix = M2.add(M4);
        var C22:AdvancedMatrix = M1.subtract(M2).add(M3).add(M6);
        
        // 合并子矩阵
        var C:AdvancedMatrix = C11.combineSubMatrices(C12, C21, C22);
        
        return C;
    }

    // 辅助方法：合并子矩阵
    // 合并四个子矩阵，生成最终结果矩阵
    // C11, C12, C21, C22: 四个子矩阵
    private function combineSubMatrices(C11:AdvancedMatrix, C12:AdvancedMatrix, C21:AdvancedMatrix, C22:AdvancedMatrix):AdvancedMatrix {
        var newSize:Number = C11.getRows() * 2;
        var result:Array = new Array(newSize * newSize);

        for (var i:Number = 0; i < newSize / 2; i++) {
            for (var j:Number = 0; j < newSize / 2; j++) {
                result[i * newSize + j] = C11.data[i * C11.getCols() + j];
                result[i * newSize + j + newSize / 2] = C12.data[i * C12.getCols() + j];
                result[(i + newSize / 2) * newSize + j] = C21.data[i * C21.getCols() + j];
                result[(i + newSize / 2) * newSize + j + newSize / 2] = C22.data[i * C22.getCols() + j];
            }
        }
        return new AdvancedMatrix(result).init(newSize, newSize);
    }

    // 辅助方法：检查数字是否是 2 的幂次方，用于 Strassen 算法的矩阵尺寸检查
    // num: 待检查的数字
    private function isPowerOfTwo(num:Number):Boolean {
        return (num & (num - 1)) == 0;
    }

    // 辅助方法：计算下一个 2 的幂次方
    // n: 当前尺寸
    private function nextPowerOfTwo(n:Number):Number {
        var power:Number = 1;
        while (power < n) {
            power *= 2;
        }
        return power;
    }

    // 矩阵转置
    // 将矩阵的行和列互换
    // 返回一个新的 AdvancedMatrix 对象，包含转置的结果
    public function transpose():AdvancedMatrix {
        var result:Array = new Array(this.rows * this.cols);
        for (var i:Number = 0; i < this.rows; i++) {
            for (var j:Number = 0; j < this.cols; j++) {
                result[j * this.rows + i] = this.data[i * this.cols + j];
            }
        }
        return new AdvancedMatrix(result).init(this.cols, this.rows);
    }

    // LU 分解
    // 将矩阵分解为下三角矩阵 L 和上三角矩阵 U，以及置换矩阵 P
    // 返回一个对象，包含 L、U、P 和行交换次数
    // 仅适用于方阵
    private function luDecomposition():Object {
        if (this.rows != this.cols) {
            throw new Error("LU 分解错误：矩阵必须是方阵。");
        }
        
        var n:Number = this.rows;
        var A:Array = this.data.concat(); // 创建矩阵数据的副本
        var L:Array = [];
        var U:Array = [];
        var P:Array = [];
        var pivot:Number;
        var rowSwapCount:Number = 0;
        
        // 初始化 P 为单位矩阵
        for (var i:Number = 0; i < n; i++) {
            P[i] = i;
        }
        
        for (var k:Number = 0; k < n; k++) {
            // 寻找主元
            pivot = k;
            var max:Number = Math.abs(A[k * n + k]);
            for (var i2:Number = k + 1; i2 < n; i2++) {
                if (Math.abs(A[i2 * n + k]) > max) {
                    max = Math.abs(A[i2 * n + k]);
                    pivot = i2;
                }
            }
            
            if (max == 0) {
                throw new Error("LU 分解错误：矩阵是奇异的。");
            }
            
            // 如果主元不是当前行，交换行
            if (pivot != k) {
                for (var j:Number = 0; j < n; j++) {
                    var temp:Number = A[k * n + j];
                    A[k * n + j] = A[pivot * n + j];
                    A[pivot * n + j] = temp;
                }
                // 跟踪行交换次数
                var tempP:Number = P[k];
                P[k] = P[pivot];
                P[pivot] = tempP;
                rowSwapCount++;
            }
            
            // 计算 U 矩阵和 L 矩阵的下三角部分
            for (var i3:Number = k + 1; i3 < n; i3++) {
                A[i3 * n + k] /= A[k * n + k];
                for (var j2:Number = k + 1; j2 < n; j2++) {
                    A[i3 * n + j2] -= A[i3 * n + k] * A[k * n + j2];
                }
            }
        }
        
        // 提取 L 和 U 矩阵
        for (var i4:Number = 0; i4 < n; i4++) {
            L[i4] = [];
            U[i4] = [];
            for (var j3:Number = 0; j3 < n; j3++) {
                if (i4 > j3) {
                    L[i4][j3] = A[i4 * n + j3];
                    U[i4][j3] = 0;
                } else if (i4 == j3) {
                    L[i4][j3] = 1;
                    U[i4][j3] = A[i4 * n + j3];
                } else {
                    L[i4][j3] = 0;
                    U[i4][j3] = A[i4 * n + j3];
                }
            }
        }
        
        return {
            L: L,
            U: U,
            P: P,
            rowSwapCount: rowSwapCount
        };
    }

    // 矩阵的行列式
    // 使用 LU 分解计算行列式的值
    // 返回矩阵的行列式值
    public function determinant():Number {
        if (this.rows != this.cols) {
            throw new Error("行列式错误：矩阵必须是方阵。");
        }
        
        var n:Number = this.rows;
        var lu:Object = this.luDecomposition();
        var det:Number = 1;
        
        // 行列式是 U 矩阵对角线元素的乘积
        for (var i:Number = 0; i < n; i++) {
            det *= lu.U[i][i];
        }
        
        // 如果行交换次数为奇数，行列式取相反数
        if (lu.rowSwapCount % 2 != 0) {
            det = -det;
        }
        
        return det;
    }

    // 矩阵求逆
    // 计算矩阵的逆矩阵
    // 返回一个新的 AdvancedMatrix 对象，包含逆矩阵
    public function inverse():AdvancedMatrix {
        if (this.rows != this.cols) {
            throw new Error("求逆错误：矩阵必须是方阵。");
        }
        
        var n:Number = this.rows;
        var lu:Object = this.luDecomposition();
        var L:Array = lu.L;
        var U:Array = lu.U;
        var P:Array = lu.P;
        
        // 初始化逆矩阵的数据数组
        var inverseData:Array = new Array(n * n);
        
        // 对单位矩阵的每一列求解
        for (var col:Number = 0; col < n; col++) {
            // 创建单位向量（右侧）
            var e:Array = [];
            for (var i:Number = 0; i < n; i++) {
                e[i] = (P[i] == col) ? 1 : 0;
            }
            
            // 前向替代解 Ly = Pb
            var y:Array = [];
            for (var i2:Number = 0; i2 < n; i2++) {
                var sum:Number = 0;
                for (var j:Number = 0; j < i2; j++) {
                    sum += L[i2][j] * y[j];
                }
                y[i2] = e[i2] - sum;
            }
            
            // 后向替代解 Ux = y
            var x:Array = [];
            for (var i3:Number = n - 1; i3 >= 0; i3--) {
                var sum2:Number = 0;
                for (var j2:Number = i3 + 1; j2 < n; j2++) {
                    sum2 += U[i3][j2] * x[j2];
                }
                if (U[i3][i3] == 0) {
                    throw new Error("求逆错误：矩阵是奇异的。");
                }
                x[i3] = (y[i3] - sum2) / U[i3][i3];
            }
            
            // 将解 x 放入逆矩阵的对应列
            for (var i4:Number = 0; i4 < n; i4++) {
                inverseData[i4 * n + col] = x[i4];
            }
        }
        
        return new AdvancedMatrix(inverseData).init(n, n);
    }

    // 卷积操作
    // 使用指定的卷积核对矩阵进行卷积操作
    // kernel: 卷积核矩阵，通常是一个较小的矩阵，用于在图像处理中的滤波等操作
    // padding: 填充大小，在矩阵边缘添加零，以保持输出尺寸
    // stride: 步幅，即卷积核在矩阵上移动的步长
    // 返回一个新的 AdvancedMatrix 对象，包含卷积操作的结果
    public function convolve(kernel:AdvancedMatrix, padding:Number, stride:Number):AdvancedMatrix {
        // 检查核是否为奇数尺寸
        if (kernel.getRows() % 2 == 0 || kernel.getCols() % 2 == 0) {
            throw new Error("卷积错误：卷积核的尺寸应为奇数。");
        }

        var kernelRows:Number = kernel.getRows();
        var kernelCols:Number = kernel.getCols();
        var padRows:Number = padding;
        var padCols:Number = padding;

        // 计算输出矩阵的尺寸
        var outputRows:Number = Math.floor((this.rows + 2 * padRows - kernelRows) / stride) + 1;
        var outputCols:Number = Math.floor((this.cols + 2 * padCols - kernelCols) / stride) + 1;

        var outputData:Array = new Array(outputRows * outputCols);

        // 对输入矩阵进行填充
        var paddedMatrix:AdvancedMatrix = this.padMatrixForConvolution(padRows, padCols);

        // 进行卷积运算
        for (var i:Number = 0; i < outputRows; i++) {
            for (var j:Number = 0; j < outputCols; j++) {
                var sum:Number = 0;
                for (var m:Number = 0; m < kernelRows; m++) {
                    for (var n:Number = 0; n < kernelCols; n++) {
                        var rowIndex:Number = i * stride + m;
                        var colIndex:Number = j * stride + n;
                        var imageValue:Number = paddedMatrix.getElement(rowIndex, colIndex);
                        var kernelValue:Number = kernel.getElement(kernelRows - 1 - m, kernelCols - 1 - n); // 旋转核
                        sum += imageValue * kernelValue;
                    }
                }
                outputData[i * outputCols + j] = sum;
            }
        }

        return new AdvancedMatrix(outputData).init(outputRows, outputCols);
    }

    // 辅助方法：为卷积操作填充矩阵
    // 在矩阵边缘添加零，以保持卷积后输出尺寸
    // padRows: 行方向上的填充大小
    // padCols: 列方向上的填充大小
    private function padMatrixForConvolution(padRows:Number, padCols:Number):AdvancedMatrix {
        var newRows:Number = this.rows + 2 * padRows;
        var newCols:Number = this.cols + 2 * padCols;
        var paddedData:Array = new Array(newRows * newCols);

        for (var i:Number = 0; i < newRows; i++) {
            for (var j:Number = 0; j < newCols; j++) {
                if (i >= padRows && i < padRows + this.rows && j >= padCols && j < padCols + this.cols) {
                    paddedData[i * newCols + j] = this.getElement(i - padRows, j - padCols);
                } else {
                    paddedData[i * newCols + j] = 0; // 填充零
                }
            }
        }

        return new AdvancedMatrix(paddedData).init(newRows, newCols);
    }

    // 应用仿射变换
    // 对矩阵应用仿射变换，如旋转、缩放和平移
    // transformationMatrix: 3x3 仿射变换矩阵
    // 返回一个新的 AdvancedMatrix 对象，包含变换后的矩阵
    public function applyTransformation(transformationMatrix:AdvancedMatrix):AdvancedMatrix {
        if (transformationMatrix.getRows() != 3 || transformationMatrix.getCols() != 3) {
            throw new Error("仿射变换错误：变换矩阵必须是 3x3 矩阵。");
        }

        var newData:Array = [];
        var inverseTransform:AdvancedMatrix = transformationMatrix.inverse();

        // 计算输出图像的尺寸（假设与原图像相同）
        var outputRows:Number = this.rows;
        var outputCols:Number = this.cols;

        for (var i:Number = 0; i < outputRows; i++) {
            for (var j:Number = 0; j < outputCols; j++) {
                // 构建目标图像的像素位置齐次坐标
                var destCoord:AdvancedMatrix = new AdvancedMatrix([j, i, 1]).init(3, 1);
                // 计算对应的源图像坐标
                var srcCoord:AdvancedMatrix = inverseTransform.multiply(destCoord);
                var x:Number = srcCoord.getElement(0, 0);
                var y:Number = srcCoord.getElement(1, 0);

                // 最近邻插值
                var x0:Number = Math.round(x);
                var y0:Number = Math.round(y);

                if (x0 >= 0 && x0 < this.cols && y0 >= 0 && y0 < this.rows) {
                    var value:Number = this.getElement(y0, x0);
                    newData.push(value);
                } else {
                    newData.push(0); // 超出范围，填充0
                }
            }
        }

        return new AdvancedMatrix(newData).init(outputRows, outputCols);
    }

    // 生成旋转矩阵
    // 创建用于二维平面旋转的仿射变换矩阵
    // angle: 旋转角度（以度为单位）
    public static function rotationMatrix(angle:Number):AdvancedMatrix {
        var rad:Number = angle * Math.PI / 180; // 角度转换为弧度
        var cosA:Number = Math.cos(rad);
        var sinA:Number = Math.sin(rad);
        var data:Array = [
            cosA, -sinA, 0,
            sinA, cosA, 0,
            0, 0, 1
        ];
        return new AdvancedMatrix(data).init(3, 3);
    }

    // 生成缩放矩阵
    // 创建用于二维平面缩放的仿射变换矩阵
    // sx: x 轴缩放比例
    // sy: y 轴缩放比例
    public static function scalingMatrix(sx:Number, sy:Number):AdvancedMatrix {
        var data:Array = [
            sx, 0, 0,
            0, sy, 0,
            0, 0, 1
        ];
        return new AdvancedMatrix(data).init(3, 3);
    }

    // 生成平移矩阵
    // 创建用于二维平面平移的仿射变换矩阵
    // tx: x 轴平移距离
    // ty: y 轴平移距离
    public static function translationMatrix(tx:Number, ty:Number):AdvancedMatrix {
        var data:Array = [
            1, 0, tx,
            0, 1, ty,
            0, 0, 1
        ];
        return new AdvancedMatrix(data).init(3, 3);
    }

    // 矩阵归一化
    // 将矩阵的每个元素缩放到 [0, 1] 的范围
    // 返回一个新的 AdvancedMatrix 对象，包含归一化后的矩阵
    public function normalize():AdvancedMatrix {
        var max:Number = getMax(this.data); // 找到最大值
        var min:Number = getMin(this.data); // 找到最小值
        var range:Number = max - min; // 计算范围

        if (range == 0) {
            throw new Error("归一化错误：矩阵是常数矩阵，无法进行归一化。");
        }

        var result:Array = new Array(this.rows * this.cols);
        for (var i:Number = 0; i < this.data.length; i++) {
            result[i] = (this.data[i] - min) / range;
        }
        return new AdvancedMatrix(result).init(this.rows, this.cols);
    }

    // 应用激活函数
    // 对矩阵的每个元素应用指定的激活函数，如 sigmoid、tanh、ReLU
    // functionName: 激活函数名称 ("sigmoid"、"tanh"、"relu")
    // 返回一个新的 AdvancedMatrix 对象，包含应用激活函数后的矩阵
    public function applyActivation(functionName:String):AdvancedMatrix {
        var result:Array = new Array(this.data.length);
        for (var i:Number = 0; i < this.data.length; i++) {
            var value:Number = this.data[i];
            switch (functionName.toLowerCase()) {
                case "sigmoid":
                    result[i] = 1 / (1 + Math.exp(-value));
                    break;
                case "tanh":
                    result[i] = tanh(value);
                    break;
                case "relu":
                    result[i] = Math.max(0, value);
                    break;
                default:
                    throw new Error("激活函数错误：不支持的激活函数 '" + functionName + "'。");
            }
        }
        return new AdvancedMatrix(result).init(this.rows, this.cols);
    }

    // 实现 tanh 函数
    // x: 输入值
    // 返回 tanh(x) 的值
    private static function tanh(x:Number):Number {
        var ePosX:Number = Math.exp(x);
        var eNegX:Number = Math.exp(-x);
        return (ePosX - eNegX) / (ePosX + eNegX);
    }

    // 计算损失函数（均方误差）
    // 计算两个矩阵之间的均方误差
    // output: 输出矩阵
    // target: 目标矩阵
    // 返回均方误差的值
    public static function meanSquaredError(output:AdvancedMatrix, target:AdvancedMatrix):Number {
        if (output.rows != target.rows || output.cols != target.cols) {
            throw new Error("均方误差错误：输出和目标矩阵的维度不匹配。");
        }
        var sum:Number = 0;
        for (var i:Number = 0; i < output.data.length; i++) {
            var diff:Number = output.data[i] - target.data[i];
            sum += diff * diff;
        }
        return sum / output.data.length;
    }

    // 计算损失函数的导数（对于均方误差）
    // 计算均方误差损失函数关于输出矩阵的导数
    // output: 输出矩阵
    // target: 目标矩阵
    // 返回一个新的 AdvancedMatrix 对象，包含损失函数的导数
    public static function meanSquaredErrorDerivative(output:AdvancedMatrix, target:AdvancedMatrix):AdvancedMatrix {
        if (output.rows != target.rows || output.cols != target.cols) {
            throw new Error("均方误差导数错误：输出和目标矩阵的维度不匹配。");
        }
        var result:Array = new Array(output.data.length);
        for (var i:Number = 0; i < output.data.length; i++) {
            result[i] = 2 * (output.data[i] - target.data[i]) / output.data.length;
        }
        return new AdvancedMatrix(result).init(output.rows, output.cols);
    }

    // 更新权重矩阵
    // 使用梯度下降法更新矩阵的权重
    // gradient: 梯度矩阵
    // learningRate: 学习率
    // 返回一个新的 AdvancedMatrix 对象，包含更新后的权重矩阵
    public function updateWeights(gradient:AdvancedMatrix, learningRate:Number):AdvancedMatrix {
        if (this.rows != gradient.rows || this.cols != gradient.cols) {
            throw new Error("权重更新错误：权重矩阵和梯度矩阵的维度不匹配。");
        }
        var result:Array = new Array(this.data.length);
        for (var i:Number = 0; i < this.data.length; i++) {
            result[i] = this.data[i] - learningRate * gradient.data[i];
        }
        return new AdvancedMatrix(result).init(this.rows, this.cols);
    }

    // 矩阵行归一化
    // 将矩阵的每一行归一化，使每一行的元素之和为 1
    // 返回一个新的 AdvancedMatrix 对象，包含归一化后的矩阵
    // 如果行的和为零，将抛出错误
    public function normalizeRows():AdvancedMatrix {
        var result:Array = new Array(this.rows * this.cols);
        for (var i:Number = 0; i < this.rows; i++) {
            var rowSum:Number = 0;
            // 计算当前行的和
            for (var j:Number = 0; j < this.cols; j++) {
                rowSum += this.data[i * this.cols + j];
            }
            // 检查行和是否为零，避免除零错误
            if (rowSum == 0) {
                throw new Error("归一化错误：行的和不能为零。");
            }
            // 归一化当前行的元素
            for (var j:Number = 0; j < this.cols; j++) {
                result[i * this.cols + j] = this.data[i * this.cols + j] / rowSum;
            }
        }
        return new AdvancedMatrix(result).init(this.rows, this.cols);
    }


    // 判断矩阵是否收敛
    // previousState: 前一步的状态向量
    // threshold: 收敛判断的阈值
    // 返回布尔值，表示当前矩阵与前一步状态向量之间的差异是否小于阈值
    // 通过比较矩阵之间的差异来判断收敛
    public function hasConverged(previousState:AdvancedMatrix, threshold:Number):Boolean {
        // 计算当前矩阵与前一步矩阵的差异
        var difference:AdvancedMatrix = this.subtract(previousState);
        // 遍历所有元素，检查差异是否小于阈值
        for (var i:Number = 0; i < difference.data.length; i++) {
            if (Math.abs(difference.data[i]) > threshold) {
                return false;
            }
        }
        return true;
    }


    // 用特定的值填充整个矩阵
    // value: 用于填充矩阵的值
    // 返回当前 AdvancedMatrix 对象，以支持链式调用
    public function fill(value:Number):AdvancedMatrix {
        for (var i:Number = 0; i < this.data.length; i++) {
            this.data[i] = value;
        }
        return this;
    }

    // 用随机数填充矩阵
    // min: 随机数的最小值
    // max: 随机数的最大值
    // 返回当前 AdvancedMatrix 对象，以支持链式调用
    public function randomize(min:Number, max:Number):AdvancedMatrix {
        for (var i:Number = 0; i < this.data.length; i++) {
            this.data[i] = Math.random() * (max - min) + min;
        }
        return this;
    }

    // 辅助方法：从填充后的矩阵中移除多余的行和列
    // originalRows: 原矩阵的行数
    // originalCols: 原矩阵的列数
    // 该方法用于移除之前填充的零，恢复矩阵的原始大小
    private function unpadMatrix(originalRows:Number, originalCols:Number):AdvancedMatrix {
        var unpaddedData:Array = [];
        for (var i:Number = 0; i < originalRows; i++) {
            for (var j:Number = 0; j < originalCols; j++) {
                // 只提取原始矩阵尺寸范围内的元素
                unpaddedData.push(this.data[i * this.cols + j]);
            }
        }
        return new AdvancedMatrix(unpaddedData).init(originalRows, originalCols);
    }


    // 辅助方法：扩展矩阵到指定大小，填充零
    // newSize: 扩展后的矩阵大小
    // 该方法用于将当前矩阵扩展到指定大小，并在新增加的位置填充零
    private function padMatrix(newSize:Number):AdvancedMatrix {
        var paddedData:Array = [];
        for (var i:Number = 0; i < newSize; i++) {
            for (var j:Number = 0; j < newSize; j++) {
                // 如果在原矩阵的范围内，则复制元素；否则填充零
                if (i < this.rows && j < this.cols) {
                    paddedData.push(this.data[i * this.cols + j]);
                } else {
                    paddedData.push(0);
                }
            }
        }
        return new AdvancedMatrix(paddedData).init(newSize, newSize);
    }


    // 提取矩阵中的一个子矩阵
    // startRow: 子矩阵的起始行
    // startCol: 子矩阵的起始列
    // numRows: 子矩阵的行数
    // numCols: 子矩阵的列数
    // 返回一个新的 AdvancedMatrix 对象，包含子矩阵
    public function getSubMatrix(startRow:Number, startCol:Number, numRows:Number, numCols:Number):AdvancedMatrix {
        var subData:Array = [];
        for (var i:Number = 0; i < numRows; i++) {
            for (var j:Number = 0; j < numCols; j++) {
                subData.push(this.data[(startRow + i) * this.cols + (startCol + j)]);
            }
        }
        return new AdvancedMatrix(subData).init(numRows, numCols);
    }

    // 克隆矩阵数据到一维数组
    // 返回当前矩阵数据的副本
    public function toArray():Array {
        return this.data.concat(); // 返回数据的副本
    }

    // 矩阵复制，创建矩阵的副本
    // 返回一个新的 AdvancedMatrix 对象，包含与当前矩阵相同的数据
    public function clone():AdvancedMatrix {
        return new AdvancedMatrix(this.data).init(this.rows, this.cols);
    }

    // 计算方阵的迹，即对角线元素的和
    // 仅适用于方阵
    // 返回矩阵的迹
    public function trace():Number {
        if (this.rows != this.cols) {
            throw new Error("迹计算错误：仅适用于方阵。");
        }
        var sum:Number = 0;
        for (var i:Number = 0; i < this.rows; i++) {
            sum += this.data[i * this.cols + i];
        }
        return sum;
    }

    // 重写 toString 方法，打印矩阵内容
    // 返回矩阵内容的字符串表示形式
    public function toString():String {
        var result:String = "";
        for (var i:Number = 0; i < this.rows; i++) {
            for (var j:Number = 0; j < this.cols; j++) {
                result += this.data[i * this.cols + j] + "\t";
            }
            result += "\n";
        }
        return result;
    }

    // 打印矩阵（用于调试）
    // 直接输出矩阵内容以便调试和查看
    public function printMatrix():Void {
        trace(this.toString());
    }

    // 获取数组的最大值
    // arr: 数组
    // 返回数组中的最大值
    private function getMax(arr:Array):Number {
        var max:Number = arr[0];
        for (var i:Number = 1; i < arr.length; i++) {
            if (arr[i] > max) {
                max = arr[i];
            }
        }
        return max;
    }

    // 获取数组的最小值
    // arr: 数组
    // 返回数组中的最小值
    private function getMin(arr:Array):Number {
        var min:Number = arr[0];
        for (var i:Number = 1; i < arr.length; i++) {
            if (arr[i] < min) {
                min = arr[i];
            }
        }
        return min;
    }
}
