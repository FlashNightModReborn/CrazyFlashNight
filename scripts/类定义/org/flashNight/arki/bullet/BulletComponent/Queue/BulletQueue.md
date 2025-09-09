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
ascending     56     0.6       10.71
ascending     64     0         0
ascending     72     0.2       2.78
ascending     80     0.6       7.5
ascending     96     0         0
ascending     112    0         0
ascending     128    0.4       3.13
ascending     192    0.6       3.12
ascending     256    0.8       3.13
ascending     384    0.4       1.04
ascending     512    1.2       2.34
ascending     768    1.6       2.08
ascending     1000   2         2
ascending     2000   5         2.5
ascending     5000   11.8      2.36
descending    8      0.2       25
descending    12     0.2       16.67
descending    16     0.2       12.5
descending    24     0.4       16.67
descending    32     0.4       12.5
descending    40     0.8       20
descending    48     1.4       29.17
descending    56     2         35.71
descending    64     0         0
descending    72     0.8       11.11
descending    80     1         12.5
descending    96     0.8       8.33
descending    112    1.2       10.71
descending    128    0.6       4.69
descending    192    1.4       7.29
descending    256    2.8       10.94
descending    384    2.8       7.29
descending    512    4         7.81
descending    768    6         7.81
descending    1000   7.2       7.2
descending    2000   15.4      7.7
descending    5000   41.6      8.32
random        8      0         0
random        12     0         0
random        16     0         0
random        24     0         0
random        32     0.2       6.25
random        40     0.4       10
random        48     0.6       12.5
random        56     1         17.86
random        64     1.2       18.75
random        72     2.2       30.56
random        80     2.2       27.5
random        96     3         31.25
random        112    4.2       37.5
random        128    4.8       37.5
random        192    7.4       38.54
random        256    9         35.16
random        384    15.6      40.63
random        512    20.8      40.63
random        768    37        48.18
random        1000   53        53
random        2000   123       61.5
random        5000   553.4     110.68
nearlySorted  8      0         0
nearlySorted  12     0         0
nearlySorted  16     0         0
nearlySorted  24     0         0
nearlySorted  32     0         0
nearlySorted  40     0.2       5
nearlySorted  48     0.2       4.17
nearlySorted  56     0.4       7.14
nearlySorted  64     1         15.63
nearlySorted  72     0.8       11.11
nearlySorted  80     0.6       7.5
nearlySorted  96     0.8       8.33
nearlySorted  112    1.4       12.5
nearlySorted  128    1.8       14.06
nearlySorted  192    3         15.63
nearlySorted  256    3.6       14.06
nearlySorted  384    6.4       16.67
nearlySorted  512    10        19.53
nearlySorted  768    17.6      22.92
nearlySorted  1000   22.4      22.4
nearlySorted  2000   59.6      29.8
nearlySorted  5000   171.6     34.32
sawtooth      8      0         0
sawtooth      12     0         0
sawtooth      16     0         0
sawtooth      24     0.2       8.33
sawtooth      32     0.4       12.5
sawtooth      40     1         25
sawtooth      48     0.6       12.5
sawtooth      56     1         17.86
sawtooth      64     2         31.25
sawtooth      72     2.2       30.56
sawtooth      80     2         25
sawtooth      96     3.2       33.33
sawtooth      112    3.8       33.93
sawtooth      128    4.2       32.81
sawtooth      192    7         36.46
sawtooth      256    10.2      39.84
sawtooth      384    17.8      46.35
sawtooth      512    20.6      40.23
sawtooth      768    29.8      38.8
sawtooth      1000   37.8      37.8
sawtooth      2000   73.4      36.7
sawtooth      5000   190.2     38.04
endsHeavy     8      0         0
endsHeavy     12     0         0
endsHeavy     16     0.2       12.5
endsHeavy     24     0.4       16.67
endsHeavy     32     0.6       18.75
endsHeavy     40     0         0
endsHeavy     48     1.2       25
endsHeavy     56     1.2       21.43
endsHeavy     64     1.6       25
endsHeavy     72     2.4       33.33
endsHeavy     80     2.6       32.5
endsHeavy     96     3.6       37.5
endsHeavy     112    4         35.71
endsHeavy     128    4.8       37.5
endsHeavy     192    7.4       38.54
endsHeavy     256    9.4       36.72
endsHeavy     384    16.6      43.23
endsHeavy     512    21        41.02
endsHeavy     768    37.8      49.22
endsHeavy     1000   57.2      57.2
endsHeavy     2000   136.8     68.4
endsHeavy     5000   533.4     106.68
fewUniques    8      0         0
fewUniques    12     0         0
fewUniques    16     0.2       12.5
fewUniques    24     0         0
fewUniques    32     0.2       6.25
fewUniques    40     1         25
fewUniques    48     1.2       25
fewUniques    56     1.2       21.43
fewUniques    64     1.8       28.13
fewUniques    72     2         27.78
fewUniques    80     2.6       32.5
fewUniques    96     3.4       35.42
fewUniques    112    4         35.71
fewUniques    128    4.2       32.81
fewUniques    192    7.6       39.58
fewUniques    256    10        39.06
fewUniques    384    17.2      44.79
fewUniques    512    25.2      49.22
fewUniques    768    42.4      55.21
fewUniques    1000   86.4      86.4
fewUniques    2000   201       100.5
fewUniques    5000   587.6     117.52
altHighLow    8      0.2       25
altHighLow    12     0.2       16.67
altHighLow    16     0.2       12.5
altHighLow    24     0.2       8.33
altHighLow    32     0.4       12.5
altHighLow    40     0.2       5
altHighLow    48     0.8       16.67
altHighLow    56     1         17.86
altHighLow    64     1.6       25
altHighLow    72     2.2       30.56
altHighLow    80     2.2       27.5
altHighLow    96     3         31.25
altHighLow    112    3.8       33.93
altHighLow    128    3.8       29.69
altHighLow    192    6.8       35.42
altHighLow    256    8.4       32.81
altHighLow    384    14.6      38.02
altHighLow    512    18.6      36.33
altHighLow    768    30.2      39.32
altHighLow    1000   76.2      76.2
altHighLow    2000   171.4     85.7
altHighLow    5000   445.2     89.04
withInvalid   8      0         0
withInvalid   12     0         0
withInvalid   16     0         0
withInvalid   24     0.4       16.67
withInvalid   32     0.8       25
withInvalid   40     0         0
withInvalid   48     0.8       16.67
withInvalid   56     1.4       25
withInvalid   64     1.4       21.88
withInvalid   72     2         27.78
withInvalid   80     2         25
withInvalid   96     3.4       35.42
withInvalid   112    3.6       32.14
withInvalid   128    4.8       37.5
withInvalid   192    6         31.25
withInvalid   256    11.2      43.75
withInvalid   384    14        36.46
withInvalid   512    22.2      43.36
withInvalid   768    34.2      44.53
withInvalid   1000   54        54
withInvalid   2000   144.8     72.4
withInvalid   5000   493       98.6
allSame       8      0.2       25
allSame       12     0.2       16.67
allSame       16     0         0
allSame       24     0         0
allSame       32     0.2       6.25
allSame       40     0.2       5
allSame       48     0         0
allSame       56     0         0
allSame       64     0.2       3.13
allSame       72     0.2       2.78
allSame       80     0         0
allSame       96     0.2       2.08
allSame       112    1.2       10.71
allSame       128    0         0
allSame       192    0.2       1.04
allSame       256    0.8       3.13
allSame       384    1         2.6
allSame       512    1         1.95
allSame       768    1.6       2.08
allSame       1000   2.4       2.4
allSame       2000   4.6       2.3
allSame       5000   11.4      2.28
------------------------------------------------------------
 断言统计: total=447, failed=0
 ✅ 全部断言通过
============================================================
 完成，结果已写入 _root.gameworld.BulletQueueBench.results
============================================================
