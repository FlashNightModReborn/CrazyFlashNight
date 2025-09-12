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
鲁棒性测试: 8 通过, 0 失败
====================================================

dist          n      ms_avg    ms/1k
------------------------------------------------------------
ascending     8      0.4       50
ascending     12     0.2       16.67
ascending     16     0.4       25
ascending     24     0.2       8.33
ascending     32     0.2       6.25
ascending     40     0.2       5
ascending     48     0.2       4.17
ascending     56     0.4       7.14
ascending     64     0.2       3.13
ascending     72     0.4       5.56
ascending     80     0.2       2.5
ascending     96     0.6       6.25
ascending     112    0.6       5.36
ascending     128    0.6       4.69
ascending     192    0.6       3.12
ascending     256    0.8       3.13
ascending     384    1.2       3.12
ascending     512    1.8       3.52
ascending     768    3         3.91
ascending     1000   3.4       3.4
ascending     2000   5.2       2.6
ascending     5000   15.4      3.08
descending    8      0         0
descending    12     0.2       16.67
descending    16     0.6       37.5
descending    24     1         41.67
descending    32     0.4       12.5
descending    40     0.6       15
descending    48     0.6       12.5
descending    56     1         17.86
descending    64     1         15.63
descending    72     1.2       16.67
descending    80     1         12.5
descending    96     1.6       16.67
descending    112    1.2       10.71
descending    128    2         15.63
descending    192    3.2       16.67
descending    256    3.6       14.06
descending    384    5.6       14.58
descending    512    7         13.67
descending    768    11        14.32
descending    1000   14.4      14.4
descending    2000   28.6      14.3
descending    5000   67        13.4
random        8      0.4       50
random        12     0         0
random        16     0.2       12.5
random        24     0.6       25
random        32     1.2       37.5
random        40     1.8       45
random        48     2.4       50
random        56     2.8       50
random        64     4.2       65.63
random        72     4.6       63.89
random        80     4.4       55
random        96     7         72.92
random        112    8.2       73.21
random        128    7.8       60.94
random        192    13.8      71.88
random        256    19.6      76.56
random        384    31.2      81.25
random        512    43.2      84.38
random        768    69.2      90.1
random        1000   88.2      88.2
random        2000   200.8     100.4
random        5000   547.6     109.52
nearlySorted  8      0         0
nearlySorted  12     0.2       16.67
nearlySorted  16     0.4       25
nearlySorted  24     0.2       8.33
nearlySorted  32     0.6       18.75
nearlySorted  40     1.6       40
nearlySorted  48     1.2       25
nearlySorted  56     1.4       25
nearlySorted  64     1.6       25
nearlySorted  72     1.2       16.67
nearlySorted  80     2.4       30
nearlySorted  96     2.4       25
nearlySorted  112    3         26.79
nearlySorted  128    2.8       21.88
nearlySorted  192    5         26.04
nearlySorted  256    9.4       36.72
nearlySorted  384    14.4      37.5
nearlySorted  512    19.8      38.67
nearlySorted  768    31.2      40.63
nearlySorted  1000   48.6      48.6
nearlySorted  2000   115.6     57.8
nearlySorted  5000   336       67.2
sawtooth      8      0.2       25
sawtooth      12     0.2       16.67
sawtooth      16     0.2       12.5
sawtooth      24     0.6       25
sawtooth      32     2.6       81.25
sawtooth      40     2.2       55
sawtooth      48     3.2       66.67
sawtooth      56     2.8       50
sawtooth      64     3.4       53.13
sawtooth      72     3.8       52.78
sawtooth      80     4.4       55
sawtooth      96     5.2       54.17
sawtooth      112    5.8       51.79
sawtooth      128    7.6       59.38
sawtooth      192    12.6      65.63
sawtooth      256    17        66.41
sawtooth      384    29.2      76.04
sawtooth      512    32        62.5
sawtooth      768    46.2      60.16
sawtooth      1000   61.8      61.8
sawtooth      2000   116.6     58.3
sawtooth      5000   303.8     60.76
endsHeavy     8      0         0
endsHeavy     12     0.2       16.67
endsHeavy     16     0.4       25
endsHeavy     24     0.4       16.67
endsHeavy     32     1.4       43.75
endsHeavy     40     2         50
endsHeavy     48     3         62.5
endsHeavy     56     3         53.57
endsHeavy     64     3.6       56.25
endsHeavy     72     4         55.56
endsHeavy     80     5         62.5
endsHeavy     96     5.8       60.42
endsHeavy     112    6.6       58.93
endsHeavy     128    9         70.31
endsHeavy     192    14.6      76.04
endsHeavy     256    17.2      67.19
endsHeavy     384    29.2      76.04
endsHeavy     512    42.8      83.59
endsHeavy     768    67        87.24
endsHeavy     1000   90.4      90.4
endsHeavy     2000   198.2     99.1
endsHeavy     5000   489.4     97.88
fewUniques    8      0.2       25
fewUniques    12     0         0
fewUniques    16     0.2       12.5
fewUniques    24     0.2       8.33
fewUniques    32     0.8       25
fewUniques    40     1         25
fewUniques    48     1         20.83
fewUniques    56     1.4       25
fewUniques    64     1.8       28.13
fewUniques    72     2         27.78
fewUniques    80     2.2       27.5
fewUniques    96     2.4       25
fewUniques    112    3.2       28.57
fewUniques    128    3.8       29.69
fewUniques    192    6         31.25
fewUniques    256    8.2       32.03
fewUniques    384    13        33.85
fewUniques    512    18.8      36.72
fewUniques    768    28.8      37.5
fewUniques    1000   38.4      38.4
fewUniques    2000   87        43.5
fewUniques    5000   238.4     47.68
altHighLow    8      0         0
altHighLow    12     0.2       16.67
altHighLow    16     0         0
altHighLow    24     0         0
altHighLow    32     0.6       18.75
altHighLow    40     0.8       20
altHighLow    48     1         20.83
altHighLow    56     1.2       21.43
altHighLow    64     1.6       25
altHighLow    72     1.6       22.22
altHighLow    80     1.8       22.5
altHighLow    96     2         20.83
altHighLow    112    2.6       23.21
altHighLow    128    3         23.44
altHighLow    192    5         26.04
altHighLow    256    6.8       26.56
altHighLow    384    10        26.04
altHighLow    512    14.2      27.73
altHighLow    768    21.2      27.6
altHighLow    1000   29.2      29.2
altHighLow    2000   62.8      31.4
altHighLow    5000   164.2     32.84
withInvalid   8      0         0
withInvalid   12     0         0
withInvalid   16     0         0
withInvalid   24     0.2       8.33
withInvalid   32     0.2       6.25
withInvalid   40     0.8       20
withInvalid   48     1         20.83
withInvalid   56     1         17.86
withInvalid   64     1.2       18.75
withInvalid   72     1.6       22.22
withInvalid   80     2         25
withInvalid   96     2         20.83
withInvalid   112    2         17.86
withInvalid   128    2.6       20.31
withInvalid   192    4.6       23.96
withInvalid   256    6.4       25
withInvalid   384    10.2      26.56
withInvalid   512    14.4      28.13
withInvalid   768    21.6      28.13
withInvalid   1000   28.8      28.8
withInvalid   2000   69.8      34.9
withInvalid   5000   188.8     37.76
allSame       8      0         0
allSame       12     0         0
allSame       16     0         0
allSame       24     0         0
allSame       32     0         0
allSame       40     0         0
allSame       48     0.2       4.17
allSame       56     0.2       3.57
allSame       64     0.2       3.13
allSame       72     0         0
allSame       80     0         0
allSame       96     0         0
allSame       112    0.2       1.79
allSame       128    0.2       1.56
allSame       192    0         0
allSame       256    0.4       1.56
allSame       384    0.8       2.08
allSame       512    0.6       1.17
allSame       768    1         1.3
allSame       1000   1         1
allSame       2000   2.4       1.2
allSame       5000   6.2       1.24
------------------------------------------------------------
 断言统计: total=448, failed=0
 ✅ 全部断言通过
============================================================
 完成，结果已写入 _root.gameworld.BulletQueueBench.results
============================================================