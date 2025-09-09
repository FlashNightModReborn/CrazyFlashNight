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
ascending     72     0.8       11.11
ascending     80     0         0
ascending     96     0.4       4.17
ascending     112    0         0
ascending     128    0.6       4.69
ascending     192    0.2       1.04
ascending     256    0.6       2.34
ascending     384    1         2.6
ascending     512    1.2       2.34
ascending     768    1.4       1.82
ascending     1000   2         2
ascending     2000   4.8       2.4
ascending     5000   10.8      2.16
descending    8      0         0
descending    12     0         0
descending    16     0.2       12.5
descending    24     0.4       16.67
descending    32     1         31.25
descending    40     1         25
descending    48     1.4       29.17
descending    56     1.8       32.14
descending    64     0.4       6.25
descending    72     0.8       11.11
descending    80     0.6       7.5
descending    96     0.6       6.25
descending    112    0.6       5.36
descending    128    0.8       6.25
descending    192    1.4       7.29
descending    256    2.4       9.38
descending    384    3         7.81
descending    512    4         7.81
descending    768    6.8       8.85
descending    1000   8.6       8.6
descending    2000   14.8      7.4
descending    5000   38.8      7.76
random        8      0         0
random        12     0         0
random        16     0.2       12.5
random        24     0.4       16.67
random        32     0.4       12.5
random        40     0.8       20
random        48     0.8       16.67
random        56     1         17.86
random        64     1.8       28.13
random        72     2         27.78
random        80     2.2       27.5
random        96     3         31.25
random        112    4.4       39.29
random        128    3.6       28.13
random        192    6.8       35.42
random        256    8.4       32.81
random        384    14.8      38.54
random        512    20.4      39.84
random        768    33.6      43.75
random        1000   48.2      48.2
random        2000   112.4     56.2
random        5000   510       102
nearlySorted  8      0         0
nearlySorted  12     0         0
nearlySorted  16     0.2       12.5
nearlySorted  24     0         0
nearlySorted  32     0         0
nearlySorted  40     0.4       10
nearlySorted  48     0         0
nearlySorted  56     0.4       7.14
nearlySorted  64     0.6       9.38
nearlySorted  72     0.4       5.56
nearlySorted  80     0.8       10
nearlySorted  96     0.8       8.33
nearlySorted  112    2         17.86
nearlySorted  128    2.2       17.19
nearlySorted  192    2         10.42
nearlySorted  256    3.6       14.06
nearlySorted  384    6.2       16.15
nearlySorted  512    8         15.63
nearlySorted  768    14.2      18.49
nearlySorted  1000   20.8      20.8
nearlySorted  2000   52.2      26.1
nearlySorted  5000   155       31
sawtooth      8      0         0
sawtooth      12     0         0
sawtooth      16     0         0
sawtooth      24     0         0
sawtooth      32     0         0
sawtooth      40     0.2       5
sawtooth      48     1         20.83
sawtooth      56     1         17.86
sawtooth      64     2.4       37.5
sawtooth      72     2.4       33.33
sawtooth      80     2.2       27.5
sawtooth      96     3         31.25
sawtooth      112    4         35.71
sawtooth      128    4.4       34.38
sawtooth      192    5.2       27.08
sawtooth      256    8.2       32.03
sawtooth      384    15.6      40.63
sawtooth      512    15.8      30.86
sawtooth      768    25.8      33.59
sawtooth      1000   28.8      28.8
sawtooth      2000   64.8      32.4
sawtooth      5000   166.8     33.36
endsHeavy     8      0         0
endsHeavy     12     0         0
endsHeavy     16     0         0
endsHeavy     24     0.4       16.67
endsHeavy     32     0.2       6.25
endsHeavy     40     1.2       30
endsHeavy     48     0.6       12.5
endsHeavy     56     1         17.86
endsHeavy     64     1.2       18.75
endsHeavy     72     1.8       25
endsHeavy     80     3.6       45
endsHeavy     96     3.4       35.42
endsHeavy     112    3.4       30.36
endsHeavy     128    3.2       25
endsHeavy     192    7         36.46
endsHeavy     256    8.6       33.59
endsHeavy     384    15        39.06
endsHeavy     512    18.4      35.94
endsHeavy     768    31.8      41.41
endsHeavy     1000   48        48
endsHeavy     2000   127       63.5
endsHeavy     5000   478.4     95.68
fewUniques    8      0.2       25
fewUniques    12     0         0
fewUniques    16     0         0
fewUniques    24     0.4       16.67
fewUniques    32     0.4       12.5
fewUniques    40     0.4       10
fewUniques    48     1.2       25
fewUniques    56     0.6       10.71
fewUniques    64     2.2       34.38
fewUniques    72     1.6       22.22
fewUniques    80     2.2       27.5
fewUniques    96     3.8       39.58
fewUniques    112    4.6       41.07
fewUniques    128    3.4       26.56
fewUniques    192    6.4       33.33
fewUniques    256    8.4       32.81
fewUniques    384    18.4      47.92
fewUniques    512    23        44.92
fewUniques    768    38        49.48
fewUniques    1000   81.2      81.2
fewUniques    2000   193       96.5
fewUniques    5000   567.4     113.48
altHighLow    8      0         0
altHighLow    12     0         0
altHighLow    16     0.2       12.5
altHighLow    24     0.4       16.67
altHighLow    32     0.2       6.25
altHighLow    40     0.4       10
altHighLow    48     0.6       12.5
altHighLow    56     1.6       28.57
altHighLow    64     2.4       37.5
altHighLow    72     1.2       16.67
altHighLow    80     1.6       20
altHighLow    96     3.4       35.42
altHighLow    112    3.4       30.36
altHighLow    128    4         31.25
altHighLow    192    7.2       37.5
altHighLow    256    8         31.25
altHighLow    384    14.4      37.5
altHighLow    512    16        31.25
altHighLow    768    28.6      37.24
altHighLow    1000   80.6      80.6
altHighLow    2000   168       84
altHighLow    5000   431.8     86.36
withInvalid   8      0         0
withInvalid   12     0.2       16.67
withInvalid   16     0         0
withInvalid   24     0         0
withInvalid   32     0         0
withInvalid   40     0.8       20
withInvalid   48     0.8       16.67
withInvalid   56     0.8       14.29
withInvalid   64     0.8       12.5
withInvalid   72     1.8       25
withInvalid   80     3.4       42.5
withInvalid   96     3.8       39.58
withInvalid   112    3.4       30.36
withInvalid   128    4.6       35.94
withInvalid   192    7.2       37.5
withInvalid   256    10.2      39.84
withInvalid   384    13.4      34.9
withInvalid   512    22.2      43.36
withInvalid   768    36.8      47.92
withInvalid   1000   57.6      57.6
withInvalid   2000   141.2     70.6
withInvalid   5000   487.2     97.44
allSame       8      0         0
allSame       12     0         0
allSame       16     0         0
allSame       24     0.2       8.33
allSame       32     0         0
allSame       40     0.4       10
allSame       48     0.2       4.17
allSame       56     0         0
allSame       64     0.2       3.13
allSame       72     0.4       5.56
allSame       80     0.2       2.5
allSame       96     0.4       4.17
allSame       112    0.6       5.36
allSame       128    0.2       1.56
allSame       192    0.6       3.12
allSame       256    1         3.91
allSame       384    0.6       1.56
allSame       512    1.6       3.13
allSame       768    2.4       3.12
allSame       1000   2.4       2.4
allSame       2000   4.2       2.1
allSame       5000   10.4      2.08
------------------------------------------------------------
 断言统计: total=447, failed=0
 ✅ 全部断言通过
============================================================
 完成，结果已写入 _root.gameworld.BulletQueueBench.results
============================================================
