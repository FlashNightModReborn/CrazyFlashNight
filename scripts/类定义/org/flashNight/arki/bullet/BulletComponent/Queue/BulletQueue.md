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
[FAIL] processAndClear方法测试
鲁棒性测试: 7 通过, 1 失败
====================================================

dist          n      ms_avg    ms/1k
------------------------------------------------------------
ascending     8      0.2       25
ascending     12     0         0
ascending     16     0.2       12.5
ascending     24     0.2       8.33
ascending     32     0         0
ascending     40     0         0
ascending     48     0         0
ascending     56     0         0
ascending     64     0.2       3.13
ascending     72     0         0
ascending     80     0         0
ascending     96     0.4       4.17
ascending     112    0         0
ascending     128    0         0
ascending     192    0.4       2.08
ascending     256    0.8       3.13
ascending     384    0.8       2.08
ascending     512    0.8       1.56
ascending     768    1.4       1.82
ascending     1000   1.6       1.6
ascending     2000   2.6       1.3
ascending     5000   7.4       1.48
descending    8      0         0
descending    12     0.4       33.33
descending    16     0.2       12.5
descending    24     0.6       25
descending    32     0.2       6.25
descending    40     0.6       15
descending    48     0.2       4.17
descending    56     0         0
descending    64     0.8       12.5
descending    72     0.2       2.78
descending    80     0.6       7.5
descending    96     0.2       2.08
descending    112    0.6       5.36
descending    128    1.2       9.38
descending    192    1         5.21
descending    256    1.4       5.47
descending    384    2.2       5.73
descending    512    3         5.86
descending    768    5.4       7.03
descending    1000   7.8       7.8
descending    2000   14.8      7.4
descending    5000   34        6.8
random        8      0         0
random        12     0         0
random        16     0         0
random        24     0.6       25
random        32     1         31.25
random        40     0.6       15
random        48     0.8       16.67
random        56     1.2       21.43
random        64     1.4       21.88
random        72     1.6       22.22
random        80     2.8       35
random        96     2.4       25
random        112    2.6       23.21
random        128    4.2       32.81
random        192    6.8       35.42
random        256    11.6      45.31
random        384    18        46.88
random        512    26.2      51.17
random        768    40        52.08
random        1000   57.8      57.8
random        2000   127.6     63.8
random        5000   260.4     52.08
nearlySorted  8      0         0
nearlySorted  12     0         0
nearlySorted  16     0         0
nearlySorted  24     0.2       8.33
nearlySorted  32     0.2       6.25
nearlySorted  40     0.2       5
nearlySorted  48     1.2       25
nearlySorted  56     1.2       21.43
nearlySorted  64     1         15.63
nearlySorted  72     0.8       11.11
nearlySorted  80     0.4       5
nearlySorted  96     1         10.42
nearlySorted  112    1.2       10.71
nearlySorted  128    1.2       9.38
nearlySorted  192    2.8       14.58
nearlySorted  256    3.8       14.84
nearlySorted  384    6.2       16.15
nearlySorted  512    10        19.53
nearlySorted  768    17.6      22.92
nearlySorted  1000   22.6      22.6
nearlySorted  2000   57.6      28.8
nearlySorted  5000   157.4     31.48
sawtooth      8      0.2       25
sawtooth      12     0.2       16.67
sawtooth      16     0.2       12.5
sawtooth      24     0         0
sawtooth      32     0.4       12.5
sawtooth      40     0.6       15
sawtooth      48     1.4       29.17
sawtooth      56     1.6       28.57
sawtooth      64     1.6       25
sawtooth      72     1.2       16.67
sawtooth      80     2.2       27.5
sawtooth      96     2         20.83
sawtooth      112    2.4       21.43
sawtooth      128    3.2       25
sawtooth      192    8         41.67
sawtooth      256    11.8      46.09
sawtooth      384    15.4      40.1
sawtooth      512    15        29.3
sawtooth      768    21.8      28.39
sawtooth      1000   28.6      28.6
sawtooth      2000   67.8      33.9
sawtooth      5000   152.2     30.44
endsHeavy     8      0         0
endsHeavy     12     0.2       16.67
endsHeavy     16     0.2       12.5
endsHeavy     24     0         0
endsHeavy     32     0.6       18.75
endsHeavy     40     0.8       20
endsHeavy     48     1.8       37.5
endsHeavy     56     1.4       25
endsHeavy     64     1.6       25
endsHeavy     72     1.8       25
endsHeavy     80     2.2       27.5
endsHeavy     96     3         31.25
endsHeavy     112    3.2       28.57
endsHeavy     128    3.4       26.56
endsHeavy     192    7         36.46
endsHeavy     256    7.8       30.47
endsHeavy     384    13.6      35.42
endsHeavy     512    18.2      35.55
endsHeavy     768    41        53.39
endsHeavy     1000   38.4      38.4
endsHeavy     2000   96        48
endsHeavy     5000   274.8     54.96
fewUniques    8      0         0
fewUniques    12     0         0
fewUniques    16     0         0
fewUniques    24     0.2       8.33
fewUniques    32     1         31.25
fewUniques    40     1.2       30
fewUniques    48     1         20.83
fewUniques    56     1         17.86
fewUniques    64     1.4       21.88
fewUniques    72     1.8       25
fewUniques    80     1.4       17.5
fewUniques    96     2.4       25
fewUniques    112    2.8       25
fewUniques    128    3         23.44
fewUniques    192    6.2       32.29
fewUniques    256    7.8       30.47
fewUniques    384    15        39.06
fewUniques    512    19.8      38.67
fewUniques    768    36        46.88
fewUniques    1000   45        45
fewUniques    2000   89.8      44.9
fewUniques    5000   253       50.6
altHighLow    8      0         0
altHighLow    12     0.2       16.67
altHighLow    16     0.2       12.5
altHighLow    24     0         0
altHighLow    32     0.6       18.75
altHighLow    40     1.2       30
altHighLow    48     1         20.83
altHighLow    56     1.2       21.43
altHighLow    64     1.8       28.13
altHighLow    72     1.4       19.44
altHighLow    80     2.4       30
altHighLow    96     2.4       25
altHighLow    112    2         17.86
altHighLow    128    3.2       25
altHighLow    192    5         26.04
altHighLow    256    6.2       24.22
altHighLow    384    10.8      28.13
altHighLow    512    13.8      26.95
altHighLow    768    21.4      27.86
altHighLow    1000   33        33
altHighLow    2000   69.8      34.9
altHighLow    5000   213       42.6
withInvalid   8      0         0
withInvalid   12     0.2       16.67
withInvalid   16     0.2       12.5
withInvalid   24     0.4       16.67
withInvalid   32     0.2       6.25
withInvalid   40     0.8       20
withInvalid   48     1         20.83
withInvalid   56     1.4       25
withInvalid   64     2         31.25
withInvalid   72     1.4       19.44
withInvalid   80     1.4       17.5
withInvalid   96     2         20.83
withInvalid   112    2.6       23.21
withInvalid   128    4         31.25
withInvalid   192    4.6       23.96
withInvalid   256    6.2       24.22
withInvalid   384    11.4      29.69
withInvalid   512    15.8      30.86
withInvalid   768    24.4      31.77
withInvalid   1000   39.2      39.2
withInvalid   2000   75.4      37.7
withInvalid   5000   201.4     40.28
allSame       8      0         0
allSame       12     0         0
allSame       16     0         0
allSame       24     0.2       8.33
allSame       32     0.2       6.25
allSame       40     0         0
allSame       48     0         0
allSame       56     0         0
allSame       64     0         0
allSame       72     0         0
allSame       80     0         0
allSame       96     0         0
allSame       112    0         0
allSame       128    0         0
allSame       192    0.2       1.04
allSame       256    0.4       1.56
allSame       384    0.2       0.52
allSame       512    1         1.95
allSame       768    0.8       1.04
allSame       1000   1.6       1.6
allSame       2000   3         1.5
allSame       5000   6.6       1.32
------------------------------------------------------------
 断言统计: total=448, failed=1
 ❌ 存在断言失败，请检查上方 FAIL 日志
============================================================
 完成，结果已写入 _root.gameworld.BulletQueueBench.results
============================================================
