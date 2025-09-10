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
ascending     32     0         0
ascending     40     0         0
ascending     48     0         0
ascending     56     0         0
ascending     64     0         0
ascending     72     0.2       2.78
ascending     80     0.2       2.5
ascending     96     0         0
ascending     112    0.6       5.36
ascending     128    0.2       1.56
ascending     192    0.2       1.04
ascending     256    0.4       1.56
ascending     384    0.6       1.56
ascending     512    0.6       1.17
ascending     768    1.2       1.56
ascending     1000   1.4       1.4
ascending     2000   2.6       1.3
ascending     5000   6.8       1.36
descending    8      0         0
descending    12     0         0
descending    16     0.2       12.5
descending    24     0.2       8.33
descending    32     0.6       18.75
descending    40     1.4       35
descending    48     1.2       25
descending    56     1.6       28.57
descending    64     1         15.63
descending    72     0.8       11.11
descending    80     0.6       7.5
descending    96     0.6       6.25
descending    112    0.6       5.36
descending    128    0.8       6.25
descending    192    1.2       6.25
descending    256    1.4       5.47
descending    384    1.6       4.17
descending    512    4.6       8.98
descending    768    5.6       7.29
descending    1000   6.4       6.4
descending    2000   11.2      5.6
descending    5000   31.2      6.24
random        8      0         0
random        12     0.2       16.67
random        16     0         0
random        24     0.2       8.33
random        32     0.4       12.5
random        40     0.6       15
random        48     1         20.83
random        56     0.6       10.71
random        64     1.6       25
random        72     1.6       22.22
random        80     2         25
random        96     2         20.83
random        112    2.8       25
random        128    3.4       26.56
random        192    5.2       27.08
random        256    8.2       32.03
random        384    13.2      34.37
random        512    18.4      35.94
random        768    28        36.46
random        1000   37.8      37.8
random        2000   87.2      43.6
random        5000   239.8     47.96
nearlySorted  8      0         0
nearlySorted  12     0         0
nearlySorted  16     0         0
nearlySorted  24     0         0
nearlySorted  32     0         0
nearlySorted  40     0.2       5
nearlySorted  48     0.2       4.17
nearlySorted  56     0.2       3.57
nearlySorted  64     0.6       9.38
nearlySorted  72     0.6       8.33
nearlySorted  80     0.8       10
nearlySorted  96     0.6       6.25
nearlySorted  112    1.4       12.5
nearlySorted  128    1.4       10.94
nearlySorted  192    2.2       11.46
nearlySorted  256    3.6       14.06
nearlySorted  384    5.8       15.1
nearlySorted  512    8.8       17.19
nearlySorted  768    14.2      18.49
nearlySorted  1000   20.4      20.4
nearlySorted  2000   50.4      25.2
nearlySorted  5000   145.2     29.04
sawtooth      8      0         0
sawtooth      12     0.2       16.67
sawtooth      16     0         0
sawtooth      24     0         0
sawtooth      32     0.4       12.5
sawtooth      40     0.4       10
sawtooth      48     0.8       16.67
sawtooth      56     1         17.86
sawtooth      64     1.4       21.88
sawtooth      72     2.2       30.56
sawtooth      80     1.6       20
sawtooth      96     2.6       27.08
sawtooth      112    2.4       21.43
sawtooth      128    3.6       28.13
sawtooth      192    5         26.04
sawtooth      256    7.2       28.13
sawtooth      384    11.4      29.69
sawtooth      512    13.4      26.17
sawtooth      768    19.2      25
sawtooth      1000   26.8      26.8
sawtooth      2000   51        25.5
sawtooth      5000   127.2     25.44
endsHeavy     8      0         0
endsHeavy     12     0.2       16.67
endsHeavy     16     0.4       25
endsHeavy     24     0         0
endsHeavy     32     0         0
endsHeavy     40     0.2       5
endsHeavy     48     1.2       25
endsHeavy     56     0.8       14.29
endsHeavy     64     1.6       25
endsHeavy     72     1.8       25
endsHeavy     80     1.6       20
endsHeavy     96     2.8       29.17
endsHeavy     112    3.4       30.36
endsHeavy     128    3.4       26.56
endsHeavy     192    6         31.25
endsHeavy     256    7.8       30.47
endsHeavy     384    15        39.06
endsHeavy     512    19.6      38.28
endsHeavy     768    29        37.76
endsHeavy     1000   37.4      37.4
endsHeavy     2000   84.8      42.4
endsHeavy     5000   238.4     47.68
fewUniques    8      0         0
fewUniques    12     0         0
fewUniques    16     0         0
fewUniques    24     0.2       8.33
fewUniques    32     0.6       18.75
fewUniques    40     0.6       15
fewUniques    48     0.2       4.17
fewUniques    56     0.8       14.29
fewUniques    64     2         31.25
fewUniques    72     1.4       19.44
fewUniques    80     2         25
fewUniques    96     2.8       29.17
fewUniques    112    2.4       21.43
fewUniques    128    4         31.25
fewUniques    192    5.2       27.08
fewUniques    256    8.6       33.59
fewUniques    384    12        31.25
fewUniques    512    17.8      34.77
fewUniques    768    27.4      35.68
fewUniques    1000   38        38
fewUniques    2000   85        42.5
fewUniques    5000   233.6     46.72
altHighLow    8      0         0
altHighLow    12     0.2       16.67
altHighLow    16     0.2       12.5
altHighLow    24     0.2       8.33
altHighLow    32     0.8       25
altHighLow    40     1         25
altHighLow    48     1         20.83
altHighLow    56     1.2       21.43
altHighLow    64     1         15.63
altHighLow    72     1.2       16.67
altHighLow    80     1.6       20
altHighLow    96     2         20.83
altHighLow    112    2.6       23.21
altHighLow    128    2.8       21.88
altHighLow    192    5.2       27.08
altHighLow    256    6.8       26.56
altHighLow    384    9.8       25.52
altHighLow    512    13.4      26.17
altHighLow    768    21.6      28.13
altHighLow    1000   27.4      27.4
altHighLow    2000   63.4      31.7
altHighLow    5000   166       33.2
withInvalid   8      0         0
withInvalid   12     0.2       16.67
withInvalid   16     0.2       12.5
withInvalid   24     0.2       8.33
withInvalid   32     0         0
withInvalid   40     0.4       10
withInvalid   48     0.2       4.17
withInvalid   56     1         17.86
withInvalid   64     1.4       21.88
withInvalid   72     1.4       19.44
withInvalid   80     2.4       30
withInvalid   96     1.8       18.75
withInvalid   112    1.8       16.07
withInvalid   128    3.4       26.56
withInvalid   192    4.8       25
withInvalid   256    5.8       22.66
withInvalid   384    10        26.04
withInvalid   512    13.4      26.17
withInvalid   768    22.8      29.69
withInvalid   1000   30        30
withInvalid   2000   66        33
withInvalid   5000   181.6     36.32
allSame       8      0         0
allSame       12     0         0
allSame       16     0         0
allSame       24     0         0
allSame       32     0         0
allSame       40     0         0
allSame       48     0.2       4.17
allSame       56     0         0
allSame       64     0.6       9.38
allSame       72     0         0
allSame       80     0         0
allSame       96     0         0
allSame       112    0         0
allSame       128    0         0
allSame       192    0.2       1.04
allSame       256    0.4       1.56
allSame       384    0.2       0.52
allSame       512    0.6       1.17
allSame       768    1         1.3
allSame       1000   1.2       1.2
allSame       2000   2.2       1.1
allSame       5000   6.8       1.36
------------------------------------------------------------
 断言统计: total=447, failed=0
 ✅ 全部断言通过
============================================================
 完成，结果已写入 _root.gameworld.BulletQueueBench.results
============================================================