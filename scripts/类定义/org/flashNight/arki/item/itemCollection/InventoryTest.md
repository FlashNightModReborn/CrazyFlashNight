var a = new org.flashNight.arki.item.itemCollection.InventoryTest();
a.runTests();

> 说明：本文件中的输出日志用于记录一次运行结果。此前 `testRequirement` 的 2 个失败样例，根因是测试环境未初始化 `ItemUtil.equipmentDict/materialDict/informationMaxValueDict`（导致装备/材料/情报全部被当作普通可堆叠物品塞进背包，背包很快满，后续 acquire/submit 失败）。  
> `scripts/类定义/org/flashNight/arki/item/itemCollection/InventoryTest.as` 已补齐上述字典初始化，并补齐 `_root.物品栏.药剂栏`，重新运行测试应不再出现这 2 个失败。


开始 Inventory 测试...
初始化测试数据...

===> 测试 testBasic (add/remove) ...
After add: items: {"0": {"name": "普通hp药剂", "value": 5}, "1": {"name": "牛肉罐头", "value": 2}, "2": {"name": "普通mp药剂", "value": 5}, "3": {"name": "匕首", "value": {"level": 1}}, "4": {"name": "AK47", "value": {"level": 7}}}
After add: indexes: [0, 1, 2, 3, 4]
PASS: 添加物品后，首个空格应为 -1

测试 remove 方法...
After remove: items: {"0": {"name": "普通hp药剂", "value": 5}, "2": {"name": "普通mp药剂", "value": 5}, "3": {"name": "匕首", "value": {"level": 1}}}
After remove: indexes: [0, 2, 3]
PASS: 移除物品后，首个空格应为 1

===> 测试 testIndexTreeRepair ...
PASS: 索引树缺项时应自动修复，首个空格应为 4

===> 测试 testRequirement (acquire/submit) ...
PASS: 添加 3 个物品，1 个材料和 1 个情报
PASS: 添加 3 个物品，其中 2 个物品可叠加
PASS: 添加 3 个物品，其中 1 个物品可叠加，应由于空间不足而添加失败
背包状态 after acquire: items: {"0": {"lastUpdate": 1765714322406, "name": "匕首", "value": {"level": 1, "mods": []}}, "1": {"lastUpdate": 1765714322406, "name": "普通hp药剂", "value": 10}, "2": {"lastUpdate": 1765714322406, "name": "牛肉罐头", "value": 4}, "3": {"lastUpdate": 1765714322406, "name": "普通mp药剂", "value": 5}}, indexes: [0, 1, 2, 3]
PASS: 提交 3 个物品和 1 个材料
PASS: 提交 2 个物品，应由于物品不足而提交失败
背包状态 after submit: items: {"0": {"lastUpdate": 1765714322406, "name": "匕首", "value": {"level": 1, "mods": []}}, "1": {"lastUpdate": 1765714322406, "name": "普通hp药剂", "value": 5}, "2": {"lastUpdate": 1765714322406, "name": "牛肉罐头", "value": 4}}, indexes: [0, 1, 2]

===> 测试 testEdgeCases (边界与异常) ...
PASS: 不能添加 null 物品
PASS: 物品没有 name 字段应被拒绝添加
PASS: 物品 value 为 null，应该被拒绝添加
PASS: 已占满，首个空格应为 -1
PASS: 超出容量的添加应失败
PASS: 移除 index 越界物品应失败
PASS: 移除 index 负数物品应失败
PASS: 负数 value 应判为不合法，添加失败
PASS: NaN value 应判为不合法，添加失败

===> 测试 testSearchAndValueMethods (searchFirstKey, searchKeys, addValue) ...
PASS: searchFirstKey 返回应为第一个 AK47 的格子 (key=0)
PASS: searchFirstKey 对不存在的物品应返回 undefined
PASS: searchKeys('AK47') 返回应为 [0, 1] 共 2 个格子
PASS: searchKeys 对没有物品返回空数组
PASS: addValue(3) 后物品数量应变为 5
PASS: 当物品 value <= 0 时应自动 remove

===> 测试 testMoveMergeSwap (move/merge/swap) ...
PASS: move 成功，匕首不受影响
PASS: 目标格子应成功接收 普通hp药剂
PASS: 源格子应被清空
PASS: move 到已占用格子应失败
PASS: merge 同名可叠加物品成功
PASS: merge 后物品数量应累加为 10
PASS: merge 后源格子应被清空
PASS: merge 不同物品应失败
PASS: swap 应该成功
PASS: swap 后 invA[0] 应变成牛肉罐头
PASS: swap 后 invB[1] 应变成匕首
PASS: swap 空格子或不存在物品应失败

===> 测试 testRebuildOrder ...
PASS: 空物品栏重建后应保持为空
PASS: 无排序重建应保持原序并压缩空格
PASS: 索引应重新映射为连续
PASS: 应按名称倒序排列
PASS: 重建后物品数量不应超过容量
PASS: 数值类型应排在前面
PASS: 满容量应按value降序排列
测试完成。通过: 42 个，失败: 0 个。
