org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueTest.runSuite({sizes:[64,128,1000,5000], repeats:5});

============================================================
 BulletQueue 测试/基准开始（类版）
 sizes=64, 128, 1000, 5000  repeats=5
============================================================

==================== 鲁棒性测试 ====================
[PASS] 空队列测试
[FAIL] 单元素测试
[PASS] 边界值测试(63/64/65)
[PASS] clear()方法测试
[FAIL] 缓冲区扩容测试
[FAIL] API一致性测试
[PASS] Keys对齐测试
鲁棒性测试: 4 通过, 3 失败
====================================================

dist          n      ms_avg    ms/1k
------------------------------------------------------------
ascending     64     0.2       3.13
ascending     128    0.4       3.13
ascending     1000   2.8       2.8
ascending     5000   12.6      2.52
descending    64     0.2       3.13
descending    128    0.8       6.25
descending    1000   7.4       7.4
descending    5000   38.4      7.68
random        64     1.4       21.88
random        128    4         31.25
random        1000   52.2      52.2
random        5000   506.4     101.28
nearlySorted  64     1         15.63
nearlySorted  128    2         15.63
nearlySorted  1000   23.6      23.6
nearlySorted  5000   156.4     31.28
sawtooth      64     1.6       25
sawtooth      128    4.6       35.94
sawtooth      1000   34.6      34.6
sawtooth      5000   167.8     33.56
endsHeavy     64     1.6       25
endsHeavy     128    3.8       29.69
endsHeavy     1000   46.6      46.6
endsHeavy     5000   584.6     116.92
fewUniques    64     1.6       25
fewUniques    128    3.8       29.69
fewUniques    1000   80.4      80.4
fewUniques    5000   562       112.4
altHighLow    64     2         31.25
altHighLow    128    5         39.06
altHighLow    1000   77.8      77.8
altHighLow    5000   432       86.4
withInvalid   64     1.4       21.88
withInvalid   128    4.6       35.94
withInvalid   1000   47.6      47.6
withInvalid   5000   492.2     98.44
allSame       64     0.2       3.13
allSame       128    0.2       1.56
allSame       1000   2         2
allSame       5000   11.8      2.36
------------------------------------------------------------
 断言统计: total=87, failed=3
 ❌ 存在断言失败，请检查上方 FAIL 日志
============================================================
 完成，结果已写入 _root.gameworld.BulletQueueBench.results
============================================================
