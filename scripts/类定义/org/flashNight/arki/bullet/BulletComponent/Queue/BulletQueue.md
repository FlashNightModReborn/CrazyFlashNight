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
ascending     48     0.2       4.17
ascending     56     0         0
ascending     64     0         0
ascending     72     0.4       5.56
ascending     80     0         0
ascending     96     0.2       2.08
ascending     112    0         0
ascending     128    0         0
ascending     192    0.4       2.08
ascending     256    0.6       2.34
ascending     384    0.6       1.56
ascending     512    1         1.95
ascending     768    1.2       1.56
ascending     1000   1.6       1.6
ascending     2000   3.2       1.6
ascending     5000   7.6       1.52
descending    8      0         0
descending    12     0         0
descending    16     0         0
descending    24     0.2       8.33
descending    32     0.4       12.5
descending    40     1         25
descending    48     0.8       16.67
descending    56     1.2       21.43
descending    64     0.4       6.25
descending    72     0.4       5.56
descending    80     0.2       2.5
descending    96     0.2       2.08
descending    112    0.8       7.14
descending    128    0.6       4.69
descending    192    1         5.21
descending    256    1         3.91
descending    384    1.8       4.69
descending    512    2.8       5.47
descending    768    3.6       4.69
descending    1000   4.6       4.6
descending    2000   9.8       4.9
descending    5000   24.4      4.88
random        8      0         0
random        12     0.2       16.67
random        16     0         0
random        24     0.4       16.67
random        32     0.6       18.75
random        40     0.2       5
random        48     1         20.83
random        56     0.8       14.29
random        64     1.2       18.75
random        72     1.2       16.67
random        80     1.8       22.5
random        96     2.6       27.08
random        112    2.8       25
random        128    2.8       21.88
random        192    4.8       25
random        256    6.2       24.22
random        384    10.4      27.08
random        512    13.6      26.56
random        768    22.8      29.69
random        1000   34.4      34.4
random        2000   78.4      39.2
random        5000   365.4     73.08
nearlySorted  8      0         0
nearlySorted  12     0         0
nearlySorted  16     0         0
nearlySorted  24     0         0
nearlySorted  32     0         0
nearlySorted  40     0.2       5
nearlySorted  48     0         0
nearlySorted  56     0         0
nearlySorted  64     0.4       6.25
nearlySorted  72     0.8       11.11
nearlySorted  80     1         12.5
nearlySorted  96     0.4       4.17
nearlySorted  112    1         8.93
nearlySorted  128    1.4       10.94
nearlySorted  192    1.4       7.29
nearlySorted  256    2.4       9.38
nearlySorted  384    4.8       12.5
nearlySorted  512    6.2       12.11
nearlySorted  768    10.2      13.28
nearlySorted  1000   14.6      14.6
nearlySorted  2000   37.4      18.7
nearlySorted  5000   106       21.2
sawtooth      8      0         0
sawtooth      12     0         0
sawtooth      16     0         0
sawtooth      24     0.2       8.33
sawtooth      32     0.2       6.25
sawtooth      40     0.4       10
sawtooth      48     0.2       4.17
sawtooth      56     0.4       7.14
sawtooth      64     1         15.63
sawtooth      72     1.4       19.44
sawtooth      80     1.2       15
sawtooth      96     1.8       18.75
sawtooth      112    2.4       21.43
sawtooth      128    2.8       21.88
sawtooth      192    4.4       22.92
sawtooth      256    5.4       21.09
sawtooth      384    9.8       25.52
sawtooth      512    10.6      20.7
sawtooth      768    16.4      21.35
sawtooth      1000   21        21
sawtooth      2000   44.8      22.4
sawtooth      5000   117       23.4
endsHeavy     8      0         0
endsHeavy     12     0         0
endsHeavy     16     0.2       12.5
endsHeavy     24     0.2       8.33
endsHeavy     32     0         0
endsHeavy     40     0.2       5
endsHeavy     48     0.4       8.33
endsHeavy     56     0.8       14.29
endsHeavy     64     1.2       18.75
endsHeavy     72     1.2       16.67
endsHeavy     80     1.8       22.5
endsHeavy     96     2         20.83
endsHeavy     112    2.4       21.43
endsHeavy     128    2.8       21.88
endsHeavy     192    4.6       23.96
endsHeavy     256    6         23.44
endsHeavy     384    10.6      27.6
endsHeavy     512    13.6      26.56
endsHeavy     768    23.2      30.21
endsHeavy     1000   34.8      34.8
endsHeavy     2000   88        44
endsHeavy     5000   341.6     68.32
fewUniques    8      0.2       25
fewUniques    12     0.2       16.67
fewUniques    16     0         0
fewUniques    24     0         0
fewUniques    32     0         0
fewUniques    40     0.2       5
fewUniques    48     0.6       12.5
fewUniques    56     0         0
fewUniques    64     1.2       18.75
fewUniques    72     1.2       16.67
fewUniques    80     1.8       22.5
fewUniques    96     2.2       22.92
fewUniques    112    2.6       23.21
fewUniques    128    2.6       20.31
fewUniques    192    4.8       25
fewUniques    256    6         23.44
fewUniques    384    10.8      28.13
fewUniques    512    15.6      30.47
fewUniques    768    27.6      35.94
fewUniques    1000   58.2      58.2
fewUniques    2000   137.8     68.9
fewUniques    5000   397.8     79.56
altHighLow    8      0         0
altHighLow    12     0         0
altHighLow    16     0.2       12.5
altHighLow    24     0.2       8.33
altHighLow    32     0         0
altHighLow    40     0.4       10
altHighLow    48     0.4       8.33
altHighLow    56     0.6       10.71
altHighLow    64     1         15.63
altHighLow    72     1.4       19.44
altHighLow    80     1.8       22.5
altHighLow    96     2         20.83
altHighLow    112    2.6       23.21
altHighLow    128    2.4       18.75
altHighLow    192    4.4       22.92
altHighLow    256    5.8       22.66
altHighLow    384    9.6       25
altHighLow    512    12        23.44
altHighLow    768    20.4      26.56
altHighLow    1000   54        54
altHighLow    2000   120.4     60.2
altHighLow    5000   307       61.4
withInvalid   8      0         0
withInvalid   12     0         0
withInvalid   16     0         0
withInvalid   24     0         0
withInvalid   32     0.2       6.25
withInvalid   40     0.4       10
withInvalid   48     0.4       8.33
withInvalid   56     0.8       14.29
withInvalid   64     1         15.63
withInvalid   72     1         13.89
withInvalid   80     1.6       20
withInvalid   96     2         20.83
withInvalid   112    2.6       23.21
withInvalid   128    3         23.44
withInvalid   192    4.4       22.92
withInvalid   256    7         27.34
withInvalid   384    10        26.04
withInvalid   512    14.8      28.91
withInvalid   768    21.8      28.39
withInvalid   1000   36.2      36.2
withInvalid   2000   98.8      49.4
withInvalid   5000   338.8     67.76
allSame       8      0         0
allSame       12     0         0
allSame       16     0         0
allSame       24     0         0
allSame       32     0         0
allSame       40     0.2       5
allSame       48     0         0
allSame       56     0         0
allSame       64     0         0
allSame       72     0.2       2.78
allSame       80     0.2       2.5
allSame       96     0         0
allSame       112    0         0
allSame       128    0.2       1.56
allSame       192    0.4       2.08
allSame       256    0.2       0.78
allSame       384    0.6       1.56
allSame       512    0.8       1.56
allSame       768    1         1.3
allSame       1000   1.4       1.4
allSame       2000   3         1.5
allSame       5000   8         1.6
------------------------------------------------------------
 断言统计: total=447, failed=0
 ✅ 全部断言通过
============================================================
 完成，结果已写入 _root.gameworld.BulletQueueBench.results
============================================================
