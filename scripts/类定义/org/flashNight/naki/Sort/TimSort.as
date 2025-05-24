class org.flashNight.naki.Sort.TimSort {
    /**
     * TimSort 的最终优化版 (AS2)
     * - 严格遵循 TimSort 的堆栈不变量，确保正确性
     * - 使用预分配的临时数组和 run 栈，提升性能
     * - 保证稳定性，当元素相等时，优先选择左 run 的元素
     *
     * @param arr 要排序的数组
     * @param compareFunction 若为 null, 则使用默认的比较函数
     * @return 排好序的原数组 (就地修改)
     */
    
    public static function sort(arr:Array, compareFunction:Function):Array {
        var length:Number = arr.length;
        if (length <= 1) {
            return arr; // 长度<=1，直接返回
        }

        // 0) 确定比较函数
        var compare:Function = (compareFunction == null)
            ? function(a, b):Number { 
                return a - b;
              }
            : compareFunction;

        // 1) 预检测：检查是否整体有序或整体逆序
        var isSorted:Boolean = true;
        for (var iCheck:Number = 1; iCheck < length; iCheck++) {
            if (compare(arr[iCheck -1], arr[iCheck]) > 0) {
                isSorted = false;
                break;
            }
        }
        if (isSorted) {
            return arr; // 已整体有序，直接返回
        }

        var isReversed:Boolean = true;
        for (var jCheck:Number = 1; jCheck < length; jCheck++) {
            if (compare(arr[jCheck -1], arr[jCheck]) < 0) {
                isReversed = false;
                break;
            }
        }
        if (isReversed) {
            // 整体逆序，直接反转
            var lRev:Number = 0;
            var rRev:Number = length -1;
            while (lRev < rRev) {
                var tempSwap:Object = arr[lRev];
                arr[lRev] = arr[rRev];
                arr[rRev] = tempSwap;
                lRev++;
                rRev--;
            }
            return arr;
        }

        // 2) 动态计算最小 run 长度 MIN_RUN
        var MIN_RUN:Number;
        var n:Number = length;
        var r:Number = 0;
        while (n >= 32) {
            r |= n & 1;
            n >>= 1;
        }
        MIN_RUN = n + r; // 动态计算 MIN_RUN

        // 3) 初始化模拟栈 + 临时数组
        var stackRuns:Array = new Array(2 * length);
        var sp:Number = 0;
        var temp:Array = new Array(length);

        // 4) 收集 run 并合并
        var startRun:Number = 0;
        while (startRun < length) {
            var runStart:Number = startRun;
            var runEnd:Number = runStart + 1;

            // 检测单调性
            if (runEnd < length) {
                if (compare(arr[runStart], arr[runEnd]) <= 0) {
                    while (runEnd < length -1 && compare(arr[runEnd], arr[runEnd +1]) <= 0) {
                        runEnd++;
                    }
                } else {
                    while (runEnd < length -1 && compare(arr[runEnd], arr[runEnd +1]) > 0) {
                        runEnd++;
                    }
                    // 反转降序区间
                    var leftFlip:Number = runStart;
                    var rightFlip:Number = runEnd;
                    while (leftFlip < rightFlip) {
                        var tempSwap2:Object = arr[leftFlip];
                        arr[leftFlip] = arr[rightFlip];
                        arr[rightFlip] = tempSwap2;
                        leftFlip++;
                        rightFlip--;
                    }
                }
            }

            var currentRunSize:Number = runEnd - runStart + 1;

            // 扩展小 run 到 MIN_RUN 使用插入排序
            if (currentRunSize < MIN_RUN) {
                var endBound:Number = (runStart + MIN_RUN -1 < length -1) ? (runStart + MIN_RUN -1) : (length -1);
                
                // 使用紧凑型插入排序 (性能优化关键点)
                var iIns:Number = runStart + 1;
                do {
                    var keyVal:Object = arr[iIns];
                    var j:Number = iIns;
                    
                    // 合并比较和移动操作的单层循环
                    while (--j >= runStart && compare(arr[j], keyVal) > 0) {
                        arr[j + 1] = arr[j];
                    }
                    arr[j + 1] = keyVal;
                } while (++iIns <= endBound);
                
                runEnd = endBound;
                currentRunSize = runEnd - runStart + 1;
            }


            // 将该 run 入栈
            stackRuns[sp++] = runStart;
            stackRuns[sp++] = runEnd;

            // 内联 mergeInvariant
            while (sp >= 4) {
                if (sp >= 6) {
                    var runXStart:Number = stackRuns[sp - 6];
                    var runXEnd:Number = stackRuns[sp - 5];
                    var runYStart:Number = stackRuns[sp - 4];
                    var runYEnd:Number = stackRuns[sp - 3];
                    var runZStart:Number = stackRuns[sp - 2];
                    var runZEnd:Number = stackRuns[sp - 1];

                    var sizeX:Number = runXEnd - runXStart + 1;
                    var sizeY:Number = runYEnd - runYStart + 1;
                    var sizeZ:Number = runZEnd - runZStart + 1;

                    if (sizeX <= sizeY + sizeZ && sizeY <= sizeZ) {
                        if (sizeX < sizeZ) {
                            // 合并 runX 和 runY
                            sp -= 4;

                            var sizeA:Number = runXEnd - runXStart + 1;
                            var sizeB:Number = runYEnd - runYStart + 1;
                            for (var i:Number = 0; i < sizeA; i++) {
                                temp[i] = arr[runXStart + i];
                            }
                            var idxTemp:Number = 0;
                            var idxArr:Number = runXStart;
                            var idxBPtr:Number = runYStart;
                            var endA:Number = sizeA;
                            var endB:Number = runYEnd + 1;
                            while (idxTemp < endA && idxBPtr < endB) {
                                if (compare(temp[idxTemp], arr[idxBPtr]) <= 0) {
                                    arr[idxArr++] = temp[idxTemp++];
                                } else {
                                    arr[idxArr++] = arr[idxBPtr++];
                                }
                            }
                            while (idxTemp < endA) {
                                arr[idxArr++] = temp[idxTemp++];
                            }
                            stackRuns[sp++] = runXStart;
                            stackRuns[sp++] = runYEnd;
                        } else {
                            // 合并 runY 和 runZ
                            sp -= 4;

                            var sizeA2:Number = runYEnd - runYStart + 1;
                            var sizeB2:Number = runZEnd - runZStart + 1;
                            for (var j:Number = 0; j < sizeA2; j++) {
                                temp[j] = arr[runYStart + j];
                            }
                            var idxTemp2:Number = 0;
                            var idxArr2:Number = runYStart;
                            var idxBPtr2:Number = runZStart;
                            var endA2:Number = sizeA2;
                            var endB2:Number = runZEnd + 1;
                            while (idxTemp2 < endA2 && idxBPtr2 < endB2) {
                                if (compare(temp[idxTemp2], arr[idxBPtr2]) <= 0) {
                                    arr[idxArr2++] = temp[idxTemp2++];
                                } else {
                                    arr[idxArr2++] = arr[idxBPtr2++];
                                }
                            }
                            while (idxTemp2 < endA2) {
                                arr[idxArr2++] = temp[idxTemp2++];
                            }
                            stackRuns[sp++] = runYStart;
                            stackRuns[sp++] = runZEnd;
                        }
                        continue;
                    }
                }

                // 如果只有两个 run，检查 Y ≤ Z
                if (sp >= 4) {
                    var runYStart2:Number = stackRuns[sp - 4];
                    var runYEnd2:Number = stackRuns[sp - 3];
                    var runZStart2:Number = stackRuns[sp - 2];
                    var runZEnd2:Number = stackRuns[sp - 1];

                    var sizeY2:Number = runYEnd2 - runYStart2 + 1;
                    var sizeZ2:Number = runZEnd2 - runZStart2 + 1;

                    if (sizeY2 <= sizeZ2) {
                        // 合并 runY 和 runZ
                        sp -= 4;

                        var sizeA3:Number = runYEnd2 - runYStart2 + 1;
                        var sizeB3:Number = runZEnd2 - runZStart2 + 1;
                        for (var m:Number = 0; m < sizeA3; m++) {
                            temp[m] = arr[runYStart2 + m];
                        }
                        var idxTemp3:Number = 0;
                        var idxArr3:Number = runYStart2;
                        var idxBPtr3:Number = runZStart2;
                        var endA3:Number = sizeA3;
                        var endB3:Number = runZEnd2 + 1;
                        while (idxTemp3 < endA3 && idxBPtr3 < endB3) {
                            if (compare(temp[idxTemp3], arr[idxBPtr3]) <= 0) {
                                arr[idxArr3++] = temp[idxTemp3++];
                            } else {
                                arr[idxArr3++] = arr[idxBPtr3++];
                            }
                        }
                        while (idxTemp3 < endA3) {
                            arr[idxArr3++] = temp[idxTemp3++];
                        }
                        stackRuns[sp++] = runYStart2;
                        stackRuns[sp++] = runZEnd2;
                        continue;
                    }
                }

                break;
            }

            startRun = runEnd + 1;
        }

        // 5) 最终合并
        while (sp > 2) {
            // 内联 mergeInvariant
            while (sp >= 4) {
                if (sp >= 6) {
                    var runXStart:Number = stackRuns[sp - 6];
                    var runXEnd:Number = stackRuns[sp - 5];
                    var runYStart:Number = stackRuns[sp - 4];
                    var runYEnd:Number = stackRuns[sp - 3];
                    var runZStart:Number = stackRuns[sp - 2];
                    var runZEnd:Number = stackRuns[sp - 1];

                    var sizeX:Number = runXEnd - runXStart + 1;
                    var sizeY:Number = runYEnd - runYStart + 1;
                    var sizeZ:Number = runZEnd - runZStart + 1;

                    if (sizeX <= sizeY + sizeZ && sizeY <= sizeZ) {
                        if (sizeX < sizeZ) {
                            // 合并 runX 和 runY
                            sp -= 4;

                            var sizeA4:Number = runXEnd - runXStart + 1;
                            var sizeB4:Number = runYEnd - runYStart + 1;
                            for (var n:Number = 0; n < sizeA4; n++) {
                                temp[n] = arr[runXStart + n];
                            }
                            var idxTemp4:Number = 0;
                            var idxArr4:Number = runXStart;
                            var idxBPtr4:Number = runYStart;
                            var endA4:Number = sizeA4;
                            var endB4:Number = runYEnd + 1;
                            while (idxTemp4 < endA4 && idxBPtr4 < endB4) {
                                if (compare(temp[idxTemp4], arr[idxBPtr4]) <= 0) {
                                    arr[idxArr4++] = temp[idxTemp4++];
                                } else {
                                    arr[idxArr4++] = arr[idxBPtr4++];
                                }
                            }
                            while (idxTemp4 < endA4) {
                                arr[idxArr4++] = temp[idxTemp4++];
                            }
                            stackRuns[sp++] = runXStart;
                            stackRuns[sp++] = runYEnd;
                        } else {
                            // 合并 runY 和 runZ
                            sp -= 4;

                            var sizeA5:Number = runYEnd - runYStart + 1;
                            var sizeB5:Number = runZEnd - runZStart + 1;
                            for (var p:Number = 0; p < sizeA5; p++) {
                                temp[p] = arr[runYStart + p];
                            }
                            var idxTemp5:Number = 0;
                            var idxArr5:Number = runYStart;
                            var idxBPtr5:Number = runZStart;
                            var endA5:Number = sizeA5;
                            var endB5:Number = runZEnd + 1;
                            while (idxTemp5 < endA5 && idxBPtr5 < endB5) {
                                if (compare(temp[idxTemp5], arr[idxBPtr5]) <= 0) {
                                    arr[idxArr5++] = temp[idxTemp5++];
                                } else {
                                    arr[idxArr5++] = arr[idxBPtr5++];
                                }
                            }
                            while (idxTemp5 < endA5) {
                                arr[idxArr5++] = temp[idxTemp5++];
                            }
                            stackRuns[sp++] = runYStart;
                            stackRuns[sp++] = runZEnd;
                        }
                        continue;
                    }
                }

                // 如果只有两个 run，检查 Y ≤ Z
                if (sp >= 4) {
                    var runYStart6:Number = stackRuns[sp - 4];
                    var runYEnd6:Number = stackRuns[sp - 3];
                    var runZStart6:Number = stackRuns[sp - 2];
                    var runZEnd6:Number = stackRuns[sp - 1];

                    var sizeY6:Number = runYEnd6 - runYStart6 + 1;
                    var sizeZ6:Number = runZEnd6 - runZStart6 + 1;

                    if (sizeY6 <= sizeZ6) {
                        // 合并 runY 和 runZ
                        sp -= 4;

                        var sizeA6:Number = runYEnd6 - runYStart6 + 1;
                        var sizeB6:Number = runZEnd6 - runZStart6 + 1;
                        for (var q:Number = 0; q < sizeA6; q++) {
                            temp[q] = arr[runYStart6 + q];
                        }
                        var idxTemp6:Number = 0;
                        var idxArr6:Number = runYStart6;
                        var idxBPtr6:Number = runZStart6;
                        var endA6:Number = sizeA6;
                        var endB6:Number = runZEnd6 + 1;
                        while (idxTemp6 < endA6 && idxBPtr6 < endB6) {
                            if (compare(temp[idxTemp6], arr[idxBPtr6]) <= 0) {
                                arr[idxArr6++] = temp[idxTemp6++];
                            } else {
                                arr[idxArr6++] = arr[idxBPtr6++];
                            }
                        }
                        while (idxTemp6 < endA6) {
                            arr[idxArr6++] = temp[idxTemp6++];
                        }
                        stackRuns[sp++] = runYStart6;
                        stackRuns[sp++] = runZEnd6;
                        continue;
                    }
                }

                break;
            }

            if (sp > 2) {
                // 强制合并栈顶两个 run
                var run2End:Number = stackRuns[sp - 1];
                var run2Start:Number = stackRuns[sp - 2];
                var run1End:Number = stackRuns[sp - 3];
                var run1Start:Number = stackRuns[sp - 4];
                sp -= 4;

                var sizeA7:Number = run1End - run1Start + 1;
                var sizeB7:Number = run2End - run2Start + 1;
                for (var n2:Number = 0; n2 < sizeA7; n2++) {
                    temp[n2] = arr[run1Start + n2];
                }
                var idxTemp7:Number = 0;
                var idxArr7:Number = run1Start;
                var idxBPtr7:Number = run2Start;
                var endA7:Number = sizeA7;
                var endB7:Number = run2End + 1;
                while (idxTemp7 < endA7 && idxBPtr7 < endB7) {
                    if (compare(temp[idxTemp7], arr[idxBPtr7]) <= 0) {
                        arr[idxArr7++] = temp[idxTemp7++];
                    } else {
                        arr[idxArr7++] = arr[idxBPtr7++];
                    }
                }
                while (idxTemp7 < endA7) {
                    arr[idxArr7++] = temp[idxTemp7++];
                }
                stackRuns[sp++] = run1Start;
                stackRuns[sp++] = run2End;
            }
        }

        return arr; // 数组已整体有序
    }
}
