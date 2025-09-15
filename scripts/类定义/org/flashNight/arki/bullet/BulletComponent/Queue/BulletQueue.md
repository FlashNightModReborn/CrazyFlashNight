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
ascending     8      0         0
ascending     12     0.2       16.67
ascending     16     0         0
ascending     24     0         0
ascending     32     0         0
ascending     40     0.2       5
ascending     48     0         0
ascending     56     0         0
ascending     64     0         0
ascending     72     0         0
ascending     80     0         0
ascending     96     0         0
ascending     112    0.4       3.57
ascending     128    0         0
ascending     192    0.4       2.08
ascending     256    0.6       2.34
ascending     384    0.4       1.04
ascending     512    0.6       1.17
ascending     768    1.2       1.56
ascending     1000   1.2       1.2
ascending     2000   2.6       1.3
ascending     5000   7.2       1.44
descending    8      0.2       25
descending    12     0         0
descending    16     0.2       12.5
descending    24     0.4       16.67
descending    32     0.2       6.25
descending    40     0.2       5
descending    48     0.4       8.33
descending    56     0         0
descending    64     0.6       9.38
descending    72     0         0
descending    80     0.8       10
descending    96     0.4       4.17
descending    112    0.8       7.14
descending    128    0.8       6.25
descending    192    1.2       6.25
descending    256    1.4       5.47
descending    384    2.6       6.77
descending    512    3.4       6.64
descending    768    4.8       6.25
descending    1000   6.6       6.6
descending    2000   12.4      6.2
descending    5000   31        6.2
random        8      0         0
random        12     0         0
random        16     0         0
random        24     0.4       16.67
random        32     1.6       50
random        40     1         25
random        48     1.4       29.17
random        56     1.2       21.43
random        64     1.8       28.13
random        72     1.8       25
random        80     2.2       27.5
random        96     2.8       29.17
random        112    2.2       19.64
random        128    4         31.25
random        192    5.8       30.21
random        256    8.4       32.81
random        384    13.2      34.37
random        512    18.6      36.33
random        768    30        39.06
random        1000   39.4      39.4
random        2000   86.6      43.3
random        5000   244.8     48.96
nearlySorted  8      0         0
nearlySorted  12     0         0
nearlySorted  16     0         0
nearlySorted  24     0         0
nearlySorted  32     0.6       18.75
nearlySorted  40     0.6       15
nearlySorted  48     0.4       8.33
nearlySorted  56     0.4       7.14
nearlySorted  64     0.8       12.5
nearlySorted  72     1         13.89
nearlySorted  80     0.8       10
nearlySorted  96     1         10.42
nearlySorted  112    1.2       10.71
nearlySorted  128    1         7.81
nearlySorted  192    2.4       12.5
nearlySorted  256    3.4       13.28
nearlySorted  384    6         15.63
nearlySorted  512    8.4       16.41
nearlySorted  768    13.2      17.19
nearlySorted  1000   21.2      21.2
nearlySorted  2000   47.8      23.9
nearlySorted  5000   140       28
sawtooth      8      0         0
sawtooth      12     0         0
sawtooth      16     0         0
sawtooth      24     0         0
sawtooth      32     0.4       12.5
sawtooth      40     1.2       30
sawtooth      48     1         20.83
sawtooth      56     1         17.86
sawtooth      64     1.2       18.75
sawtooth      72     1.8       25
sawtooth      80     1.2       15
sawtooth      96     2.2       22.92
sawtooth      112    2.8       25
sawtooth      128    3.4       26.56
sawtooth      192    5.2       27.08
sawtooth      256    7.6       29.69
sawtooth      384    11.6      30.21
sawtooth      512    13        25.39
sawtooth      768    18.8      24.48
sawtooth      1000   24.2      24.2
sawtooth      2000   50        25
sawtooth      5000   131       26.2
endsHeavy     8      0         0
endsHeavy     12     0         0
endsHeavy     16     0.2       12.5
endsHeavy     24     0         0
endsHeavy     32     1         31.25
endsHeavy     40     0.8       20
endsHeavy     48     1.8       37.5
endsHeavy     56     1         17.86
endsHeavy     64     1.4       21.88
endsHeavy     72     1.6       22.22
endsHeavy     80     2         25
endsHeavy     96     2.4       25
endsHeavy     112    3.6       32.14
endsHeavy     128    3.2       25
endsHeavy     192    5.8       30.21
endsHeavy     256    8         31.25
endsHeavy     384    12.8      33.33
endsHeavy     512    18.4      35.94
endsHeavy     768    29        37.76
endsHeavy     1000   39        39
endsHeavy     2000   82        41
endsHeavy     5000   233.6     46.72
fewUniques    8      0.2       25
fewUniques    12     0         0
fewUniques    16     0.2       12.5
fewUniques    24     0         0
fewUniques    32     0.2       6.25
fewUniques    40     0.6       15
fewUniques    48     1         20.83
fewUniques    56     1         17.86
fewUniques    64     1.4       21.88
fewUniques    72     1.6       22.22
fewUniques    80     1.8       22.5
fewUniques    96     2.2       22.92
fewUniques    112    3         26.79
fewUniques    128    3.4       26.56
fewUniques    192    5.2       27.08
fewUniques    256    7.6       29.69
fewUniques    384    12        31.25
fewUniques    512    16.8      32.81
fewUniques    768    27.4      35.68
fewUniques    1000   37.4      37.4
fewUniques    2000   82.6      41.3
fewUniques    5000   231.6     46.32
altHighLow    8      0         0
altHighLow    12     0         0
altHighLow    16     0.2       12.5
altHighLow    24     0.2       8.33
altHighLow    32     1         31.25
altHighLow    40     1.2       30
altHighLow    48     1         20.83
altHighLow    56     1.2       21.43
altHighLow    64     1.6       25
altHighLow    72     1.6       22.22
altHighLow    80     2.2       27.5
altHighLow    96     2.6       27.08
altHighLow    112    2.6       23.21
altHighLow    128    3.2       25
altHighLow    192    5         26.04
altHighLow    256    6.6       25.78
altHighLow    384    10.2      26.56
altHighLow    512    14.2      27.73
altHighLow    768    20.8      27.08
altHighLow    1000   28.2      28.2
altHighLow    2000   60.4      30.2
altHighLow    5000   162.8     32.56
withInvalid   8      0         0
withInvalid   12     0         0
withInvalid   16     0         0
withInvalid   24     0         0
withInvalid   32     0.2       6.25
withInvalid   40     0.8       20
withInvalid   48     0.6       12.5
withInvalid   56     1         17.86
withInvalid   64     1         15.63
withInvalid   72     1.2       16.67
withInvalid   80     1.6       20
withInvalid   96     1.4       14.58
withInvalid   112    2.4       21.43
withInvalid   128    2.4       18.75
withInvalid   192    4.6       23.96
withInvalid   256    5.8       22.66
withInvalid   384    9.2       23.96
withInvalid   512    13.2      25.78
withInvalid   768    22.4      29.17
withInvalid   1000   29.8      29.8
withInvalid   2000   63        31.5
withInvalid   5000   178.6     35.72
allSame       8      0         0
allSame       12     0         0
allSame       16     0.2       12.5
allSame       24     0         0
allSame       32     0         0
allSame       40     0.2       5
allSame       48     0         0
allSame       56     0         0
allSame       64     0         0
allSame       72     0         0
allSame       80     0.2       2.5
allSame       96     0.4       4.17
allSame       112    0         0
allSame       128    0.2       1.56
allSame       192    0.6       3.12
allSame       256    0.6       2.34
allSame       384    0.2       0.52
allSame       512    0.6       1.17
allSame       768    0.8       1.04
allSame       1000   1.2       1.2
allSame       2000   2.8       1.4
allSame       5000   6.2       1.24
------------------------------------------------------------
 断言统计: total=449, failed=0
 ✅ 全部断言通过
============================================================
 完成，结果已写入 _root.gameworld.BulletQueueBench.results
============================================================