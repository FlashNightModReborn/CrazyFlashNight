import org.flashNight.gesh.iterator.*;
import org.flashNight.naki.DataStructures.*;

TreeSetIteratorTest.runAllTests();



start
=== testEmptyTree ===
✔ 空树中，迭代器 hasNext() 应该为 false => PASS
✔ 空树的 next() 结果应为 done=true => PASS
✔ 空树的 next() 的 value 应为 undefined => PASS

=== testSingleElement ===
✔ 单元素时，迭代器 hasNext() 应该为 true => PASS
✔ 获取到第一个元素时，应 done=false => PASS
✔ 返回的元素值应为 42 => PASS
✔ 已经没有更多元素了，应 done=true => PASS
✔ 应返回 undefined => PASS

=== testMultipleElements ===
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与中序遍历结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与中序遍历结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与中序遍历结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与中序遍历结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与中序遍历结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与中序遍历结果一致 => PASS
✔ 迭代结束后，next() 返回的 done 应为 true => PASS
✔ 迭代结束后，value 应为 undefined => PASS

=== testDuplicateElements ===
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与中序遍历结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与中序遍历结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与中序遍历结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与中序遍历结果一致 => PASS
✔ 迭代结束后，next() 返回的 done 应为 true => PASS
✔ 迭代结束后，value 应为 undefined => PASS
✔ TreeSet size 应与唯一元素数量一致 => PASS

=== testAscendingOrderInsertion ===
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与升序插入结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与升序插入结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与升序插入结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与升序插入结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与升序插入结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与升序插入结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与升序插入结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与升序插入结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与升序插入结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与升序插入结果一致 => PASS
✔ 迭代结束后，next() 返回的 done 应为 true => PASS
✔ 迭代结束后，value 应为 undefined => PASS

=== testDescendingOrderInsertion ===
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与降序插入结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与降序插入结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与降序插入结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与降序插入结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与降序插入结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与降序插入结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与降序插入结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与降序插入结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与降序插入结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与降序插入结果一致 => PASS
✔ 迭代结束后，next() 返回的 done 应为 true => PASS
✔ 迭代结束后，value 应为 undefined => PASS

=== testStringElements ===
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与字符串中序遍历结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与字符串中序遍历结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与字符串中序遍历结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与字符串中序遍历结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与字符串中序遍历结果一致 => PASS
✔ 迭代结束后，next() 返回的 done 应为 true => PASS
✔ 迭代结束后，value 应为 undefined => PASS

=== testNegativeAndFloatingNumbers ===
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与负数和浮点数中序遍历结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与负数和浮点数中序遍历结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与负数和浮点数中序遍历结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与负数和浮点数中序遍历结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与负数和浮点数中序遍历结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与负数和浮点数中序遍历结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与负数和浮点数中序遍历结果一致 => PASS
✔ 迭代结束后，next() 返回的 done 应为 true => PASS
✔ 迭代结束后，value 应为 undefined => PASS

=== testModificationDuringIteration ===
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与中序遍历结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与中序遍历结果一致 => PASS
Inserted 6 into TreeSet during iteration.
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与中序遍历结果一致 => PASS
Removed 1 from TreeSet during iteration.
✔ TreeSet 最终长度应为 5 => PASS
✔ TreeSet 最终元素应为 2 => PASS
✔ TreeSet 最终元素应为 3 => PASS
✔ TreeSet 最终元素应为 4 => PASS
✔ TreeSet 最终元素应为 5 => PASS
✔ TreeSet 最终元素应为 6 => PASS

=== testMultipleIterators ===
✔ it1 应在最后一次返回 done=false (迭代未结束) => PASS
✔ it2 应在最后一次返回 done=false (迭代未结束) => PASS
✔ it1 迭代获取值应与预期一致 => PASS
✔ it2 迭代获取值应与预期一致 => PASS
✔ it1 应在最后一次返回 done=false (迭代未结束) => PASS
✔ it2 应在最后一次返回 done=false (迭代未结束) => PASS
✔ it1 迭代获取值应与预期一致 => PASS
✔ it2 迭代获取值应与预期一致 => PASS
✔ it1 应在最后一次返回 done=false (迭代未结束) => PASS
✔ it2 应在最后一次返回 done=false (迭代未结束) => PASS
✔ it1 迭代获取值应与预期一致 => PASS
✔ it2 迭代获取值应与预期一致 => PASS
✔ it1 应在最后一次返回 done=false (迭代未结束) => PASS
✔ it2 应在最后一次返回 done=false (迭代未结束) => PASS
✔ it1 迭代获取值应与预期一致 => PASS
✔ it2 迭代获取值应与预期一致 => PASS
✔ it1 应在最后一次返回 done=false (迭代未结束) => PASS
✔ it2 应在最后一次返回 done=false (迭代未结束) => PASS
✔ it1 迭代获取值应与预期一致 => PASS
✔ it2 迭代获取值应与预期一致 => PASS
✔ it1 应在最后一次返回 done=false (迭代未结束) => PASS
✔ it2 应在最后一次返回 done=false (迭代未结束) => PASS
✔ it1 迭代获取值应与预期一致 => PASS
✔ it2 迭代获取值应与预期一致 => PASS
✔ it1 应在最后一次返回 done=false (迭代未结束) => PASS
✔ it2 应在最后一次返回 done=false (迭代未结束) => PASS
✔ it1 迭代获取值应与预期一致 => PASS
✔ it2 迭代获取值应与预期一致 => PASS
✔ it1 应在最后一次返回 done=false (迭代未结束) => PASS
✔ it2 应在最后一次返回 done=false (迭代未结束) => PASS
✔ it1 迭代获取值应与预期一致 => PASS
✔ it2 迭代获取值应与预期一致 => PASS
✔ it1 应在最后一次返回 done=false (迭代未结束) => PASS
✔ it2 应在最后一次返回 done=false (迭代未结束) => PASS
✔ it1 迭代获取值应与预期一致 => PASS
✔ it2 迭代获取值应与预期一致 => PASS
✔ it1 应在最后一次返回 done=false (迭代未结束) => PASS
✔ it2 应在最后一次返回 done=false (迭代未结束) => PASS
✔ it1 迭代获取值应与预期一致 => PASS
✔ it2 迭代获取值应与预期一致 => PASS
✔ it1 迭代结束后，next() 返回的 done 应为 true => PASS
✔ it1 迭代结束后，value 应为 undefined => PASS
✔ it2 迭代结束后，next() 返回的 done 应为 true => PASS
✔ it2 迭代结束后，value 应为 undefined => PASS

=== testMultipleTraversals ===
✔ 第一次遍历中，应在最后一次返回 done=false (迭代未结束) => PASS
✔ 第一次遍历获取值应与预期一致 => PASS
✔ 第一次遍历中，应在最后一次返回 done=false (迭代未结束) => PASS
✔ 第一次遍历获取值应与预期一致 => PASS
✔ 第一次遍历中，应在最后一次返回 done=false (迭代未结束) => PASS
✔ 第一次遍历获取值应与预期一致 => PASS
✔ 第一次遍历中，应在最后一次返回 done=false (迭代未结束) => PASS
✔ 第一次遍历获取值应与预期一致 => PASS
✔ 第一次遍历中，应在最后一次返回 done=false (迭代未结束) => PASS
✔ 第一次遍历获取值应与预期一致 => PASS
✔ 第一次遍历结束后，next() 返回的 done 应为 true => PASS
✔ 第一次遍历结束后，value 应为 undefined => PASS
✔ 第二次遍历中，应在最后一次返回 done=false (迭代未结束) => PASS
✔ 第二次遍历获取值应与预期一致 => PASS
✔ 第二次遍历中，应在最后一次返回 done=false (迭代未结束) => PASS
✔ 第二次遍历获取值应与预期一致 => PASS
✔ 第二次遍历中，应在最后一次返回 done=false (迭代未结束) => PASS
✔ 第二次遍历获取值应与预期一致 => PASS
✔ 第二次遍历中，应在最后一次返回 done=false (迭代未结束) => PASS
✔ 第二次遍历获取值应与预期一致 => PASS
✔ 第二次遍历中，应在最后一次返回 done=false (迭代未结束) => PASS
✔ 第二次遍历获取值应与预期一致 => PASS
✔ 第二次遍历结束后，next() 返回的 done 应为 true => PASS
✔ 第二次遍历结束后，value 应为 undefined => PASS

=== testDeletionDuringTraversal ===
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与中序遍历结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与中序遍历结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与中序遍历结果一致 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与中序遍历结果一致 => PASS
Removed 4 from TreeSet during iteration.
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与中序遍历结果一致 => PASS
✔ 迭代结束后，next() 返回的 done 应为 true => PASS
✔ 迭代结束后，value 应为 undefined => PASS
✔ TreeSet 最终长度应为 4 => PASS
✔ TreeSet 最终元素应为 1 => PASS
✔ TreeSet 最终元素应为 2 => PASS
✔ TreeSet 最终元素应为 3 => PASS
✔ TreeSet 最终元素应为 5 => PASS

=== testDifferentTypesSameValue ===
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与中序遍历结果一致，处理不同类型的相同值 => PASS
✔ 应在最后一次返回 done=false (迭代未结束) => PASS
✔ 迭代获取值应与中序遍历结果一致，处理不同类型的相同值 => PASS
✔ 迭代结束后，next() 返回的 done 应为 true => PASS
✔ 迭代结束后，value 应为 undefined => PASS
✔ TreeSet size 应与唯一元素数量一致 => PASS

=== testPerformance (numElements=10000) ===
迭代完成，耗时: 101 ms, 计数: 10000
✔ 遍历计数应与插入数相同, count=10000 vs numElements=10000 => PASS

=== testPerformance (numElements=100000) ===
迭代完成，耗时: 1157 ms, 计数: 100000
✔ 遍历计数应与插入数相同, count=100000 vs numElements=100000 => PASS

=== testIteratorStability ===
✔ 前半部分第 1 个元素应为 1 => PASS
✔ 前半部分第 2 个元素应为 2 => PASS
✔ 前半部分第 3 个元素应为 3 => PASS
✔ 前半部分第 4 个元素应为 4 => PASS
✔ 前半部分第 5 个元素应为 5 => PASS
✔ 前半部分第 6 个元素应为 6 => PASS
✔ 前半部分第 7 个元素应为 7 => PASS
✔ 前半部分第 8 个元素应为 8 => PASS
✔ 前半部分第 9 个元素应为 9 => PASS
✔ 前半部分第 10 个元素应为 10 => PASS
✔ 前半部分第 11 个元素应为 11 => PASS
✔ 前半部分第 12 个元素应为 12 => PASS
✔ 前半部分第 13 个元素应为 13 => PASS
✔ 前半部分第 14 个元素应为 14 => PASS
✔ 前半部分第 15 个元素应为 15 => PASS
✔ 前半部分第 16 个元素应为 16 => PASS
✔ 前半部分第 17 个元素应为 17 => PASS
✔ 前半部分第 18 个元素应为 18 => PASS
✔ 前半部分第 19 个元素应为 19 => PASS
✔ 前半部分第 20 个元素应为 20 => PASS
✔ 前半部分第 21 个元素应为 21 => PASS
✔ 前半部分第 22 个元素应为 22 => PASS
✔ 前半部分第 23 个元素应为 23 => PASS
✔ 前半部分第 24 个元素应为 24 => PASS
✔ 前半部分第 25 个元素应为 25 => PASS
✔ 前半部分第 26 个元素应为 26 => PASS
✔ 前半部分第 27 个元素应为 27 => PASS
✔ 前半部分第 28 个元素应为 28 => PASS
✔ 前半部分第 29 个元素应为 29 => PASS
✔ 前半部分第 30 个元素应为 30 => PASS
✔ 前半部分第 31 个元素应为 31 => PASS
✔ 前半部分第 32 个元素应为 32 => PASS
✔ 前半部分第 33 个元素应为 33 => PASS
✔ 前半部分第 34 个元素应为 34 => PASS
✔ 前半部分第 35 个元素应为 35 => PASS
✔ 前半部分第 36 个元素应为 36 => PASS
✔ 前半部分第 37 个元素应为 37 => PASS
✔ 前半部分第 38 个元素应为 38 => PASS
✔ 前半部分第 39 个元素应为 39 => PASS
✔ 前半部分第 40 个元素应为 40 => PASS
✔ 前半部分第 41 个元素应为 41 => PASS
✔ 前半部分第 42 个元素应为 42 => PASS
✔ 前半部分第 43 个元素应为 43 => PASS
✔ 前半部分第 44 个元素应为 44 => PASS
✔ 前半部分第 45 个元素应为 45 => PASS
✔ 前半部分第 46 个元素应为 46 => PASS
✔ 前半部分第 47 个元素应为 47 => PASS
✔ 前半部分第 48 个元素应为 48 => PASS
✔ 前半部分第 49 个元素应为 49 => PASS
✔ 前半部分第 50 个元素应为 50 => PASS
✔ 后半部分第 1 个元素应为 51 => PASS
✔ 后半部分第 2 个元素应为 52 => PASS
✔ 后半部分第 3 个元素应为 53 => PASS
✔ 后半部分第 4 个元素应为 54 => PASS
✔ 后半部分第 5 个元素应为 55 => PASS
✔ 后半部分第 6 个元素应为 56 => PASS
✔ 后半部分第 7 个元素应为 57 => PASS
✔ 后半部分第 8 个元素应为 58 => PASS
✔ 后半部分第 9 个元素应为 59 => PASS
✔ 后半部分第 10 个元素应为 60 => PASS
✔ 后半部分第 11 个元素应为 61 => PASS
✔ 后半部分第 12 个元素应为 62 => PASS
✔ 后半部分第 13 个元素应为 63 => PASS
✔ 后半部分第 14 个元素应为 64 => PASS
✔ 后半部分第 15 个元素应为 65 => PASS
✔ 后半部分第 16 个元素应为 66 => PASS
✔ 后半部分第 17 个元素应为 67 => PASS
✔ 后半部分第 18 个元素应为 68 => PASS
✔ 后半部分第 19 个元素应为 69 => PASS
✔ 后半部分第 20 个元素应为 70 => PASS
✔ 后半部分第 21 个元素应为 71 => PASS
✔ 后半部分第 22 个元素应为 72 => PASS
✔ 后半部分第 23 个元素应为 73 => PASS
✔ 后半部分第 24 个元素应为 74 => PASS
✔ 后半部分第 25 个元素应为 75 => PASS
✔ 后半部分第 26 个元素应为 76 => PASS
✔ 后半部分第 27 个元素应为 77 => PASS
✔ 后半部分第 28 个元素应为 78 => PASS
✔ 后半部分第 29 个元素应为 79 => PASS
✔ 后半部分第 30 个元素应为 80 => PASS
✔ 后半部分第 31 个元素应为 81 => PASS
✔ 后半部分第 32 个元素应为 82 => PASS
✔ 后半部分第 33 个元素应为 83 => PASS
✔ 后半部分第 34 个元素应为 84 => PASS
✔ 后半部分第 35 个元素应为 85 => PASS
✔ 后半部分第 36 个元素应为 86 => PASS
✔ 后半部分第 37 个元素应为 87 => PASS
✔ 后半部分第 38 个元素应为 88 => PASS
✔ 后半部分第 39 个元素应为 89 => PASS
✔ 后半部分第 40 个元素应为 90 => PASS
✔ 后半部分第 41 个元素应为 91 => PASS
✔ 后半部分第 42 个元素应为 92 => PASS
✔ 后半部分第 43 个元素应为 93 => PASS
✔ 后半部分第 44 个元素应为 94 => PASS
✔ 后半部分第 45 个元素应为 95 => PASS
✔ 后半部分第 46 个元素应为 96 => PASS
✔ 后半部分第 47 个元素应为 97 => PASS
✔ 后半部分第 48 个元素应为 98 => PASS
✔ 后半部分第 49 个元素应为 99 => PASS
✔ 后半部分第 50 个元素应为 100 => PASS

╔══════════════════════════════════════════════════════════════╗
║           TreeSetMinimalIterator 性能测试套件                 ║
╚══════════════════════════════════════════════════════════════╝

────────────────────────────────────────────────────────────────
测试规模: 1000 个元素
────────────────────────────────────────────────────────────────
  构建 TreeSet 耗时: 37 ms
  迭代器遍历: 10 ms (count=1000)
  toArray遍历: 1 ms (length=1000)
  后继搜索(3轮半遍历): 4 ms (avg)

  ┌─────────────────────────────────────────┐
  │ 性能对比结果 (1000 元素)
  ├─────────────────────────────────────────┤
  │ 迭代器遍历:         10 ms
  │ toArray遍历:         1 ms
  │ 后继搜索测试:        4 ms
  │ 迭代器/toArray:     10 x
  └─────────────────────────────────────────┘

────────────────────────────────────────────────────────────────
测试规模: 5000 个元素
────────────────────────────────────────────────────────────────
  构建 TreeSet 耗时: 170 ms
  迭代器遍历: 50 ms (count=5000)
  toArray遍历: 6 ms (length=5000)
  后继搜索(3轮半遍历): 24 ms (avg)

  ┌─────────────────────────────────────────┐
  │ 性能对比结果 (5000 元素)
  ├─────────────────────────────────────────┤
  │ 迭代器遍历:         50 ms
  │ toArray遍历:         6 ms
  │ 后继搜索测试:       24 ms
  │ 迭代器/toArray:   8.33 x
  └─────────────────────────────────────────┘

────────────────────────────────────────────────────────────────
测试规模: 10000 个元素
────────────────────────────────────────────────────────────────
  构建 TreeSet 耗时: 366 ms
  迭代器遍历: 104 ms (count=10000)
  toArray遍历: 12 ms (length=10000)
  后继搜索(3轮半遍历): 50 ms (avg)

  ┌─────────────────────────────────────────┐
  │ 性能对比结果 (10000 元素)
  ├─────────────────────────────────────────┤
  │ 迭代器遍历:        104 ms
  │ toArray遍历:        12 ms
  │ 后继搜索测试:       50 ms
  │ 迭代器/toArray:   8.67 x
  └─────────────────────────────────────────┘

────────────────────────────────────────────────────────────────
测试规模: 50000 个元素
────────────────────────────────────────────────────────────────
  构建 TreeSet 耗时: 2144 ms
  迭代器遍历: 583 ms (count=50000)
  toArray遍历: 71 ms (length=50000)
  后继搜索(3轮半遍历): 290 ms (avg)

  ┌─────────────────────────────────────────┐
  │ 性能对比结果 (50000 元素)
  ├─────────────────────────────────────────┤
  │ 迭代器遍历:        583 ms
  │ toArray遍历:        71 ms
  │ 后继搜索测试:      290 ms
  │ 迭代器/toArray:   8.21 x
  └─────────────────────────────────────────┘

═══════════════════ 性能测试完成 ═══════════════════
All tests completed successfully!
