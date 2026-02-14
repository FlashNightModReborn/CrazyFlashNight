/**
 * TIMSORT_MERGE_INDIRECT.as - TimSort 间接排序合并逻辑宏
 *
 * 从 TIMSORT_MERGE.as 机械变换：所有 compare(A,B) OP 0 替换为 keys[A] OP keys[B]
 * 通过 #include 内联到 sortIndirect() 函数中，实现：
 * - 完全消除比较器函数调用开销（内联 keys[X] OP keys[Y]）
 * - 单一维护点（mergeCollapse / forceCollapse 共享同一份源码）
 *
 * 关键洞察：keys 数组在排序期间只读，tempArray 存储的是索引值，
 * 因此 keys[tempArray[pos]] 正确访问原始键值，无需额外 tempKeys。
 *
 * 前置条件（调用方需在 #include 前设置）:
 *   loA, lenA - A run 的起始位置和长度
 *   loB, lenB - B run 的起始位置和长度
 *   loB == loA + lenA, 两段各自已排序
 *
 * 使用 sortIndirect() 作用域中的变量:
 *   arr, keys, tempArray, minGallop, MIN_GALLOP, n
 *   gallopK, target, base, len, ofs, lastOfs, left, hi2, mid
 *   pa, pb, d, ea, eb, ca, cb, ba0, tmp, i, j
 *   copyLen, copyI, copyIdx, copyEnd, tempIdx
 */
do {

// ---- gallopRight: 在A中找B[0]的插入位置（upper_bound），裁剪A前缀 ----
gallopK = 0;
target = keys[arr[loB]];
base = loA;
len = lenA;
if (keys[arr[base]] <= target) {
    ofs = 1; lastOfs = 0;
    while (ofs < len && keys[arr[base + ofs]] <= target) {
        lastOfs = ofs; ofs = (ofs << 1) + 1;
        if (ofs <= 0) ofs = len;
    }
    if (ofs > len) ofs = len;
    left = lastOfs; hi2 = ofs;
    while (left < hi2) {
        mid = (left + hi2) >> 1;
        if (keys[arr[base + mid]] <= target) left = mid + 1;
        else hi2 = mid;
    }
    gallopK = left;
}
if (gallopK == lenA) break;
loA += gallopK;
lenA -= gallopK;

// ---- gallopLeft: 在B中找A[last]的插入位置（lower_bound），裁剪B尾部 ----
// P1 fix: 从RIGHT搜索，因为A[last]大，答案接近B右端
target = keys[arr[loA + lenA - 1]];
base = loB;
len = lenB;
if (keys[arr[base + len - 1]] < target) {
    gallopK = len;
} else if (keys[arr[base]] >= target) {
    gallopK = 0;
} else {
    ofs = 1; lastOfs = 0;
    while (ofs < len && keys[arr[base + len - 1 - ofs]] >= target) {
        lastOfs = ofs; ofs = (ofs << 1) + 1;
        if (ofs <= 0) ofs = len;
    }
    if (ofs > len) ofs = len;
    left = lastOfs; hi2 = ofs;
    while (left < hi2) {
        mid = (left + hi2) >> 1;
        if (keys[arr[base + len - 1 - mid]] >= target) left = mid + 1;
        else hi2 = mid;
    }
    gallopK = len - left;
}
if (gallopK == 0) break;
lenB = gallopK;

// ---- 单元素快速路径 ----
if (lenA == 1) {
    tmp = arr[loA];
    target = keys[tmp];
    left = 0; hi2 = lenB;
    while (left < hi2) {
        mid = (left + hi2) >> 1;
        if (keys[arr[loB + mid]] < target) left = mid + 1;
        else hi2 = mid;
    }
    for (i = 0; i < left; i++) { arr[loA + i] = arr[loB + i]; }
    arr[loA + left] = tmp;
    break;
}
if (lenB == 1) {
    tmp = arr[loB];
    target = keys[tmp];
    left = 0; hi2 = lenA;
    while (left < hi2) {
        mid = (left + hi2) >> 1;
        if (keys[arr[loA + mid]] <= target) left = mid + 1;
        else hi2 = mid;
    }
    for (j = lenA - 1; j >= left; j--) { arr[loA + j + 1] = arr[loA + j]; }
    arr[loA + left] = tmp;
    break;
}

// ---- 延迟分配临时数组 ----
if (tempArray == null) {
    tempArray = new Array((n + 1) >> 1);
    _workspace = tempArray; _wsLen = tempArray.length;
}

// ======================================================================
//  mergeLo / mergeHi 分支
// ======================================================================
if (lenA <= lenB) {
    // ============ mergeLo: 复制A到tempArray，从左到右合并 ============
    pa = 0; pb = loB; d = loA; ea = lenA; eb = loB + lenB;

    // 复制A到临时数组（×4展开）
    copyEnd = lenA - (lenA & 3);
    for (copyI = 0; copyI < copyEnd; copyI += 4) {
        tempArray[copyI]     = arr[copyIdx = loA + copyI];
        tempArray[copyI + 1] = arr[copyIdx + 1];
        tempArray[copyI + 2] = arr[copyIdx + 2];
        tempArray[copyI + 3] = arr[copyIdx + 3];
    }
    for (; copyI < lenA; copyI++) { tempArray[copyI] = arr[loA + copyI]; }

    // P3: 哨兵搬运 - pre-trim保证B[loB] < A[loA]，B首元素必先输出
    // 此后 pa < ea (lenA>=2) 且 pb < eb (lenB-1>=1)，do-while安全
    arr[d++] = arr[pb++];

    // === P0: 标准双阶段合并 ===
    do {
        // Phase 1: one-at-a-time (P1: keyA/keyB缓存，消除败者侧重复键查找)
        ca = 0; cb = 0;
        keyA = keys[tempArray[pa]];
        keyB = keys[arr[pb]];
        do {
            if (keyA <= keyB) {
                arr[d++] = tempArray[pa];
                if (++pa >= ea) break;
                keyA = keys[tempArray[pa]];
                ca++; cb = 0;
                if (ca >= minGallop) break;
            } else {
                arr[d++] = arr[pb];
                if (++pb >= eb) break;
                keyB = keys[arr[pb]];
                cb++; ca = 0;
                if (cb >= minGallop) break;
            }
        } while (true);
        if (pa >= ea || pb >= eb) break;

        // Phase 2: galloping (do-while)
        do {
            // A-gallop: gallopRight in tempArray for arr[pb]
            target = keys[arr[pb]];
            base = pa; len = ea - pa;
            ca = 0;
            if (keys[tempArray[base]] <= target) {
                ofs = 1; lastOfs = 0;
                while (ofs < len && keys[tempArray[base + ofs]] <= target) {
                    lastOfs = ofs; ofs = (ofs << 1) + 1;
                    if (ofs <= 0) ofs = len;
                }
                if (ofs > len) ofs = len;
                left = lastOfs; hi2 = ofs;
                while (left < hi2) {
                    mid = (left + hi2) >> 1;
                    if (keys[tempArray[base + mid]] <= target) left = mid + 1;
                    else hi2 = mid;
                }
                ca = left;
            }
            // batch copy ca elements from A
            copyEnd = ca - (ca & 3);
            for (copyI = 0; copyI < copyEnd; copyI += 4) {
                arr[tempIdx = d + copyI] = tempArray[copyIdx = pa + copyI];
                arr[tempIdx + 1] = tempArray[copyIdx + 1];
                arr[tempIdx + 2] = tempArray[copyIdx + 2];
                arr[tempIdx + 3] = tempArray[copyIdx + 3];
            }
            for (; copyI < ca; copyI++) { arr[d + copyI] = tempArray[pa + copyI]; }
            d += ca; pa += ca;
            if (pa >= ea) break;
            // copy 1 B trigger element
            arr[d++] = arr[pb++];
            if (pb >= eb) break;

            // B-gallop: gallopLeft in arr for tempArray[pa]
            target = keys[tempArray[pa]];
            base = pb; len = eb - pb;
            cb = 0;
            if (keys[arr[base]] < target) {
                ofs = 1; lastOfs = 0;
                while (ofs < len && keys[arr[base + ofs]] < target) {
                    lastOfs = ofs; ofs = (ofs << 1) + 1;
                    if (ofs <= 0) ofs = len;
                }
                if (ofs > len) ofs = len;
                left = lastOfs; hi2 = ofs;
                while (left < hi2) {
                    mid = (left + hi2) >> 1;
                    if (keys[arr[base + mid]] < target) left = mid + 1;
                    else hi2 = mid;
                }
                cb = left;
            }
            // batch copy cb elements from B
            copyEnd = cb - (cb & 3);
            for (copyI = 0; copyI < copyEnd; copyI += 4) {
                arr[copyIdx = d + copyI] = arr[tempIdx = pb + copyI];
                arr[copyIdx + 1] = arr[tempIdx + 1];
                arr[copyIdx + 2] = arr[tempIdx + 2];
                arr[copyIdx + 3] = arr[tempIdx + 3];
            }
            for (; copyI < cb; copyI++) { arr[d + copyI] = arr[pb + copyI]; }
            d += cb; pb += cb;
            if (pb >= eb) break;
            // copy 1 A trigger element
            arr[d++] = tempArray[pa++];
            if (pa >= ea) break;

            --minGallop;
        } while (ca >= MIN_GALLOP || cb >= MIN_GALLOP);

        if (pa >= ea || pb >= eb) break;
        if (minGallop < 0) minGallop = 0;
        minGallop += 2; // penalty for leaving gallop mode
    } while (pa < ea && pb < eb);

    // remainder: copy leftover A
    copyLen = ea - pa;
    copyEnd = copyLen - (copyLen & 3);
    for (copyI = 0; copyI < copyEnd; copyI += 4) {
        arr[tempIdx = d + copyI] = tempArray[copyIdx = pa + copyI];
        arr[tempIdx + 1] = tempArray[copyIdx + 1];
        arr[tempIdx + 2] = tempArray[copyIdx + 2];
        arr[tempIdx + 3] = tempArray[copyIdx + 3];
    }
    for (; copyI < copyLen; copyI++) { arr[d + copyI] = tempArray[pa + copyI]; }

} else {
    // ============ mergeHi: 复制B到tempArray，从右到左合并 ============
    pa = loA + lenA - 1; pb = lenB - 1; d = loB + lenB - 1; ba0 = loA;

    // 复制B到临时数组（×4展开）
    copyEnd = lenB - (lenB & 3);
    for (copyI = 0; copyI < copyEnd; copyI += 4) {
        tempArray[copyI]     = arr[copyIdx = loB + copyI];
        tempArray[copyI + 1] = arr[copyIdx + 1];
        tempArray[copyI + 2] = arr[copyIdx + 2];
        tempArray[copyI + 3] = arr[copyIdx + 3];
    }
    for (; copyI < lenB; copyI++) { tempArray[copyI] = arr[loB + copyI]; }

    // P3: 哨兵搬运 - pre-trim保证A[last] > B[last]，A尾元素必先输出
    // 此后 pa >= ba0 (lenA-1>=1) 且 pb >= 0 (lenB>=2)，do-while安全
    arr[d--] = arr[pa--];

    // === P0: 标准双阶段合并（反向） ===
    do {
        // Phase 1: one-at-a-time (right to left, P1: keyA/keyB缓存)
        ca = 0; cb = 0;
        keyA = keys[arr[pa]];
        keyB = keys[tempArray[pb]];
        do {
            if (keyA > keyB) {
                arr[d--] = arr[pa];
                if (--pa < ba0) break;
                keyA = keys[arr[pa]];
                ca++; cb = 0;
                if (ca >= minGallop) break;
            } else {
                arr[d--] = tempArray[pb];
                if (--pb < 0) break;
                keyB = keys[tempArray[pb]];
                cb++; ca = 0;
                if (cb >= minGallop) break;
            }
        } while (true);
        if (pa < ba0 || pb < 0) break;

        // Phase 2: galloping (do-while, right to left)
        do {
            // A-gallop: reverse gallopRight from pa leftward
            target = keys[tempArray[pb]];
            len = pa - ba0 + 1;
            ca = 0;
            if (keys[arr[pa]] > target) {
                if (keys[arr[ba0]] > target) {
                    ca = len;
                } else {
                    ofs = 1; lastOfs = 0;
                    while (ofs < len && keys[arr[pa - ofs]] > target) {
                        lastOfs = ofs; ofs = (ofs << 1) + 1;
                        if (ofs <= 0) ofs = len;
                    }
                    if (ofs > len) ofs = len;
                    left = lastOfs; hi2 = ofs;
                    while (left < hi2) {
                        mid = (left + hi2) >> 1;
                        if (keys[arr[pa - mid]] > target) left = mid + 1;
                        else hi2 = mid;
                    }
                    ca = left;
                }
            }
            // batch copy ca elements from A (right to left)
            copyEnd = ca - (ca & 3);
            for (copyI = 0; copyI < copyEnd; copyI += 4) {
                arr[copyIdx = d - copyI]     = arr[tempIdx = pa - copyI];
                arr[copyIdx - 1] = arr[tempIdx - 1];
                arr[copyIdx - 2] = arr[tempIdx - 2];
                arr[copyIdx - 3] = arr[tempIdx - 3];
            }
            for (; copyI < ca; copyI++) { arr[d - copyI] = arr[pa - copyI]; }
            d -= ca; pa -= ca;
            if (pa < ba0) break;
            // copy 1 B trigger element
            arr[d--] = tempArray[pb--];
            if (pb < 0) break;

            // B-gallop: reverse gallopLeft in tempArray from pb leftward
            // P1 fix: search from RIGHT (pb) since answer is near pb
            target = keys[arr[pa]];
            len = pb + 1;
            cb = 0;
            if (keys[tempArray[pb]] >= target) {
                if (keys[tempArray[0]] >= target) {
                    cb = len;
                } else {
                    ofs = 1; lastOfs = 0;
                    while (ofs < len && keys[tempArray[pb - ofs]] >= target) {
                        lastOfs = ofs; ofs = (ofs << 1) + 1;
                        if (ofs <= 0) ofs = len;
                    }
                    if (ofs > len) ofs = len;
                    left = lastOfs; hi2 = ofs;
                    while (left < hi2) {
                        mid = (left + hi2) >> 1;
                        if (keys[tempArray[pb - mid]] >= target) left = mid + 1;
                        else hi2 = mid;
                    }
                    cb = left;
                }
            }
            // batch copy cb elements from B (right to left)
            copyEnd = cb - (cb & 3);
            for (copyI = 0; copyI < copyEnd; copyI += 4) {
                arr[copyIdx = d - copyI]     = tempArray[tempIdx = pb - copyI];
                arr[copyIdx - 1] = tempArray[tempIdx - 1];
                arr[copyIdx - 2] = tempArray[tempIdx - 2];
                arr[copyIdx - 3] = tempArray[tempIdx - 3];
            }
            for (; copyI < cb; copyI++) { arr[d - copyI] = tempArray[pb - copyI]; }
            d -= cb; pb -= cb;
            if (pb < 0) break;
            // copy 1 A trigger element
            arr[d--] = arr[pa--];
            if (pa < ba0) break;

            --minGallop;
        } while (ca >= MIN_GALLOP || cb >= MIN_GALLOP);

        if (pa < ba0 || pb < 0) break;
        if (minGallop < 0) minGallop = 0;
        minGallop += 2;
    } while (pa >= ba0 && pb >= 0);

    // remainder: copy leftover B
    copyLen = pb + 1;
    copyEnd = copyLen - (copyLen & 3);
    for (copyI = 0; copyI < copyEnd; copyI += 4) {
        arr[copyIdx = d - copyI]     = tempArray[tempIdx = pb - copyI];
        arr[copyIdx - 1] = tempArray[tempIdx - 1];
        arr[copyIdx - 2] = tempArray[tempIdx - 2];
        arr[copyIdx - 3] = tempArray[tempIdx - 3];
    }
    for (; copyI < copyLen; copyI++) { arr[d - copyI] = tempArray[pb - copyI]; }
}

// final clamp
if (minGallop < 1) minGallop = 1;

} while (false);
