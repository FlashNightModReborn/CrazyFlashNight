var sortTester:org.flashNight.naki.Sort.SortTest = new org.flashNight.naki.Sort.SortTest();
sortTester.runCompleteTestSuite();


================================================================================
启动增强版排序算法测试套件 
================================================================================

========================================
基础功能测试
========================================

测试: 空数组
  ✓ InsertionSort
  ✓ PDQSort
  ✓ QuickSort
  ✓ AdaptiveSort
  ✓ TimSort
  ✓ BuiltInSort
总结: 6/6 算法通过

测试: 单元素
  ✓ InsertionSort
  ✓ PDQSort
  ✓ QuickSort
  ✓ AdaptiveSort
  ✓ TimSort
  ✓ BuiltInSort
总结: 6/6 算法通过

测试: 两元素正序
  ✓ InsertionSort
  ✓ PDQSort
  ✓ QuickSort
  ✓ AdaptiveSort
  ✓ TimSort
  ✓ BuiltInSort
总结: 6/6 算法通过

测试: 两元素逆序
  ✓ InsertionSort
  ✓ PDQSort
  ✓ QuickSort
  ✓ AdaptiveSort
  ✓ TimSort
  ✓ BuiltInSort
总结: 6/6 算法通过

测试: 小型随机
  ✓ InsertionSort
  ✓ PDQSort
  ✓ QuickSort
  ✓ AdaptiveSort
  ✓ TimSort
  ✓ BuiltInSort
总结: 6/6 算法通过

测试: 负数混合
  ✓ InsertionSort
  ✓ PDQSort
  ✓ QuickSort
  ✓ AdaptiveSort
  ✓ TimSort
  ✓ BuiltInSort
总结: 6/6 算法通过

测试: 浮点数
  ✓ InsertionSort
  ✓ PDQSort
  ✓ QuickSort
  ✓ AdaptiveSort
  ✓ TimSort
  ✓ BuiltInSort
总结: 6/6 算法通过

========================================
稳定性测试 - 增强版
========================================

原始数据: [5(A1), 2(B1), 5(A2), 1(C1), 2(B2), 5(A3), 3(D1), 1(C2), 3(D2), 2(B3), 1(C3), 4(E1)]
稳定排序期望: [1(C1), 1(C2), 1(C3), 2(B1), 2(B2), 2(B3), 3(D1), 3(D2), 4(E1), 5(A1), 5(A2), 5(A3)]

InsertionSort: ✓ 稳定
  结果: [1(C1), 1(C2), 1(C3), 2(B1), 2(B2), 2(B3), 3(D1), 3(D2), 4(E1), 5(A1), 5(A2), 5(A3)]

PDQSort: ✓ 稳定
  结果: [1(C1), 1(C2), 1(C3), 2(B1), 2(B2), 2(B3), 3(D1), 3(D2), 4(E1), 5(A1), 5(A2), 5(A3)]

QuickSort: ✗ 不稳定
  结果: [1(C1), 1(C2), 1(C3), 2(B1), 2(B2), 2(B3), 3(D1), 3(D2), 4(E1), 5(A3), 5(A2), 5(A1)]
  → 稳定性违规详情:
    值 5 的相对顺序错误:
      期望: A1,A2,A3
      实际: A3,A2,A1

AdaptiveSort: ✓ 稳定
  结果: [1(C1), 1(C2), 1(C3), 2(B1), 2(B2), 2(B3), 3(D1), 3(D2), 4(E1), 5(A1), 5(A2), 5(A3)]

TimSort: ✓ 稳定
  结果: [1(C1), 1(C2), 1(C3), 2(B1), 2(B2), 2(B3), 3(D1), 3(D2), 4(E1), 5(A1), 5(A2), 5(A3)]

BuiltInSort: ✗ 不稳定
  结果: [1(C1), 1(C2), 1(C3), 2(B3), 2(B2), 2(B1), 3(D2), 3(D1), 4(E1), 5(A1), 5(A3), 5(A2)]
  → 稳定性违规详情:
    值 5 的相对顺序错误:
      期望: A1,A2,A3
      实际: A1,A3,A2
    值 3 的相对顺序错误:
      期望: D1,D2
      实际: D2,D1
    值 2 的相对顺序错误:
      期望: B1,B2,B3
      实际: B3,B2,B1

========================================
性能基准测试
========================================

--- 随机数据 ---

规模: 10
  InsertionSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  PDQSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  QuickSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  AdaptiveSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  TimSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  BuiltInSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%

规模: 50
  InsertionSort 平均:0.8ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  PDQSort 平均:0.6ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  QuickSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  AdaptiveSort 平均:0.6ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  TimSort 平均:0.6ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  BuiltInSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%

规模: 100
  InsertionSort 平均:2.2ms 最小:2.0ms 最大:3.0ms 成功率:100.0%
  PDQSort 平均:1.0ms 最小:1.0ms 最大:1.0ms 成功率:100.0%
  QuickSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  AdaptiveSort 平均:0.8ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  TimSort 平均:1.0ms 最小:1.0ms 最大:1.0ms 成功率:100.0%
  BuiltInSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%

规模: 300
  InsertionSort 平均:19.2ms 最小:18.0ms 最大:20.0ms 成功率:100.0%
  PDQSort 平均:3.6ms 最小:3.0ms 最大:4.0ms 成功率:100.0%
  QuickSort 平均:1.4ms 最小:1.0ms 最大:2.0ms 成功率:100.0%
  AdaptiveSort 平均:2.8ms 最小:2.0ms 最大:3.0ms 成功率:100.0%
  TimSort 平均:3.6ms 最小:3.0ms 最大:5.0ms 成功率:100.0%
  BuiltInSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%

规模: 1000
  InsertionSort 平均:202.2ms 最小:201.0ms 最大:204.0ms 成功率:100.0%
  PDQSort 平均:18.0ms 最小:17.0ms 最大:19.0ms 成功率:100.0%
  QuickSort 平均:4.4ms 最小:4.0ms 最大:5.0ms 成功率:100.0%
  AdaptiveSort 平均:10.8ms 最小:10.0ms 最大:11.0ms 成功率:100.0%
  TimSort 平均:15.0ms 最小:14.0ms 最大:16.0ms 成功率:100.0%
  BuiltInSort 平均:0.4ms 最小:0.0ms 最大:1.0ms 成功率:100.0%

规模: 3000
  InsertionSort 平均:1852.8ms 最小:1836.0ms 最大:1871.0ms 成功率:100.0%
  PDQSort 平均:67.6ms 最小:66.0ms 最大:69.0ms 成功率:100.0%
  QuickSort 平均:14.6ms 最小:14.0ms 最大:15.0ms 成功率:100.0%
  AdaptiveSort 平均:33.4ms 最小:33.0ms 最大:35.0ms 成功率:100.0%
  TimSort 平均:49.0ms 最小:48.0ms 最大:50.0ms 成功率:100.0%
  BuiltInSort 平均:2.0ms 最小:1.0ms 最大:3.0ms 成功率:100.0%

规模: 10000
  InsertionSort 平均:20020.2ms 最小:19869.0ms 最大:20533.0ms 成功率:100.0%
  PDQSort 平均:258.6ms 最小:256.0ms 最大:260.0ms 成功率:100.0%
  QuickSort 平均:54.8ms 最小:54.0ms 最大:56.0ms 成功率:100.0%
  AdaptiveSort 平均:128.8ms 最小:127.0ms 最大:132.0ms 成功率:100.0%
  TimSort 平均:365.6ms 最小:358.0ms 最大:376.0ms 成功率:100.0%
  BuiltInSort 平均:4.6ms 最小:4.0ms 最大:5.0ms 成功率:100.0%

--- 已排序 ---

规模: 10
  InsertionSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  PDQSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  QuickSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  AdaptiveSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  TimSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  BuiltInSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%

规模: 50
  InsertionSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  PDQSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  QuickSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  AdaptiveSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  TimSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  BuiltInSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%

规模: 100
  InsertionSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  PDQSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  QuickSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  AdaptiveSort 平均:0.6ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  TimSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  BuiltInSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%

规模: 300
  InsertionSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  PDQSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  QuickSort 平均:0.6ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  AdaptiveSort 平均:1.2ms 最小:0.0ms 最大:2.0ms 成功率:100.0%
  TimSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  BuiltInSort 平均:0.6ms 最小:0.0ms 最大:1.0ms 成功率:100.0%

规模: 1000
  InsertionSort 平均:1.0ms 最小:1.0ms 最大:1.0ms 成功率:100.0%
  PDQSort 平均:1.0ms 最小:1.0ms 最大:1.0ms 成功率:100.0%
  QuickSort 平均:2.8ms 最小:2.0ms 最大:3.0ms 成功率:100.0%
  AdaptiveSort 平均:7.2ms 最小:6.0ms 最大:8.0ms 成功率:100.0%
  TimSort 平均:0.8ms 最小:0.0ms 最大:2.0ms 成功率:100.0%
  BuiltInSort 平均:6.2ms 最小:5.0ms 最大:7.0ms 成功率:100.0%

规模: 3000
  InsertionSort 平均:2.8ms 最小:2.0ms 最大:3.0ms 成功率:100.0%
  PDQSort 平均:2.6ms 最小:2.0ms 最大:3.0ms 成功率:100.0%
  QuickSort 平均:9.0ms 最小:8.0ms 最大:10.0ms 成功率:100.0%
  AdaptiveSort 平均:22.2ms 最小:22.0ms 最大:23.0ms 成功率:100.0%
  TimSort 平均:2.2ms 最小:2.0ms 最大:3.0ms 成功率:100.0%
  BuiltInSort 平均:52.6ms 最小:52.0ms 最大:54.0ms 成功率:100.0%

规模: 10000
  InsertionSort 平均:9.2ms 最小:8.0ms 最大:10.0ms 成功率:100.0%
  PDQSort 平均:9.6ms 最小:9.0ms 最大:11.0ms 成功率:100.0%
  QuickSort 平均:37.6ms 最小:37.0ms 最大:38.0ms 成功率:100.0%
  AdaptiveSort 平均:88.4ms 最小:87.0ms 最大:89.0ms 成功率:100.0%
  TimSort 平均:7.4ms 最小:7.0ms 最大:8.0ms 成功率:100.0%
  BuiltInSort 平均:581.8ms 最小:579.0ms 最大:584.0ms 成功率:100.0%

--- 逆序 ---

规模: 10
  InsertionSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  PDQSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  QuickSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  AdaptiveSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  TimSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  BuiltInSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%

规模: 50
  InsertionSort 平均:1.0ms 最小:1.0ms 最大:1.0ms 成功率:100.0%
  PDQSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  QuickSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  AdaptiveSort 平均:1.2ms 最小:1.0ms 最大:2.0ms 成功率:100.0%
  TimSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  BuiltInSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%

规模: 100
  InsertionSort 平均:4.2ms 最小:4.0ms 最大:5.0ms 成功率:100.0%
  PDQSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  QuickSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  AdaptiveSort 平均:0.4ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  TimSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  BuiltInSort 平均:0.4ms 最小:0.0ms 最大:1.0ms 成功率:100.0%

规模: 300
  InsertionSort 平均:36.6ms 最小:35.0ms 最大:40.0ms 成功率:100.0%
  PDQSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  QuickSort 平均:1.2ms 最小:1.0ms 最大:2.0ms 成功率:100.0%
  AdaptiveSort 平均:1.8ms 最小:1.0ms 最大:2.0ms 成功率:100.0%
  TimSort 平均:0.4ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  BuiltInSort 平均:0.8ms 最小:0.0ms 最大:1.0ms 成功率:100.0%

规模: 1000
  InsertionSort 平均:400.6ms 最小:397.0ms 最大:406.0ms 成功率:100.0%
  PDQSort 平均:1.2ms 最小:1.0ms 最大:2.0ms 成功率:100.0%
  QuickSort 平均:3.8ms 最小:3.0ms 最大:4.0ms 成功率:100.0%
  AdaptiveSort 平均:8.4ms 最小:8.0ms 最大:9.0ms 成功率:100.0%
  TimSort 平均:1.2ms 最小:1.0ms 最大:2.0ms 成功率:100.0%
  BuiltInSort 平均:6.0ms 最小:6.0ms 最大:6.0ms 成功率:100.0%

规模: 3000
  InsertionSort 平均:3608.0ms 最小:3589.0ms 最大:3622.0ms 成功率:100.0%
  PDQSort 平均:3.6ms 最小:3.0ms 最大:4.0ms 成功率:100.0%
  QuickSort 平均:13.8ms 最小:13.0ms 最大:15.0ms 成功率:100.0%
  AdaptiveSort 平均:29.4ms 最小:28.0ms 最大:30.0ms 成功率:100.0%
  TimSort 平均:2.6ms 最小:2.0ms 最大:4.0ms 成功率:100.0%
  BuiltInSort 平均:51.6ms 最小:51.0ms 最大:53.0ms 成功率:100.0%

规模: 10000
  InsertionSort 平均:40385.6ms 最小:39862.0ms 最大:41078.0ms 成功率:100.0%
  PDQSort 平均:12.4ms 最小:12.0ms 最大:13.0ms 成功率:100.0%
  QuickSort 平均:47.8ms 最小:47.0ms 最大:50.0ms 成功率:100.0%
  AdaptiveSort 平均:115.8ms 最小:109.0ms 最大:120.0ms 成功率:100.0%
  TimSort 平均:9.6ms 最小:9.0ms 最大:10.0ms 成功率:100.0%
  BuiltInSort 平均:568.4ms 最小:564.0ms 最大:574.0ms 成功率:100.0%

--- 部分有序 ---

规模: 10
  InsertionSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  PDQSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  QuickSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  AdaptiveSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  TimSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  BuiltInSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%

规模: 50
  InsertionSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  PDQSort 平均:0.4ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  QuickSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  AdaptiveSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  TimSort 平均:0.4ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  BuiltInSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%

规模: 100
  InsertionSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  PDQSort 平均:1.0ms 最小:0.0ms 最大:2.0ms 成功率:100.0%
  QuickSort 平均:0.4ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  AdaptiveSort 平均:0.6ms 最小:0.0ms 最大:2.0ms 成功率:100.0%
  TimSort 平均:0.4ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  BuiltInSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%

规模: 300
  InsertionSort 平均:4.2ms 最小:4.0ms 最大:5.0ms 成功率:100.0%
  PDQSort 平均:3.2ms 最小:3.0ms 最大:4.0ms 成功率:100.0%
  QuickSort 平均:1.2ms 最小:1.0ms 最大:2.0ms 成功率:100.0%
  AdaptiveSort 平均:1.8ms 最小:1.0ms 最大:2.0ms 成功率:100.0%
  TimSort 平均:2.6ms 最小:2.0ms 最大:3.0ms 成功率:100.0%
  BuiltInSort 平均:0.4ms 最小:0.0ms 最大:2.0ms 成功率:100.0%

规模: 1000
  InsertionSort 平均:47.4ms 最小:46.0ms 最大:48.0ms 成功率:100.0%
  PDQSort 平均:17.0ms 最小:16.0ms 最大:18.0ms 成功率:100.0%
  QuickSort 平均:4.4ms 最小:4.0ms 最大:5.0ms 成功率:100.0%
  AdaptiveSort 平均:9.4ms 最小:9.0ms 最大:10.0ms 成功率:100.0%
  TimSort 平均:12.6ms 最小:12.0ms 最大:13.0ms 成功率:100.0%
  BuiltInSort 平均:0.4ms 最小:0.0ms 最大:1.0ms 成功率:100.0%

规模: 3000
  InsertionSort 平均:398.8ms 最小:398.0ms 最大:400.0ms 成功率:100.0%
  PDQSort 平均:67.6ms 最小:67.0ms 最大:68.0ms 成功率:100.0%
  QuickSort 平均:15.8ms 最小:15.0ms 最大:16.0ms 成功率:100.0%
  AdaptiveSort 平均:36.2ms 最小:36.0ms 最大:37.0ms 成功率:100.0%
  TimSort 平均:47.6ms 最小:47.0ms 最大:48.0ms 成功率:100.0%
  BuiltInSort 平均:1.4ms 最小:1.0ms 最大:2.0ms 成功率:100.0%

规模: 10000
  InsertionSort 平均:4821.4ms 最小:4732.0ms 最大:4887.0ms 成功率:100.0%
  PDQSort 平均:268.2ms 最小:264.0ms 最大:271.0ms 成功率:100.0%
  QuickSort 平均:65.0ms 最小:64.0ms 最大:66.0ms 成功率:100.0%
  AdaptiveSort 平均:151.0ms 最小:150.0ms 最大:153.0ms 成功率:100.0%
  TimSort 平均:201.0ms 最小:199.0ms 最大:203.0ms 成功率:100.0%
  BuiltInSort 平均:7.8ms 最小:7.0ms 最大:8.0ms 成功率:100.0%

--- 重复元素 ---

规模: 10
  InsertionSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  PDQSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  QuickSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  AdaptiveSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  TimSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  BuiltInSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%

规模: 50
  InsertionSort 平均:0.8ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  PDQSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  QuickSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  AdaptiveSort 平均:0.6ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  TimSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  BuiltInSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%

规模: 100
  InsertionSort 平均:1.6ms 最小:1.0ms 最大:2.0ms 成功率:100.0%
  PDQSort 平均:0.8ms 最小:0.0ms 最大:2.0ms 成功率:100.0%
  QuickSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  AdaptiveSort 平均:0.4ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  TimSort 平均:0.6ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  BuiltInSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%

规模: 300
  InsertionSort 平均:17.2ms 最小:16.0ms 最大:18.0ms 成功率:100.0%
  PDQSort 平均:1.6ms 最小:1.0ms 最大:2.0ms 成功率:100.0%
  QuickSort 平均:1.6ms 最小:1.0ms 最大:2.0ms 成功率:100.0%
  AdaptiveSort 平均:1.6ms 最小:1.0ms 最大:2.0ms 成功率:100.0%
  TimSort 平均:4.4ms 最小:4.0ms 最大:5.0ms 成功率:100.0%
  BuiltInSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%

规模: 1000
  InsertionSort 平均:182.6ms 最小:181.0ms 最大:187.0ms 成功率:100.0%
  PDQSort 平均:5.0ms 最小:4.0ms 最大:6.0ms 成功率:100.0%
  QuickSort 平均:10.4ms 最小:10.0ms 最大:11.0ms 成功率:100.0%
  AdaptiveSort 平均:18.0ms 最小:17.0ms 最大:19.0ms 成功率:100.0%
  TimSort 平均:24.2ms 最小:24.0ms 最大:25.0ms 成功率:100.0%
  BuiltInSort 平均:1.0ms 最小:1.0ms 最大:1.0ms 成功率:100.0%

规模: 3000
  InsertionSort 平均:1665.4ms 最小:1650.0ms 最大:1682.0ms 成功率:100.0%
  PDQSort 平均:15.6ms 最小:15.0ms 最大:16.0ms 成功率:100.0%
  QuickSort 平均:80.8ms 最小:80.0ms 最大:82.0ms 成功率:100.0%
  AdaptiveSort 平均:145.4ms 最小:144.0ms 最大:147.0ms 成功率:100.0%
  TimSort 平均:89.2ms 最小:88.0ms 最大:91.0ms 成功率:100.0%
  BuiltInSort 平均:6.6ms 最小:6.0ms 最大:7.0ms 成功率:100.0%

规模: 10000
  InsertionSort 平均:17681.8ms 最小:17549.0ms 最大:18049.0ms 成功率:100.0%
  PDQSort 平均:53.6ms 最小:52.0ms 最大:55.0ms 成功率:100.0%
  QuickSort 平均:807.0ms 最小:804.0ms 最大:811.0ms 成功率:100.0%
  AdaptiveSort 平均:1591.4ms 最小:1538.0ms 最大:1626.0ms 成功率:100.0%
  TimSort 平均:345.0ms 最小:340.0ms 最大:351.0ms 成功率:100.0%
  BuiltInSort 平均:59.8ms 最小:59.0ms 最大:61.0ms 成功率:100.0%

--- 全相同 ---

规模: 10
  InsertionSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  PDQSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  QuickSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  AdaptiveSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  TimSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  BuiltInSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%

规模: 50
  InsertionSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  PDQSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  QuickSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  AdaptiveSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  TimSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  BuiltInSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%

规模: 100
  InsertionSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  PDQSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  QuickSort 平均:1.0ms 最小:1.0ms 最大:1.0ms 成功率:100.0%
  AdaptiveSort 平均:1.8ms 最小:1.0ms 最大:2.0ms 成功率:100.0%
  TimSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  BuiltInSort 平均:0.4ms 最小:0.0ms 最大:1.0ms 成功率:100.0%

规模: 300
  InsertionSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  PDQSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  QuickSort 平均:7.6ms 最小:7.0ms 最大:8.0ms 成功率:100.0%
  AdaptiveSort 平均:13.8ms 最小:13.0ms 最大:14.0ms 成功率:100.0%
  TimSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  BuiltInSort 平均:0.6ms 最小:0.0ms 最大:1.0ms 成功率:100.0%

规模: 1000
  InsertionSort 平均:0.8ms 最小:0.0ms 最大:2.0ms 成功率:100.0%
  PDQSort 平均:1.4ms 最小:1.0ms 最大:2.0ms 成功率:100.0%
  QuickSort 平均:84.8ms 最小:83.0ms 最大:88.0ms 成功率:100.0%
  AdaptiveSort 平均:169.0ms 最小:166.0ms 最大:173.0ms 成功率:100.0%
  TimSort 平均:0.8ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  BuiltInSort 平均:5.6ms 最小:5.0ms 最大:6.0ms 成功率:100.0%

规模: 3000
  InsertionSort 平均:2.4ms 最小:2.0ms 最大:3.0ms 成功率:100.0%
  PDQSort 平均:3.0ms 最小:2.0ms 最大:4.0ms 成功率:100.0%
  QuickSort 平均:751.0ms 最小:737.0ms 最大:764.0ms 成功率:100.0%
  AdaptiveSort 平均:1401.0ms 最小:1394.0ms 最大:1414.0ms 成功率:100.0%
  TimSort 平均:2.2ms 最小:2.0ms 最大:3.0ms 成功率:100.0%
  BuiltInSort 平均:52.2ms 最小:51.0ms 最大:54.0ms 成功率:100.0%

规模: 10000
  InsertionSort 平均:9.2ms 最小:9.0ms 最大:10.0ms 成功率:100.0%
  PDQSort 平均:10.4ms 最小:10.0ms 最大:11.0ms 成功率:100.0%
  QuickSort 平均:7914.2ms 最小:7837.0ms 最大:8025.0ms 成功率:100.0%
  AdaptiveSort 平均:16016.0ms 最小:15438.0ms 最大:16200.0ms 成功率:100.0%
  TimSort 平均:7.6ms 最小:7.0ms 最大:8.0ms 成功率:100.0%
  BuiltInSort 平均:574.0ms 最小:569.0ms 最大:583.0ms 成功率:100.0%

--- 几乎排序 ---

规模: 10
  InsertionSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  PDQSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  QuickSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  AdaptiveSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  TimSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  BuiltInSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%

规模: 50
  InsertionSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  PDQSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  QuickSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  AdaptiveSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  TimSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  BuiltInSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%

规模: 100
  InsertionSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  PDQSort 平均:0.4ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  QuickSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  AdaptiveSort 平均:0.4ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  TimSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  BuiltInSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%

规模: 300
  InsertionSort 平均:0.4ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  PDQSort 平均:1.0ms 最小:1.0ms 最大:1.0ms 成功率:100.0%
  QuickSort 平均:0.8ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  AdaptiveSort 平均:2.0ms 最小:2.0ms 最大:2.0ms 成功率:100.0%
  TimSort 平均:0.8ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  BuiltInSort 平均:0.4ms 最小:0.0ms 最大:1.0ms 成功率:100.0%

规模: 1000
  InsertionSort 平均:6.2ms 最小:5.0ms 最大:7.0ms 成功率:100.0%
  PDQSort 平均:7.6ms 最小:7.0ms 最大:8.0ms 成功率:100.0%
  QuickSort 平均:3.4ms 最小:3.0ms 最大:4.0ms 成功率:100.0%
  AdaptiveSort 平均:7.8ms 最小:7.0ms 最大:9.0ms 成功率:100.0%
  TimSort 平均:3.8ms 最小:3.0ms 最大:4.0ms 成功率:100.0%
  BuiltInSort 平均:2.4ms 最小:2.0ms 最大:3.0ms 成功率:100.0%

规模: 3000
  InsertionSort 平均:49.0ms 最小:49.0ms 最大:49.0ms 成功率:100.0%
  PDQSort 平均:55.4ms 最小:54.0ms 最大:57.0ms 成功率:100.0%
  QuickSort 平均:12.8ms 最小:12.0ms 最大:13.0ms 成功率:100.0%
  AdaptiveSort 平均:29.0ms 最小:28.0ms 最大:30.0ms 成功率:100.0%
  TimSort 平均:23.6ms 最小:23.0ms 最大:25.0ms 成功率:100.0%
  BuiltInSort 平均:12.2ms 最小:11.0ms 最大:13.0ms 成功率:100.0%

规模: 10000
  InsertionSort 平均:521.0ms 最小:511.0ms 最大:529.0ms 成功率:100.0%
  PDQSort 平均:559.2ms 最小:554.0ms 最大:574.0ms 成功率:100.0%
  QuickSort 平均:52.2ms 最小:51.0ms 最大:53.0ms 成功率:100.0%
  AdaptiveSort 平均:119.0ms 最小:115.0ms 最大:121.0ms 成功率:100.0%
  TimSort 平均:110.2ms 最小:109.0ms 最大:111.0ms 成功率:100.0%
  BuiltInSort 平均:38.2ms 最小:38.0ms 最大:39.0ms 成功率:100.0%

--- 管道风琴 ---

规模: 10
  InsertionSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  PDQSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  QuickSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  AdaptiveSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  TimSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  BuiltInSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%

规模: 50
  InsertionSort 平均:0.4ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  PDQSort 平均:0.4ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  QuickSort 平均:0.4ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  AdaptiveSort 平均:0.6ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  TimSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  BuiltInSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%

规模: 100
  InsertionSort 平均:1.8ms 最小:1.0ms 最大:2.0ms 成功率:100.0%
  PDQSort 平均:1.0ms 最小:1.0ms 最大:1.0ms 成功率:100.0%
  QuickSort 平均:1.2ms 最小:1.0ms 最大:2.0ms 成功率:100.0%
  AdaptiveSort 平均:2.6ms 最小:2.0ms 最大:4.0ms 成功率:100.0%
  TimSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  BuiltInSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%

规模: 300
  InsertionSort 平均:18.2ms 最小:18.0ms 最大:19.0ms 成功率:100.0%
  PDQSort 平均:5.2ms 最小:5.0ms 最大:6.0ms 成功率:100.0%
  QuickSort 平均:10.4ms 最小:10.0ms 最大:11.0ms 成功率:100.0%
  AdaptiveSort 平均:22.2ms 最小:22.0ms 最大:23.0ms 成功率:100.0%
  TimSort 平均:0.6ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  BuiltInSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%

规模: 1000
  InsertionSort 平均:203.8ms 最小:202.0ms 最大:205.0ms 成功率:100.0%
  PDQSort 平均:39.4ms 最小:39.0ms 最大:40.0ms 成功率:100.0%
  QuickSort 平均:115.8ms 最小:115.0ms 最大:117.0ms 成功率:100.0%
  AdaptiveSort 平均:235.2ms 最小:233.0ms 最大:238.0ms 成功率:100.0%
  TimSort 平均:2.2ms 最小:2.0ms 最大:3.0ms 成功率:100.0%
  BuiltInSort 平均:0.4ms 最小:0.0ms 最大:1.0ms 成功率:100.0%

规模: 3000
  InsertionSort 平均:1799.8ms 最小:1781.0ms 最大:1839.0ms 成功率:100.0%
  PDQSort 平均:312.2ms 最小:305.0ms 最大:326.0ms 成功率:100.0%
  QuickSort 平均:1030.0ms 最小:1016.0ms 最大:1037.0ms 成功率:100.0%
  AdaptiveSort 平均:2123.6ms 最小:2116.0ms 最大:2136.0ms 成功率:100.0%
  TimSort 平均:6.6ms 最小:6.0ms 最大:7.0ms 成功率:100.0%
  BuiltInSort 平均:2.4ms 最小:2.0ms 最大:3.0ms 成功率:100.0%

规模: 10000
  InsertionSort 平均:20131.8ms 最小:19907.0ms 最大:20293.0ms 成功率:100.0%
  PDQSort 平均:3116.0ms 最小:3103.0ms 最大:3125.0ms 成功率:100.0%
  QuickSort 平均:11574.8ms 最小:11543.0ms 最大:11598.0ms 成功率:100.0%
  AdaptiveSort 平均:24261.4ms 最小:23817.0ms 最大:24858.0ms 成功率:100.0%
  TimSort 平均:23.0ms 最小:22.0ms 最大:24.0ms 成功率:100.0%
  BuiltInSort 平均:7.0ms 最小:6.0ms 最大:8.0ms 成功率:100.0%

--- 锯齿波 ---

规模: 10
  InsertionSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  PDQSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  QuickSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  AdaptiveSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  TimSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  BuiltInSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%

规模: 50
  InsertionSort 平均:0.4ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  PDQSort 平均:0.4ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  QuickSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  AdaptiveSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  TimSort 平均:0.4ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  BuiltInSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%

规模: 100
  InsertionSort 平均:1.6ms 最小:1.0ms 最大:3.0ms 成功率:100.0%
  PDQSort 平均:2.2ms 最小:2.0ms 最大:3.0ms 成功率:100.0%
  QuickSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%
  AdaptiveSort 平均:0.4ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  TimSort 平均:0.8ms 最小:0.0ms 最大:1.0ms 成功率:100.0%
  BuiltInSort 平均:0.0ms 最小:0.0ms 最大:0.0ms 成功率:100.0%

规模: 300
  InsertionSort 平均:15.8ms 最小:15.0ms 最大:17.0ms 成功率:100.0%
  PDQSort 平均:17.4ms 最小:17.0ms 最大:18.0ms 成功率:100.0%
  QuickSort 平均:2.4ms 最小:2.0ms 最大:3.0ms 成功率:100.0%
  AdaptiveSort 平均:1.6ms 最小:1.0ms 最大:2.0ms 成功率:100.0%
  TimSort 平均:2.0ms 最小:2.0ms 最大:2.0ms 成功率:100.0%
  BuiltInSort 平均:0.2ms 最小:0.0ms 最大:1.0ms 成功率:100.0%

规模: 1000
  InsertionSort 平均:179.8ms 最小:173.0ms 最大:186.0ms 成功率:100.0%
  PDQSort 平均:193.6ms 最小:190.0ms 最大:201.0ms 成功率:100.0%
  QuickSort 平均:25.0ms 最小:24.0ms 最大:26.0ms 成功率:100.0%
  AdaptiveSort 平均:7.4ms 最小:6.0ms 最大:8.0ms 成功率:100.0%
  TimSort 平均:7.0ms 最小:7.0ms 最大:7.0ms 成功率:100.0%
  BuiltInSort 平均:0.4ms 最小:0.0ms 最大:1.0ms 成功率:100.0%

规模: 3000
  InsertionSort 平均:1657.8ms 最小:1646.0ms 最大:1668.0ms 成功率:100.0%
  PDQSort 平均:1767.4ms 最小:1747.0ms 最大:1806.0ms 成功率:100.0%
  QuickSort 平均:223.6ms 最小:218.0ms 最大:236.0ms 成功率:100.0%
  AdaptiveSort 平均:225.8ms 最小:220.0ms 最大:228.0ms 成功率:100.0%
  TimSort 平均:21.6ms 最小:21.0ms 最大:22.0ms 成功率:100.0%
  BuiltInSort 平均:2.2ms 最小:2.0ms 最大:3.0ms 成功率:100.0%

规模: 10000
  InsertionSort 平均:18125.8ms 最小:17818.0ms 最大:18446.0ms 成功率:100.0%
  PDQSort 平均:19424.0ms 最小:19170.0ms 最大:19797.0ms 成功率:100.0%
  QuickSort 平均:2447.6ms 最小:2439.0ms 最大:2455.0ms 成功率:100.0%
  AdaptiveSort 平均:4939.8ms 最小:4901.0ms 最大:5035.0ms 成功率:100.0%
  TimSort 平均:74.2ms 最小:72.0ms 最大:76.0ms 成功率:100.0%
  BuiltInSort 平均:6.0ms 最小:6.0ms 最大:6.0ms 成功率:100.0%

========================================
特殊场景测试
========================================

--- 极值数据 ---
示例前10:-1000000,305,105,451,-1000000,175,1000000,842,-1000000,-1000000
  InsertionSort: 202ms ✓
  PDQSort: 18ms ✓
  QuickSort: 6ms ✓
  AdaptiveSort: 16ms ✓
  TimSort: 23ms ✓
  BuiltInSort: 1ms ✓

--- 高重复率 ---
示例前10:2,1,1,1,2,2,3,1,3,1
  InsertionSort: 132ms ✓
  PDQSort: 4ms ✓
  QuickSort: 29ms ✓
  AdaptiveSort: 55ms ✓
  TimSort: 24ms ✓
  BuiltInSort: 3ms ✓

--- 三值分布 ---
示例前10:1,1,1,1,1,1,1,1,1,1
  InsertionSort: 1ms ✓
  PDQSort: 1ms ✓
  QuickSort: 30ms ✓
  AdaptiveSort: 162ms ✓
  TimSort: 2ms ✓
  BuiltInSort: 6ms ✓

--- 交替模式 ---
示例前10:1,1000,1,1000,1,1000,1,1000,1,1000
  InsertionSort: 104ms ✓
  PDQSort: 4ms ✓
  QuickSort: 41ms ✓
  AdaptiveSort: 82ms ✓
  TimSort: 14ms ✓
  BuiltInSort: 4ms ✓

--- 指数分布 ---
示例前10:1,55,630,1,208,19,21,2,244,11
  InsertionSort: 208ms ✓
  PDQSort: 17ms ✓
  QuickSort: 7ms ✓
  AdaptiveSort: 11ms ✓
  TimSort: 17ms ✓
  BuiltInSort: 1ms ✓

========================================
算法比较分析
========================================

数据模式性能分析:

BuiltInSort:
  锯齿波: 1.26ms
  管道风琴: 1.4ms
  几乎排序: 7.6ms
  全相同: 90.43ms
  重复元素: 9.69ms
  部分有序: 1.46ms
  逆序: 89.6ms
  已排序: 91.6ms
  随机数据: 1.00ms
  最优: 随机数据(1.00ms)
  最差: 已排序(91.6ms)

TimSort:
  锯齿波: 15.14ms
  管道风琴: 4.63ms
  几乎排序: 19.77ms
  全相同: 1.57ms
  重复元素: 66.23ms
  部分有序: 37.8ms
  逆序: 2.00ms
  已排序: 1.51ms
  随机数据: 62.11ms
  最优: 已排序(1.51ms)
  最差: 重复元素(66.23ms)

AdaptiveSort:
  锯齿波: 739.31ms
  管道风琴: 3806.51ms
  几乎排序: 22.63ms
  全相同: 2514.51ms
  重复元素: 251.06ms
  部分有序: 28.46ms
  逆序: 22.43ms
  已排序: 17.09ms
  随机数据: 25.31ms
  最优: 已排序(17.09ms)
  最差: 管道风琴(3806.51ms)

QuickSort:
  锯齿波: 385.54ms
  管道风琴: 1818.94ms
  几乎排序: 9.91ms
  全相同: 1251.26ms
  重复元素: 128.6ms
  部分有序: 12.43ms
  逆序: 9.54ms
  已排序: 7.2ms
  随机数据: 10.77ms
  最优: 已排序(7.2ms)
  最差: 管道风琴(1818.94ms)

PDQSort:
  锯齿波: 3057.86ms
  管道风琴: 496.31ms
  几乎排序: 89.09ms
  全相同: 2.14ms
  重复元素: 11.00ms
  部分有序: 51.06ms
  逆序: 2.49ms
  已排序: 1.91ms
  随机数据: 49.94ms
  最优: 已排序(1.91ms)
  最差: 锯齿波(3057.86ms)

InsertionSort:
  锯齿波: 2854.46ms
  管道风琴: 3165.14ms
  几乎排序: 82.37ms
  全相同: 1.83ms
  重复元素: 2792.77ms
  部分有序: 753.17ms
  逆序: 6348.00ms
  已排序: 1.91ms
  随机数据: 3156.77ms
  最优: 全相同(1.83ms)
  最差: 逆序(6348.00ms)

规模伸缩性分析:

InsertionSort 随机数据趋势:
  10→50: 时间比N/A 复杂度因子N/A
  50→100: 时间比2.75 复杂度因子1.375
  100→300: 时间比8.727 复杂度因子2.909
  300→1000: 时间比10.531 复杂度因子3.159
  1000→3000: 时间比9.163 复杂度因子3.054
  3000→10000: 时间比10.805 复杂度因子3.242

PDQSort 随机数据趋势:
  10→50: 时间比3.000 复杂度因子0.6
  50→100: 时间比1.667 复杂度因子0.833
  100→300: 时间比3.6 复杂度因子1.2
  300→1000: 时间比5.000 复杂度因子1.5
  1000→3000: 时间比3.756 复杂度因子1.252
  3000→10000: 时间比3.825 复杂度因子1.148

QuickSort 随机数据趋势:
  10→50: 时间比N/A 复杂度因子N/A
  50→100: 时间比0.000 复杂度因子0.000
  100→300: 时间比N/A 复杂度因子N/A
  300→1000: 时间比3.143 复杂度因子0.943
  1000→3000: 时间比3.318 复杂度因子1.106
  3000→10000: 时间比3.753 复杂度因子1.126

AdaptiveSort 随机数据趋势:
  10→50: 时间比N/A 复杂度因子N/A
  50→100: 时间比1.333 复杂度因子0.667
  100→300: 时间比3.5 复杂度因子1.167
  300→1000: 时间比3.857 复杂度因子1.157
  1000→3000: 时间比3.093 复杂度因子1.031
  3000→10000: 时间比3.856 复杂度因子1.157

TimSort 随机数据趋势:
  10→50: 时间比N/A 复杂度因子N/A
  50→100: 时间比1.667 复杂度因子0.833
  100→300: 时间比3.6 复杂度因子1.2
  300→1000: 时间比4.167 复杂度因子1.25
  1000→3000: 时间比3.267 复杂度因子1.089
  3000→10000: 时间比7.461 复杂度因子2.238

BuiltInSort 随机数据趋势:
  10→50: 时间比N/A 复杂度因子N/A
  50→100: 时间比N/A 复杂度因子N/A
  100→300: 时间比N/A 复杂度因子N/A
  300→1000: 时间比N/A 复杂度因子N/A
  1000→3000: 时间比5.000 复杂度因子1.667
  3000→10000: 时间比2.3 复杂度因子0.69

使用建议:
  • 小数据(<100): BuiltInSort
  • 需要稳定: TimSort
  • 内存受限: PDQSort
  • 随机数据: BuiltInSort
  • 部分有序: BuiltInSort
  • 重复多: BuiltInSort

================================================================================
最终测试报告 - 修复版
================================================================================

------------------------------------------------------------
📊 执行摘要
------------------------------------------------------------
• 测试算法数量: 6
• 数据分布类型: 9 (锯齿波, 管道风琴, 几乎排序, 全相同, 重复元素, 部分有序, 逆序, 已排序, 随机数据)
• 测试规模范围: 10 - 10000
• 总测试样本: 378 个性能数据点
• 每组重复次数: 5
• 综合最佳算法: TimSort
• 测试完成时间: Sat Jun 21 09:38:17 GMT+0800 2025

------------------------------------------------------------
📈 性能矩阵 (平均执行时间 ms)
------------------------------------------------------------

锯齿波:
算法\规模	10	50	100	300	1000	3000	10000
InsertionSort	0.0	0.4	1.6	15.8	179.8	1657.8	18125.8
PDQSort	0.0	0.4	2.2	17.4	193.6	1767.4	19424.0
QuickSort	0.0	0.2	0.0	2.4	25.0	223.6	2447.6
AdaptiveSort	0.0	0.2	0.4	1.6	7.4	225.8	4939.8
TimSort	0.0	0.4	0.8	2.0	7.0	21.6	74.2
BuiltInSort	0.0	0.0	0.0	0.2	0.4	2.2	6.0
最佳: BuiltInSort

管道风琴:
算法\规模	10	50	100	300	1000	3000	10000
InsertionSort	0.2	0.4	1.8	18.2	203.8	1799.8	20131.8
PDQSort	0.0	0.4	1.0	5.2	39.4	312.2	3116.0
QuickSort	0.0	0.4	1.2	10.4	115.8	1030.0	11574.8
AdaptiveSort	0.0	0.6	2.6	22.2	235.2	2123.6	24261.4
TimSort	0.0	0.0	0.0	0.6	2.2	6.6	23.0
BuiltInSort	0.0	0.0	0.0	0.0	0.4	2.4	7.0
最佳: BuiltInSort

几乎排序:
算法\规模	10	50	100	300	1000	3000	10000
InsertionSort	0.0	0.0	0.0	0.4	6.2	49.0	521.0
PDQSort	0.0	0.0	0.4	1.0	7.6	55.4	559.2
QuickSort	0.0	0.0	0.2	0.8	3.4	12.8	52.2
AdaptiveSort	0.2	0.0	0.4	2.0	7.8	29.0	119.0
TimSort	0.0	0.0	0.0	0.8	3.8	23.6	110.2
BuiltInSort	0.0	0.0	0.0	0.4	2.4	12.2	38.2
最佳: BuiltInSort

全相同:
算法\规模	10	50	100	300	1000	3000	10000
InsertionSort	0.0	0.0	0.2	0.2	0.8	2.4	9.2
PDQSort	0.0	0.0	0.0	0.2	1.4	3.0	10.4
QuickSort	0.0	0.2	1.0	7.6	84.8	751.0	7914.2
AdaptiveSort	0.0	0.0	1.8	13.8	169.0	1401.0	16016.0
TimSort	0.0	0.2	0.0	0.2	0.8	2.2	7.6
BuiltInSort	0.0	0.2	0.4	0.6	5.6	52.2	574.0
最佳: TimSort

重复元素:
算法\规模	10	50	100	300	1000	3000	10000
InsertionSort	0.0	0.8	1.6	17.2	182.6	1665.4	17681.8
PDQSort	0.2	0.2	0.8	1.6	5.0	15.6	53.6
QuickSort	0.0	0.2	0.2	1.6	10.4	80.8	807.0
AdaptiveSort	0.0	0.6	0.4	1.6	18.0	145.4	1591.4
TimSort	0.0	0.2	0.6	4.4	24.2	89.2	345.0
BuiltInSort	0.0	0.0	0.2	0.2	1.0	6.6	59.8
最佳: BuiltInSort

部分有序:
算法\规模	10	50	100	300	1000	3000	10000
InsertionSort	0.0	0.2	0.2	4.2	47.4	398.8	4821.4
PDQSort	0.0	0.4	1.0	3.2	17.0	67.6	268.2
QuickSort	0.0	0.2	0.4	1.2	4.4	15.8	65.0
AdaptiveSort	0.0	0.2	0.6	1.8	9.4	36.2	151.0
TimSort	0.0	0.4	0.4	2.6	12.6	47.6	201.0
BuiltInSort	0.0	0.2	0.0	0.4	0.4	1.4	7.8
最佳: BuiltInSort

逆序:
算法\规模	10	50	100	300	1000	3000	10000
InsertionSort	0.0	1.0	4.2	36.6	400.6	3608.0	40385.6
PDQSort	0.0	0.0	0.0	0.2	1.2	3.6	12.4
QuickSort	0.0	0.2	0.0	1.2	3.8	13.8	47.8
AdaptiveSort	0.0	1.2	0.4	1.8	8.4	29.4	115.8
TimSort	0.0	0.0	0.2	0.4	1.2	2.6	9.6
BuiltInSort	0.0	0.0	0.4	0.8	6.0	51.6	568.4
最佳: TimSort

已排序:
算法\规模	10	50	100	300	1000	3000	10000
InsertionSort	0.0	0.0	0.2	0.2	1.0	2.8	9.2
PDQSort	0.0	0.0	0.0	0.2	1.0	2.6	9.6
QuickSort	0.0	0.2	0.2	0.6	2.8	9.0	37.6
AdaptiveSort	0.0	0.0	0.6	1.2	7.2	22.2	88.4
TimSort	0.0	0.0	0.0	0.2	0.8	2.2	7.4
BuiltInSort	0.0	0.0	0.0	0.6	6.2	52.6	581.8
最佳: TimSort

随机数据:
算法\规模	10	50	100	300	1000	3000	10000
InsertionSort	0.0	0.8	2.2	19.2	202.2	1852.8	20020.2
PDQSort	0.2	0.6	1.0	3.6	18.0	67.6	258.6
QuickSort	0.0	0.2	0.0	1.4	4.4	14.6	54.8
AdaptiveSort	0.0	0.6	0.8	2.8	10.8	33.4	128.8
TimSort	0.0	0.6	1.0	3.6	15.0	49.0	365.6
BuiltInSort	0.0	0.0	0.0	0.0	0.4	2.0	4.6
最佳: BuiltInSort

------------------------------------------------------------
🏆 算法综合排名
------------------------------------------------------------
排名	算法		综合得分		理论复杂度	最佳场景	最差场景
--------------------------------------------------------------------------------
1	TimSort		23.42		O(n log n)	已排序	重复元素
2	BuiltInSort		32.67		O(n log n)	随机数据	已排序
3	QuickSort		403.8		O(n log n)	已排序	管道风琴
4	PDQSort		417.98		O(n log n)	已排序	锯齿波
5	AdaptiveSort		825.26		O(n log n)	已排序	管道风琴
6	InsertionSort		2128.49		O(n²)	全相同	逆序

------------------------------------------------------------
📊 复杂度分析 - 修复版
------------------------------------------------------------

InsertionSort (理论: O(n²)):
  实际表现: O(n^2.27) (斜率: 2.274)
  R²相关系数: 0.984 (越接近1越准确)
  最佳情况: 全相同 (1.83ms)
  最差情况: 逆序 (6348.00ms)
  性能比率: 3471.6:1

PDQSort (理论: O(n log n)):
  实际表现: O(n) (斜率: 1.082)
  R²相关系数: 0.993 (越接近1越准确)
  最佳情况: 已排序 (1.91ms)
  最差情况: 锯齿波 (3057.86ms)
  性能比率: 1597.4:1

QuickSort (理论: O(n log n)):
  实际表现: O(n log n) (斜率: 1.621)
  R²相关系数: 0.887 (越接近1越准确)
  最佳情况: 已排序 (7.2ms)
  最差情况: 管道风琴 (1818.94ms)
  性能比率: 252.6:1

AdaptiveSort (理论: O(n log n)):
  实际表现: O(n log n) (斜率: 1.493)
  R²相关系数: 0.94 (越接近1越准确)
  最佳情况: 已排序 (17.09ms)
  最差情况: 管道风琴 (3806.51ms)
  性能比率: 222.8:1

TimSort (理论: O(n log n)):
  实际表现: O(n log n) (斜率: 1.621)
  R²相关系数: 0.953 (越接近1越准确)
  最佳情况: 已排序 (1.51ms)
  最差情况: 重复元素 (66.23ms)
  性能比率: 43.7:1

BuiltInSort (理论: O(n log n)):
  实际表现: O(n log n) (斜率: 1.488)
  R²相关系数: 0.9 (越接近1越准确)
  最佳情况: 随机数据 (1.00ms)
  最差情况: 已排序 (91.6ms)
  性能比率: 91.6:1

------------------------------------------------------------
🎯 特殊场景性能摘要
------------------------------------------------------------

已排序 - 测试算法对有序数据的优化
  1. TimSort: 1.51ms
  2. InsertionSort: 1.91ms
  3. PDQSort: 1.91ms

逆序 - 测试算法对逆序数据的处理
  1. TimSort: 2.00ms
  2. PDQSort: 2.49ms
  3. QuickSort: 9.54ms

全相同 - 测试算法对重复元素的处理
  1. TimSort: 1.57ms
  2. InsertionSort: 1.83ms
  3. PDQSort: 2.14ms

几乎排序 - 测试算法对近有序数据的适应性
  1. BuiltInSort: 7.6ms
  2. QuickSort: 9.91ms
  3. TimSort: 19.77ms

------------------------------------------------------------
💡 使用推荐矩阵
------------------------------------------------------------
• 数据规模 < 100
  推荐: BuiltInSort
  原因: 小数据量时简单算法开销更低

• 数据规模 > 3000
  推荐: TimSort
  原因: 大数据量需要高效的分治算法

• 数据已基本有序
  推荐: TimSort
  原因: 利用现有有序性可显著提升性能

• 包含大量重复元素
  推荐: BuiltInSort
  原因: 三路分区等技术可优化重复元素处理

• 需要稳定排序
  推荐: TimSort
  原因: 保持相同元素的相对顺序

• 内存限制严格
  推荐: PDQSort
  原因: 原地排序算法减少额外内存使用


------------------------------------------------------------
📈 统计摘要 - 修复版
------------------------------------------------------------
整体统计:
• 最快单次执行: 0.0ms (BuiltInSort - 锯齿波, 100元素)
• 最慢单次执行: 40385.6ms (InsertionSort - 逆序, 10000元素)
• 性能差距: 无法计算
• 平均执行时间: 638.6ms
• 标准差: 3435.32ms

算法可靠性 (变异系数):
• InsertionSort: 3.181 (一般)
• PDQSort: 5.921 (一般)
• QuickSort: 4.389 (一般)
• AdaptiveSort: 4.449 (一般)
• TimSort: 2.929 (一般)
• BuiltInSort: 3.764 (一般)

------------------------------------------------------------
📄 CSV格式数据导出
------------------------------------------------------------
CSV数据已生成 (共 379 行)
数据格式: 算法,数据分布,规模,平均时间,迭代次数

前5行数据示例:
Algorithm,DataDistribution,Size,AverageTime,Iterations
BuiltInSort,锯齿波,10000,6.000,5
BuiltInSort,锯齿波,3000,2.2,5
BuiltInSort,锯齿波,1000,0.4,5
BuiltInSort,锯齿波,300,0.2,5
...(完整数据可导出到文件)

------------------------------------------------------------
🎯 测试结论
------------------------------------------------------------
基于本次测试的主要发现:

1. 综合性能最佳: TimSort
   在大多数测试场景中表现优异，具有良好的时间复杂度特性。

2. 适应性最强: InsertionSort
   在各种数据分布下都能保持相对稳定的性能表现。

3. 关键洞察:
   • 算法选择应基于具体使用场景和数据特征
   • 预排序检测对性能提升显著
   • 三路分区技术在处理重复元素时优势明显
   • 大规模数据更能体现高级算法的优势
   • 内存使用模式是选择算法的重要考虑因素

4. 建议:
   • 一般用途推荐: TimSort
   • 性能要求极高: TimSort
   • 稳定性要求: TimSort
   • 内存受限环境: PDQSort

================================================================================
测试报告生成完成 - 修复版
================================================================================
================================================================================
测试套件完成
================================================================================
