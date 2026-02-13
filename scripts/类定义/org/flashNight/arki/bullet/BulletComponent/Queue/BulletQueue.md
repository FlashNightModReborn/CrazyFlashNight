org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueTest.runSuite({sizes:[8, 12, 16, 24, 32, 40, 48, 56, 64, 72, 80, 96, 112, 128, 192, 256, 384, 512, 768, 1000, 2000, 5000], repeats:5});

============================================================
 BulletQueue 测试/基准开始（类版）
 sizes=8, 12, 16, 24, 32, 40, 48, 56, 64, 72, 80, 96, 112, 128, 192, 256, 384, 512, 768, 1000, 2000, 5000  repeats=5
============================================================

==================== 鲁棒性测试 ====================
[PASS] 空队列测试
[PASS] 单元素测试
[PASS] 边界值测试(63/64/65)
[PASS] clear()方法测试
[PASS] 缓冲区扩容测试
[PASS] API一致性测试
[PASS] Keys对齐测试
[DEBUG] 开始 testProcessAndClear 测试
[TEST 1] 测试空队列
  visitCount1=0 (期望:0)
  q1.getCount()=0 (期望:0)
  [PASS] 测试1通过
[TEST 2] 测试小数组路径(20个元素)
  visitCount2=20 (期望:20)
  sorted2=true (期望:true)
  q2.getCount()=0 (期望:0)
  [PASS] 测试2通过
[TEST 3] 测试大数组路径(100个元素)
  visitCount3=100 (期望:100)
  sorted3=true (期望:true)
  q3.getCount()=0 (期望:0)
  前5个值: [0]=0 [1]=2 [2]=3 [3]=4 [4]=5
  [PASS] 测试3通过
[TEST 4] 测试连续调用
  firstCall=10 (期望:10)
  secondCall=0 (期望:0)
  [PASS] 测试4通过
[TEST 5] 测试稳定性
  stableIds长度=10 (期望:10)
  [PASS] 测试5通过
[DEBUG] testProcessAndClear 全部测试通过
[PASS] processAndClear方法测试
[DEBUG] 开始 testAddBatch 测试
[TEST 1] 测试空数组批量添加
  added1=0 (期望:0)
  q1.getCount()=0 (期望:0)
  [PASS] 测试1通过
[TEST 2] 测试null参数
  added2=0 (期望:0)
  q2.getCount()=0 (期望:0)
  [PASS] 测试2通过
[TEST 3] 测试正常批量添加
  added3=50 (期望:50)
  q3.getCount()=50 (期望:50)
  排序正确性=true (期望:true)
  [PASS] 测试3通过
[TEST 4] 测试包含无效对象的批量添加
  added4=5 (期望:5，只有有效子弹)
  q4.getCount()=5 (期望:5)
  所有子弹有效=true (期望:true)
  [PASS] 测试4通过
[TEST 5] 测试大批量添加(1000个元素)
  added5=1000 (期望:1000)
  q5.getCount()=1000 (期望:1000)
  批量添加耗时=1ms
  排序正确性=true (期望:true)
  [PASS] 测试5通过
[TEST 6] 测试混合使用add和addBatch
  批量添加返回值=10 (期望:10)
  总数量=25 (期望:25)
  排序正确性=true (期望:true)
  [PASS] 测试6通过
[DEBUG] testAddBatch 全部测试通过
[PASS] addBatch方法测试
鲁棒性测试: 9 通过, 0 失败
====================================================

dist          n      ms_avg    ms/1k
------------------------------------------------------------
ascending     8      0.4       50
ascending     12     0         0
ascending     16     0         0
ascending     24     0         0
ascending     32     0         0
ascending     40     0         0
ascending     48     0         0
ascending     56     0.2       3.57
ascending     64     0.2       3.13
ascending     72     0.2       2.78
ascending     80     0         0
ascending     96     0         0
ascending     112    0.2       1.79
ascending     128    0         0
ascending     192    0.4       2.08
ascending     256    0.8       3.13
ascending     384    1         2.6
ascending     512    1         1.95
ascending     768    1         1.3
ascending     1000   1         1
ascending     2000   2.8       1.4
ascending     5000   7.6       1.52
descending    8      0.2       25
descending    12     0.4       33.33
descending    16     0.2       12.5
descending    24     0.2       8.33
descending    32     0.4       12.5
descending    40     0         0
descending    48     0.2       4.17
descending    56     0.4       7.14
descending    64     0         0
descending    72     0.8       11.11
descending    80     1         12.5
descending    96     0.4       4.17
descending    112    0.6       5.36
descending    128    0.6       4.69
descending    192    1         5.21
descending    256    1.2       4.69
descending    384    1.4       3.65
descending    512    2.4       4.69
descending    768    3.4       4.43
descending    1000   5.4       5.4
descending    2000   9.2       4.6
descending    5000   22.6      4.52
random        8      0         0
random        12     0         0
random        16     0.2       12.5
random        24     0         0
random        32     0.4       12.5
random        40     0         0
random        48     0.6       12.5
random        56     0.6       10.71
random        64     0.6       9.38
random        72     0.8       11.11
random        80     1         12.5
random        96     1.2       12.5
random        112    1.8       16.07
random        128    1.8       14.06
random        192    2.6       13.54
random        256    3.4       13.28
random        384    6         15.63
random        512    8.2       16.02
random        768    13.6      17.71
random        1000   17.8      17.8
random        2000   39.8      19.9
random        5000   114.2     22.84
nearlySorted  8      0         0
nearlySorted  12     0         0
nearlySorted  16     0.2       12.5
nearlySorted  24     0         0
nearlySorted  32     0         0
nearlySorted  40     0.4       10
nearlySorted  48     0.2       4.17
nearlySorted  56     0.4       7.14
nearlySorted  64     0.4       6.25
nearlySorted  72     0.2       2.78
nearlySorted  80     0.2       2.5
nearlySorted  96     0.6       6.25
nearlySorted  112    0.4       3.57
nearlySorted  128    1         7.81
nearlySorted  192    1         5.21
nearlySorted  256    1.8       7.03
nearlySorted  384    2.4       6.25
nearlySorted  512    4         7.81
nearlySorted  768    6         7.81
nearlySorted  1000   8.2       8.2
nearlySorted  2000   16.4      8.2
nearlySorted  5000   46.6      9.32
sawtooth      8      0         0
sawtooth      12     0.2       16.67
sawtooth      16     0.2       12.5
sawtooth      24     0.2       8.33
sawtooth      32     0.2       6.25
sawtooth      40     0.4       10
sawtooth      48     0.2       4.17
sawtooth      56     0.4       7.14
sawtooth      64     0.6       9.38
sawtooth      72     0.6       8.33
sawtooth      80     1         12.5
sawtooth      96     1.2       12.5
sawtooth      112    1.4       12.5
sawtooth      128    1.2       9.38
sawtooth      192    2.2       11.46
sawtooth      256    3.4       13.28
sawtooth      384    4.6       11.98
sawtooth      512    6.4       12.5
sawtooth      768    9         11.72
sawtooth      1000   11.8      11.8
sawtooth      2000   22.2      11.1
sawtooth      5000   57.4      11.48
endsHeavy     8      0         0
endsHeavy     12     0         0
endsHeavy     16     0         0
endsHeavy     24     0.8       33.33
endsHeavy     32     0.2       6.25
endsHeavy     40     0.2       5
endsHeavy     48     0.6       12.5
endsHeavy     56     0.6       10.71
endsHeavy     64     0.8       12.5
endsHeavy     72     0.6       8.33
endsHeavy     80     1         12.5
endsHeavy     96     1.4       14.58
endsHeavy     112    1.4       12.5
endsHeavy     128    1.6       12.5
endsHeavy     192    2.8       14.58
endsHeavy     256    3.4       13.28
endsHeavy     384    6         15.63
endsHeavy     512    8.4       16.41
endsHeavy     768    13.4      17.45
endsHeavy     1000   19.4      19.4
endsHeavy     2000   39.4      19.7
endsHeavy     5000   111.2     22.24
fewUniques    8      0         0
fewUniques    12     0         0
fewUniques    16     0.2       12.5
fewUniques    24     0.2       8.33
fewUniques    32     0.2       6.25
fewUniques    40     0.6       15
fewUniques    48     0.6       12.5
fewUniques    56     0.6       10.71
fewUniques    64     1         15.63
fewUniques    72     0.6       8.33
fewUniques    80     1.4       17.5
fewUniques    96     1.2       12.5
fewUniques    112    1.4       12.5
fewUniques    128    1.8       14.06
fewUniques    192    2.8       14.58
fewUniques    256    4         15.63
fewUniques    384    5.8       15.1
fewUniques    512    8.6       16.8
fewUniques    768    12.8      16.67
fewUniques    1000   17        17
fewUniques    2000   38        19
fewUniques    5000   104.4     20.88
altHighLow    8      0         0
altHighLow    12     0.2       16.67
altHighLow    16     0         0
altHighLow    24     0.6       25
altHighLow    32     0.4       12.5
altHighLow    40     0.4       10
altHighLow    48     0         0
altHighLow    56     0.4       7.14
altHighLow    64     0.8       12.5
altHighLow    72     0.8       11.11
altHighLow    80     1.4       17.5
altHighLow    96     1         10.42
altHighLow    112    1.2       10.71
altHighLow    128    1.8       14.06
altHighLow    192    2.4       12.5
altHighLow    256    3.6       14.06
altHighLow    384    5         13.02
altHighLow    512    5.8       11.33
altHighLow    768    11.2      14.58
altHighLow    1000   13        13
altHighLow    2000   27        13.5
altHighLow    5000   70.2      14.04
withInvalid   8      0         0
withInvalid   12     0.2       16.67
withInvalid   16     0.2       12.5
withInvalid   24     0.2       8.33
withInvalid   32     0.2       6.25
withInvalid   40     0.2       5
withInvalid   48     0.4       8.33
withInvalid   56     0.4       7.14
withInvalid   64     0.8       12.5
withInvalid   72     1         13.89
withInvalid   80     0         0
withInvalid   96     0.8       8.33
withInvalid   112    0.8       7.14
withInvalid   128    1.4       10.94
withInvalid   192    2         10.42
withInvalid   256    2.8       10.94
withInvalid   384    4.8       12.5
withInvalid   512    6         11.72
withInvalid   768    10.6      13.8
withInvalid   1000   14.4      14.4
withInvalid   2000   34        17
withInvalid   5000   88.6      17.72
allSame       8      0         0
allSame       12     0         0
allSame       16     0         0
allSame       24     0         0
allSame       32     0.2       6.25
allSame       40     0.2       5
allSame       48     0         0
allSame       56     0.2       3.57
allSame       64     0         0
allSame       72     0         0
allSame       80     0.4       5
allSame       96     0.2       2.08
allSame       112    0.2       1.79
allSame       128    0.2       1.56
allSame       192    0         0
allSame       256    0.6       2.34
allSame       384    0.8       2.08
allSame       512    0.4       0.78
allSame       768    1         1.3
allSame       1000   1.2       1.2
allSame       2000   3.4       1.7
allSame       5000   7.4       1.48
------------------------------------------------------------
 断言统计: total=449, failed=0
 ✅ 全部断言通过
============================================================
 完成，结果已写入 _root.gameworld.BulletQueueBench.results
============================================================
