import org.flashNight.gesh.depth.*;

// 创建测试实例并运行测试
var depthManagerTest:DepthManagerTest = new DepthManagerTest();
depthManagerTest.runTests();


[DepthManagerTest] 
==================================================
[DepthManagerTest]  DepthManager 测试套件
[DepthManagerTest] ==================================================
[DepthManagerTest] 正在设置测试环境...
[DepthManager] DM0 已创建，关联容器: testContainer_94
[DepthManagerTest] 测试环境设置完成，创建了 50 个测试影片剪辑
[DepthManagerTest] 
==================================================
[DepthManagerTest]  功能测试
[DepthManagerTest] ==================================================
[DepthManagerTest] 
----- 基本操作测试 -----
[DepthManager] DM0 已清空所有数据
[DepthManager] DM0 添加新节点: testClip_0 深度: 200
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_1 深度: 300
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManagerTest] √ 测试通过: 添加新节点
[DepthManager] DM0 已清空所有数据
[DepthManager] DM0 添加新节点: testClip_0 深度: 200
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 更新节点: testClip_0 深度从 200 变为 300
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManagerTest] √ 测试通过: 更新已存在节点的深度
[DepthManager] DM0 已清空所有数据
[DepthManager] DM0 添加新节点: testClip_0 深度: 200
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_1 深度: 200
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_2 深度: 200
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManagerTest] √ 测试通过: 相同深度值的处理
[DepthManager] DM0 已清空所有数据
[DepthManager] DM0 添加新节点: testClip_0 深度: 200
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_1 深度: 300
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 已移除节点: testClip_0
[DepthManagerTest] √ 测试通过: 移除节点
[DepthManagerTest] 
----- 边界条件测试 -----
[DepthManager] DM0 已清空所有数据
[DepthManager] DM0 添加新节点: testClip_0 深度: 1000
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_1 深度: 1001
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_2 深度: 1002
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_3 深度: 1003
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_4 深度: 1004
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_5 深度: 1005
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_6 深度: 1006
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_7 深度: 1007
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_8 深度: 1008
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_9 深度: 1009
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_10 深度: 1010
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_11 深度: 1011
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_12 深度: 1012
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_13 深度: 1013
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_14 深度: 1014
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_15 深度: 1015
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_16 深度: 1016
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_17 深度: 1017
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_18 深度: 1018
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_19 深度: 1019
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_20 深度: 1020
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_21 深度: 1021
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_22 深度: 1022
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_23 深度: 1023
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_24 深度: 1024
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_25 深度: 1025
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_26 深度: 1026
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_27 深度: 1027
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_28 深度: 1028
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_29 深度: 1029
[DepthManager] DM0 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM0 添加新节点: testClip_30 深度: 1030
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_31 深度: 1031
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_32 深度: 1032
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_33 深度: 1033
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_34 深度: 1034
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_35 深度: 1035
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_36 深度: 1036
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_37 深度: 1037
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_38 深度: 1038
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_39 深度: 1039
[DepthManager] DM0 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM0 添加新节点: testClip_40 深度: 1040
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_41 深度: 1041
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_42 深度: 1042
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_43 深度: 1043
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_44 深度: 1044
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_45 深度: 1045
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_46 深度: 1046
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_47 深度: 1047
[DepthManager] DM0 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM0 添加新节点: testClip_48 深度: 1048
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_49 深度: 1049
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManagerTest] √ 测试通过: 大量节点情况
[DepthManager] DM0 已清空所有数据
[DepthManager] DM0 添加新节点: testClip_0 深度: -16384
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_1 深度: 0
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_2 深度: 16383
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManagerTest] √ 测试通过: 极端深度值
[DepthManager] DM0 已清空所有数据
[DepthManager] DM0 添加新节点: testClip_0 深度: 100
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 更新节点: testClip_0 深度从 100 变为 101
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 更新节点: testClip_0 深度从 101 变为 102
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 更新节点: testClip_0 深度从 102 变为 103
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 更新节点: testClip_0 深度从 103 变为 104
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 更新节点: testClip_0 深度从 104 变为 105
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 更新节点: testClip_0 深度从 105 变为 106
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 更新节点: testClip_0 深度从 106 变为 107
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 更新节点: testClip_0 深度从 107 变为 108
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 更新节点: testClip_0 深度从 108 变为 109
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 更新节点: testClip_0 深度从 109 变为 110
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 更新节点: testClip_0 深度从 110 变为 111
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 更新节点: testClip_0 深度从 111 变为 112
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 更新节点: testClip_0 深度从 112 变为 113
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 更新节点: testClip_0 深度从 113 变为 114
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 更新节点: testClip_0 深度从 114 变为 115
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 更新节点: testClip_0 深度从 115 变为 116
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 更新节点: testClip_0 深度从 116 变为 117
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 更新节点: testClip_0 深度从 117 变为 118
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 更新节点: testClip_0 深度从 118 变为 119
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 更新节点: testClip_0 深度从 119 变为 120
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 更新节点: testClip_0 深度从 120 变为 121
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 更新节点: testClip_0 深度从 121 变为 122
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 更新节点: testClip_0 深度从 122 变为 123
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 更新节点: testClip_0 深度从 123 变为 124
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 更新节点: testClip_0 深度从 124 变为 125
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 更新节点: testClip_0 深度从 125 变为 126
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 更新节点: testClip_0 深度从 126 变为 127
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 更新节点: testClip_0 深度从 127 变为 128
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 更新节点: testClip_0 深度从 128 变为 129
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManagerTest] √ 测试通过: 快速连续更新同一节点
[DepthManagerTest] 
----- 错误处理测试 -----
[DepthManager] DM0 已清空所有数据
[DepthManager] DM0 更新深度失败: 无效参数
[DepthManagerTest] √ 测试通过: 空参数处理
[DepthManager] DM0 已清空所有数据
[DepthManager] DM0 添加新节点: testClip_0 深度: NaN
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManagerTest] √ 测试通过: 无效深度值处理
[DepthManager] DM0 已清空所有数据
[DepthManagerTest] √ 测试通过: 处理不存在的影片剪辑
[DepthManagerTest] 
----- 内存管理测试 -----
[DepthManager] DM0 已清空所有数据
[DepthManager] DM0 添加新节点: testClip_0 深度: 1000
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_1 深度: 1001
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_2 深度: 1002
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_3 深度: 1003
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_4 深度: 1004
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_5 深度: 1005
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_6 深度: 1006
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_7 深度: 1007
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_8 深度: 1008
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_9 深度: 1009
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_10 深度: 1010
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_11 深度: 1011
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_12 深度: 1012
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_13 深度: 1013
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_14 深度: 1014
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_15 深度: 1015
[DepthManager] DM0 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM0 添加新节点: testClip_16 深度: 1016
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_17 深度: 1017
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_18 深度: 1018
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_19 深度: 1019
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_20 深度: 1020
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_21 深度: 1021
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_22 深度: 1022
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_23 深度: 1023
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_24 深度: 1024
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_25 深度: 1025
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_26 深度: 1026
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_27 深度: 1027
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_28 深度: 1028
[DepthManager] DM0 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM0 添加新节点: testClip_29 深度: 1029
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_30 深度: 1030
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_31 深度: 1031
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_32 深度: 1032
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_33 深度: 1033
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_34 深度: 1034
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_35 深度: 1035
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_36 深度: 1036
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_37 深度: 1037
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_38 深度: 1038
[DepthManager] DM0 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM0 添加新节点: testClip_39 深度: 1039
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_40 深度: 1040
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_41 深度: 1041
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_42 深度: 1042
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_43 深度: 1043
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_44 深度: 1044
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_45 深度: 1045
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_46 深度: 1046
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_47 深度: 1047
[DepthManager] DM0 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM0 添加新节点: testClip_48 深度: 1048
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_49 深度: 1049
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 已移除节点: testClip_0
[DepthManager] DM0 已移除节点: testClip_1
[DepthManager] DM0 已移除节点: testClip_2
[DepthManager] DM0 已移除节点: testClip_3
[DepthManager] DM0 已移除节点: testClip_4
[DepthManager] DM0 已移除节点: testClip_5
[DepthManager] DM0 已移除节点: testClip_6
[DepthManager] DM0 已移除节点: testClip_7
[DepthManager] DM0 已移除节点: testClip_8
[DepthManager] DM0 已移除节点: testClip_9
[DepthManager] DM0 已移除节点: testClip_10
[DepthManager] DM0 已移除节点: testClip_11
[DepthManager] DM0 已移除节点: testClip_12
[DepthManager] DM0 已移除节点: testClip_13
[DepthManager] DM0 已移除节点: testClip_14
[DepthManager] DM0 已移除节点: testClip_15
[DepthManager] DM0 已移除节点: testClip_16
[DepthManager] DM0 已移除节点: testClip_17
[DepthManager] DM0 已移除节点: testClip_18
[DepthManager] DM0 已移除节点: testClip_19
[DepthManager] DM0 已移除节点: testClip_20
[DepthManager] DM0 已移除节点: testClip_21
[DepthManager] DM0 已移除节点: testClip_22
[DepthManager] DM0 已移除节点: testClip_23
[DepthManager] DM0 已移除节点: testClip_24
[DepthManager] DM0 添加新节点: testClip_0 深度: 2000
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_1 深度: 2001
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_2 深度: 2002
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_3 深度: 2003
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_4 深度: 2004
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_5 深度: 2005
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_6 深度: 2006
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_7 深度: 2007
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_8 深度: 2008
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_9 深度: 2009
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_10 深度: 2010
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_11 深度: 2011
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_12 深度: 2012
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_13 深度: 2013
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_14 深度: 2014
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_15 深度: 2015
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_16 深度: 2016
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_17 深度: 2017
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_18 深度: 2018
[DepthManager] DM0 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM0 添加新节点: testClip_19 深度: 2019
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_20 深度: 2020
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_21 深度: 2021
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_22 深度: 2022
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_23 深度: 2023
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_24 深度: 2024
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManagerTest] √ 测试通过: 大量添加和删除
[DepthManager] DM0 已清空所有数据
[DepthManager] DM0 添加新节点: testClip_0 深度: 1000
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_1 深度: 1001
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_2 深度: 1002
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_3 深度: 1003
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_4 深度: 1004
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_5 深度: 1005
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_6 深度: 1006
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_7 深度: 1007
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_8 深度: 1008
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_9 深度: 1009
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_10 深度: 1010
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_11 深度: 1011
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_12 深度: 1012
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_13 深度: 1013
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_14 深度: 1014
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_15 深度: 1015
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_16 深度: 1016
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_17 深度: 1017
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_18 深度: 1018
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_19 深度: 1019
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_20 深度: 1020
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_21 深度: 1021
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_22 深度: 1022
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_23 深度: 1023
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_24 深度: 1024
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_25 深度: 1025
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_26 深度: 1026
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_27 深度: 1027
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_28 深度: 1028
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_29 深度: 1029
[DepthManager] DM0 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM0 添加新节点: testClip_30 深度: 1030
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_31 深度: 1031
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_32 深度: 1032
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_33 深度: 1033
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_34 深度: 1034
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_35 深度: 1035
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_36 深度: 1036
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_37 深度: 1037
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_38 深度: 1038
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_39 深度: 1039
[DepthManager] DM0 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM0 添加新节点: testClip_40 深度: 1040
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_41 深度: 1041
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_42 深度: 1042
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_43 深度: 1043
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_44 深度: 1044
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_45 深度: 1045
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_46 深度: 1046
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_47 深度: 1047
[DepthManager] DM0 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM0 添加新节点: testClip_48 深度: 1048
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_49 深度: 1049
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 已清空所有数据
[DepthManagerTest] √ 测试通过: 清空操作
[DepthManager] DM0 已清空所有数据
[DepthManager] DM0 添加新节点: testClip_0 深度: 1000
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_1 深度: 1001
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_2 深度: 1002
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_3 深度: 1003
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_4 深度: 1004
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_5 深度: 1005
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_6 深度: 1006
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_7 深度: 1007
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_8 深度: 1008
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_9 深度: 1009
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_10 深度: 1010
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_11 深度: 1011
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_12 深度: 1012
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_13 深度: 1013
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_14 深度: 1014
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_15 深度: 1015
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_16 深度: 1016
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_17 深度: 1017
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_18 深度: 1018
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_19 深度: 1019
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_20 深度: 1020
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_21 深度: 1021
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_22 深度: 1022
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_23 深度: 1023
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_24 深度: 1024
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_25 深度: 1025
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_26 深度: 1026
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_27 深度: 1027
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_28 深度: 1028
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_29 深度: 1029
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_30 深度: 1030
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_31 深度: 1031
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_32 深度: 1032
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_33 深度: 1033
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_34 深度: 1034
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_35 深度: 1035
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_36 深度: 1036
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_37 深度: 1037
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_38 深度: 1038
[DepthManager] DM0 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM0 添加新节点: testClip_39 深度: 1039
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_40 深度: 1040
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_41 深度: 1041
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_42 深度: 1042
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_43 深度: 1043
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_44 深度: 1044
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_45 深度: 1045
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_46 深度: 1046
[DepthManager] DM0 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM0 添加新节点: testClip_47 深度: 1047
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_48 深度: 1048
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_49 深度: 1049
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 开始销毁...
[DepthManager] DM0 已清空所有数据
[DepthManager] DM0 已销毁
[DepthManager] DM1 已创建，关联容器: testContainer_94
[DepthManagerTest] √ 测试通过: 资源释放
[DepthManagerTest] 
==================================================
[DepthManagerTest]  性能测试
[DepthManagerTest] ==================================================
[DepthManagerTest] 正在预热测试环境...
[DepthManager] DM2 已创建，关联容器: warmupContainer
[DepthManager] DM2 添加新节点: warmupClip_0 深度: 200
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 添加新节点: warmupClip_1 深度: 201
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 添加新节点: warmupClip_2 深度: 202
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 添加新节点: warmupClip_3 深度: 203
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 添加新节点: warmupClip_4 深度: 204
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 添加新节点: warmupClip_5 深度: 205
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 添加新节点: warmupClip_6 深度: 206
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 添加新节点: warmupClip_7 深度: 207
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 添加新节点: warmupClip_8 深度: 208
[DepthManager] DM2 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM2 添加新节点: warmupClip_9 深度: 209
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 添加新节点: warmupClip_10 深度: 210
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 添加新节点: warmupClip_11 深度: 211
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 添加新节点: warmupClip_12 深度: 212
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 添加新节点: warmupClip_13 深度: 213
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 添加新节点: warmupClip_14 深度: 214
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 添加新节点: warmupClip_15 深度: 215
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 添加新节点: warmupClip_16 深度: 216
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 添加新节点: warmupClip_17 深度: 217
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 添加新节点: warmupClip_18 深度: 218
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 添加新节点: warmupClip_19 深度: 219
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_0
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_1
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_2
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_3
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_4
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_5
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_6
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_7
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_8
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_9
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_10
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_11
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_12
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_13
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_14
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_15
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_16
[DepthManager] DM2 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM2 更新节点时间戳: warmupClip_17
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_18
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_19
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_0
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_1
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_2
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_3
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_4
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_5
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_6
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_7
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_8
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_9
[DepthManager] DM2 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM2 更新节点时间戳: warmupClip_10
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_11
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_12
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_13
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_14
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_15
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_16
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_17
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_18
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_19
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_0
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_1
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_2
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_3
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_4
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_5
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_6
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_7
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_8
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_9
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_10
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_11
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_12
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_13
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_14
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_15
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_16
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_17
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_18
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_19
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_0
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_1
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_2
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_3
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_4
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_5
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_6
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_7
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_8
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_9
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_10
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_11
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_12
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_13
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_14
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_15
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_16
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_17
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_18
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 更新节点时间戳: warmupClip_19
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM2 开始销毁...
[DepthManager] DM2 已清空所有数据
[DepthManager] DM2 已销毁
[DepthManagerTest] 预热完成
[DepthManagerTest] 测试原生 swapDepths 性能...
[DepthManagerTest] 原生 swapDepths 平均耗时: 0.1 毫秒
[DepthManagerTest] 测试 DepthManager 性能...
[DepthManager] DM1 已清空所有数据
[DepthManager] DM1 添加新节点: testClip_0 深度: 1363
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_1 深度: 1356
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_2 深度: 1448
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_3 深度: 1052
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_4 深度: 1162
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_5 深度: 1169
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_6 深度: 1007
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_7 深度: 1150
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_8 深度: 1654
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_9 深度: 1239
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_10 深度: 1374
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_11 深度: 1960
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_12 深度: 1444
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_13 深度: 1433
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_14 深度: 1111
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_15 深度: 1071
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_16 深度: 1590
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_17 深度: 1082
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_18 深度: 1938
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_19 深度: 1902
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_20 深度: 1783
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_21 深度: 1118
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_22 深度: 1682
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_23 深度: 1215
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_24 深度: 1303
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_25 深度: 1077
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_26 深度: 1139
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_27 深度: 1811
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_28 深度: 1117
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_29 深度: 1974
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_30 深度: 1565
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_31 深度: 1019
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_32 深度: 1662
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_33 深度: 1708
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_34 深度: 1583
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_35 深度: 1899
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_36 深度: 1227
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_37 深度: 1405
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_38 深度: 1247
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_39 深度: 1777
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_40 深度: 1148
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_41 深度: 1519
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_42 深度: 1214
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_43 深度: 1175
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_44 深度: 1586
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_45 深度: 1042
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_46 深度: 1477
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_47 深度: 1337
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_48 深度: 1933
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_49 深度: 1204
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 已清空所有数据
[DepthManager] DM1 添加新节点: testClip_0 深度: 1227
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_1 深度: 1772
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_2 深度: 1228
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_3 深度: 1027
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_4 深度: 1352
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_5 深度: 1624
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_6 深度: 1749
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_7 深度: 1190
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_8 深度: 1344
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_9 深度: 1730
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_10 深度: 1416
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_11 深度: 1624
[DepthManager] DM1 处理了 0 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_12 深度: 1473
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_13 深度: 1874
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_14 深度: 1339
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_15 深度: 1083
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_16 深度: 1366
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_17 深度: 1164
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_18 深度: 1905
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_19 深度: 1557
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_20 深度: 1126
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_21 深度: 1454
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_22 深度: 1447
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_23 深度: 1478
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_24 深度: 1212
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_25 深度: 1301
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_26 深度: 1434
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_27 深度: 1844
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_28 深度: 1989
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_29 深度: 1829
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_30 深度: 1112
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_31 深度: 1211
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_32 深度: 1847
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_33 深度: 1814
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_34 深度: 1046
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_35 深度: 1728
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_36 深度: 1259
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_37 深度: 1784
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_38 深度: 1555
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_39 深度: 1881
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_40 深度: 1566
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_41 深度: 1481
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_42 深度: 1409
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_43 深度: 1544
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_44 深度: 1351
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_45 深度: 1232
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_46 深度: 1108
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_47 深度: 1536
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_48 深度: 1096
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_49 深度: 1448
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 已清空所有数据
[DepthManager] DM1 添加新节点: testClip_0 深度: 1813
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_1 深度: 1680
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_2 深度: 1257
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_3 深度: 1610
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_4 深度: 1934
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_5 深度: 1774
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_6 深度: 1389
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_7 深度: 1546
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_8 深度: 1569
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_9 深度: 1571
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_10 深度: 1940
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_11 深度: 1168
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_12 深度: 1709
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_13 深度: 1474
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_14 深度: 1715
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_15 深度: 1302
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_16 深度: 1047
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_17 深度: 1847
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_18 深度: 1714
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_19 深度: 1678
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_20 深度: 1540
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_21 深度: 1381
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_22 深度: 1918
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_23 深度: 1334
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_24 深度: 1241
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_25 深度: 1070
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_26 深度: 1232
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_27 深度: 1887
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_28 深度: 1633
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_29 深度: 1914
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_30 深度: 1302
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_31 深度: 1512
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_32 深度: 1434
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_33 深度: 1033
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_34 深度: 1072
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_35 深度: 1665
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_36 深度: 1643
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_37 深度: 1033
[DepthManager] DM1 处理了 0 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_38 深度: 1241
[DepthManager] DM1 处理了 0 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_39 深度: 1474
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_40 深度: 1222
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_41 深度: 1004
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_42 深度: 1131
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_43 深度: 1605
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_44 深度: 1834
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_45 深度: 1337
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_46 深度: 1675
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_47 深度: 1944
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_48 深度: 1643
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_49 深度: 1377
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 已清空所有数据
[DepthManager] DM1 添加新节点: testClip_0 深度: 1734
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_1 深度: 1275
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_2 深度: 1330
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_3 深度: 1802
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_4 深度: 1037
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_5 深度: 1738
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_6 深度: 1171
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_7 深度: 1168
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_8 深度: 1500
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_9 深度: 1830
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_10 深度: 1632
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_11 深度: 1870
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_12 深度: 1336
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_13 深度: 1242
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_14 深度: 1808
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_15 深度: 1017
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_16 深度: 1845
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_17 深度: 1170
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_18 深度: 1453
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_19 深度: 1399
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_20 深度: 1714
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_21 深度: 1757
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_22 深度: 1304
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_23 深度: 1712
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_24 深度: 1645
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_25 深度: 1250
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_26 深度: 1115
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_27 深度: 1780
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_28 深度: 1701
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_29 深度: 1095
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_30 深度: 1763
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_31 深度: 1504
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_32 深度: 1827
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_33 深度: 1545
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_34 深度: 1455
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_35 深度: 1434
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_36 深度: 1014
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_37 深度: 1379
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_38 深度: 1211
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_39 深度: 1697
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_40 深度: 1278
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_41 深度: 1886
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_42 深度: 1140
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_43 深度: 1815
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_44 深度: 1086
[DepthManager] DM1 处理了 1 个深度更新，耗时:  [... 截断的文本] 更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_32 深度: 1148
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_33 深度: 1546
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_34 深度: 1027
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_35 深度: 1063
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_36 深度: 1825
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_37 深度: 1103
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_38 深度: 1536
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_39 深度: 1333
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_40 深度: 1317
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_41 深度: 1242
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_42 深度: 1528
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_43 深度: 1372
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_44 深度: 1966
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_45 深度: 1343
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_46 深度: 1733
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_47 深度: 1785
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_48 深度: 1282
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_49 深度: 1360
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 已清空所有数据
[DepthManager] DM1 添加新节点: testClip_0 深度: 1880
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_1 深度: 1040
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_2 深度: 1072
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_3 深度: 1656
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_4 深度: 1668
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_5 深度: 1374
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_6 深度: 1018
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_7 深度: 1617
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_8 深度: 1961
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_9 深度: 1965
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_10 深度: 1722
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_11 深度: 1919
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_12 深度: 1366
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_13 深度: 1898
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_14 深度: 1855
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_15 深度: 1910
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_16 深度: 1361
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_17 深度: 1928
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_18 深度: 1393
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_19 深度: 1827
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_20 深度: 1971
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_21 深度: 1469
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_22 深度: 1567
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_23 深度: 1079
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_24 深度: 1308
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_25 深度: 1874
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_26 深度: 1318
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_27 深度: 1661
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_28 深度: 1285
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_29 深度: 1740
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_30 深度: 1614
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_31 深度: 1194
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_32 深度: 1401
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_33 深度: 1177
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_34 深度: 1544
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_35 深度: 1021
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_36 深度: 1982
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_37 深度: 1916
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_38 深度: 1380
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_39 深度: 1038
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_40 深度: 1284
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_41 深度: 1842
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_42 深度: 1791
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_43 深度: 1440
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_44 深度: 1745
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_45 深度: 1418
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_46 深度: 1363
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_47 深度: 1878
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_48 深度: 1908
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_49 深度: 1940
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 已清空所有数据
[DepthManager] DM1 添加新节点: testClip_0 深度: 1097
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_1 深度: 1667
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_2 深度: 1943
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_3 深度: 1054
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_4 深度: 1361
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_5 深度: 1461
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_6 深度: 1694
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_7 深度: 1330
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_8 深度: 1544
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_9 深度: 1586
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_10 深度: 1772
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_11 深度: 1793
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_12 深度: 1445
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_13 深度: 1208
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_14 深度: 1711
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_15 深度: 1338
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_16 深度: 1926
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_17 深度: 1762
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_18 深度: 1331
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_19 深度: 1597
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_20 深度: 1014
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_21 深度: 1875
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_22 深度: 1282
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_23 深度: 1865
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_24 深度: 1836
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_25 深度: 1988
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_26 深度: 1927
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_27 深度: 1222
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_28 深度: 1136
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_29 深度: 1649
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_30 深度: 1056
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_31 深度: 1711
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_32 深度: 1472
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_33 深度: 1115
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_34 深度: 1047
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_35 深度: 1827
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_36 深度: 1750
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_37 深度: 1802
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_38 深度: 1254
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_39 深度: 1529
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_40 深度: 1820
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_41 深度: 1357
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_42 深度: 1734
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_43 深度: 1721
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_44 深度: 1449
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_45 深度: 1123
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_46 深度: 1707
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_47 深度: 1792
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_48 深度: 1976
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_49 深度: 1922
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 已清空所有数据
[DepthManager] DM1 添加新节点: testClip_0 深度: 1440
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_1 深度: 1619
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_2 深度: 1534
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_3 深度: 1692
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_4 深度: 1111
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_5 深度: 1581
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_6 深度: 1742
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_7 深度: 1936
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_8 深度: 1944
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_9 深度: 1242
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_10 深度: 1096
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_11 深度: 1840
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_12 深度: 1608
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_13 深度: 1058
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_14 深度: 1366
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_15 深度: 1728
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_16 深度: 1634
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_17 深度: 1132
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_18 深度: 1219
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_19 深度: 1920
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_20 深度: 1893
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_21 深度: 1554
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_22 深度: 1610
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_23 深度: 1079
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_24 深度: 1177
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_25 深度: 1437
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_26 深度: 1684
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_27 深度: 1842
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_28 深度: 1424
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_29 深度: 1667
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_30 深度: 1218
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_31 深度: 1956
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_32 深度: 1196
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_33 深度: 1667
[DepthManager] DM1 处理了 0 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_34 深度: 1209
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_35 深度: 1316
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_36 深度: 1694
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_37 深度: 1392
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_38 深度: 1211
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_39 深度: 1203
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_40 深度: 1910
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_41 深度: 1971
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_42 深度: 1959
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_43 深度: 1264
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_44 深度: 1919
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_45 深度: 1432
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_46 深度: 1668
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_47 深度: 1037
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_48 深度: 1029
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_49 深度: 1682
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 已清空所有数据
[DepthManager] DM1 添加新节点: testClip_0 深度: 1722
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_1 深度: 1435
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_2 深度: 1854
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_3 深度: 1973
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_4 深度: 1155
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_5 深度: 1609
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_6 深度: 1340
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_7 深度: 1800
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_8 深度: 1324
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_9 深度: 1459
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_10 深度: 1723
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_11 深度: 1769
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_12 深度: 1180
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_13 深度: 1980
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_14 深度: 1100
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_15 深度: 1927
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_16 深度: 1167
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_17 深度: 1824
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_18 深度: 1380
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_19 深度: 1914
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_20 深度: 1320
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_21 深度: 1539
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_22 深度: 1050
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_23 深度: 1407
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_24 深度: 1117
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_25 深度: 1248
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_26 深度: 1184
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_27 深度: 1414
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_28 深度: 1276
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_29 深度: 1436
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_30 深度: 1991
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_31 深度: 1763
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_32 深度: 1370
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_33 深度: 1895
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_34 深度: 1621
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_35 深度: 1187
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_36 深度: 1827
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_37 深度: 1676
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_38 深度: 1334
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_39 深度: 1951
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_40 深度: 1329
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_41 深度: 1001
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_42 深度: 1404
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_43 深度: 1726
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_44 深度: 1007
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_45 深度: 1985
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_46 深度: 1664
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_47 深度: 1880
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_48 深度: 1985
[DepthManager] DM1 处理了 0 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_49 深度: 1367
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 已清空所有数据
[DepthManager] DM1 添加新节点: testClip_0 深度: 1449
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_1 深度: 1551
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_2 深度: 1191
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_3 深度: 1882
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_4 深度: 1741
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_5 深度: 1795
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_6 深度: 1413
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_7 深度: 1481
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_8 深度: 1587
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_9 深度: 1308
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_10 深度: 1147
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_11 深度: 1442
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_12 深度: 1094
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_13 深度: 1510
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_14 深度: 1932
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_15 深度: 1063
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_16 深度: 1749
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_17 深度: 1084
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_18 深度: 1555
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_19 深度: 1640
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_20 深度: 1282
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_21 深度: 1181
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_22 深度: 1626
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_23 深度: 1578
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_24 深度: 1430
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_25 深度: 1487
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_26 深度: 1598
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_27 深度: 1524
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_28 深度: 1365
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_29 深度: 1413
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_30 深度: 1308
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_31 深度: 1728
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_32 深度: 1521
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_33 深度: 1803
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_34 深度: 1907
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_35 深度: 1122
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_36 深度: 1031
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_37 深度: 1248
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_38 深度: 1493
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_39 深度: 1025
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_40 深度: 1212
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_41 深度: 1821
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_42 深度: 1151
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_43 深度: 1718
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_44 深度: 1450
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_45 深度: 1740
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_46 深度: 1912
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_47 深度: 1625
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_48 深度: 1231
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_49 深度: 1550
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 已清空所有数据
[DepthManager] DM1 添加新节点: testClip_0 深度: 1609
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_1 深度: 1908
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_2 深度: 1921
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_3 深度: 1638
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_4 深度: 1751
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_5 深度: 1126
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_6 深度: 1335
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_7 深度: 1791
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_8 深度: 1913
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_9 深度: 1075
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_10 深度: 1164
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_11 深度: 1299
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_12 深度: 1308
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_13 深度: 1238
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_14 深度: 1722
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_15 深度: 1216
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_16 深度: 1332
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_17 深度: 1064
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_18 深度: 1598
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_19 深度: 1157
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_20 深度: 1956
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_21 深度: 1541
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_22 深度: 1187
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_23 深度: 1559
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_24 深度: 1069
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_25 深度: 1878
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_26 深度: 1378
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_27 深度: 1760
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_28 深度: 1210
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_29 深度: 1161
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_30 深度: 1225
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_31 深度: 1194
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_32 深度: 1668
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_33 深度: 1040
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_34 深度: 1289
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_35 深度: 1679
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_36 深度: 1542
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_37 深度: 1016
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_38 深度: 1123
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_39 深度: 1495
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_40 深度: 1113
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_41 深度: 1673
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_42 深度: 1258
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_43 深度: 1646
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_44 深度: 1282
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_45 深度: 1926
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_46 深度: 1628
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_47 深度: 1584
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_48 深度: 1384
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_49 深度: 1386
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 已清空所有数据
[DepthManager] DM1 添加新节点: testClip_0 深度: 1155
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_1 深度: 1642
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_2 深度: 1256
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_3 深度: 1846
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_4 深度: 1562
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_5 深度: 1040
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_6 深度: 1043
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_7 深度: 1427
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_8 深度: 1802
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_9 深度: 1168
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_10 深度: 1356
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_11 深度: 1973
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_12 深度: 1122
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_13 深度: 1335
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_14 深度: 1410
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_15 深度: 1513
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_16 深度: 1398
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_17 深度: 1553
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_18 深度: 1922
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_19 深度: 1985
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_20 深度: 1116
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_21 深度: 1166
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_22 深度: 1559
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_23 深度: 1436
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_24 深度: 1317
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_25 深度: 1554
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_26 深度: 1122
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_27 深度: 1443
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_28 深度: 1057
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_29 深度: 1594
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_30 深度: 1770
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_31 深度: 1231
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_32 深度: 1807
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_33 深度: 1605
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_34 深度: 1787
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_35 深度: 1520
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_36 深度: 1068
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_37 深度: 1580
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_38 深度: 1597
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_39 深度: 1008
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_40 深度: 1252
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_41 深度: 1643
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_42 深度: 1251
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_43 深度: 1180
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_44 深度: 1425
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_45 深度: 1693
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_46 深度: 1877
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_47 深度: 1031
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_48 深度: 1321
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_49 深度: 1041
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 已清空所有数据
[DepthManager] DM1 添加新节点: testClip_0 深度: 1671
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_1 深度: 1389
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_2 深度: 1664
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_3 深度: 1105
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_4 深度: 1563
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_5 深度: 1254
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_6 深度: 1394
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_7 深度: 1666
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_8 深度: 1666
[DepthManager] DM1 处理了 0 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_9 深度: 1519
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_10 深度: 1748
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_11 深度: 1004
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_12 深度: 1511
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_13 深度: 1778
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_14 深度: 1206
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_15 深度: 1541
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_16 深度: 1067
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_17 深度: 1254
[DepthManager] DM1 处理了 0 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_18 深度: 1196
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_19 深度: 1306
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_20 深度: 1573
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_21 深度: 1495
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_22 深度: 1671
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_23 深度: 1325
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_24 深度: 1035
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_25 深度: 1568
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_26 深度: 1626
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_27 深度: 1708
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_28 深度: 1626
[DepthManager] DM1 处理了 0 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_29 深度: 1145
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_30 深度: 1823
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_31 深度: 1203
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_32 深度: 1032
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_33 深度: 1243
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_34 深度: 1931
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_35 深度: 1457
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_36 深度: 1333
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_37 深度: 1543
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_38 深度: 1419
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_39 深度: 1818
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_40 深度: 1980
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_41 深度: 1196
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_42 深度: 1557
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_43 深度: 1029
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_44 深度: 1163
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_45 深度: 1057
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_46 深度: 1572
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_47 深度: 1375
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_48 深度: 1765
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_49 深度: 1079
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 已清空所有数据
[DepthManager] DM1 添加新节点: testClip_0 深度: 1807
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_1 深度: 1249
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_2 深度: 1786
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_3 深度: 1877
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_4 深度: 1733
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_5 深度: 1661
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_6 深度: 1264
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_7 深度: 1318
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_8 深度: 1999
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_9 深度: 1411
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_10 深度: 1217
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_11 深度: 1580
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_12 深度: 1461
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_13 深度: 1040
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_14 深度: 1708
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_15 深度: 1330
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_16 深度: 1587
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_17 深度: 1947
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_18 深度: 1322
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_19 深度: 1678
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_20 深度: 1035
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_21 深度: 1481
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_22 深度: 1857
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_23 深度: 1411
[DepthManager] DM1 处理了 0 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_24 深度: 1878
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_25 深度: 1392
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_26 深度: 1544
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_27 深度: 1756
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_28 深度: 1632
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_29 深度: 1257
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_30 深度: 1005
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_31 深度: 1582
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_32 深度: 1611
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_33 深度: 1457
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_34 深度: 1155
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_35 深度: 1483
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_36 深度: 1550
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_37 深度: 1447
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_38 深度: 1954
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_39 深度: 1654
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_40 深度: 1577
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_41 深度: 1861
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_42 深度: 1624
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_43 深度: 1755
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_44 深度: 1485
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_45 深度: 1398
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_46 深度: 1215
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_47 深度: 1233
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_48 深度: 1833
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_49 深度: 1644
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 已清空所有数据
[DepthManager] DM1 添加新节点: testClip_0 深度: 1232
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_1 深度: 1774
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_2 深度: 1852
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_3 深度: 1456
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_4 深度: 1648
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_5 深度: 1558
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_6 深度: 1979
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_7 深度: 1031
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_8 深度: 1386
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_9 深度: 1448
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_10 深度: 1401
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_11 深度: 1808
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_12 深度: 1138
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_13 深度: 1609
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_14 深度: 1758
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_15 深度: 1064
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_16 深度: 1459
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_17 深度: 1207
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_18 深度: 1055
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_19 深度: 1193
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_20 深度: 1441
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_21 深度: 1208
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_22 深度: 1812
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_23 深度: 1804
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_24 深度: 1433
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_25 深度: 1282
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_26 深度: 1647
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_27 深度: 1276
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_28 深度: 1886
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_29 深度: 1742
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_30 深度: 1866
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_31 深度: 1789
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_32 深度: 1503
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_33 深度: 1729
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_34 深度: 1937
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_35 深度: 1463
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_36 深度: 1130
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_37 深度: 1340
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_38 深度: 1062
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_39 深度: 1867
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_40 深度: 1063
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_41 深度: 1010
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_42 深度: 1145
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_43 深度: 1615
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_44 深度: 1378
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_45 深度: 1734
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_46 深度: 1859
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_47 深度: 1680
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_48 深度: 1940
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_49 深度: 1347
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 已清空所有数据
[DepthManager] DM1 添加新节点: testClip_0 深度: 1068
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_1 深度: 1940
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_2 深度: 1911
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_3 深度: 1345
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_4 深度: 1444
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_5 深度: 1133
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_6 深度: 1406
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_7 深度: 1385
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_8 深度: 1561
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_9 深度: 1641
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_10 深度: 1821
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_11 深度: 1285
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_12 深度: 1139
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_13 深度: 1161
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_14 深度: 1762
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_15 深度: 1710
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_16 深度: 1203
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_17 深度: 1584
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_18 深度: 1801
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_19 深度: 1095
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_20 深度: 1675
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_21 深度: 1026
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_22 深度: 1828
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_23 深度: 1853
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_24 深度: 1263
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_25 深度: 1086
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_26 深度: 1713
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_27 深度: 1570
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_28 深度: 1296
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_29 深度: 1935
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_30 深度: 1336
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_31 深度: 1428
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_32 深度: 1214
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_33 深度: 1499
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_34 深度: 1366
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_35 深度: 1065
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_36 深度: 1268
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_37 深度: 1196
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_38 深度: 1712
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_39 深度: 1233
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_40 深度: 1347
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_41 深度: 1274
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_42 深度: 1038
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_43 深度: 1511
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_44 深度: 1346
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_45 深度: 1364
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_46 深度: 1290
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_47 深度: 1105
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_48 深度: 1149
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_49 深度: 1888
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManagerTest] DepthManager 平均耗时: 3.75 毫秒
[DepthManagerTest] 性能比较结果:
[DepthManagerTest] 深度管理器比原生 swapDepths 慢 3650%
[DepthManagerTest] 在当前测试条件下，深度管理器的性能开销大于其收益
[DepthManagerTest] 上线建议:
[DepthManagerTest] × 深度管理器性能开销较大，建议重新评估或进一步优化
[DepthManagerTest]   - 考虑在更新频率较低的场景中使用
[DepthManagerTest]   - 或者在更新频率高的场景中降低更新频率
[DepthManagerTest] 
==================================================
[DepthManagerTest]  测试总结
[DepthManagerTest] ==================================================
[DepthManagerTest] 功能测试:
[DepthManagerTest] - 总测试数: 13
[DepthManagerTest] - 通过测试: 13
[DepthManagerTest] - 失败测试: 0
[DepthManagerTest] 
性能测试:
[DepthManagerTest] - 原生 swapDepths 平均耗时: 0.1 毫秒
[DepthManagerTest] - DepthManager 平均耗时: 3.75 毫秒
[DepthManagerTest] - 性能退化: -3650%
[DepthManagerTest] 
==================================================
[DepthManagerTest]  综合评估
[DepthManagerTest] ==================================================
[DepthManagerTest] √ 功能测试全部通过
[DepthManagerTest] × 性能测试显示 DepthManager 有明显性能开销
[DepthManagerTest] 
最终建议:
[DepthManagerTest] △ DepthManager 功能可靠，但有性能开销
[DepthManagerTest]   - 建议在性能不敏感的场景中使用
[DepthManagerTest]   - 或继续优化性能后再投入生产环境
[DepthManagerTest] 正在清理测试环境...
[DepthManager] DM1 开始销毁...
[DepthManager] DM1 已清空所有数据
[DepthManager] DM1 已销毁
[DepthManagerTest] 测试环境已清理
[DepthManager] undefined 开始销毁...
[DepthManager] undefined 已销毁
[DepthManager] undefined 开始销毁...
[DepthManager] undefined 已销毁
[DepthManager] undefined 开始销毁...
[DepthManager] undefined 已销毁
