org.flashNight.naki.DataStructures.BVHBuilderTest.runAll();


================================================================================
🚀 BVHBuilder 完整测试套件启动
================================================================================

🔧 初始化BVHBuilder测试数据...
📦 创建了 50 个基础测试对象
📦 创建了 50 个预排序测试对象
📦 创建了 20 个重叠对象
📦 创建了 30 个分散对象
📦 创建了 15 个极值对象

📋 执行基础功能测试...
✅ MAX_OBJECTS_IN_LEAF默认值合理 PASS
✅ MAX_OBJECTS_IN_LEAF默认值不会太大 PASS
✅ MAX_OBJECTS_IN_LEAF可修改 PASS (expected=5, actual=5)
✅ MAX_OBJECTS_IN_LEAF恢复原值 PASS (expected=8, actual=8)
✅ build方法返回BVH对象 PASS (object is not null)
✅ build方法创建根节点 PASS (object is not null)
✅ 构建的BVH查询返回结果 PASS (object is not null)
✅ 构建的BVH查询有结果 PASS
✅ 查询结果对象0与查询区域相交 PASS
✅ 查询结果对象1与查询区域相交 PASS
✅ 查询结果对象2与查询区域相交 PASS
✅ 查询结果对象3与查询区域相交 PASS
✅ buildFromSortedX返回BVH对象 PASS (object is not null)
✅ buildFromSortedX创建根节点 PASS (object is not null)
✅ 预排序构建的BVH查询返回结果 PASS (object is not null)
✅ 预排序查询结果对象0与查询区域相交 PASS
✅ 预排序查询结果对象1与查询区域相交 PASS
✅ 预排序查询结果对象2与查询区域相交 PASS
✅ 预排序查询结果对象3与查询区域相交 PASS
✅ 预排序查询结果对象4与查询区域相交 PASS
✅ 预排序查询结果对象5与查询区域相交 PASS
✅ 预排序查询结果对象6与查询区域相交 PASS
✅ 预排序查询结果对象7与查询区域相交 PASS
✅ 预排序查询结果对象8与查询区域相交 PASS
✅ 预排序查询结果对象9与查询区域相交 PASS
✅ 预排序查询结果对象10与查询区域相交 PASS
✅ 空数组build返回BVH PASS (object is not null)
✅ 空数组build根节点为null PASS (object is null)
✅ 空数组buildFromSortedX返回BVH PASS (object is not null)
✅ 空数组buildFromSortedX根节点为null PASS (object is null)
✅ null数组build返回BVH PASS (object is not null)
✅ null数组build根节点为null PASS (object is null)
✅ null数组buildFromSortedX返回BVH PASS (object is not null)
✅ null数组buildFromSortedX根节点为null PASS (object is null)
✅ 空BVH查询返回数组 PASS (object is not null)
✅ 空BVH查询返回空数组 PASS (length=0)

🔨 执行构建方法测试...
✅ 基础对象集合构建成功 PASS (object is not null)
✅ 基础对象集合有根节点 PASS (object is not null)
✅ 基础对象集合包含所有对象 PASS
✅ 重叠对象集合构建成功 PASS (object is not null)
✅ 重叠对象集合有根节点 PASS (object is not null)
✅ 重叠对象集合包含所有对象 PASS
✅ 分散对象集合构建成功 PASS (object is not null)
✅ 分散对象集合有根节点 PASS (object is not null)
✅ 分散对象集合包含所有对象 PASS
✅ 极值对象集合构建成功 PASS (object is not null)
✅ 极值对象集合有根节点 PASS (object is not null)
✅ 极值对象集合包含所有对象 PASS
✅ 预排序集合0构建成功 PASS (object is not null)
✅ 预排序集合0有根节点 PASS (object is not null)
✅ 预排序集合0树深度合理 PASS (1 <= 7)
✅ 预排序集合1构建成功 PASS (object is not null)
✅ 预排序集合1有根节点 PASS (object is not null)
✅ 预排序集合1树深度合理 PASS (2 <= 8)
✅ 预排序集合2构建成功 PASS (object is not null)
✅ 预排序集合2有根节点 PASS (object is not null)
✅ 预排序集合2树深度合理 PASS (3 <= 9)
✅ 两种构建方法结果等价 PASS (BVH behavior equivalent)
✅ 两种方法树深度相近 PASS (0 <= 2)
✅ 普通构建叶子节点对象数量限制 PASS
✅ 预排序构建叶子节点对象数量限制 PASS
✅ 单对象普通构建成功 PASS (object is not null)
✅ 单对象预排序构建成功 PASS (object is not null)
✅ 单对象普通构建为叶子节点 PASS
✅ 单对象预排序构建为叶子节点 PASS
✅ 单对象普通构建对象数量 PASS (length=1)
✅ 单对象预排序构建对象数量 PASS (length=1)
✅ 大对象集构建成功 PASS (object is not null)
✅ 大对象集有根节点 PASS (object is not null)
✅ 大对象集构建性能合理 PASS
✅ 大对象集树深度合理 PASS (4 <= 20)
✅ 大对象集树平衡度合理 PASS (0 <= 3)
✅ 大对象集查询功能正常 PASS

🌳 执行树结构质量测试...
✅ 对象数10树深度合理 PASS (1 <= 9)
📊 对象数10: 深度=1, 理论最优=4
✅ 对象数25树深度合理 PASS (2 <= 10)
📊 对象数25: 深度=2, 理论最优=5
✅ 对象数50树深度合理 PASS (3 <= 11)
📊 对象数50: 深度=3, 理论最优=6
✅ 对象数100树深度合理 PASS (4 <= 12)
📊 对象数100: 深度=4, 理论最优=7
✅ 平衡对象集树平衡度良好 PASS (0 <= 2)
✅ 不平衡对象集树平衡度可接受 PASS (0 <= 4)
📊 平衡度测试: 平衡集=0, 不平衡集=0
✅ 叶子节点对象数量限制 PASS
✅ 叶子节点数量合理 PASS
✅ 平均叶子对象数合理 PASS
✅ 最大叶子对象数不超限 PASS (7 <= 8)
📊 叶子节点统计: 数量=8, 平均对象=6.25, 最大对象=7
✅ 包围盒层次结构正确 PASS
✅ 包围盒紧密度合理 PASS
📊 包围盒紧密度: 100%
✅ 空间聚集性良好 PASS
📊 空间聚集性: 100%

🔄 执行排序优化验证...
✅ X轴排序正确性0 PASS
✅ X轴排序正确性1 PASS
✅ X轴排序正确性2 PASS
✅ X轴排序正确性3 PASS
✅ X轴排序正确性4 PASS
✅ X轴排序正确性5 PASS
✅ X轴排序正确性6 PASS
✅ X轴排序正确性7 PASS
✅ X轴排序正确性8 PASS
✅ X轴排序正确性9 PASS
✅ X轴排序正确性10 PASS
✅ X轴排序正确性11 PASS
✅ X轴排序正确性12 PASS
✅ X轴排序正确性13 PASS
✅ X轴排序正确性14 PASS
✅ X轴排序正确性15 PASS
✅ X轴排序正确性16 PASS
✅ X轴排序正确性17 PASS
✅ X轴排序正确性18 PASS
✅ X轴排序正确性19 PASS
✅ X轴排序正确性20 PASS
✅ X轴排序正确性21 PASS
✅ X轴排序正确性22 PASS
✅ X轴排序正确性23 PASS
✅ X轴排序正确性24 PASS
✅ X轴排序正确性25 PASS
✅ X轴排序正确性26 PASS
✅ X轴排序正确性27 PASS
✅ X轴排序正确性28 PASS
✅ 排序优化结果正确性 PASS (BVH behavior equivalent)
✅ 输入确实已预排序 PASS
✅ 预排序输入构建成功 PASS (object is not null)
✅ 预排序输入树深度合理 PASS (2 <= 10)
✅ 预排序输入树平衡度良好 PASS (0 <= 3)
📊 排序性能影响:
  普通构建: 4ms
  排序时间: 3ms
  预排序构建: 2ms
  总预排序时间: 5ms
✅ 预排序构建本身更快 PASS
✅ 总预排序时间合理 PASS
✅ 使用了X轴分割 PASS
✅ 使用了Y轴分割 PASS
✅ 轴使用合理 PASS
📊 轴使用分析: 最大深度=2, X轴=true, Y轴=true

🔍 执行边界条件测试...
✅ 1个对象构建成功 PASS (object is not null)
✅ 1个对象为叶子节点 PASS
✅ 2个对象构建成功 PASS (object is not null)
✅ 大量对象构建成功 PASS (object is not null)
✅ 大量对象构建性能 PASS (7ms <= 500ms)
✅ 极值坐标构建成功 PASS (object is not null)
✅ 极值坐标预排序构建成功 PASS (object is not null)
✅ 极值坐标查询找到所有对象 PASS (length=4)
✅ 退化对象构建成功 PASS (object is not null)
✅ 退化对象查询正常 PASS
✅ MAX_OBJECTS_IN_LEAF=1构建成功 PASS (object is not null)
✅ MAX_OBJECTS_IN_LEAF=1限制有效 PASS
✅ MAX_OBJECTS_IN_LEAF=1查询正常 PASS
✅ MAX_OBJECTS_IN_LEAF=3构建成功 PASS (object is not null)
✅ MAX_OBJECTS_IN_LEAF=3限制有效 PASS
✅ MAX_OBJECTS_IN_LEAF=3查询正常 PASS
✅ MAX_OBJECTS_IN_LEAF=8构建成功 PASS (object is not null)
✅ MAX_OBJECTS_IN_LEAF=8限制有效 PASS
✅ MAX_OBJECTS_IN_LEAF=8查询正常 PASS
✅ MAX_OBJECTS_IN_LEAF=15构建成功 PASS (object is not null)
✅ MAX_OBJECTS_IN_LEAF=15限制有效 PASS
✅ MAX_OBJECTS_IN_LEAF=15查询正常 PASS
✅ 相同位置对象构建成功 PASS (object is not null)
✅ 嵌套对象构建成功 PASS (object is not null)
✅ 嵌套对象查询找到所有相交对象 PASS (expected=3, actual=3)

⚡ 执行性能基准测试...
📊 build()方法性能: 100次构建耗时 148ms
✅ build()方法性能达标 PASS (1.48ms <= 10ms)
📊 buildFromSortedX()方法性能: 100次构建耗时 113ms
✅ buildFromSortedX()方法性能达标 PASS (1.13ms <= 7ms)
📊 方法性能对比:
  普通构建平均: 3.64ms
  预排序构建平均: 2.88ms
  加速比: 1.26x
✅ 预排序方法确实更快 PASS
✅ 加速比合理 PASS
📊 可扩展性测试:
  100对象: 5ms, 深度=4, 0.05ms/对象
✅ 100对象构建时间合理 PASS
  500对象: 24ms, 深度=6, 0.048ms/对象
✅ 500对象构建时间合理 PASS
  1000对象: 57ms, 深度=7, 0.057ms/对象
✅ 1000对象构建时间合理 PASS
  2000对象: 139ms, 深度=8, 0.07ms/对象
✅ 2000对象构建时间合理 PASS
📊 优化有效性测试:
  随机分布: 普通=8ms, 预排序=7ms, 提升=13%
✅ 随机分布场景预排序更快 PASS
  聚集分布: 普通=9ms, 预排序=7ms, 提升=22%
✅ 聚集分布场景预排序更快 PASS
  线性分布: 普通=6ms, 预排序=6ms, 提升=0%
✅ 线性分布场景预排序更快 PASS
  网格分布: 普通=10ms, 预排序=8ms, 提升=20%
✅ 网格分布场景预排序更快 PASS

💾 执行数据完整性测试...
✅ 原始对象0在BVH中 PASS
✅ 原始对象1在BVH中 PASS
✅ 原始对象2在BVH中 PASS
✅ 原始对象3在BVH中 PASS
✅ 原始对象4在BVH中 PASS
✅ 原始对象5在BVH中 PASS
✅ 原始对象6在BVH中 PASS
✅ 原始对象7在BVH中 PASS
✅ 原始对象8在BVH中 PASS
✅ 原始对象9在BVH中 PASS
✅ 原始对象10在BVH中 PASS
✅ 原始对象11在BVH中 PASS
✅ 原始对象12在BVH中 PASS
✅ 原始对象13在BVH中 PASS
✅ 原始对象14在BVH中 PASS
✅ 原始对象15在BVH中 PASS
✅ 原始对象16在BVH中 PASS
✅ 原始对象17在BVH中 PASS
✅ 原始对象18在BVH中 PASS
✅ 原始对象19在BVH中 PASS
✅ BVH对象总数正确 PASS (expected=20, actual=20)
✅ BVH对象0不为null PASS (object is not null)
✅ BVH对象0有AABB PASS (object is not null)
✅ BVH对象1不为null PASS (object is not null)
✅ BVH对象1有AABB PASS (object is not null)
✅ BVH对象2不为null PASS (object is not null)
✅ BVH对象2有AABB PASS (object is not null)
✅ BVH对象3不为null PASS (object is not null)
✅ BVH对象3有AABB PASS (object is not null)
✅ BVH对象4不为null PASS (object is not null)
✅ BVH对象4有AABB PASS (object is not null)
✅ BVH对象5不为null PASS (object is not null)
✅ BVH对象5有AABB PASS (object is not null)
✅ BVH对象6不为null PASS (object is not null)
✅ BVH对象6有AABB PASS (object is not null)
✅ BVH对象7不为null PASS (object is not null)
✅ BVH对象7有AABB PASS (object is not null)
✅ BVH对象8不为null PASS (object is not null)
✅ BVH对象8有AABB PASS (object is not null)
✅ BVH对象9不为null PASS (object is not null)
✅ BVH对象9有AABB PASS (object is not null)
✅ BVH对象10不为null PASS (object is not null)
✅ BVH对象10有AABB PASS (object is not null)
✅ BVH对象11不为null PASS (object is not null)
✅ BVH对象11有AABB PASS (object is not null)
✅ BVH对象12不为null PASS (object is not null)
✅ BVH对象12有AABB PASS (object is not null)
✅ BVH对象13不为null PASS (object is not null)
✅ BVH对象13有AABB PASS (object is not null)
✅ BVH对象14不为null PASS (object is not null)
✅ BVH对象14有AABB PASS (object is not null)
✅ BVH对象15不为null PASS (object is not null)
✅ BVH对象15有AABB PASS (object is not null)
✅ BVH对象16不为null PASS (object is not null)
✅ BVH对象16有AABB PASS (object is not null)
✅ BVH对象17不为null PASS (object is not null)
✅ BVH对象17有AABB PASS (object is not null)
✅ BVH对象18不为null PASS (object is not null)
✅ BVH对象18有AABB PASS (object is not null)
✅ BVH对象19不为null PASS (object is not null)
✅ BVH对象19有AABB PASS (object is not null)
✅ 包围盒层次结构完整 PASS
✅ 根包围盒包含对象0 PASS
✅ 根包围盒包含对象1 PASS
✅ 根包围盒包含对象2 PASS
✅ 根包围盒包含对象3 PASS
✅ 根包围盒包含对象4 PASS
✅ 根包围盒包含对象5 PASS
✅ 根包围盒包含对象6 PASS
✅ 根包围盒包含对象7 PASS
✅ 根包围盒包含对象8 PASS
✅ 根包围盒包含对象9 PASS
✅ 根包围盒包含对象10 PASS
✅ 根包围盒包含对象11 PASS
✅ 根包围盒包含对象12 PASS
✅ 根包围盒包含对象13 PASS
✅ 根包围盒包含对象14 PASS
✅ 根包围盒包含对象15 PASS
✅ 根包围盒包含对象16 PASS
✅ 根包围盒包含对象17 PASS
✅ 根包围盒包含对象18 PASS
✅ 根包围盒包含对象19 PASS
✅ 根包围盒包含对象20 PASS
✅ 根包围盒包含对象21 PASS
✅ 根包围盒包含对象22 PASS
✅ 根包围盒包含对象23 PASS
✅ 根包围盒包含对象24 PASS
✅ 根包围盒宽度非负 PASS
✅ 根包围盒高度非负 PASS
✅ 树结构完整 PASS
✅ 存在叶子节点 PASS
✅ 叶子节点对象数量合理 PASS
✅ 内部节点没有对象 PASS
📊 树结构统计: 叶子=4, 内部=3, 叶子对象=30
✅ 全范围查询返回所有对象 PASS (expected=40, actual=40)
✅ 空范围查询返回空结果 PASS (length=0)
✅ 精确查询结果0确实相交 PASS
✅ 精确查询结果1确实相交 PASS
✅ 精确查询没有遗漏对象 PASS (expected=0, actual=0)
✅ BVH不受原始数组修改影响 PASS
✅ BVH查询结果0不为null PASS (object is not null)
✅ BVH查询结果1不为null PASS (object is not null)
✅ BVH查询结果2不为null PASS (object is not null)
✅ BVH查询结果3不为null PASS (object is not null)
✅ BVH查询结果4不为null PASS (object is not null)
✅ BVH查询结果5不为null PASS (object is not null)
✅ BVH查询结果6不为null PASS (object is not null)
✅ BVH查询结果7不为null PASS (object is not null)
✅ BVH查询结果8不为null PASS (object is not null)
✅ BVH查询结果9不为null PASS (object is not null)
✅ BVH查询结果10不为null PASS (object is not null)
✅ BVH查询结果11不为null PASS (object is not null)
✅ BVH查询结果12不为null PASS (object is not null)
✅ BVH查询结果13不为null PASS (object is not null)
✅ BVH查询结果14不为null PASS (object is not null)

💪 执行压力测试...
🔥 大规模构建测试: 5000个对象
✅ 大规模构建成功 PASS (object is not null)
✅ 大规模构建有根节点 PASS (object is not null)
✅ 大规模构建时间合理 PASS
✅ 大规模构建树深度合理 PASS (10 <= 22.2877123795495)
✅ 大规模查询功能正常 PASS
✅ 大规模查询性能合理 PASS
📊 大规模测试结果:
  构建时间: 421ms (0.084ms/对象)
  树深度: 10
  查询时间: 4ms
  查询结果: 1246个对象
🧠 内存测试进度: 1/20
🧠 内存测试进度: 6/20
🧠 内存测试进度: 11/20
🧠 内存测试进度: 16/20
🧠 内存使用测试: 20次迭代(10000总对象)耗时 729ms
✅ 内存使用测试通过 PASS
✅ 极深树构建成功 PASS (object is not null)
🔥 极深树测试: 深度=4, 构建时间=3ms
✅ 极深树深度可接受 PASS (4 <= 40)
✅ 极深树构建时间合理 PASS
✅ 极深树查询功能正常 PASS
✅ 极深树查询性能可接受 PASS
✅ 并发操作0结果有效 PASS
✅ 并发操作0结果有效 PASS
✅ 并发操作0结果有效 PASS
✅ 并发操作1结果有效 PASS
✅ 并发操作1结果有效 PASS
✅ 并发操作1结果有效 PASS
✅ 并发操作2结果有效 PASS
✅ 并发操作2结果有效 PASS
✅ 并发操作2结果有效 PASS
✅ 并发操作3结果有效 PASS
✅ 并发操作3结果有效 PASS
✅ 并发操作3结果有效 PASS
✅ 并发操作4结果有效 PASS
✅ 并发操作4结果有效 PASS
✅ 并发操作4结果有效 PASS
✅ 并发操作5结果有效 PASS
✅ 并发操作5结果有效 PASS
✅ 并发操作5结果有效 PASS
✅ 并发操作6结果有效 PASS
✅ 并发操作6结果有效 PASS
✅ 并发操作6结果有效 PASS
✅ 并发操作7结果有效 PASS
✅ 并发操作7结果有效 PASS
✅ 并发操作7结果有效 PASS
✅ 并发操作8结果有效 PASS
✅ 并发操作8结果有效 PASS
✅ 并发操作8结果有效 PASS
✅ 并发操作9结果有效 PASS
✅ 并发操作9结果有效 PASS
✅ 并发操作9结果有效 PASS
✅ 并发操作10结果有效 PASS
✅ 并发操作10结果有效 PASS
✅ 并发操作10结果有效 PASS
✅ 并发操作11结果有效 PASS
✅ 并发操作11结果有效 PASS
✅ 并发操作11结果有效 PASS
✅ 并发操作12结果有效 PASS
✅ 并发操作12结果有效 PASS
✅ 并发操作12结果有效 PASS
✅ 并发操作13结果有效 PASS
✅ 并发操作13结果有效 PASS
✅ 并发操作13结果有效 PASS
✅ 并发操作14结果有效 PASS
✅ 并发操作14结果有效 PASS
✅ 并发操作14结果有效 PASS
✅ 并发操作15结果有效 PASS
✅ 并发操作15结果有效 PASS
✅ 并发操作15结果有效 PASS
✅ 并发操作16结果有效 PASS
✅ 并发操作16结果有效 PASS
✅ 并发操作16结果有效 PASS
✅ 并发操作17结果有效 PASS
✅ 并发操作17结果有效 PASS
✅ 并发操作17结果有效 PASS
✅ 并发操作18结果有效 PASS
✅ 并发操作18结果有效 PASS
✅ 并发操作18结果有效 PASS
✅ 并发操作19结果有效 PASS
✅ 并发操作19结果有效 PASS
✅ 并发操作19结果有效 PASS
✅ 并发操作20结果有效 PASS
✅ 并发操作20结果有效 PASS
✅ 并发操作20结果有效 PASS
✅ 并发操作21结果有效 PASS
✅ 并发操作21结果有效 PASS
✅ 并发操作21结果有效 PASS
✅ 并发操作22结果有效 PASS
✅ 并发操作22结果有效 PASS
✅ 并发操作22结果有效 PASS
✅ 并发操作23结果有效 PASS
✅ 并发操作23结果有效 PASS
✅ 并发操作23结果有效 PASS
✅ 并发操作24结果有效 PASS
✅ 并发操作24结果有效 PASS
✅ 并发操作24结果有效 PASS
✅ 并发操作25结果有效 PASS
✅ 并发操作25结果有效 PASS
✅ 并发操作25结果有效 PASS
✅ 并发操作26结果有效 PASS
✅ 并发操作26结果有效 PASS
✅ 并发操作26结果有效 PASS
✅ 并发操作27结果有效 PASS
✅ 并发操作27结果有效 PASS
✅ 并发操作27结果有效 PASS
✅ 并发操作28结果有效 PASS
✅ 并发操作28结果有效 PASS
✅ 并发操作28结果有效 PASS
✅ 并发操作29结果有效 PASS
✅ 并发操作29结果有效 PASS
✅ 并发操作29结果有效 PASS
✅ 并发操作30结果有效 PASS
✅ 并发操作30结果有效 PASS
✅ 并发操作30结果有效 PASS
✅ 并发操作31结果有效 PASS
✅ 并发操作31结果有效 PASS
✅ 并发操作31结果有效 PASS
✅ 并发操作32结果有效 PASS
✅ 并发操作32结果有效 PASS
✅ 并发操作32结果有效 PASS
✅ 并发操作33结果有效 PASS
✅ 并发操作33结果有效 PASS
✅ 并发操作33结果有效 PASS
✅ 并发操作34结果有效 PASS
✅ 并发操作34结果有效 PASS
✅ 并发操作34结果有效 PASS
✅ 并发操作35结果有效 PASS
✅ 并发操作35结果有效 PASS
✅ 并发操作35结果有效 PASS
✅ 并发操作36结果有效 PASS
✅ 并发操作36结果有效 PASS
✅ 并发操作36结果有效 PASS
✅ 并发操作37结果有效 PASS
✅ 并发操作37结果有效 PASS
✅ 并发操作37结果有效 PASS
✅ 并发操作38结果有效 PASS
✅ 并发操作38结果有效 PASS
✅ 并发操作38结果有效 PASS
✅ 并发操作39结果有效 PASS
✅ 并发操作39结果有效 PASS
✅ 并发操作39结果有效 PASS
✅ 并发操作40结果有效 PASS
✅ 并发操作40结果有效 PASS
✅ 并发操作40结果有效 PASS
✅ 并发操作41结果有效 PASS
✅ 并发操作41结果有效 PASS
✅ 并发操作41结果有效 PASS
✅ 并发操作42结果有效 PASS
✅ 并发操作42结果有效 PASS
✅ 并发操作42结果有效 PASS
✅ 并发操作43结果有效 PASS
✅ 并发操作43结果有效 PASS
✅ 并发操作43结果有效 PASS
✅ 并发操作44结果有效 PASS
✅ 并发操作44结果有效 PASS
✅ 并发操作44结果有效 PASS
✅ 并发操作45结果有效 PASS
✅ 并发操作45结果有效 PASS
✅ 并发操作45结果有效 PASS
✅ 并发操作46结果有效 PASS
✅ 并发操作46结果有效 PASS
✅ 并发操作46结果有效 PASS
✅ 并发操作47结果有效 PASS
✅ 并发操作47结果有效 PASS
✅ 并发操作47结果有效 PASS
✅ 并发操作48结果有效 PASS
✅ 并发操作48结果有效 PASS
✅ 并发操作48结果有效 PASS
✅ 并发操作49结果有效 PASS
✅ 并发操作49结果有效 PASS
✅ 并发操作49结果有效 PASS
🔄 并发操作测试: 50次并发操作耗时 377ms
✅ 并发操作性能合理 PASS
✅ 边界情况混合构建成功 PASS (object is not null)
✅ 边界情况混合构建时间合理 PASS
✅ 边界情况查询0结果有效 PASS
✅ 边界情况查询1结果有效 PASS
✅ 边界情况查询2结果有效 PASS
✅ 边界情况查询3结果有效 PASS
✅ 边界情况查询4结果有效 PASS
✅ 边界情况查询5结果有效 PASS
✅ 边界情况查询6结果有效 PASS
✅ 边界情况查询7结果有效 PASS
✅ 边界情况查询8结果有效 PASS
✅ 边界情况查询9结果有效 PASS
✅ 边界情况查询10结果有效 PASS
✅ 边界情况查询11结果有效 PASS
✅ 边界情况查询12结果有效 PASS
✅ 边界情况查询13结果有效 PASS
✅ 边界情况查询14结果有效 PASS
✅ 边界情况查询15结果有效 PASS
✅ 边界情况查询16结果有效 PASS
✅ 边界情况查询17结果有效 PASS
✅ 边界情况查询18结果有效 PASS
✅ 边界情况查询19结果有效 PASS
🔥 边界情况混合测试: 50个混合边界对象，构建耗时 1ms

🧮 执行算法验证测试...
✅ 查询0结果数量一致 PASS (expected=0, actual=0)
✅ 查询1结果数量一致 PASS (expected=0, actual=0)
✅ 查询2结果数量一致 PASS (expected=0, actual=0)
✅ 查询3结果数量一致 PASS (expected=1, actual=1)
✅ BVH查询3结果0在暴力搜索中 PASS
✅ 查询4结果数量一致 PASS (expected=0, actual=0)
📊 与暴力搜索对比: 5个查询全部一致
📊 构建质量指标:
  深度: 3 (理论最优: 6, 质量: 200%)
  平衡度: 0 (质量: 100%)
  紧密度: 100%
  聚集性: 100%
✅ 深度质量合理 PASS
✅ 平衡度质量合理 PASS
✅ 紧密度合理 PASS
✅ 聚集性合理 PASS
📊 查询性能验证:
  BVH查询: 8ms
  暴力搜索: 30ms
  加速比: 3.75x
✅ BVH查询确实更快 PASS
✅ 加速比显著 PASS
📊 构建策略优劣对比:
  普通构建: 时间=2ms, 深度=4, 平衡=0, 查询=2ms
  预排序构建: 时间=2ms, 深度=4, 平衡=0, 查询=2ms
✅ 预排序构建时间优势 PASS
✅ 预排序构建质量不劣 PASS
✅ 预排序构建平衡度不劣 PASS

🌍 执行实际场景测试...
🎮 游戏世界构建场景测试
🏗️ 创建游戏世界: 460个对象
✅ 游戏世界BVH构建成功 PASS (object is not null)
✅ 游戏世界构建时间合理 PASS
✅ 玩家视野查询快速 PASS
✅ 玩家视野有对象 PASS
✅ 技能范围检测快速 PASS
🎯 游戏世界测试结果:
  构建时间: 27ms
  视野查询: 0ms, 找到76个对象
  技能检测: 0ms, 找到26个目标
🖼️ UI元素层次结构场景测试
🎨 创建UI界面: 49个元素
✅ UI层次构建成功 PASS (object is not null)
✅ UI构建时间优秀 PASS
  面板区域点击: 0ms, 4个元素
  按钮区域点击: 0ms, 3个元素
  文本区域点击: 1ms, 4个元素
  空白区域点击: 0ms, 0个元素
✅ UI点击检测快速 PASS
🖱️ UI测试结果: 总构建1ms, 点击检测1ms
🗺️ 地图POI索引场景测试
📍 创建地图POI: 115个兴趣点
✅ 地图POI索引构建成功 PASS (object is not null)
✅ 地图构建时间合理 PASS
  市中心: 0ms, 1个POI
  商业区: 0ms, 8个POI
  住宅区: 0ms, 7个POI
  郊区: 0ms, 7个POI
  500m范围搜索: 0ms, 0个POI
  1km范围搜索: 0ms, 3个POI
  1.5km范围搜索: 0ms, 9个POI
✅ 地图区域查询快速 PASS
✅ 附近搜索快速 PASS
🗺️ 地图测试结果: 构建5ms, 区域查询0ms, 附近搜索0ms
✨ 粒子系统优化场景测试
💫 创建粒子系统: 450个粒子
✅ 粒子系统BVH构建成功 PASS (object is not null)
✅ 粒子系统构建时间优秀 PASS
  爆炸区域碰撞: 0ms, 38个粒子
  全屏雨滴碰撞: 1ms, 450个粒子
  火花区域碰撞: 1ms, 169个粒子
✅ 粒子碰撞检测快速 PASS
✅ 视觉剔除快速 PASS
✨ 粒子测试结果: 构建24ms, 碰撞2ms, 剔除1ms
🔄 动态内容管理场景测试
📱 创建动态内容: 180个内容项
✅ 动态内容BVH构建成功 PASS (object is not null)
✅ 动态内容构建时间优秀 PASS
  主视口: 0ms, 42个内容
  滚动视口: 1ms, 43个内容
  预测视口: 0ms, 36个内容
  高优先级区域: 0ms, 17个内容
  中优先级区域: 0ms, 29个内容
  低优先级区域: 0ms, 46个内容
✅ 视口管理快速 PASS
✅ 优先级查询快速 PASS
🔄 动态内容测试结果: 构建9ms, 视口1ms, 优先级0ms

================================================================================
📊 BVHBuilder 测试结果汇总
================================================================================
总测试数: 496
通过: 496 ✅
失败: 0 ❌
成功率: 100%
总耗时: 3246ms

⚡ 性能基准报告:
  Build Method: 1.48ms/次 (100次测试)
  BuildFromSortedX Method: 1.13ms/次 (100次测试)
  Method Comparison:
    普通构建: 3.64ms/次
    预排序构建: 2.88ms/次
    加速比: 1.26x

🎯 测试覆盖范围:
  📋 基础功能: 静态配置, build(), buildFromSortedX(), 空输入处理
  🔨 构建方法: 方法变体, 等价性验证, 单/大对象集构建
  🌳 树结构质量: 深度, 平衡度, 叶子节点, 包围盒, 空间聚集性
  🔄 排序优化: 正确性验证, 预排序行为, 性能影响, 轴交替
  🔍 边界条件: 极值对象数, 极值坐标, 退化对象, 配置变体
  ⚡ 性能基准: 构建速度, 方法对比, 可扩展性, 优化有效性
  💾 数据完整性: 对象引用, 包围盒, 树结构, 查询结果, 修改安全
  💪 压力测试: 大规模构建, 内存使用, 极深树, 并发操作, 边界混合
  🧮 算法验证: 暴力对比, 质量指标, 查询性能, 树优化度
  🌍 实际场景: 游戏世界, UI层次, 地图POI, 粒子系统, 动态内容

🚀 BVHBuilder 性能特性:
  ✨ 双构建方法: 通用build()和优化buildFromSortedX()
  ✨ TimSort集成: 保证O(n log n)最坏情况性能
  ✨ 预排序优化: 跳过根节点排序，显著提升性能
  ✨ 轴交替分割: X/Y轴交替，保证空间分布平衡
  ✨ 可配置叶子限制: MAX_OBJECTS_IN_LEAF灵活控制
  ✨ 健壮边界处理: 空输入、极值坐标、退化对象

🎉 所有测试通过！BVHBuilder 组件质量优秀！
🏗️ BVHBuilder 已准备好构建高性能BVH树结构！
⚡ 推荐在性能敏感场景中使用 buildFromSortedX() 方法！
================================================================================
