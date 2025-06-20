/**
ActionScript 2.0 完全内联 TimSort 实现（完整版本，无任何省略）
*/
class org.flashNight.naki.Sort.TimSort {
    
    public static function sort(arr:Array, compareFunction:Function):Array {
        var n:Number = arr.length;
        if (n < 2) return arr;
        
        // 内部常量
        var MIN_MERGE:Number = 32;
        var MIN_GALLOP:Number = 7;
        
        var compare:Function = (compareFunction == null)
            ? function(a, b):Number { return a - b; }
            : compareFunction;
        
        var tempArray:Array = new Array(Math.ceil(n / 2));
        var runBase:Array = [];
        var runLen:Array = [];
        var stackSize:Number = 0;
        var minGallop:Number = MIN_GALLOP;
        
        // 内联 _calculateMinRun
        var minRun:Number;
        var tempN:Number = n;
        var r:Number = 0;
        while (tempN >= 32) {
            r |= tempN & 1;
            tempN >>= 1;
        }
        minRun = tempN + r;
        
        var remaining:Number = n;
        var lo:Number = 0;
        
        while (remaining > 0) {
            // 内联 _countRunAndReverse
            var runLength:Number;
            var hi:Number = lo + 1;
            if (hi >= n) {
                runLength = 1;
            } else {
                if (compare(arr[lo], arr[hi]) > 0) {
                    hi++;
                    while (hi < n && compare(arr[hi - 1], arr[hi]) > 0) hi++;
                    // 内联 _reverseRange
                    var revLo:Number = lo, revHi:Number = hi - 1;
                    while (revLo < revHi) {
                        var tmp:Object = arr[revLo];
                        arr[revLo++] = arr[revHi];
                        arr[revHi--] = tmp;
                    }
                } else {
                    while (hi < n && compare(arr[hi - 1], arr[hi]) <= 0) hi++;
                }
                runLength = hi - lo;
            }
            
            if (runLength < minRun) {
                var force:Number = (remaining < minRun) ? remaining : minRun;
                // 内联 _insertionSort
                var right:Number = lo + force - 1;
                for (var i:Number = lo + 1; i <= right; i++) {
                    var key:Object = arr[i];
                    var j:Number = i - 1;
                    while (j >= lo && compare(arr[j], key) > 0) {
                        arr[j + 1] = arr[j];
                        j--;
                    }
                    arr[j + 1] = key;
                }
                runLength = force;
            }
            
            runBase[stackSize] = lo;
            runLen[stackSize++] = runLength;
            
            // 内联 _mergeCollapse - 完整版本
            var size:Number = stackSize;
            while (size > 1) {
                var n_idx:Number = size - 2;
                var shouldMerge:Boolean = false;
                var mergeIdx:Number;
                
                if (n_idx > 0 && runLen[n_idx - 1] <= runLen[n_idx] + runLen[n_idx + 1]) {
                    if (runLen[n_idx - 1] < runLen[n_idx + 1]) {
                        mergeIdx = n_idx - 1;
                    } else {
                        mergeIdx = n_idx;
                    }
                    shouldMerge = true;
                } else if (runLen[n_idx] <= runLen[n_idx + 1]) {
                    mergeIdx = n_idx;
                    shouldMerge = true;
                }
                
                if (!shouldMerge) break;
                
                // 内联 _mergeAt - 完整版本
                var loA:Number = runBase[mergeIdx];
                var lenA:Number = runLen[mergeIdx];
                var loB:Number = runBase[mergeIdx + 1];
                var lenB:Number = runLen[mergeIdx + 1];
                
                runLen[mergeIdx] = lenA + lenB;
                
                var mergeN:Number = stackSize - 1;
                for (var mergeJ:Number = mergeIdx + 1; mergeJ < mergeN; mergeJ++) {
                    runBase[mergeJ] = runBase[mergeJ + 1];
                    runLen[mergeJ] = runLen[mergeJ + 1];
                }
                stackSize--;
                
                // 内联 _gallopRight for first element - 完整版本
                var gallopK:Number = 0;
                var target:Object = arr[loB];
                var base:Number = loA;
                var len:Number = lenA;
                
                if (len == 0 || compare(arr[base], target) >= 0) {
                    gallopK = 0;
                } else {
                    var ofs:Number = 1;
                    var lastOfs:Number = 0;
                    
                    while (ofs < len && compare(arr[base + ofs], target) < 0) {
                        lastOfs = ofs;
                        ofs = (ofs << 1) + 1;
                        if (ofs <= 0) ofs = len;
                    }
                    if (ofs > len) ofs = len;
                    
                    // 内联 _binarySearchLeft
                    var bsLo:Number = lastOfs;
                    var bsHi:Number = ofs;
                    var bsMid:Number;
                    while (bsLo < bsHi) {
                        bsMid = (bsLo + bsHi) >> 1;
                        if (compare(arr[base + bsMid], target) < 0) {
                            bsLo = bsMid + 1;
                        } else {
                            bsHi = bsMid;
                        }
                    }
                    gallopK = bsLo;
                }
                
                if (gallopK == lenA) {
                    // 无需合并，直接继续
                } else {
                    loA += gallopK;
                    lenA -= gallopK;
                    
                    // 内联 _gallopLeft for last element - 完整版本
                    var gallopK2:Number = 0;
                    target = arr[loA + lenA - 1];
                    base = loB;
                    len = lenB;
                    
                    if (len == 0 || compare(arr[base], target) > 0) {
                        gallopK2 = 0;
                    } else {
                        ofs = 1;
                        lastOfs = 0;
                        
                        while (ofs < len && compare(arr[base + ofs], target) <= 0) {
                            lastOfs = ofs;
                            ofs = (ofs << 1) + 1;
                            if (ofs <= 0) ofs = len;
                        }
                        if (ofs > len) ofs = len;
                        
                        // 内联 _binarySearchRight
                        bsLo = lastOfs;
                        bsHi = ofs;
                        while (bsLo < bsHi) {
                            bsMid = (bsLo + bsHi) >> 1;
                            if (compare(arr[base + bsMid], target) <= 0) {
                                bsLo = bsMid + 1;
                            } else {
                                bsHi = bsMid;
                            }
                        }
                        gallopK2 = bsLo;
                    }
                    
                    if (gallopK2 == 0) {
                        // 无需合并，直接继续
                    } else {
                        lenB = gallopK2;
                        
                        // 选择合并方向并内联相应的合并逻辑
                        if (lenA <= lenB) {
                            // 内联 _mergeLo - 完整版本
                            var pa:Number = 0, pb:Number = loB, d:Number = loA;
                            var ea:Number = lenA, eb:Number = loB + lenB;
                            var ca:Number = 0, cb:Number = 0;
                            var tempIdx:Number, copyLen:Number;
                            
                            for (var copyI:Number = 0; copyI < lenA; copyI++) {
                                tempArray[copyI] = arr[loA + copyI];
                            }
                            
                            while (pa < ea && pb < eb && ca < minGallop && cb < minGallop) {
                                if (compare(tempArray[pa], arr[pb]) <= 0) {
                                    arr[d++] = tempArray[pa++];
                                    ca++;
                                    cb = 0;
                                } else {
                                    arr[d++] = arr[pb++];
                                    cb++;
                                    ca = 0;
                                }
                            }
                            
                            while (pa < ea && pb < eb) {
                                if (ca >= minGallop) {
                                    // 内联 gallopRight 逻辑 - 完整版本
                                    target = tempArray[pa];
                                    base = pb;
                                    len = eb - pb;
                                    gallopK = 0;
                                    
                                    if (len == 0 || compare(arr[base], target) >= 0) {
                                        gallopK = 0;
                                    } else {
                                        ofs = 1;
                                        lastOfs = 0;
                                        while (ofs < len && compare(arr[base + ofs], target) < 0) {
                                            lastOfs = ofs;
                                            ofs = (ofs << 1) + 1;
                                            if (ofs <= 0) ofs = len;
                                        }
                                        if (ofs > len) ofs = len;
                                        bsLo = lastOfs;
                                        bsHi = ofs;
                                        while (bsLo < bsHi) {
                                            bsMid = (bsLo + bsHi) >> 1;
                                            if (compare(arr[base + bsMid], target) < 0) {
                                                bsLo = bsMid + 1;
                                            } else {
                                                bsHi = bsMid;
                                            }
                                        }
                                        gallopK = bsLo;
                                    }
                                    
                                    for (copyI = 0; copyI < gallopK; copyI++) {
                                        arr[d + copyI] = arr[pb + copyI];
                                    }
                                    d += gallopK;
                                    pb += gallopK;
                                    ca = 0;
                                    minGallop += (gallopK < MIN_GALLOP ? 1 : 0) - 1;
                                    if (minGallop < 1) minGallop = 1;
                                } else if (cb >= minGallop) {
                                    // 内联 gallopLeft 逻辑 - 完整版本
                                    target = arr[pb];
                                    base = pa;
                                    len = ea - pa;
                                    gallopK = 0;
                                    
                                    if (len == 0 || compare(tempArray[base], target) > 0) {
                                        gallopK = 0;
                                    } else {
                                        ofs = 1;
                                        lastOfs = 0;
                                        while (ofs < len && compare(tempArray[base + ofs], target) <= 0) {
                                            lastOfs = ofs;
                                            ofs = (ofs << 1) + 1;
                                            if (ofs <= 0) ofs = len;
                                        }
                                        if (ofs > len) ofs = len;
                                        bsLo = lastOfs;
                                        bsHi = ofs;
                                        while (bsLo < bsHi) {
                                            bsMid = (bsLo + bsHi) >> 1;
                                            if (compare(tempArray[base + bsMid], target) <= 0) {
                                                bsLo = bsMid + 1;
                                            } else {
                                                bsHi = bsMid;
                                            }
                                        }
                                        gallopK = bsLo;
                                    }
                                    
                                    for (copyI = 0; copyI < gallopK; copyI++) {
                                        arr[d + copyI] = tempArray[pa + copyI];
                                    }
                                    d += gallopK;
                                    pa += gallopK;
                                    cb = 0;
                                    minGallop += (gallopK < MIN_GALLOP ? 1 : 0) - 1;
                                    if (minGallop < 1) minGallop = 1;
                                } else {
                                    while (pa < ea && pb < eb && ca < minGallop && cb < minGallop) {
                                        if (compare(tempArray[pa], arr[pb]) <= 0) {
                                            arr[d++] = tempArray[pa++];
                                            ca++;
                                            cb = 0;
                                        } else {
                                            arr[d++] = arr[pb++];
                                            cb++;
                                            ca = 0;
                                        }
                                    }
                                }
                            }
                            
                            for (copyI = 0; copyI < ea - pa; copyI++) {
                                arr[d + copyI] = tempArray[pa + copyI];
                            }
                        } else {
                            // 内联 _mergeHi - 完整版本
                            pa = loA + lenA - 1;
                            pb = lenB - 1;
                            d = loB + lenB - 1;
                            var ba0:Number = loA;
                            cb = 0;
                            ca = 0;
                            
                            for (copyI = 0; copyI < lenB; copyI++) {
                                tempArray[copyI] = arr[loB + copyI];
                            }
                            
                            while (pa >= ba0 && pb >= 0 && ca < minGallop && cb < minGallop) {
                                if (compare(arr[pa], tempArray[pb]) > 0) {
                                    arr[d--] = arr[pa--];
                                    ca++;
                                    cb = 0;
                                } else {
                                    arr[d--] = tempArray[pb--];
                                    cb++;
                                    ca = 0;
                                }
                            }
                            
                            while (pa >= ba0 && pb >= 0) {
                                if (ca >= minGallop) {
                                    // 内联 gallopLeft 逻辑用于mergeHi - 完整版本
                                    target = tempArray[pb];
                                    base = ba0;
                                    len = pa - ba0 + 1;
                                    gallopK = len;
                                    
                                    if (len == 0 || compare(arr[base], target) > 0) {
                                        gallopK = len;
                                    } else {
                                        ofs = 1;
                                        lastOfs = 0;
                                        while (ofs < len && compare(arr[base + ofs], target) <= 0) {
                                            lastOfs = ofs;
                                            ofs = (ofs << 1) + 1;
                                            if (ofs <= 0) ofs = len;
                                        }
                                        if (ofs > len) ofs = len;
                                        bsLo = lastOfs;
                                        bsHi = ofs;
                                        while (bsLo < bsHi) {
                                            bsMid = (bsLo + bsHi) >> 1;
                                            if (compare(arr[base + bsMid], target) <= 0) {
                                                bsLo = bsMid + 1;
                                            } else {
                                                bsHi = bsMid;
                                            }
                                        }
                                        gallopK = len - bsLo;
                                    }
                                    
                                    for (copyI = 0; copyI < gallopK; copyI++) {
                                        arr[d - copyI] = arr[pa - copyI];
                                    }
                                    d -= gallopK;
                                    pa -= gallopK;
                                    ca = 0;
                                    minGallop += (gallopK < MIN_GALLOP ? 1 : 0) - 1;
                                    if (minGallop < 1) minGallop = 1;
                                } else if (cb >= minGallop) {
                                    // 内联 gallopLeft 逻辑用于temp数组 - 完整版本
                                    target = arr[pa];
                                    base = 0;
                                    len = pb + 1;
                                    gallopK = len;
                                    
                                    if (len == 0 || compare(tempArray[base], target) > 0) {
                                        gallopK = len;
                                    } else {
                                        ofs = 1;
                                        lastOfs = 0;
                                        while (ofs < len && compare(tempArray[base + ofs], target) <= 0) {
                                            lastOfs = ofs;
                                            ofs = (ofs << 1) + 1;
                                            if (ofs <= 0) ofs = len;
                                        }
                                        if (ofs > len) ofs = len;
                                        bsLo = lastOfs;
                                        bsHi = ofs;
                                        while (bsLo < bsHi) {
                                            bsMid = (bsLo + bsHi) >> 1;
                                            if (compare(tempArray[base + bsMid], target) <= 0) {
                                                bsLo = bsMid + 1;
                                            } else {
                                                bsHi = bsMid;
                                            }
                                        }
                                        gallopK = len - bsLo;
                                    }
                                    
                                    for (copyI = 0; copyI < gallopK; copyI++) {
                                        arr[d - copyI] = tempArray[pb - copyI];
                                    }
                                    d -= gallopK;
                                    pb -= gallopK;
                                    cb = 0;
                                    minGallop += (gallopK < MIN_GALLOP ? 1 : 0) - 1;
                                    if (minGallop < 1) minGallop = 1;
                                } else {
                                    while (pa >= ba0 && pb >= 0 && ca < minGallop && cb < minGallop) {
                                        if (compare(arr[pa], tempArray[pb]) > 0) {
                                            arr[d--] = arr[pa--];
                                            ca++;
                                            cb = 0;
                                        } else {
                                            arr[d--] = tempArray[pb--];
                                            cb++;
                                            ca = 0;
                                        }
                                    }
                                }
                            }
                            
                            for (copyI = 0; copyI <= pb; copyI++) {
                                arr[d - copyI] = tempArray[pb - copyI];
                            }
                        }
                    }
                }
                
                size = stackSize;
            }
            
            lo += runLength;
            remaining -= runLength;
        }
        
        // 内联 _mergeForceCollapse - 完整版本
        while (stackSize > 1) {
            var forceIdx:Number = (stackSize > 2 && runLen[stackSize - 3] < runLen[stackSize - 1])
                ? stackSize - 3
                : stackSize - 2;
            
            // 完整内联 _mergeAt 逻辑（与上面相同的完整实现）
            loA = runBase[forceIdx];
            lenA = runLen[forceIdx];
            loB = runBase[forceIdx + 1];
            lenB = runLen[forceIdx + 1];
            
            runLen[forceIdx] = lenA + lenB;
            
            mergeN = stackSize - 1;
            for (mergeJ = forceIdx + 1; mergeJ < mergeN; mergeJ++) {
                runBase[mergeJ] = runBase[mergeJ + 1];
                runLen[mergeJ] = runLen[mergeJ + 1];
            }
            stackSize--;
            
            // 完整的gallopRight逻辑
            gallopK = 0;
            target = arr[loB];
            base = loA;
            len = lenA;
            
            if (len == 0 || compare(arr[base], target) >= 0) {
                gallopK = 0;
            } else {
                ofs = 1;
                lastOfs = 0;
                while (ofs < len && compare(arr[base + ofs], target) < 0) {
                    lastOfs = ofs;
                    ofs = (ofs << 1) + 1;
                    if (ofs <= 0) ofs = len;
                }
                if (ofs > len) ofs = len;
                bsLo = lastOfs;
                bsHi = ofs;
                while (bsLo < bsHi) {
                    bsMid = (bsLo + bsHi) >> 1;
                    if (compare(arr[base + bsMid], target) < 0) {
                        bsLo = bsMid + 1;
                    } else {
                        bsHi = bsMid;
                    }
                }
                gallopK = bsLo;
            }
            
            if (gallopK == lenA) {
                // 无需合并，直接继续
            } else {
                loA += gallopK;
                lenA -= gallopK;
                
                // 完整的gallopLeft逻辑
                gallopK2 = 0;
                target = arr[loA + lenA - 1];
                base = loB;
                len = lenB;
                
                if (len == 0 || compare(arr[base], target) > 0) {
                    gallopK2 = 0;
                } else {
                    ofs = 1;
                    lastOfs = 0;
                    while (ofs < len && compare(arr[base + ofs], target) <= 0) {
                        lastOfs = ofs;
                        ofs = (ofs << 1) + 1;
                        if (ofs <= 0) ofs = len;
                    }
                    if (ofs > len) ofs = len;
                    bsLo = lastOfs;
                    bsHi = ofs;
                    while (bsLo < bsHi) {
                        bsMid = (bsLo + bsHi) >> 1;
                        if (compare(arr[base + bsMid], target) <= 0) {
                            bsLo = bsMid + 1;
                        } else {
                            bsHi = bsMid;
                        }
                    }
                    gallopK2 = bsLo;
                }
                
                if (gallopK2 == 0) {
                    // 无需合并，直接继续
                } else {
                    lenB = gallopK2;
                    
                    // 完整的合并逻辑（与上面_mergeCollapse中完全相同）
                    if (lenA <= lenB) {
                        // 完整的mergeLo
                        pa = 0;
                        pb = loB;
                        d = loA;
                        ea = lenA;
                        eb = loB + lenB;
                        ca = 0;
                        cb = 0;
                        
                        for (copyI = 0; copyI < lenA; copyI++) {
                            tempArray[copyI] = arr[loA + copyI];
                        }
                        
                        while (pa < ea && pb < eb && ca < minGallop && cb < minGallop) {
                            if (compare(tempArray[pa], arr[pb]) <= 0) {
                                arr[d++] = tempArray[pa++];
                                ca++;
                                cb = 0;
                            } else {
                                arr[d++] = arr[pb++];
                                cb++;
                                ca = 0;
                            }
                        }
                        
                        while (pa < ea && pb < eb) {
                            if (ca >= minGallop) {
                                target = tempArray[pa];
                                base = pb;
                                len = eb - pb;
                                gallopK = 0;
                                
                                if (len == 0 || compare(arr[base], target) >= 0) {
                                    gallopK = 0;
                                } else {
                                    ofs = 1;
                                    lastOfs = 0;
                                    while (ofs < len && compare(arr[base + ofs], target) < 0) {
                                        lastOfs = ofs;
                                        ofs = (ofs << 1) + 1;
                                        if (ofs <= 0) ofs = len;
                                    }
                                    if (ofs > len) ofs = len;
                                    bsLo = lastOfs;
                                    bsHi = ofs;
                                    while (bsLo < bsHi) {
                                        bsMid = (bsLo + bsHi) >> 1;
                                        if (compare(arr[base + bsMid], target) < 0) {
                                            bsLo = bsMid + 1;
                                        } else {
                                            bsHi = bsMid;
                                        }
                                    }
                                    gallopK = bsLo;
                                }
                                
                                for (copyI = 0; copyI < gallopK; copyI++) {
                                    arr[d + copyI] = arr[pb + copyI];
                                }
                                d += gallopK;
                                pb += gallopK;
                                ca = 0;
                                minGallop += (gallopK < MIN_GALLOP ? 1 : 0) - 1;
                                if (minGallop < 1) minGallop = 1;
                            } else if (cb >= minGallop) {
                                target = arr[pb];
                                base = pa;
                                len = ea - pa;
                                gallopK = 0;
                                
                                if (len == 0 || compare(tempArray[base], target) > 0) {
                                    gallopK = 0;
                                } else {
                                    ofs = 1;
                                    lastOfs = 0;
                                    while (ofs < len && compare(tempArray[base + ofs], target) <= 0) {
                                        lastOfs = ofs;
                                        ofs = (ofs << 1) + 1;
                                        if (ofs <= 0) ofs = len;
                                    }
                                    if (ofs > len) ofs = len;
                                    bsLo = lastOfs;
                                    bsHi = ofs;
                                    while (bsLo < bsHi) {
                                        bsMid = (bsLo + bsHi) >> 1;
                                        if (compare(tempArray[base + bsMid], target) <= 0) {
                                            bsLo = bsMid + 1;
                                        } else {
                                            bsHi = bsMid;
                                        }
                                    }
                                    gallopK = bsLo;
                                }
                                
                                for (copyI = 0; copyI < gallopK; copyI++) {
                                    arr[d + copyI] = tempArray[pa + copyI];
                                }
                                d += gallopK;
                                pa += gallopK;
                                cb = 0;
                                minGallop += (gallopK < MIN_GALLOP ? 1 : 0) - 1;
                                if (minGallop < 1) minGallop = 1;
                            } else {
                                while (pa < ea && pb < eb && ca < minGallop && cb < minGallop) {
                                    if (compare(tempArray[pa], arr[pb]) <= 0) {
                                        arr[d++] = tempArray[pa++];
                                        ca++;
                                        cb = 0;
                                    } else {
                                        arr[d++] = arr[pb++];
                                        cb++;
                                        ca = 0;
                                    }
                                }
                            }
                        }
                        
                        for (copyI = 0; copyI < ea - pa; copyI++) {
                            arr[d + copyI] = tempArray[pa + copyI];
                        }
                    } else {
                        // 完整的mergeHi
                        pa = loA + lenA - 1;
                        pb = lenB - 1;
                        d = loB + lenB - 1;
                        ba0 = loA;
                        cb = 0;
                        ca = 0;
                        
                        for (copyI = 0; copyI < lenB; copyI++) {
                            tempArray[copyI] = arr[loB + copyI];
                        }
                        
                        while (pa >= ba0 && pb >= 0 && ca < minGallop && cb < minGallop) {
                            if (compare(arr[pa], tempArray[pb]) > 0) {
                                arr[d--] = arr[pa--];
                                ca++;
                                cb = 0;
                            } else {
                                arr[d--] = tempArray[pb--];
                                cb++;
                                ca = 0;
                            }
                        }
                        
                        while (pa >= ba0 && pb >= 0) {
                            if (ca >= minGallop) {
                                target = tempArray[pb];
                                base = ba0;
                                len = pa - ba0 + 1;
                                gallopK = len;
                                
                                if (len == 0 || compare(arr[base], target) > 0) {
                                    gallopK = len;
                                } else {
                                    ofs = 1;
                                    lastOfs = 0;
                                    while (ofs < len && compare(arr[base + ofs], target) <= 0) {
                                        lastOfs = ofs;
                                        ofs = (ofs << 1) + 1;
                                        if (ofs <= 0) ofs = len;
                                    }
                                    if (ofs > len) ofs = len;
                                    bsLo = lastOfs;
                                    bsHi = ofs;
                                    while (bsLo < bsHi) {
                                        bsMid = (bsLo + bsHi) >> 1;
                                        if (compare(arr[base + bsMid], target) <= 0) {
                                            bsLo = bsMid + 1;
                                        } else {
                                            bsHi = bsMid;
                                        }
                                    }
                                    gallopK = len - bsLo;
                                }
                                
                                for (copyI = 0; copyI < gallopK; copyI++) {
                                    arr[d - copyI] = arr[pa - copyI];
                                }
                                d -= gallopK;
                                pa -= gallopK;
                                ca = 0;
                                minGallop += (gallopK < MIN_GALLOP ? 1 : 0) - 1;
                                if (minGallop < 1) minGallop = 1;
                            } else if (cb >= minGallop) {
                                target = arr[pa];
                                base = 0;
                                len = pb + 1;
                                gallopK = len;
                                
                                if (len == 0 || compare(tempArray[base], target) > 0) {
                                    gallopK = len;
                                } else {
                                    ofs = 1;
                                    lastOfs = 0;
                                    while (ofs < len && compare(tempArray[base + ofs], target) <= 0) {
                                        lastOfs = ofs;
                                        ofs = (ofs << 1) + 1;
                                        if (ofs <= 0) ofs = len;
                                    }
                                    if (ofs > len) ofs = len;
                                    bsLo = lastOfs;
                                    bsHi = ofs;
                                    while (bsLo < bsHi) {
                                        bsMid = (bsLo + bsHi) >> 1;
                                        if (compare(tempArray[base + bsMid], target) <= 0) {
                                            bsLo = bsMid + 1;
                                        } else {
                                            bsHi = bsMid;
                                        }
                                    }
                                    gallopK = len - bsLo;
                                }
                                
                                for (copyI = 0; copyI < gallopK; copyI++) {
                                    arr[d - copyI] = tempArray[pb - copyI];
                                }
                                d -= gallopK;
                                pb -= gallopK;
                                cb = 0;
                                minGallop += (gallopK < MIN_GALLOP ? 1 : 0) - 1;
                                if (minGallop < 1) minGallop = 1;
                            } else {
                                while (pa >= ba0 && pb >= 0 && ca < minGallop && cb < minGallop) {
                                    if (compare(arr[pa], tempArray[pb]) > 0) {
                                        arr[d--] = arr[pa--];
                                        ca++;
                                        cb = 0;
                                    } else {
                                        arr[d--] = tempArray[pb--];
                                        cb++;
                                        ca = 0;
                                    }
                                }
                            }
                        }
                        
                        for (copyI = 0; copyI <= pb; copyI++) {
                            arr[d - copyI] = tempArray[pb - copyI];
                        }
                    }
                }
            }
        }
        
        return arr;
    }
}