org.flashNight.naki.DataStructures.BVHTest.runAll();


================================================================================
🚀 BVH 完整测试套件启动
================================================================================

🔧 初始化BVH测试数据...
📦 创建了 30 个测试对象
🌳 创建了4种不同复杂度的BVH结构
📊 简单BVH：单层叶子节点
📊 复杂BVH：多层树结构
📊 空BVH：null根节点
📊 深度BVH：深度6的平衡树

📋 执行基础功能测试...
✅ BVH构造函数创建对象 PASS (object is not null)
✅ BVH构造函数设置root PASS (object is not null)
✅ BVH构造函数root引用正确 PASS
✅ null根节点BVH构造成功 PASS (object is not null)
✅ null根节点BVH的root为null PASS (object is null)
✅ 复杂BVH构造成功 PASS (object is not null)
✅ 复杂BVH根节点存在 PASS (object is not null)
✅ 复杂BVH根节点是内部节点 PASS
✅ simpleBVH root属性访问 PASS (object is not null)
✅ complexBVH root属性访问 PASS (object is not null)
✅ emptyBVH root属性为null PASS (object is null)
✅ BVH root属性可修改 PASS
✅ BVH root属性恢复 PASS
✅ AABB查询返回数组 PASS (object is not null)
✅ AABB查询返回Array类型 PASS
✅ 圆形查询返回数组 PASS (object is not null)
✅ 圆形查询返回Array类型 PASS
✅ 空BVH查询返回数组 PASS (object is not null)
✅ 空BVH查询返回空数组 PASS (length=0)
✅ 空BVH圆形查询返回数组 PASS (object is not null)
✅ 空BVH圆形查询返回空数组 PASS (length=0)

🔍 执行查询接口测试...
✅ 相交AABB查询返回结果 PASS
✅ 查询结果对象0不为null PASS (object is not null)
✅ 查询结果对象0有AABB PASS (object is not null)
✅ 查询结果对象0与查询AABB相交 PASS
✅ 查询结果对象1不为null PASS (object is not null)
✅ 查询结果对象1有AABB PASS (object is not null)
✅ 查询结果对象1与查询AABB相交 PASS
✅ 查询结果对象2不为null PASS (object is not null)
✅ 查询结果对象2有AABB PASS (object is not null)
✅ 查询结果对象2与查询AABB相交 PASS
✅ 查询结果对象3不为null PASS (object is not null)
✅ 查询结果对象3有AABB PASS (object is not null)
✅ 查询结果对象3与查询AABB相交 PASS
✅ 不相交AABB查询返回空数组 PASS (length=0)
✅ 完全包含AABB查询返回所有对象 PASS
✅ 圆形查询结果对象0不为null PASS (object is not null)
✅ 圆形查询结果对象0有AABB PASS (object is not null)
✅ 圆形查询结果对象0与圆形相交 PASS
✅ 圆形查询结果对象1不为null PASS (object is not null)
✅ 圆形查询结果对象1有AABB PASS (object is not null)
✅ 圆形查询结果对象1与圆形相交 PASS
✅ 圆形查询结果对象2不为null PASS (object is not null)
✅ 圆形查询结果对象2有AABB PASS (object is not null)
✅ 圆形查询结果对象2与圆形相交 PASS
✅ 圆形查询结果对象3不为null PASS (object is not null)
✅ 圆形查询结果对象3有AABB PASS (object is not null)
✅ 圆形查询结果对象3与圆形相交 PASS
✅ 不相交圆形查询返回空数组 PASS (length=0)
✅ 极大半径圆形查询返回对象 PASS
✅ null AABB查询返回数组 PASS (object is not null)
✅ null Vector查询返回数组 PASS (object is not null)
✅ 负半径查询返回数组 PASS (object is not null)
✅ NaN半径查询返回数组 PASS (object is not null)
✅ Infinity半径查询返回数组 PASS (object is not null)
✅ AABB查询结果一致性（长度） PASS (expected=0, actual=0)
✅ 圆形查询结果一致性（长度） PASS (expected=0, actual=0)

🔗 执行集成测试...
✅ 集成测试根节点存在 PASS (object is not null)
✅ BVH与BVHNode查询结果一致（长度） PASS (expected=6, actual=6)
✅ BVH与BVHNode查询结果一致（对象0） PASS (object found in array)
✅ BVH与BVHNode查询结果一致（对象1） PASS (object found in array)
✅ BVH与BVHNode查询结果一致（对象2） PASS (object found in array)
✅ BVH与BVHNode查询结果一致（对象3） PASS (object found in array)
✅ BVH与BVHNode查询结果一致（对象4） PASS (object found in array)
✅ BVH与BVHNode查询结果一致（对象5） PASS (object found in array)
✅ BVH与BVHNode圆形查询结果一致（长度） PASS (expected=0, actual=0)
✅ 复杂树遍历结果正确 PASS (expected=17, actual=17)
✅ 左子树对象0在结果中 PASS (object found in array)
✅ 左子树对象1在结果中 PASS (object found in array)
✅ 左子树对象2在结果中 PASS (object found in array)
✅ 左子树对象3在结果中 PASS (object found in array)
✅ 左子树对象4在结果中 PASS (object found in array)
✅ 左子树对象5在结果中 PASS (object found in array)
✅ 左子树对象6在结果中 PASS (object found in array)
✅ 左子树对象7在结果中 PASS (object found in array)
✅ 左子树对象8在结果中 PASS (object found in array)
✅ 右子树对象0在结果中 PASS (object found in array)
✅ 右子树对象1在结果中 PASS (object found in array)
✅ 右子树对象2在结果中 PASS (object found in array)
✅ 右子树对象3在结果中 PASS (object found in array)
✅ 右子树对象4在结果中 PASS (object found in array)
✅ 右子树对象5在结果中 PASS (object found in array)
✅ 右子树对象6在结果中 PASS (object found in array)
✅ 右子树对象7在结果中 PASS (object found in array)
✅ 简单BVH查询正常 PASS
✅ 复杂BVH查询正常 PASS
✅ 深度BVH查询正常 PASS
✅ 查询结果对象0与查询AABB相交 PASS
✅ 查询结果对象1与查询AABB相交 PASS
✅ 查询结果对象2与查询AABB相交 PASS
✅ 查询结果对象3与查询AABB相交 PASS
✅ 查询结果对象0与查询AABB相交 PASS
✅ 查询结果对象1与查询AABB相交 PASS
✅ AABB查询委托调用次数 PASS (expected=1, actual=1)
✅ AABB查询委托结果长度 PASS (expected=2, actual=2)
✅ 圆形查询委托调用次数 PASS (expected=1, actual=1)
✅ 圆形查询委托结果长度 PASS (expected=2, actual=2)

🔍 执行边界条件测试...
✅ 空BVH查询返回非null PASS (object is not null)
✅ 空BVH查询返回空数组 PASS (length=0)
✅ 空BVH圆形查询返回非null PASS (object is not null)
✅ 空BVH圆形查询返回空数组 PASS (length=0)
✅ 空BVH多次查询0返回空数组 PASS (length=0)
✅ 空BVH多次查询1返回空数组 PASS (length=0)
✅ 空BVH多次查询2返回空数组 PASS (length=0)
✅ 空BVH多次查询3返回空数组 PASS (length=0)
✅ 空BVH多次查询4返回空数组 PASS (length=0)
✅ 极小AABB查询正常 PASS
✅ 极大AABB查询正常 PASS
✅ 极大AABB查询返回对象 PASS
✅ 逆序AABB查询不崩溃 PASS
✅ 极值坐标AABB查询不崩溃 PASS
✅ 零面积AABB查询正常 PASS
✅ 线条AABB查询正常 PASS
✅ 边界精确查询正常 PASS
✅ 原点圆形查询正常 PASS
✅ 负坐标圆心查询正常 PASS
✅ 异常后恢复正常查询 PASS
✅ 异常后恢复圆形查询 PASS
✅ 异常后根节点完整 PASS (object is not null)
✅ 异常后根节点状态正常 PASS

⚡ 执行性能基准测试...
📊 BVH AABB查询性能: 1000次调用耗时 22ms
✅ BVH AABB查询性能达标 PASS (0.022ms <= 0.5ms)
📊 BVH圆形查询性能: 1000次调用耗时 28ms
✅ BVH圆形查询性能达标 PASS (0.028ms <= 0.5ms)
📊 复杂BVH查询性能: 500次调用耗时 12ms
✅ 复杂BVH查询性能达标 PASS (0.024ms <= 1ms)
📊 批量查询性能: 5000次调用耗时 170ms
✅ 批量查询性能达标 PASS (170ms <= 250ms)

💾 执行数据完整性测试...
✅ 查询结果数组不为null PASS (object is not null)
✅ 查询结果是Array类型 PASS
✅ 查询结果对象0不为null PASS (object is not null)
✅ 查询结果对象1不为null PASS (object is not null)
✅ 查询结果对象2不为null PASS (object is not null)
✅ 查询结果对象3不为null PASS (object is not null)
✅ 查询结果对象4不为null PASS (object is not null)
✅ 查询结果对象5不为null PASS (object is not null)
✅ 查询结果对象6不为null PASS (object is not null)
✅ 查询结果对象7不为null PASS (object is not null)
✅ 查询结果对象8不为null PASS (object is not null)
✅ 查询结果对象9不为null PASS (object is not null)
✅ 查询结果对象10不为null PASS (object is not null)
✅ 查询结果对象11不为null PASS (object is not null)
✅ 查询结果无重复对象(0,1) PASS
✅ 查询结果无重复对象(0,2) PASS
✅ 查询结果无重复对象(0,3) PASS
✅ 查询结果无重复对象(0,4) PASS
✅ 查询结果无重复对象(0,5) PASS
✅ 查询结果无重复对象(0,6) PASS
✅ 查询结果无重复对象(0,7) PASS
✅ 查询结果无重复对象(0,8) PASS
✅ 查询结果无重复对象(0,9) PASS
✅ 查询结果无重复对象(0,10) PASS
✅ 查询结果无重复对象(0,11) PASS
✅ 查询结果无重复对象(1,2) PASS
✅ 查询结果无重复对象(1,3) PASS
✅ 查询结果无重复对象(1,4) PASS
✅ 查询结果无重复对象(1,5) PASS
✅ 查询结果无重复对象(1,6) PASS
✅ 查询结果无重复对象(1,7) PASS
✅ 查询结果无重复对象(1,8) PASS
✅ 查询结果无重复对象(1,9) PASS
✅ 查询结果无重复对象(1,10) PASS
✅ 查询结果无重复对象(1,11) PASS
✅ 查询结果无重复对象(2,3) PASS
✅ 查询结果无重复对象(2,4) PASS
✅ 查询结果无重复对象(2,5) PASS
✅ 查询结果无重复对象(2,6) PASS
✅ 查询结果无重复对象(2,7) PASS
✅ 查询结果无重复对象(2,8) PASS
✅ 查询结果无重复对象(2,9) PASS
✅ 查询结果无重复对象(2,10) PASS
✅ 查询结果无重复对象(2,11) PASS
✅ 查询结果无重复对象(3,4) PASS
✅ 查询结果无重复对象(3,5) PASS
✅ 查询结果无重复对象(3,6) PASS
✅ 查询结果无重复对象(3,7) PASS
✅ 查询结果无重复对象(3,8) PASS
✅ 查询结果无重复对象(3,9) PASS
✅ 查询结果无重复对象(3,10) PASS
✅ 查询结果无重复对象(3,11) PASS
✅ 查询结果无重复对象(4,5) PASS
✅ 查询结果无重复对象(4,6) PASS
✅ 查询结果无重复对象(4,7) PASS
✅ 查询结果无重复对象(4,8) PASS
✅ 查询结果无重复对象(4,9) PASS
✅ 查询结果无重复对象(4,10) PASS
✅ 查询结果无重复对象(4,11) PASS
✅ 查询结果无重复对象(5,6) PASS
✅ 查询结果无重复对象(5,7) PASS
✅ 查询结果无重复对象(5,8) PASS
✅ 查询结果无重复对象(5,9) PASS
✅ 查询结果无重复对象(5,10) PASS
✅ 查询结果无重复对象(5,11) PASS
✅ 查询结果无重复对象(6,7) PASS
✅ 查询结果无重复对象(6,8) PASS
✅ 查询结果无重复对象(6,9) PASS
✅ 查询结果无重复对象(6,10) PASS
✅ 查询结果无重复对象(6,11) PASS
✅ 查询结果无重复对象(7,8) PASS
✅ 查询结果无重复对象(7,9) PASS
✅ 查询结果无重复对象(7,10) PASS
✅ 查询结果无重复对象(7,11) PASS
✅ 查询结果无重复对象(8,9) PASS
✅ 查询结果无重复对象(8,10) PASS
✅ 查询结果无重复对象(8,11) PASS
✅ 查询结果无重复对象(9,10) PASS
✅ 查询结果无重复对象(9,11) PASS
✅ 查询结果无重复对象(10,11) PASS
✅ 查询结果对象0实现getAABB方法 PASS
✅ 查询结果对象0的AABB不为null PASS (object is not null)
✅ 查询结果对象1实现getAABB方法 PASS
✅ 查询结果对象1的AABB不为null PASS (object is not null)
✅ 查询结果对象2实现getAABB方法 PASS
✅ 查询结果对象2的AABB不为null PASS (object is not null)
✅ 查询结果对象3实现getAABB方法 PASS
✅ 查询结果对象3的AABB不为null PASS (object is not null)
✅ 查询结果对象4实现getAABB方法 PASS
✅ 查询结果对象4的AABB不为null PASS (object is not null)
✅ 查询结果对象5实现getAABB方法 PASS
✅ 查询结果对象5的AABB不为null PASS (object is not null)
✅ 查询结果对象6实现getAABB方法 PASS
✅ 查询结果对象6的AABB不为null PASS (object is not null)
✅ 查询结果对象7实现getAABB方法 PASS
✅ 查询结果对象7的AABB不为null PASS (object is not null)
✅ 查询结果对象8实现getAABB方法 PASS
✅ 查询结果对象8的AABB不为null PASS (object is not null)
✅ 查询结果对象9实现getAABB方法 PASS
✅ 查询结果对象9的AABB不为null PASS (object is not null)
✅ 查询结果对象10实现getAABB方法 PASS
✅ 查询结果对象10的AABB不为null PASS (object is not null)
✅ 查询结果对象11实现getAABB方法 PASS
✅ 查询结果对象11的AABB不为null PASS (object is not null)
✅ 查询结果对象0是原始对象引用 PASS
✅ 查询结果对象1是原始对象引用 PASS
✅ 查询结果对象2是原始对象引用 PASS
✅ 查询结果对象3是原始对象引用 PASS
✅ 查询结果对象0名称属性 PASS (object is not null)
✅ 查询结果对象0bounds属性 PASS (object is not null)
✅ 查询结果对象1名称属性 PASS (object is not null)
✅ 查询结果对象1bounds属性 PASS (object is not null)
✅ 查询结果对象2名称属性 PASS (object is not null)
✅ 查询结果对象2bounds属性 PASS (object is not null)
✅ 查询结果对象3名称属性 PASS (object is not null)
✅ 查询结果对象3bounds属性 PASS (object is not null)
✅ 多次查询后根节点引用不变 PASS
✅ 根节点bounds完整 PASS (object is not null)
✅ 根节点objects完整 PASS (object is not null)
✅ 根节点仍是叶子节点 PASS
✅ 复杂BVH根节点左子树 PASS (object is not null)
✅ 复杂BVH根节点右子树 PASS (object is not null)
✅ 复杂BVH根节点仍是内部节点 PASS
✅ 并发访问查询0结果不为null PASS (object is not null)
✅ 并发访问查询0结果是数组 PASS
✅ 并发访问查询1结果不为null PASS (object is not null)
✅ 并发访问查询1结果是数组 PASS
✅ 并发访问查询2结果不为null PASS (object is not null)
✅ 并发访问查询2结果是数组 PASS
✅ 并发访问查询3结果不为null PASS (object is not null)
✅ 并发访问查询3结果是数组 PASS
✅ 并发访问查询4结果不为null PASS (object is not null)
✅ 并发访问查询4结果是数组 PASS
✅ 并发访问查询5结果不为null PASS (object is not null)
✅ 并发访问查询5结果是数组 PASS
✅ 并发访问查询6结果不为null PASS (object is not null)
✅ 并发访问查询6结果是数组 PASS
✅ 并发访问查询7结果不为null PASS (object is not null)
✅ 并发访问查询7结果是数组 PASS
✅ 并发访问查询8结果不为null PASS (object is not null)
✅ 并发访问查询8结果是数组 PASS
✅ 并发访问查询9结果不为null PASS (object is not null)
✅ 并发访问查询9结果是数组 PASS
✅ 并发访问查询10结果不为null PASS (object is not null)
✅ 并发访问查询10结果是数组 PASS
✅ 并发访问查询11结果不为null PASS (object is not null)
✅ 并发访问查询11结果是数组 PASS
✅ 并发访问查询12结果不为null PASS (object is not null)
✅ 并发访问查询12结果是数组 PASS
✅ 并发访问查询13结果不为null PASS (object is not null)
✅ 并发访问查询13结果是数组 PASS
✅ 并发访问查询14结果不为null PASS (object is not null)
✅ 并发访问查询14结果是数组 PASS
✅ 并发访问查询15结果不为null PASS (object is not null)
✅ 并发访问查询15结果是数组 PASS
✅ 并发访问查询16结果不为null PASS (object is not null)
✅ 并发访问查询16结果是数组 PASS
✅ 并发访问查询17结果不为null PASS (object is not null)
✅ 并发访问查询17结果是数组 PASS
✅ 并发访问查询18结果不为null PASS (object is not null)
✅ 并发访问查询18结果是数组 PASS
✅ 并发访问查询19结果不为null PASS (object is not null)
✅ 并发访问查询19结果是数组 PASS
✅ 并发访问查询20结果不为null PASS (object is not null)
✅ 并发访问查询20结果是数组 PASS
✅ 并发访问查询21结果不为null PASS (object is not null)
✅ 并发访问查询21结果是数组 PASS
✅ 并发访问查询22结果不为null PASS (object is not null)
✅ 并发访问查询22结果是数组 PASS
✅ 并发访问查询23结果不为null PASS (object is not null)
✅ 并发访问查询23结果是数组 PASS
✅ 并发访问查询24结果不为null PASS (object is not null)
✅ 并发访问查询24结果是数组 PASS
✅ 并发访问查询25结果不为null PASS (object is not null)
✅ 并发访问查询25结果是数组 PASS
✅ 并发访问查询26结果不为null PASS (object is not null)
✅ 并发访问查询26结果是数组 PASS
✅ 并发访问查询27结果不为null PASS (object is not null)
✅ 并发访问查询27结果是数组 PASS
✅ 并发访问查询28结果不为null PASS (object is not null)
✅ 并发访问查询28结果是数组 PASS
✅ 并发访问查询29结果不为null PASS (object is not null)
✅ 并发访问查询29结果是数组 PASS
✅ 并发访问查询30结果不为null PASS (object is not null)
✅ 并发访问查询30结果是数组 PASS
✅ 并发访问查询31结果不为null PASS (object is not null)
✅ 并发访问查询31结果是数组 PASS
✅ 并发访问查询32结果不为null PASS (object is not null)
✅ 并发访问查询32结果是数组 PASS
✅ 并发访问查询33结果不为null PASS (object is not null)
✅ 并发访问查询33结果是数组 PASS
✅ 并发访问查询34结果不为null PASS (object is not null)
✅ 并发访问查询34结果是数组 PASS
✅ 并发访问查询35结果不为null PASS (object is not null)
✅ 并发访问查询35结果是数组 PASS
✅ 并发访问查询36结果不为null PASS (object is not null)
✅ 并发访问查询36结果是数组 PASS
✅ 并发访问查询37结果不为null PASS (object is not null)
✅ 并发访问查询37结果是数组 PASS
✅ 并发访问查询38结果不为null PASS (object is not null)
✅ 并发访问查询38结果是数组 PASS
✅ 并发访问查询39结果不为null PASS (object is not null)
✅ 并发访问查询39结果是数组 PASS
✅ 并发访问查询40结果不为null PASS (object is not null)
✅ 并发访问查询40结果是数组 PASS
✅ 并发访问查询41结果不为null PASS (object is not null)
✅ 并发访问查询41结果是数组 PASS
✅ 并发访问查询42结果不为null PASS (object is not null)
✅ 并发访问查询42结果是数组 PASS
✅ 并发访问查询43结果不为null PASS (object is not null)
✅ 并发访问查询43结果是数组 PASS
✅ 并发访问查询44结果不为null PASS (object is not null)
✅ 并发访问查询44结果是数组 PASS
✅ 并发访问查询45结果不为null PASS (object is not null)
✅ 并发访问查询45结果是数组 PASS
✅ 并发访问查询46结果不为null PASS (object is not null)
✅ 并发访问查询46结果是数组 PASS
✅ 并发访问查询47结果不为null PASS (object is not null)
✅ 并发访问查询47结果是数组 PASS
✅ 并发访问查询48结果不为null PASS (object is not null)
✅ 并发访问查询48结果是数组 PASS
✅ 并发访问查询49结果不为null PASS (object is not null)
✅ 并发访问查询49结果是数组 PASS
✅ 并发访问查询50结果不为null PASS (object is not null)
✅ 并发访问查询50结果是数组 PASS
✅ 并发访问查询51结果不为null PASS (object is not null)
✅ 并发访问查询51结果是数组 PASS
✅ 并发访问查询52结果不为null PASS (object is not null)
✅ 并发访问查询52结果是数组 PASS
✅ 并发访问查询53结果不为null PASS (object is not null)
✅ 并发访问查询53结果是数组 PASS
✅ 并发访问查询54结果不为null PASS (object is not null)
✅ 并发访问查询54结果是数组 PASS
✅ 并发访问查询55结果不为null PASS (object is not null)
✅ 并发访问查询55结果是数组 PASS
✅ 并发访问查询56结果不为null PASS (object is not null)
✅ 并发访问查询56结果是数组 PASS
✅ 并发访问查询57结果不为null PASS (object is not null)
✅ 并发访问查询57结果是数组 PASS
✅ 并发访问查询58结果不为null PASS (object is not null)
✅ 并发访问查询58结果是数组 PASS
✅ 并发访问查询59结果不为null PASS (object is not null)
✅ 并发访问查询59结果是数组 PASS
✅ 并发访问查询60结果不为null PASS (object is not null)
✅ 并发访问查询60结果是数组 PASS
✅ 并发访问查询61结果不为null PASS (object is not null)
✅ 并发访问查询61结果是数组 PASS
✅ 并发访问查询62结果不为null PASS (object is not null)
✅ 并发访问查询62结果是数组 PASS
✅ 并发访问查询63结果不为null PASS (object is not null)
✅ 并发访问查询63结果是数组 PASS
✅ 并发访问查询64结果不为null PASS (object is not null)
✅ 并发访问查询64结果是数组 PASS
✅ 并发访问查询65结果不为null PASS (object is not null)
✅ 并发访问查询65结果是数组 PASS
✅ 并发访问查询66结果不为null PASS (object is not null)
✅ 并发访问查询66结果是数组 PASS
✅ 并发访问查询67结果不为null PASS (object is not null)
✅ 并发访问查询67结果是数组 PASS
✅ 并发访问查询68结果不为null PASS (object is not null)
✅ 并发访问查询68结果是数组 PASS
✅ 并发访问查询69结果不为null PASS (object is not null)
✅ 并发访问查询69结果是数组 PASS
✅ 并发访问查询70结果不为null PASS (object is not null)
✅ 并发访问查询70结果是数组 PASS
✅ 并发访问查询71结果不为null PASS (object is not null)
✅ 并发访问查询71结果是数组 PASS
✅ 并发访问查询72结果不为null PASS (object is not null)
✅ 并发访问查询72结果是数组 PASS
✅ 并发访问查询73结果不为null PASS (object is not null)
✅ 并发访问查询73结果是数组 PASS
✅ 并发访问查询74结果不为null PASS (object is not null)
✅ 并发访问查询74结果是数组 PASS
✅ 并发访问查询75结果不为null PASS (object is not null)
✅ 并发访问查询75结果是数组 PASS
✅ 并发访问查询76结果不为null PASS (object is not null)
✅ 并发访问查询76结果是数组 PASS
✅ 并发访问查询77结果不为null PASS (object is not null)
✅ 并发访问查询77结果是数组 PASS
✅ 并发访问查询78结果不为null PASS (object is not null)
✅ 并发访问查询78结果是数组 PASS
✅ 并发访问查询79结果不为null PASS (object is not null)
✅ 并发访问查询79结果是数组 PASS
✅ 并发访问查询80结果不为null PASS (object is not null)
✅ 并发访问查询80结果是数组 PASS
✅ 并发访问查询81结果不为null PASS (object is not null)
✅ 并发访问查询81结果是数组 PASS
✅ 并发访问查询82结果不为null PASS (object is not null)
✅ 并发访问查询82结果是数组 PASS
✅ 并发访问查询83结果不为null PASS (object is not null)
✅ 并发访问查询83结果是数组 PASS
✅ 并发访问查询84结果不为null PASS (object is not null)
✅ 并发访问查询84结果是数组 PASS
✅ 并发访问查询85结果不为null PASS (object is not null)
✅ 并发访问查询85结果是数组 PASS
✅ 并发访问查询86结果不为null PASS (object is not null)
✅ 并发访问查询86结果是数组 PASS
✅ 并发访问查询87结果不为null PASS (object is not null)
✅ 并发访问查询87结果是数组 PASS
✅ 并发访问查询88结果不为null PASS (object is not null)
✅ 并发访问查询88结果是数组 PASS
✅ 并发访问查询89结果不为null PASS (object is not null)
✅ 并发访问查询89结果是数组 PASS
✅ 并发访问查询90结果不为null PASS (object is not null)
✅ 并发访问查询90结果是数组 PASS
✅ 并发访问查询91结果不为null PASS (object is not null)
✅ 并发访问查询91结果是数组 PASS
✅ 并发访问查询92结果不为null PASS (object is not null)
✅ 并发访问查询92结果是数组 PASS
✅ 并发访问查询93结果不为null PASS (object is not null)
✅ 并发访问查询93结果是数组 PASS
✅ 并发访问查询94结果不为null PASS (object is not null)
✅ 并发访问查询94结果是数组 PASS
✅ 并发访问查询95结果不为null PASS (object is not null)
✅ 并发访问查询95结果是数组 PASS
✅ 并发访问查询96结果不为null PASS (object is not null)
✅ 并发访问查询96结果是数组 PASS
✅ 并发访问查询97结果不为null PASS (object is not null)
✅ 并发访问查询97结果是数组 PASS
✅ 并发访问查询98结果不为null PASS (object is not null)
✅ 并发访问查询98结果是数组 PASS
✅ 并发访问查询99结果不为null PASS (object is not null)
✅ 并发访问查询99结果是数组 PASS
🔄 并发访问测试: 100次查询耗时 3ms
✅ 并发访问完成 PASS

💪 执行压力测试...
🔥 高容量查询测试: 2000次随机查询耗时 104ms
✅ 高容量查询性能合理 PASS
🧠 内存使用测试: 5000次查询(分100批)耗时 116ms
✅ 内存使用测试通过 PASS
🔥 极值参数测试: 50/50 成功 (100%)
✅ 极值参数测试成功率合理 PASS
⏱️ 长时间运行测试: 5000次混合操作耗时 146ms
✅ 长时间运行测试通过 PASS

🌍 执行实际场景测试...
🎮 游戏对象碰撞检测场景测试
🎯 碰撞检测结果: 50个位置检测，39个位置发生碰撞，耗时1ms
✅ 碰撞检测性能合理 PASS
✅ 碰撞检测有结果 PASS
📍 空间索引查询场景测试
✅ 空间索引查询结果0_0正确 PASS
✅ 空间索引查询结果0_1正确 PASS
✅ 空间索引查询结果1_0正确 PASS
✅ 空间索引查询结果1_1正确 PASS
✅ 空间索引查询结果1_2正确 PASS
✅ 空间索引查询结果1_3正确 PASS
✅ 空间索引查询结果1_4正确 PASS
✅ 空间索引查询结果2_0正确 PASS
✅ 空间索引查询结果2_1正确 PASS
✅ 空间索引查询结果2_2正确 PASS
✅ 空间索引查询结果2_3正确 PASS
✅ 空间索引查询结果3_0正确 PASS
✅ 空间索引查询结果4_0正确 PASS
🗺️ 空间索引结果: 5个查询点，总计找到13个对象，耗时0ms
✅ 空间索引查询性能合理 PASS
🖱️ 交互式查询场景测试
👆 交互查询结果: 30次交互，5次点击命中，5次悬停命中，耗时2ms
✅ 交互查询性能优秀 PASS
✅ 交互查询有效 PASS
🔄 动态内容场景测试
✅ 动态查询0结果一致性 PASS (expected=4, actual=4)
✅ 动态查询1结果一致性 PASS (expected=4, actual=4)
✅ 动态查询2结果一致性 PASS (expected=4, actual=4)
✅ 动态查询3结果一致性 PASS (expected=3, actual=3)
✅ 动态查询4结果一致性 PASS (expected=4, actual=4)
✅ 动态查询5结果一致性 PASS (expected=4, actual=4)
✅ 动态查询6结果一致性 PASS (expected=3, actual=3)
✅ 动态查询7结果一致性 PASS (expected=4, actual=4)
✅ 动态查询8结果一致性 PASS (expected=4, actual=4)
✅ 动态查询9结果一致性 PASS (expected=3, actual=3)
✅ 动态查询10结果一致性 PASS (expected=4, actual=4)
✅ 动态查询11结果一致性 PASS (expected=3, actual=3)
✅ 动态查询12结果一致性 PASS (expected=3, actual=3)
✅ 动态查询13结果一致性 PASS (expected=4, actual=4)
✅ 动态查询14结果一致性 PASS (expected=3, actual=3)
✅ 动态查询15结果一致性 PASS (expected=3, actual=3)
✅ 动态查询16结果一致性 PASS (expected=4, actual=4)
✅ 动态查询17结果一致性 PASS (expected=3, actual=3)
✅ 动态查询18结果一致性 PASS (expected=3, actual=3)
✅ 动态查询19结果一致性 PASS (expected=3, actual=3)
🔧 动态内容结果: 20次状态查询，平均每次找到3.5个对象，耗时1ms
✅ 动态内容查询性能良好 PASS
✅ 动态内容查询有效 PASS

================================================================================
📊 BVH 测试结果汇总
================================================================================
总测试数: 492
通过: 492 ✅
失败: 0 ❌
成功率: 100%
总耗时: 613ms

⚡ 性能基准报告:
  BVH AABB Query: 0.022ms/次 (1000次测试)
  BVH Circle Query: 0.028ms/次 (1000次测试)
  Complex BVH Query: 0.024ms/次 (500次测试)
  Bulk Queries: 0.034ms/次 (5000次测试)

🎯 测试覆盖范围:
  📋 基础功能: 构造函数, root属性, 基本查询
  🔍 查询接口: AABB查询, 圆形查询, 参数验证, 结果一致性
  🔗 集成测试: BVHNode集成, 复杂树遍历, 查询委托
  🔍 边界条件: 空BVH, 极值查询, 边界情况, 错误恢复
  ⚡ 性能基准: 查询速度, 复杂树查询, 批量查询
  💾 数据完整性: 查询结果, 对象引用, BVH状态, 并发访问
  💪 压力测试: 高容量查询, 内存使用, 极值参数, 长时间运行
  🌍 实际场景: 碰撞检测, 空间索引, 交互查询, 动态内容

🎉 所有测试通过！BVH 组件质量优秀！
🚀 BVH已准备好在生产环境中使用！
================================================================================
