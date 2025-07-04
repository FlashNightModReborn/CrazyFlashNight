org.flashNight.naki.Select.FloydRivestTest.runTests();  

Starting Enhanced Floyd-Rivest Selection Tests...

=== 基础功能测试 ===
PASS: 空数组选择测试
PASS: 单元素数组选择测试
PASS: 两元素选择最小值
PASS: 两元素选择最大值
PASS: 两元素有序选择最小值
PASS: 两元素有序选择最大值
PASS: 三元素选择最小值
PASS: 三元素选择中值
PASS: 三元素选择最大值
PASS: 已排序数组选择测试
PASS: 逆序数组选择测试
PASS: 随机数组选择测试
PASS: 重复元素选择测试 (k=0)
PASS: 重复元素选择测试 (k=2)
PASS: 重复元素选择测试 (k=4)
PASS: 重复元素选择测试 (k=6)
PASS: 重复元素选择测试 (k=8)
PASS: 全相同元素选择测试
PASS: 自定义比较函数选择测试
PASS: 中位数选择测试
PASS: 最小元素选择测试
PASS: 最大元素选择测试

=== Floyd-Rivest 核心特性测试 ===
PASS: 智能采样策略测试 (k=10)
    位置10采样选择耗时: 5ms
PASS: 智能采样策略测试 (k=100)
    位置100采样选择耗时: 5ms
PASS: 智能采样策略测试 (k=250)
    位置250采样选择耗时: 8ms
PASS: 智能采样策略测试 (k=500)
    位置500采样选择耗时: 7ms
PASS: 智能采样策略测试 (k=750)
    位置750采样选择耗时: 3ms
PASS: 智能采样策略测试 (k=900)
    位置900采样选择耗时: 5ms
PASS: 智能采样策略测试 (k=990)
    位置990采样选择耗时: 5ms
PASS: 双pivot三路分区测试
PASS: 双pivot分区选择正确性
PASS: 递归采样深度测试 (size=500)
    大小500递归采样耗时: 2ms
PASS: 递归采样深度测试 (size=1000)
    大小1000递归采样耗时: 8ms
PASS: 递归采样深度测试 (size=5000)
    大小5000递归采样耗时: 32ms
PASS: 递归采样深度测试 (size=10000)
    大小10000递归采样耗时: 67ms
PASS: 采样大小计算测试 (size=100)
PASS: 采样大小计算测试 (size=600)
PASS: 采样大小计算测试 (size=1000)
PASS: 采样大小计算测试 (size=5000)
PASS: 自适应阈值切换测试 (size=50)
    大小50 (QuickSelect回退) 耗时: 0ms
PASS: 自适应阈值切换测试 (size=200)
    大小200 (QuickSelect回退) 耗时: 1ms
PASS: 自适应阈值切换测试 (size=300)
    大小300 (QuickSelect回退) 耗时: 1ms
PASS: 自适应阈值切换测试 (size=400)
    大小400 (Floyd-Rivest) 耗时: 3ms
PASS: 自适应阈值切换测试 (size=500)
    大小500 (Floyd-Rivest) 耗时: 3ms
PASS: 自适应阈值切换测试 (size=600)
    大小600 (Floyd-Rivest) 耗时: 3ms
PASS: 三路分区优化测试 (k=100)
    重复元素位置100选择耗时: 4ms
PASS: 三路分区优化测试 (k=300)
    重复元素位置300选择耗时: 4ms
PASS: 三路分区优化测试 (k=500)
    重复元素位置500选择耗时: 10ms
PASS: 三路分区优化测试 (k=700)
    重复元素位置700选择耗时: 5ms
PASS: 三路分区优化测试 (k=900)
    重复元素位置900选择耗时: 19ms
PASS: 采样边界条件测试 (k=0)
PASS: 采样边界条件测试 (k=1)
PASS: 采样边界条件测试 (k=2)
PASS: 采样边界条件测试 (k=997)
PASS: 采样边界条件测试 (k=998)
PASS: 采样边界条件测试 (k=999)
PASS: pivot质量验证测试
PASS: pivot质量选择正确性

=== 几何数据和BVH专项测试 ===
PASS: 几何数据X轴选择测试
PASS: 几何数据Y轴选择测试
PASS: 几何数据Z轴选择测试
PASS: 空间局部性检测测试（有序数据）
PASS: 空间局部性检测测试（随机数据）
    空间局部性数据耗时: 1ms
    随机数据耗时: 0ms
    性能提升: 否
PASS: 自适应策略测试（小有序数据）
PASS: 自适应策略测试（大随机数据）
PASS: BVH构建场景测试（范围0）
    BVH分割范围0 (轴0) 耗时: 15ms
PASS: BVH构建场景测试（范围1）
    BVH分割范围1 (轴1) 耗时: 5ms
PASS: BVH构建场景测试（范围2）
    BVH分割范围2 (轴2) 耗时: 7ms
PASS: 多轴几何数据测试（轴0）
PASS: 多轴几何数据测试（轴1）
PASS: 多轴几何数据测试（轴2）
PASS: 空间聚类数据测试
PASS: 空间聚类数据选择正确性
PASS: 随机几何分布测试（位置50）
    随机几何分布位置50选择耗时: 3ms
PASS: 随机几何分布测试（位置125）
    随机几何分布位置125选择耗时: 4ms
PASS: 随机几何分布测试（位置250）
    随机几何分布位置250选择耗时: 5ms
PASS: 随机几何分布测试（位置375）
    随机几何分布位置375选择耗时: 6ms
PASS: 随机几何分布测试（位置450）
    随机几何分布位置450选择耗时: 4ms

=== 算法阈值和边界测试 ===
PASS: 小数组阈值测试 (size=10)
    大小10 (QuickSelect) 耗时: 0ms
PASS: 小数组阈值测试 (size=50)
    大小50 (QuickSelect) 耗时: 0ms
PASS: 小数组阈值测试 (size=100)
    大小100 (QuickSelect) 耗时: 0ms
PASS: 小数组阈值测试 (size=200)
    大小200 (QuickSelect) 耗时: 3ms
PASS: 小数组阈值测试 (size=300)
    大小300 (QuickSelect) 耗时: 1ms
PASS: 小数组阈值测试 (size=400)
    大小400 (Floyd-Rivest) 耗时: 2ms
PASS: 小数组阈值测试 (size=500)
    大小500 (Floyd-Rivest) 耗时: 2ms
PASS: 最小采样阈值测试（范围0）
PASS: 最小采样阈值测试（范围1）
PASS: 最小采样阈值测试（范围2）
PASS: 最小采样阈值测试（范围3）
PASS: 大数组处理测试 (size=10000, k=1000)
    大小10000位置1000选择耗时: 71ms
PASS: 大数组处理测试 (size=10000, k=5000)
    大小10000位置5000选择耗时: 62ms
PASS: 大数组处理测试 (size=10000, k=9000)
    大小10000位置9000选择耗时: 53ms
PASS: 大数组处理测试 (size=50000, k=5000)
    大小50000位置5000选择耗时: 202ms
PASS: 大数组处理测试 (size=50000, k=25000)
    大小50000位置25000选择耗时: 274ms
PASS: 大数组处理测试 (size=50000, k=45000)
    大小50000位置45000选择耗时: 236ms
PASS: 大数组处理测试 (size=100000, k=10000)
    大小100000位置10000选择耗时: 485ms
PASS: 大数组处理测试 (size=100000, k=50000)
    大小100000位置50000选择耗时: 740ms
PASS: 大数组处理测试 (size=100000, k=90000)
    大小100000位置90000选择耗时: 403ms
PASS: 阈值边界条件测试 (size=32)
PASS: 阈值边界条件测试 (size=400)
PASS: 阈值边界条件测试 (size=600)
PASS: 采样范围验证测试 (k=0)
PASS: 采样范围验证测试 (k=1)
PASS: 采样范围验证测试 (k=2)
PASS: 采样范围验证测试 (k=997)
PASS: 采样范围验证测试 (k=998)
PASS: 采样范围验证测试 (k=999)
PASS: pivot选择边界测试（全相同）
PASS: pivot选择边界测试（两值交替）
PASS: pivot选择边界测试（递增）
PASS: pivot选择边界测试（递减）
PASS: 递归深度限制测试
    最深递归模式耗时: 11ms

=== 选择位置专项测试 ===
PASS: 最小值选择测试
PASS: 最大值选择测试
PASS: 第一四分位数选择测试
PASS: 第二四分位数（中位数）选择测试
PASS: 第三四分位数选择测试
PASS: 第5百分位数选择测试
PASS: 第10百分位数选择测试
PASS: 第25百分位数选择测试
PASS: 第50百分位数选择测试
PASS: 第75百分位数选择测试
PASS: 第90百分位数选择测试
PASS: 第95百分位数选择测试
PASS: 第99百分位数选择测试
PASS: 中位数变体测试 (size=99)
PASS: 中位数变体测试 (size=100)
PASS: 中位数变体测试 (size=101)
PASS: 中位数变体测试 (size=999)
PASS: 中位数变体测试 (size=1000)
PASS: 中位数变体测试 (size=1001)
PASS: 边界附近选择测试（开始+0）
PASS: 边界附近选择测试（开始+1）
PASS: 边界附近选择测试（开始+2）
PASS: 边界附近选择测试（开始+3）
PASS: 边界附近选择测试（开始+4）
PASS: 边界附近选择测试（结束-4）
PASS: 边界附近选择测试（结束-3）
PASS: 边界附近选择测试（结束-2）
PASS: 边界附近选择测试（结束-1）
PASS: 边界附近选择测试（结束-0）
PASS: 随机位置选择测试（k=370）
PASS: 随机位置选择测试（k=785）
PASS: 随机位置选择测试（k=105）
PASS: 随机位置选择测试（k=889）
PASS: 随机位置选择测试（k=771）
PASS: 随机位置选择测试（k=749）
PASS: 随机位置选择测试（k=421）
PASS: 随机位置选择测试（k=422）
PASS: 随机位置选择测试（k=57）
PASS: 随机位置选择测试（k=887）
PASS: 随机位置选择测试（k=783）
PASS: 随机位置选择测试（k=826）
PASS: 随机位置选择测试（k=86）
PASS: 随机位置选择测试（k=947）
PASS: 随机位置选择测试（k=413）
PASS: 随机位置选择测试（k=649）
PASS: 随机位置选择测试（k=870）
PASS: 随机位置选择测试（k=996）
PASS: 随机位置选择测试（k=875）
PASS: 随机位置选择测试（k=833）
PASS: 多次选择一致性测试

=== 数据分布模式测试 ===
PASS: 均匀分布测试（位置100）
    均匀分布位置100选择耗时: 4ms
PASS: 均匀分布测试（位置250）
    均匀分布位置250选择耗时: 5ms
PASS: 均匀分布测试（位置500）
    均匀分布位置500选择耗时: 7ms
PASS: 均匀分布测试（位置750）
    均匀分布位置750选择耗时: 8ms
PASS: 均匀分布测试（位置900）
    均匀分布位置900选择耗时: 6ms
PASS: 正态分布测试
    正态分布中位数: 507.765554812418，耗时: 10ms
PASS: 指数分布测试（位置100）
PASS: 指数分布测试（位置500）
PASS: 指数分布测试（位置800）
PASS: 双峰分布测试
    双峰分布中位数: 320.224315827449
PASS: 幂律分布测试（位置50）
PASS: 幂律分布测试（位置200）
PASS: 幂律分布测试（位置500）
PASS: 幂律分布测试（位置900）
PASS: 幂律分布测试（位置950）
PASS: 交替模式测试
    交替模式选择耗时: 6ms
PASS: 交替模式测试（位置250）
PASS: 交替模式测试（位置750）
PASS: 聚类数据测试（位置200）
    聚类数据位置200选择耗时: 4ms
PASS: 聚类数据测试（位置400）
    聚类数据位置400选择耗时: 9ms
PASS: 聚类数据测试（位置600）
    聚类数据位置600选择耗时: 8ms
PASS: 聚类数据测试（位置800）
    聚类数据位置800选择耗时: 10ms
PASS: 稀疏数据测试（位置450）
PASS: 稀疏数据测试（位置800）
PASS: 稀疏数据测试（位置950）
PASS: 稀疏数据测试（位置990）

=== 稳定性和正确性验证 ===
PASS: 选择正确性测试
PASS: 分区正确性测试
PASS: 跨运行一致性测试
PASS: 输入数组完整性测试（长度保持）
PASS: 输入数组完整性测试（元素保持）
PASS: 元素保持测试
PASS: 顺序不变性测试

=== 性能对比和压力测试 ===

开始Floyd-Rivest vs QuickSelect性能对比...
  测试数组大小: 1000
PASS: 性能对比结果一致性（random）
    random - FR: 7ms, QS: 4ms, 提升: -75%
PASS: 性能对比结果一致性（sorted）
    sorted - FR: 3ms, QS: 4ms, 提升: 25%
PASS: 性能对比结果一致性（reverse）
    reverse - FR: 12ms, QS: 2ms, 提升: -500%
PASS: 性能对比结果一致性（manyDuplicates）
    manyDuplicates - FR: 6ms, QS: 20ms, 提升: 70%
  测试数组大小: 5000
PASS: 性能对比结果一致性（random）
    random - FR: 40ms, QS: 34ms, 提升: -18%
PASS: 性能对比结果一致性（sorted）
    sorted - FR: 16ms, QS: 17ms, 提升: 6%
PASS: 性能对比结果一致性（reverse）
    reverse - FR: 36ms, QS: 8ms, 提升: -350%
PASS: 性能对比结果一致性（manyDuplicates）
    manyDuplicates - FR: 17ms, QS: 343ms, 提升: 95%
  测试数组大小: 10000
PASS: 性能对比结果一致性（random）
    random - FR: 53ms, QS: 60ms, 提升: 12%
PASS: 性能对比结果一致性（sorted）
    sorted - FR: 31ms, QS: 37ms, 提升: 16%
PASS: 性能对比结果一致性（reverse）
    reverse - FR: 85ms, QS: 20ms, 提升: -325%
PASS: 性能对比结果一致性（manyDuplicates）
    manyDuplicates - FR: 46ms, QS: 1490ms, 提升: 97%
  测试数组大小: 50000
PASS: 性能对比结果一致性（random）
    random - FR: 308ms, QS: 212ms, 提升: -45%
PASS: 性能对比结果一致性（sorted）
    sorted - FR: 177ms, QS: 191ms, 提升: 7%
PASS: 性能对比结果一致性（reverse）
    reverse - FR: 235ms, QS: 100ms, 提升: -135%
PASS: 性能对比结果一致性（manyDuplicates）
    manyDuplicates - FR: 146ms, QS: 34751ms, 提升: 100%
PASS: 大数据集压力测试（1%位置）
    大数据集位置1000选择耗时: 406ms
PASS: 大数据集压力测试（25%位置）
    大数据集位置25000选择耗时: 512ms
PASS: 大数据集压力测试（50%位置）
    大数据集位置50000选择耗时: 655ms
PASS: 大数据集压力测试（75%位置）
    大数据集位置75000选择耗时: 631ms
PASS: 大数据集压力测试（99%位置）
    大数据集位置99000选择耗时: 452ms
PASS: 最坏情况测试（交替模式）
    交替模式最坏情况耗时: 8ms
PASS: 最坏情况测试（全相同）
    全相同值最坏情况耗时: 8ms
PASS: 最佳情况优化测试（正态分布）
    正态分布最佳情况耗时: 8ms
PASS: 平均性能测试（轮次1）
PASS: 平均性能测试（轮次2）
PASS: 平均性能测试（轮次3）
PASS: 平均性能测试（轮次4）
PASS: 平均性能测试（轮次5）
PASS: 平均性能测试（轮次6）
PASS: 平均性能测试（轮次7）
PASS: 平均性能测试（轮次8）
PASS: 平均性能测试（轮次9）
PASS: 平均性能测试（轮次10）
    平均性能测试（10轮，大小10000）平均耗时: 53.2ms
PASS: 内存效率测试（数组长度保持）
PASS: 内存效率测试（元素保持完整）
PASS: 内存效率测试（选择结果有效）

=== 实际应用场景测试 ===
PASS: 数据库查询优化测试（选择结果）
    数据库查询优化 - 选择: 40ms, 排序: 139ms, 提升: 71%
PASS: 统计分析测试
    统计分析 - 最小值: 36.2641396614544, Q1: 89.7993871068631, 中位数: 99.8119643189719, Q3: 110.069429817116, 最大值: 151.405123041817
    统计分析耗时: 119ms
PASS: Top-K选择测试（第100大元素）
PASS: Top-K选择测试（范围验证）
    Top-100选择耗时: 36ms，阈值: 990.494889672846
PASS: 排名操作测试（第1名）
    第1名玩家: player533, 分数: 9999, 耗时: 4ms
PASS: 排名操作测试（第10名）
    第10名玩家: player715, 分数: 9891, 耗时: 4ms
PASS: 排名操作测试（第50名）
    第50名玩家: player489, 分数: 9429, 耗时: 4ms
PASS: 排名操作测试（第100名）
    第100名玩家: player833, 分数: 8946, 耗时: 5ms
PASS: 排名操作测试（第500名）
    第500名玩家: player766, 分数: 5024, 耗时: 9ms
PASS: 部分排序用例测试
    部分排序 vs 完整排序 - 部分: 36ms, 完整: 5ms, 提升: -620%
PASS: 流式数据选择测试
    流式数据选择 - 批次数: 100, 平均耗时: 0.46ms/批
    最后批次90分位数: 901.033618487418

All Enhanced Floyd-Rivest Tests Completed.