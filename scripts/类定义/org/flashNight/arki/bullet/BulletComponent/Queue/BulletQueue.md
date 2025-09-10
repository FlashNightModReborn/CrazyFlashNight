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
ascending     24     0         0
ascending     32     0.2       6.25
ascending     40     0.2       5
ascending     48     0.2       4.17
ascending     56     0         0
ascending     64     0.6       9.38
ascending     72     0         0
ascending     80     0.2       2.5
ascending     96     0.2       2.08
ascending     112    0         0
ascending     128    0.2       1.56
ascending     192    0.4       2.08
ascending     256    0.2       0.78
ascending     384    1         2.6
ascending     512    0.6       1.17
ascending     768    1         1.3
ascending     1000   1.6       1.6
ascending     2000   2.4       1.2
ascending     5000   6.4       1.28
descending    8      0         0
descending    12     0         0
descending    16     0         0
descending    24     0.6       25
descending    32     0.6       18.75
descending    40     1         25
descending    48     1.2       25
descending    56     1.4       25
descending    64     0.2       3.13
descending    72     0.2       2.78
descending    80     0.4       5
descending    96     0.4       4.17
descending    112    0.8       7.14
descending    128    0.8       6.25
descending    192    1         5.21
descending    256    1.8       7.03
descending    384    2.2       5.73
descending    512    3.2       6.25
descending    768    5         6.51
descending    1000   5.8       5.8
descending    2000   10.8      5.4
descending    5000   31        6.2
random        8      0         0
random        12     0         0
random        16     0.2       12.5
random        24     0.6       25
random        32     0.2       6.25
random        40     0.4       10
random        48     1.2       25
random        56     0.6       10.71
random        64     2         31.25
random        72     1.8       25
random        80     2.2       27.5
random        96     2.8       29.17
random        112    3.2       28.57
random        128    3.6       28.13
random        192    7.4       38.54
random        256    8.4       32.81
random        384    14.8      38.54
random        512    17.8      34.77
random        768    33.6      43.75
random        1000   47.8      47.8
random        2000   109.6     54.8
random        5000   534.6     106.92
nearlySorted  8      0         0
nearlySorted  12     0         0
nearlySorted  16     0         0
nearlySorted  24     0         0
nearlySorted  32     0.2       6.25
nearlySorted  40     0.4       10
nearlySorted  48     0.2       4.17
nearlySorted  56     0.2       3.57
nearlySorted  64     0         0
nearlySorted  72     0.2       2.78
nearlySorted  80     0.8       10
nearlySorted  96     1         10.42
nearlySorted  112    1.4       12.5
nearlySorted  128    1.2       9.38
nearlySorted  192    2.8       14.58
nearlySorted  256    3.6       14.06
nearlySorted  384    6         15.63
nearlySorted  512    8.8       17.19
nearlySorted  768    13.8      17.97
nearlySorted  1000   19.4      19.4
nearlySorted  2000   50        25
nearlySorted  5000   149.8     29.96
sawtooth      8      0         0
sawtooth      12     0         0
sawtooth      16     0         0
sawtooth      24     0.4       16.67
sawtooth      32     0.4       12.5
sawtooth      40     0.6       15
sawtooth      48     0.4       8.33
sawtooth      56     0.2       3.57
sawtooth      64     1.6       25
sawtooth      72     2.2       30.56
sawtooth      80     2         25
sawtooth      96     2.6       27.08
sawtooth      112    3.2       28.57
sawtooth      128    4         31.25
sawtooth      192    6.6       34.37
sawtooth      256    7.8       30.47
sawtooth      384    14.4      37.5
sawtooth      512    14        27.34
sawtooth      768    23        29.95
sawtooth      1000   31.2      31.2
sawtooth      2000   64.2      32.1
sawtooth      5000   172       34.4
endsHeavy     8      0         0
endsHeavy     12     0.2       16.67
endsHeavy     16     0.2       12.5
endsHeavy     24     0         0
endsHeavy     32     0.8       25
endsHeavy     40     0.2       5
endsHeavy     48     1         20.83
endsHeavy     56     1.2       21.43
endsHeavy     64     1.8       28.13
endsHeavy     72     2         27.78
endsHeavy     80     2.8       35
endsHeavy     96     2.8       29.17
endsHeavy     112    3.4       30.36
endsHeavy     128    4.4       34.38
endsHeavy     192    7.2       37.5
endsHeavy     256    6.8       26.56
endsHeavy     384    14.8      38.54
endsHeavy     512    19.4      37.89
endsHeavy     768    34.4      44.79
endsHeavy     1000   52.2      52.2
endsHeavy     2000   133.2     66.6
endsHeavy     5000   493.6     98.72
fewUniques    8      0.4       50
fewUniques    12     0         0
fewUniques    16     0         0
fewUniques    24     0         0
fewUniques    32     0.4       12.5
fewUniques    40     0.2       5
fewUniques    48     0.2       4.17
fewUniques    56     1.4       25
fewUniques    64     1.8       28.13
fewUniques    72     1.8       25
fewUniques    80     2         25
fewUniques    96     2.4       25
fewUniques    112    4.2       37.5
fewUniques    128    3.8       29.69
fewUniques    192    6.4       33.33
fewUniques    256    7.6       29.69
fewUniques    384    15        39.06
fewUniques    512    21.8      42.58
fewUniques    768    42.8      55.73
fewUniques    1000   85        85
fewUniques    2000   201.2     100.6
fewUniques    5000   573.2     114.64
altHighLow    8      0.2       25
altHighLow    12     0         0
altHighLow    16     0.2       12.5
altHighLow    24     0.2       8.33
altHighLow    32     0.8       25
altHighLow    40     1         25
altHighLow    48     0.8       16.67
altHighLow    56     1.4       25
altHighLow    64     1.6       25
altHighLow    72     2         27.78
altHighLow    80     2.4       30
altHighLow    96     2.8       29.17
altHighLow    112    3.2       28.57
altHighLow    128    4         31.25
altHighLow    192    5.8       30.21
altHighLow    256    8.6       33.59
altHighLow    384    14.2      36.98
altHighLow    512    18.8      36.72
altHighLow    768    28.8      37.5
altHighLow    1000   77.4      77.4
altHighLow    2000   177.2     88.6
altHighLow    5000   444       88.8
withInvalid   8      0         0
withInvalid   12     0         0
withInvalid   16     0         0
withInvalid   24     0         0
withInvalid   32     0.2       6.25
withInvalid   40     0.4       10
withInvalid   48     0.4       8.33
withInvalid   56     1         17.86
withInvalid   64     1.2       18.75
withInvalid   72     1         13.89
withInvalid   80     1.6       20
withInvalid   96     2.8       29.17
withInvalid   112    2         17.86
withInvalid   128    3.8       29.69
withInvalid   192    4.8       25
withInvalid   256    7.4       28.91
withInvalid   384    12        31.25
withInvalid   512    16        31.25
withInvalid   768    27.6      35.94
withInvalid   1000   38.4      38.4
withInvalid   2000   89        44.5
withInvalid   5000   429.2     85.84
allSame       8      0.2       25
allSame       12     0         0
allSame       16     0         0
allSame       24     0.2       8.33
allSame       32     0         0
allSame       40     0.2       5
allSame       48     0         0
allSame       56     0.2       3.57
allSame       64     0.4       6.25
allSame       72     0         0
allSame       80     0         0
allSame       96     0.6       6.25
allSame       112    0.4       3.57
allSame       128    0.2       1.56
allSame       192    0.8       4.17
allSame       256    0.4       1.56
allSame       384    0.4       1.04
allSame       512    0.4       0.78
allSame       768    1         1.3
allSame       1000   1.2       1.2
allSame       2000   2.6       1.3
allSame       5000   6.6       1.32
------------------------------------------------------------
 断言统计: total=447, failed=0
 ✅ 全部断言通过
============================================================
 完成，结果已写入 _root.gameworld.BulletQueueBench.results
============================================================