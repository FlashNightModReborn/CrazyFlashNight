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
ascending     12     0.2       16.67
ascending     16     0         0
ascending     24     0         0
ascending     32     0         0
ascending     40     0.4       10
ascending     48     0         0
ascending     56     0         0
ascending     64     0.2       3.13
ascending     72     0.2       2.78
ascending     80     0.2       2.5
ascending     96     0.2       2.08
ascending     112    0         0
ascending     128    0         0
ascending     192    0.2       1.04
ascending     256    0         0
ascending     384    0.6       1.56
ascending     512    0.6       1.17
ascending     768    1.2       1.56
ascending     1000   1         1
ascending     2000   2.4       1.2
ascending     5000   6.4       1.28
descending    8      0         0
descending    12     0.2       16.67
descending    16     0.2       12.5
descending    24     0.2       8.33
descending    32     0.2       6.25
descending    40     0         0
descending    48     0         0
descending    56     0.6       10.71
descending    64     0.6       9.38
descending    72     1         13.89
descending    80     0.8       10
descending    96     0.6       6.25
descending    112    0.4       3.57
descending    128    0.8       6.25
descending    192    0.8       4.17
descending    256    1.4       5.47
descending    384    2.4       6.25
descending    512    2.6       5.08
descending    768    3.6       4.69
descending    1000   6.2       6.2
descending    2000   11.2      5.6
descending    5000   28.4      5.68
random        8      0         0
random        12     0         0
random        16     0.2       12.5
random        24     0         0
random        32     0.4       12.5
random        40     0.6       15
random        48     1.2       25
random        56     1         17.86
random        64     1.6       25
random        72     1.8       25
random        80     1.6       20
random        96     2.6       27.08
random        112    4.6       41.07
random        128    3.8       29.69
random        192    5.6       29.17
random        256    8         31.25
random        384    11.6      30.21
random        512    17.8      34.77
random        768    27.6      35.94
random        1000   38.6      38.6
random        2000   82.8      41.4
random        5000   231.4     46.28
nearlySorted  8      0.2       25
nearlySorted  12     0         0
nearlySorted  16     0         0
nearlySorted  24     0.2       8.33
nearlySorted  32     0.6       18.75
nearlySorted  40     0.6       15
nearlySorted  48     0.4       8.33
nearlySorted  56     0.6       10.71
nearlySorted  64     1.2       18.75
nearlySorted  72     0.2       2.78
nearlySorted  80     0.4       5
nearlySorted  96     1         10.42
nearlySorted  112    1         8.93
nearlySorted  128    1.6       12.5
nearlySorted  192    2         10.42
nearlySorted  256    3.6       14.06
nearlySorted  384    5.6       14.58
nearlySorted  512    9         17.58
nearlySorted  768    14.6      19.01
nearlySorted  1000   20.2      20.2
nearlySorted  2000   48.6      24.3
nearlySorted  5000   136.4     27.28
sawtooth      8      0.6       75
sawtooth      12     0.2       16.67
sawtooth      16     0         0
sawtooth      24     0.4       16.67
sawtooth      32     0.6       18.75
sawtooth      40     0.8       20
sawtooth      48     0.8       16.67
sawtooth      56     1         17.86
sawtooth      64     1.8       28.13
sawtooth      72     1.6       22.22
sawtooth      80     1.2       15
sawtooth      96     2.8       29.17
sawtooth      112    2.6       23.21
sawtooth      128    3         23.44
sawtooth      192    4.8       25
sawtooth      256    6.8       26.56
sawtooth      384    11.6      30.21
sawtooth      512    13.6      26.56
sawtooth      768    20.4      26.56
sawtooth      1000   25.8      25.8
sawtooth      2000   53.2      26.6
sawtooth      5000   128.4     25.68
endsHeavy     8      0         0
endsHeavy     12     0         0
endsHeavy     16     0         0
endsHeavy     24     0.2       8.33
endsHeavy     32     0.8       25
endsHeavy     40     0.6       15
endsHeavy     48     0.8       16.67
endsHeavy     56     1         17.86
endsHeavy     64     1.2       18.75
endsHeavy     72     1.8       25
endsHeavy     80     2.6       32.5
endsHeavy     96     2.4       25
endsHeavy     112    3         26.79
endsHeavy     128    3.6       28.13
endsHeavy     192    5.6       29.17
endsHeavy     256    7.8       30.47
endsHeavy     384    11.6      30.21
endsHeavy     512    17.6      34.38
endsHeavy     768    27.2      35.42
endsHeavy     1000   37.2      37.2
endsHeavy     2000   85        42.5
endsHeavy     5000   232       46.4
fewUniques    8      0         0
fewUniques    12     0         0
fewUniques    16     0         0
fewUniques    24     0         0
fewUniques    32     0.4       12.5
fewUniques    40     0.4       10
fewUniques    48     0.8       16.67
fewUniques    56     1.8       32.14
fewUniques    64     2.2       34.38
fewUniques    72     1.8       25
fewUniques    80     1.4       17.5
fewUniques    96     2.2       22.92
fewUniques    112    2.8       25
fewUniques    128    4         31.25
fewUniques    192    5.2       27.08
fewUniques    256    8.2       32.03
fewUniques    384    12        31.25
fewUniques    512    18.6      36.33
fewUniques    768    27.6      35.94
fewUniques    1000   38        38
fewUniques    2000   83.4      41.7
fewUniques    5000   230.6     46.12
altHighLow    8      0         0
altHighLow    12     0.2       16.67
altHighLow    16     0.2       12.5
altHighLow    24     0.2       8.33
altHighLow    32     0.6       18.75
altHighLow    40     1         25
altHighLow    48     1         20.83
altHighLow    56     1         17.86
altHighLow    64     1.2       18.75
altHighLow    72     1.2       16.67
altHighLow    80     1.2       15
altHighLow    96     3         31.25
altHighLow    112    2.2       19.64
altHighLow    128    3         23.44
altHighLow    192    6         31.25
altHighLow    256    6.4       25
altHighLow    384    12.6      32.81
altHighLow    512    14        27.34
altHighLow    768    21.6      28.13
altHighLow    1000   27.2      27.2
altHighLow    2000   60.4      30.2
altHighLow    5000   162.2     32.44
withInvalid   8      0         0
withInvalid   12     0         0
withInvalid   16     0.2       12.5
withInvalid   24     0.4       16.67
withInvalid   32     0.4       12.5
withInvalid   40     0.4       10
withInvalid   48     0.8       16.67
withInvalid   56     1         17.86
withInvalid   64     1         15.63
withInvalid   72     1.2       16.67
withInvalid   80     1.4       17.5
withInvalid   96     2.4       25
withInvalid   112    2.4       21.43
withInvalid   128    2.2       17.19
withInvalid   192    4.8       25
withInvalid   256    7.2       28.13
withInvalid   384    9.4       24.48
withInvalid   512    12.8      25
withInvalid   768    21.6      28.13
withInvalid   1000   29.6      29.6
withInvalid   2000   63.8      31.9
withInvalid   5000   176.4     35.28
allSame       8      0         0
allSame       12     0.2       16.67
allSame       16     0         0
allSame       24     0.2       8.33
allSame       32     0         0
allSame       40     0.6       15
allSame       48     0.2       4.17
allSame       56     0.4       7.14
allSame       64     0.2       3.13
allSame       72     0         0
allSame       80     0         0
allSame       96     0.4       4.17
allSame       112    0         0
allSame       128    0.6       4.69
allSame       192    0.4       2.08
allSame       256    0         0
allSame       384    0.2       0.52
allSame       512    0.4       0.78
allSame       768    0.8       1.04
allSame       1000   1.2       1.2
allSame       2000   2.6       1.3
allSame       5000   6.4       1.28
------------------------------------------------------------
 断言统计: total=447, failed=0
 ✅ 全部断言通过
============================================================
 完成，结果已写入 _root.gameworld.BulletQueueBench.results
============================================================