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
鲁棒性测试: 7 通过, 0 失败
====================================================

dist          n      ms_avg    ms/1k
------------------------------------------------------------
ascending     8      0         0
ascending     12     0         0
ascending     16     0         0
ascending     24     0.2       8.33
ascending     32     0         0
ascending     40     0         0
ascending     48     0.2       4.17
ascending     56     0         0
ascending     64     0.2       3.13
ascending     72     0         0
ascending     80     0         0
ascending     96     0         0
ascending     112    0.2       1.79
ascending     128    0         0
ascending     192    0.6       3.12
ascending     256    0         0
ascending     384    0.6       1.56
ascending     512    0.4       0.78
ascending     768    1.2       1.56
ascending     1000   1         1
ascending     2000   3         1.5
ascending     5000   6.4       1.28
descending    8      0         0
descending    12     0.4       33.33
descending    16     0         0
descending    24     0.2       8.33
descending    32     0.2       6.25
descending    40     0.4       10
descending    48     0.4       8.33
descending    56     0.6       10.71
descending    64     1         15.63
descending    72     1         13.89
descending    80     1         12.5
descending    96     0.6       6.25
descending    112    1         8.93
descending    128    0.8       6.25
descending    192    1.4       7.29
descending    256    1.6       6.25
descending    384    2         5.21
descending    512    3.2       6.25
descending    768    4.6       5.99
descending    1000   5.6       5.6
descending    2000   12.6      6.3
descending    5000   31.8      6.36
random        8      0         0
random        12     0         0
random        16     0         0
random        24     0.4       16.67
random        32     0.4       12.5
random        40     1         25
random        48     1.4       29.17
random        56     2         35.71
random        64     1         15.63
random        72     2         27.78
random        80     2         25
random        96     2.4       25
random        112    3.8       33.93
random        128    3.6       28.13
random        192    5.8       30.21
random        256    7.8       30.47
random        384    12.8      33.33
random        512    18.8      36.72
random        768    29        37.76
random        1000   39.4      39.4
random        2000   87.4      43.7
random        5000   241       48.2
nearlySorted  8      0         0
nearlySorted  12     0         0
nearlySorted  16     0         0
nearlySorted  24     0         0
nearlySorted  32     0.4       12.5
nearlySorted  40     0.2       5
nearlySorted  48     0.6       12.5
nearlySorted  56     1.2       21.43
nearlySorted  64     0.8       12.5
nearlySorted  72     1         13.89
nearlySorted  80     0.8       10
nearlySorted  96     1         10.42
nearlySorted  112    1.6       14.29
nearlySorted  128    1.8       14.06
nearlySorted  192    2.4       12.5
nearlySorted  256    3.2       12.5
nearlySorted  384    6.2       16.15
nearlySorted  512    8.2       16.02
nearlySorted  768    14.2      18.49
nearlySorted  1000   21.6      21.6
nearlySorted  2000   53.2      26.6
nearlySorted  5000   146.2     29.24
sawtooth      8      0.2       25
sawtooth      12     0         0
sawtooth      16     0         0
sawtooth      24     0.2       8.33
sawtooth      32     1         31.25
sawtooth      40     1         25
sawtooth      48     1.2       25
sawtooth      56     1.8       32.14
sawtooth      64     2         31.25
sawtooth      72     1.2       16.67
sawtooth      80     1         12.5
sawtooth      96     2.6       27.08
sawtooth      112    2.4       21.43
sawtooth      128    4.4       34.38
sawtooth      192    5.4       28.13
sawtooth      256    7.2       28.13
sawtooth      384    12.2      31.77
sawtooth      512    14.6      28.52
sawtooth      768    19.6      25.52
sawtooth      1000   27.4      27.4
sawtooth      2000   48.4      24.2
sawtooth      5000   146.6     29.32
endsHeavy     8      0         0
endsHeavy     12     0         0
endsHeavy     16     0.2       12.5
endsHeavy     24     0.2       8.33
endsHeavy     32     0.2       6.25
endsHeavy     40     1         25
endsHeavy     48     1.2       25
endsHeavy     56     1.4       25
endsHeavy     64     1.8       28.13
endsHeavy     72     1.8       25
endsHeavy     80     1.6       20
endsHeavy     96     2.8       29.17
endsHeavy     112    3         26.79
endsHeavy     128    3.6       28.13
endsHeavy     192    5.4       28.13
endsHeavy     256    9.2       35.94
endsHeavy     384    12.6      32.81
endsHeavy     512    17.8      34.77
endsHeavy     768    30        39.06
endsHeavy     1000   40.2      40.2
endsHeavy     2000   87.2      43.6
endsHeavy     5000   244.8     48.96
fewUniques    8      0         0
fewUniques    12     0         0
fewUniques    16     0.2       12.5
fewUniques    24     0         0
fewUniques    32     1         31.25
fewUniques    40     0.6       15
fewUniques    48     1         20.83
fewUniques    56     1.8       32.14
fewUniques    64     2.4       37.5
fewUniques    72     3         41.67
fewUniques    80     2.2       27.5
fewUniques    96     2.6       27.08
fewUniques    112    3         26.79
fewUniques    128    3.4       26.56
fewUniques    192    5.8       30.21
fewUniques    256    8.2       32.03
fewUniques    384    12.4      32.29
fewUniques    512    19.4      37.89
fewUniques    768    29        37.76
fewUniques    1000   39.6      39.6
fewUniques    2000   83.8      41.9
fewUniques    5000   243.4     48.68
altHighLow    8      0.2       25
altHighLow    12     0         0
altHighLow    16     0.6       37.5
altHighLow    24     0.2       8.33
altHighLow    32     0.4       12.5
altHighLow    40     1         25
altHighLow    48     1.4       29.17
altHighLow    56     1.6       28.57
altHighLow    64     1.6       25
altHighLow    72     1.8       25
altHighLow    80     1.8       22.5
altHighLow    96     2.4       25
altHighLow    112    2.8       25
altHighLow    128    3         23.44
altHighLow    192    4.8       25
altHighLow    256    7         27.34
altHighLow    384    10        26.04
altHighLow    512    15.6      30.47
altHighLow    768    22        28.65
altHighLow    1000   28.8      28.8
altHighLow    2000   62        31
altHighLow    5000   172       34.4
withInvalid   8      0         0
withInvalid   12     0         0
withInvalid   16     0         0
withInvalid   24     0.4       16.67
withInvalid   32     0.2       6.25
withInvalid   40     0.6       15
withInvalid   48     0.8       16.67
withInvalid   56     0.8       14.29
withInvalid   64     1.2       18.75
withInvalid   72     2         27.78
withInvalid   80     2.2       27.5
withInvalid   96     1.6       16.67
withInvalid   112    2.6       23.21
withInvalid   128    2.8       21.88
withInvalid   192    4.2       21.88
withInvalid   256    6.2       24.22
withInvalid   384    9.8       25.52
withInvalid   512    16        31.25
withInvalid   768    22.6      29.43
withInvalid   1000   30.2      30.2
withInvalid   2000   69.2      34.6
withInvalid   5000   185.2     37.04
allSame       8      0         0
allSame       12     0         0
allSame       16     0         0
allSame       24     0.2       8.33
allSame       32     0         0
allSame       40     0         0
allSame       48     0         0
allSame       56     0         0
allSame       64     0         0
allSame       72     0         0
allSame       80     0         0
allSame       96     0         0
allSame       112    0         0
allSame       128    0.4       3.13
allSame       192    0         0
allSame       256    0.6       2.34
allSame       384    0.6       1.56
allSame       512    0.6       1.17
allSame       768    0.8       1.04
allSame       1000   1.2       1.2
allSame       2000   2.6       1.3
allSame       5000   6.8       1.36
------------------------------------------------------------
 断言统计: total=447, failed=0
 ✅ 全部断言通过
============================================================
 完成，结果已写入 _root.gameworld.BulletQueueBench.results
============================================================
