import org.flashNight.gesh.depth.*;

// 创建测试实例并运行测试
var depthManagerTest:DepthManagerTest = new DepthManagerTest();
depthManagerTest.runTests();


[DepthManagerTest] 
==================================================
[DepthManagerTest]  DepthManager 测试套件
[DepthManagerTest] ==================================================
[DepthManagerTest] 正在设置测试环境...
[DepthManager] DM0 已创建，关联容器: testContainer_57
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
[DepthManager] DM0 处理了 1 个深度更新，耗时: 1ms
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
[DepthManager] DM0 处理了 1 个深度更新，耗时: 1ms
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
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_16 深度: 1016
[DepthManager] DM0 处理了 1 个深度更新，耗时: 1ms
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
[DepthManager] DM0 处理了 1 个深度更新，耗时: 1ms
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
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_39 深度: 1039
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_40 深度: 1040
[DepthManager] DM0 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM0 添加新节点: testClip_41 深度: 1041
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_42 深度: 1042
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_43 深度: 1043
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_44 深度: 1044
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_45 深度: 1045
[DepthManager] DM0 处理了 1 个深度更新，耗时: 1ms
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
[DepthManager] DM0 处理了 1 个深度更新，耗时: 1ms
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
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_19 深度: 2019
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_20 深度: 2020
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_21 深度: 2021
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_22 深度: 2022
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_23 深度: 2023
[DepthManager] DM0 处理了 1 个深度更新，耗时: 1ms
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
[DepthManager] DM0 处理了 1 个深度更新，耗时: 1ms
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
[DepthManager] DM0 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM0 添加新节点: testClip_35 深度: 1035
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_36 深度: 1036
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_37 深度: 1037
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_38 深度: 1038
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_39 深度: 1039
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_40 深度: 1040
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_41 深度: 1041
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_42 深度: 1042
[DepthManager] DM0 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM0 添加新节点: testClip_43 深度: 1043
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_44 深度: 1044
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_45 深度: 1045
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_46 深度: 1046
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_47 深度: 1047
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
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
[DepthManager] DM0 处理了 1 个深度更新，耗时: 1ms
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
[DepthManager] DM0 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM0 添加新节点: testClip_35 深度: 1035
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_36 深度: 1036
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_37 深度: 1037
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_38 深度: 1038
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_39 深度: 1039
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_40 深度: 1040
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_41 深度: 1041
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_42 深度: 1042
[DepthManager] DM0 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM0 添加新节点: testClip_43 深度: 1043
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_44 深度: 1044
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_45 深度: 1045
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_46 深度: 1046
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_47 深度: 1047
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_48 深度: 1048
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 添加新节点: testClip_49 深度: 1049
[DepthManager] DM0 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM0 开始销毁...
[DepthManager] DM0 已清空所有数据
[DepthManager] DM0 已销毁
[DepthManager] DM1 已创建，关联容器: testContainer_57
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
[DepthManager] DM2 处理了 1 个深度更新，耗时: 0ms
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
[DepthManager] DM2 处理了 1 个深度更新，耗时: 1ms
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
[DepthManager] DM2 处理了 1 个深度更新，耗时: 1ms
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
[DepthManager] DM2 处理了 1 个深度更新，耗时: 1ms
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
[DepthManagerTest] 原生 swapDepths 平均耗时: 0.05 毫秒
[DepthManagerTest] 测试 DepthManager 性能...
[DepthManager] DM1 已清空所有数据
[DepthManager] DM1 添加新节点: testClip_0 深度: 1113
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_1 深度: 1014
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_2 深度: 1758
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_3 深度: 1511
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_4 深度: 1532
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_5 深度: 1140
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_6 深度: 1785
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_7 深度: 1240
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_8 深度: 1163
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_9 深度: 1557
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_10 深度: 1169
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_11 深度: 1512
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_12 深度: 1773
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_13 深度: 1978
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_14 深度: 1616
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_15 深度: 1174
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_16 深度: 1768
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_17 深度: 1838
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_18 深度: 1045
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_19 深度: 1868
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_20 深度: 1879
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_21 深度: 1921
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_22 深度: 1631
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_23 深度: 1318
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_24 深度: 1970
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_25 深度: 1912
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_26 深度: 1332
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_27 深度: 1711
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_28 深度: 1408
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_29 深度: 1638
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_30 深度: 1195
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_31 深度: 1295
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_32 深度: 1371
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_33 深度: 1616
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_34 深度: 1869
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_35 深度: 1977
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_36 深度: 1365
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_37 深度: 1319
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_38 深度: 1330
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_39 深度: 1747
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_40 深度: 1011
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_41 深度: 1248
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_42 深度: 1899
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_43 深度: 1267
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_44 深度: 1116
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_45 深度: 1820
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_46 深度: 1472
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_47 深度: 1185
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_48 深度: 1995
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_49 深度: 1669
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 已清空所有数据
[DepthManager] DM1 添加新节点: testClip_0 深度: 1431
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_1 深度: 1509
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_2 深度: 1440
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_3 深度: 1821
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_4 深度: 1089
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_5 深度: 1629
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_6 深度: 1288
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_7 深度: 1437
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_8 深度: 1495
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_9 深度: 1522
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_10 深度: 1158
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_11 深度: 1022
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_12 深度: 1939
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_13 深度: 1009
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_14 深度: 1784
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_15 深度: 1357
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_16 深度: 1291
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_17 深度: 1140
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_18 深度: 1008
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_19 深度: 1581
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_20 深度: 1057
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_21 深度: 1489
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_22 深度: 1705
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_23 深度: 1235
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_24 深度: 1057
[DepthManager] DM1 处理了 0 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_25 深度: 1731
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_26 深度: 1459
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_27 深度: 1178
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_28 深度: 1230
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_29 深度: 1238
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_30 深度: 1151
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_31 深度: 1311
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_32 深度: 1991
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_33 深度: 1814
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_34 深度: 1126
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_35 深度: 1252
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_36 深度: 1802
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_37 深度: 1572
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_38 深度: 1853
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_39 深度: 1224
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_40 深度: 1256
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_41 深度: 1584
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_42 深度: 1346
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_43 深度: 1527
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_44 深度: 1662
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_45 深度: 1230
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_46 深度: 1164
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_47 深度: 1592
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_48 深度: 1393
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_49 深度: 1265
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 已清空所有数据
[DepthManager] DM1 添加新节点: testClip_0 深度: 1451
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_1 深度: 1362
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_2 深度: 1779
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_3 深度: 1620
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_4 深度: 1967
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_5 深度: 1093
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_6 深度: 1388
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_7 深度: 1292
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_8 深度: 1316
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_9 深度: 1422
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_10 深度: 1214
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_11 深度: 1087
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_12 深度: 1446
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_13 深度: 1551
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_14 深度: 1727
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_15 深度: 1917
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_16 深度: 1588
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_17 深度: 1852
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_18 深度: 1778
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_19 深度: 1499
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_20 深度: 1504
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_21 深度: 1607
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_22 深度: 1952
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_23 深度: 1273
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_24 深度: 1766
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_25 深度: 1220
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_26 深度: 1447
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_27 深度: 1193
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_28 深度: 1353
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_29 深度: 1399
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_30 深度: 1447
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_31 深度: 1752
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_32 深度: 1383
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_33 深度: 1103
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_34 深度: 1714
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_35 深度: 1251
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_36 深度: 1494
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_37 深度: 1280
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_38 深度: 1295
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_39 深度: 1051
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_40 深度: 1582
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_41 深度: 1018
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_42 深度: 1511
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_43 深度: 1582
[DepthManager] DM1 处理了 0 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_44 深度: 1991
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_45 深度: 1368
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_46 深度: 1069
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_47 深度: 1241
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_48 深度: 1528
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_49 深度: 1206
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 已清空所有数据
[DepthManager] DM1 添加新节点: testClip_0 深度: 1396
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_1 深度: 1003
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_2 深度: 1860
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_3 深度: 1172
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_4 深度: 1160
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_5 深度: 1394
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_6 深度: 1463
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_7 深度: 1708
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_8 深度: 1396
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_9 深度: 1696
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_10 深度: 1295
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_11 深度: 1456
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_12 深度: 1533
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_13 深度: 1243
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_14 深度: 1121
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_15 深度: 1898
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_16 深度: 1196
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_17 深度: 1893
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_18 深度: 1353
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_19 深度: 1204
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_20 深度: 1238
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_21 深度: 1073
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_22 深度: 1115
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_23 深度: 1616
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_24 深度: 1422
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_25 深度: 1085
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_26 深度: 1339
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_27 深度: 1172
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_28 深度: 1500
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_29 深度: 1937
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_30 深度: 1584
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_31 深度: 1340
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_32 深度: 1155
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_33 深度: 1406
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_34 深度: 1380
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_35 深度: 1903
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_36 深度: 1302
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_37 深度: 1869
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_38 深度: 1719
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_39 深度: 1053
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_40 深度: 1213
[DepthManager] DM1 处理了 1 个深度更新，耗时: 2ms
[DepthManager] DM1 添加新节点: testClip_41 深度: 1846
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_42 深度: 1488
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_43 深度: 1138
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_44 深度: 1373
[DepthManager] DM1 处理了 1 个深度更新，耗时: [... 截断的文本] 度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_32 深度: 1488
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_33 深度: 1803
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_34 深度: 1951
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_35 深度: 1161
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_36 深度: 1646
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_37 深度: 1861
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_38 深度: 1644
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_39 深度: 1264
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_40 深度: 1547
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_41 深度: 1984
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_42 深度: 1711
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_43 深度: 1982
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_44 深度: 1698
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_45 深度: 1077
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_46 深度: 1290
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_47 深度: 1788
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_48 深度: 1198
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_49 深度: 1952
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 已清空所有数据
[DepthManager] DM1 添加新节点: testClip_0 深度: 1189
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_1 深度: 1778
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_2 深度: 1892
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_3 深度: 1356
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_4 深度: 1452
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_5 深度: 1463
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_6 深度: 1958
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_7 深度: 1265
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_8 深度: 1902
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_9 深度: 1663
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_10 深度: 1235
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_11 深度: 1709
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_12 深度: 1549
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_13 深度: 1570
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_14 深度: 1923
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_15 深度: 1339
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_16 深度: 1480
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_17 深度: 1774
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_18 深度: 1628
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_19 深度: 1150
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_20 深度: 1568
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_21 深度: 1489
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_22 深度: 1839
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_23 深度: 1336
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_24 深度: 1559
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_25 深度: 1340
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_26 深度: 1547
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_27 深度: 1259
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_28 深度: 1071
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_29 深度: 1986
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_30 深度: 1776
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_31 深度: 1828
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_32 深度: 1254
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_33 深度: 1163
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_34 深度: 1076
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_35 深度: 1680
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_36 深度: 1297
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_37 深度: 1083
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_38 深度: 1622
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_39 深度: 1297
[DepthManager] DM1 处理了 0 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_40 深度: 1695
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_41 深度: 1835
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_42 深度: 1560
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_43 深度: 1974
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_44 深度: 1208
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_45 深度: 1232
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_46 深度: 1781
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_47 深度: 1234
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_48 深度: 1544
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_49 深度: 1804
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 已清空所有数据
[DepthManager] DM1 添加新节点: testClip_0 深度: 1342
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_1 深度: 1599
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_2 深度: 1814
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_3 深度: 1203
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_4 深度: 1593
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_5 深度: 1533
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_6 深度: 1830
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_7 深度: 1432
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_8 深度: 1707
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_9 深度: 1030
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_10 深度: 1388
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_11 深度: 1972
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_12 深度: 1092
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_13 深度: 1721
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_14 深度: 1768
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_15 深度: 1197
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_16 深度: 1325
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_17 深度: 1032
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_18 深度: 1286
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_19 深度: 1974
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_20 深度: 1791
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_21 深度: 1371
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_22 深度: 1267
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_23 深度: 1826
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_24 深度: 1412
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_25 深度: 1625
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_26 深度: 1585
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_27 深度: 1497
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_28 深度: 1971
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_29 深度: 1262
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_30 深度: 1679
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_31 深度: 1401
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_32 深度: 1063
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_33 深度: 1148
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_34 深度: 1998
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_35 深度: 1238
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_36 深度: 1918
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_37 深度: 1987
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_38 深度: 1333
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_39 深度: 1657
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_40 深度: 1799
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_41 深度: 1473
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_42 深度: 1785
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_43 深度: 1486
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_44 深度: 1298
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_45 深度: 1270
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_46 深度: 1658
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_47 深度: 1255
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_48 深度: 1587
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_49 深度: 1412
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 已清空所有数据
[DepthManager] DM1 添加新节点: testClip_0 深度: 1648
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_1 深度: 1203
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_2 深度: 1948
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_3 深度: 1545
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_4 深度: 1334
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_5 深度: 1015
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_6 深度: 1543
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_7 深度: 1449
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_8 深度: 1396
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_9 深度: 1973
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_10 深度: 1043
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_11 深度: 1462
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_12 深度: 1856
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_13 深度: 1266
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_14 深度: 1615
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_15 深度: 1255
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_16 深度: 1345
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_17 深度: 1359
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_18 深度: 1635
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_19 深度: 1779
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_20 深度: 1238
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_21 深度: 1642
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_22 深度: 1071
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_23 深度: 1558
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_24 深度: 1075
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_25 深度: 1807
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_26 深度: 1496
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_27 深度: 1711
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_28 深度: 1610
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_29 深度: 1342
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_30 深度: 1918
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_31 深度: 1694
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_32 深度: 1708
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_33 深度: 1724
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_34 深度: 1115
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_35 深度: 1046
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_36 深度: 1898
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_37 深度: 1190
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_38 深度: 1876
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_39 深度: 1450
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_40 深度: 1462
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_41 深度: 1130
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_42 深度: 1489
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_43 深度: 1237
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_44 深度: 1492
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_45 深度: 1132
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_46 深度: 1932
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_47 深度: 1657
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_48 深度: 1817
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_49 深度: 1922
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 已清空所有数据
[DepthManager] DM1 添加新节点: testClip_0 深度: 1504
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_1 深度: 1824
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_2 深度: 1651
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_3 深度: 1732
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_4 深度: 1098
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_5 深度: 1670
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_6 深度: 1999
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_7 深度: 1943
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_8 深度: 1686
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_9 深度: 1392
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_10 深度: 1821
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_11 深度: 1911
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_12 深度: 1058
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_13 深度: 1927
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_14 深度: 1687
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_15 深度: 1040
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_16 深度: 1381
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_17 深度: 1038
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_18 深度: 1982
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_19 深度: 1148
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_20 深度: 1343
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_21 深度: 1163
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_22 深度: 1266
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_23 深度: 1291
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_24 深度: 1497
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_25 深度: 1728
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_26 深度: 1891
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_27 深度: 1654
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_28 深度: 1380
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_29 深度: 1205
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_30 深度: 1492
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_31 深度: 1731
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_32 深度: 1837
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_33 深度: 1497
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_34 深度: 1561
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_35 深度: 1071
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_36 深度: 1414
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_37 深度: 1573
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_38 深度: 1678
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_39 深度: 1769
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_40 深度: 1108
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_41 深度: 1880
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_42 深度: 1844
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_43 深度: 1253
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_44 深度: 1621
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_45 深度: 1586
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_46 深度: 1620
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_47 深度: 1366
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_48 深度: 1022
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_49 深度: 1441
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 已清空所有数据
[DepthManager] DM1 添加新节点: testClip_0 深度: 1249
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_1 深度: 1748
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_2 深度: 1622
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_3 深度: 1709
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_4 深度: 1720
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_5 深度: 1883
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_6 深度: 1409
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_7 深度: 1025
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_8 深度: 1248
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_9 深度: 1754
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_10 深度: 1619
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_11 深度: 1152
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_12 深度: 1034
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_13 深度: 1846
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_14 深度: 1375
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_15 深度: 1992
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_16 深度: 1352
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_17 深度: 1012
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_18 深度: 1805
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_19 深度: 1970
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_20 深度: 1417
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_21 深度: 1561
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_22 深度: 1081
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_23 深度: 1496
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_24 深度: 1341
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_25 深度: 1506
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_26 深度: 1308
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_27 深度: 1195
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_28 深度: 1677
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_29 深度: 1760
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_30 深度: 1662
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_31 深度: 1461
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_32 深度: 1110
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_33 深度: 1118
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_34 深度: 1358
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_35 深度: 1253
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_36 深度: 1342
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_37 深度: 1170
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_38 深度: 1399
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_39 深度: 1508
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_40 深度: 1298
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_41 深度: 1379
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_42 深度: 1969
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_43 深度: 1985
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_44 深度: 1119
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_45 深度: 1306
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_46 深度: 1853
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_47 深度: 1329
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_48 深度: 1084
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_49 深度: 1237
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 已清空所有数据
[DepthManager] DM1 添加新节点: testClip_0 深度: 1246
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_1 深度: 1643
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_2 深度: 1174
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_3 深度: 1574
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_4 深度: 1965
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_5 深度: 1715
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_6 深度: 1164
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_7 深度: 1772
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_8 深度: 1518
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_9 深度: 1926
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_10 深度: 1549
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_11 深度: 1964
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_12 深度: 1444
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_13 深度: 1643
[DepthManager] DM1 处理了 0 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_14 深度: 1485
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_15 深度: 1734
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_16 深度: 1188
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_17 深度: 1185
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_18 深度: 1405
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_19 深度: 1116
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_20 深度: 1733
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_21 深度: 1881
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_22 深度: 1809
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_23 深度: 1817
[DepthManager] DM1 处理了 1 个深度更新，耗时: 2ms
[DepthManager] DM1 添加新节点: testClip_24 深度: 1544
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_25 深度: 1054
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_26 深度: 1932
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_27 深度: 1552
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_28 深度: 1864
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_29 深度: 1093
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_30 深度: 1549
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_31 深度: 1453
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_32 深度: 1927
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_33 深度: 1977
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_34 深度: 1621
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_35 深度: 1178
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_36 深度: 1040
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_37 深度: 1251
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_38 深度: 1972
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_39 深度: 1074
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_40 深度: 1576
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_41 深度: 1976
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_42 深度: 1267
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_43 深度: 1878
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_44 深度: 1994
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_45 深度: 1612
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_46 深度: 1120
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_47 深度: 1038
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_48 深度: 1651
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_49 深度: 1100
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 已清空所有数据
[DepthManager] DM1 添加新节点: testClip_0 深度: 1082
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_1 深度: 1039
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_2 深度: 1979
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_3 深度: 1719
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_4 深度: 1474
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_5 深度: 1152
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_6 深度: 1808
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_7 深度: 1750
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_8 深度: 1145
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_9 深度: 1561
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_10 深度: 1883
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_11 深度: 1748
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_12 深度: 1592
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_13 深度: 1510
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_14 深度: 1471
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_15 深度: 1528
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_16 深度: 1908
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_17 深度: 1372
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_18 深度: 1240
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_19 深度: 1097
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_20 深度: 1291
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_21 深度: 1221
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_22 深度: 1424
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_23 深度: 1315
[DepthManager] DM1 处理了 1 个深度更新，耗时: 2ms
[DepthManager] DM1 添加新节点: testClip_24 深度: 1769
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_25 深度: 1942
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_26 深度: 1481
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_27 深度: 1547
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_28 深度: 1716
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_29 深度: 1217
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_30 深度: 1972
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_31 深度: 1823
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_32 深度: 1739
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_33 深度: 1184
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_34 深度: 1068
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_35 深度: 1588
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_36 深度: 1717
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_37 深度: 1485
[DepthManager] DM1 处理了 1 个深度更新，耗时: 2ms
[DepthManager] DM1 添加新节点: testClip_38 深度: 1480
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_39 深度: 1515
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_40 深度: 1102
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_41 深度: 1986
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_42 深度: 1411
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_43 深度: 1353
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_44 深度: 1635
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_45 深度: 1570
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_46 深度: 1991
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_47 深度: 1077
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_48 深度: 1313
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_49 深度: 1773
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 已清空所有数据
[DepthManager] DM1 添加新节点: testClip_0 深度: 1122
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_1 深度: 1242
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_2 深度: 1123
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_3 深度: 1668
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_4 深度: 1014
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_5 深度: 1571
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_6 深度: 1491
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_7 深度: 1045
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_8 深度: 1194
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_9 深度: 1335
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_10 深度: 1595
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_11 深度: 1573
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_12 深度: 1419
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_13 深度: 1347
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_14 深度: 1921
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_15 深度: 1019
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_16 深度: 1403
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_17 深度: 1650
[DepthManager] DM1 处理了 1 个深度更新，耗时: 2ms
[DepthManager] DM1 添加新节点: testClip_18 深度: 1308
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_19 深度: 1303
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_20 深度: 1229
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_21 深度: 1110
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_22 深度: 1400
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_23 深度: 1819
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_24 深度: 1973
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_25 深度: 1017
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_26 深度: 1053
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_27 深度: 1725
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_28 深度: 1630
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_29 深度: 1656
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_30 深度: 1573
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_31 深度: 1701
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_32 深度: 1825
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_33 深度: 1395
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_34 深度: 1299
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_35 深度: 1408
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_36 深度: 1714
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_37 深度: 1058
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_38 深度: 1106
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_39 深度: 1924
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_40 深度: 1563
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_41 深度: 1466
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_42 深度: 1665
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_43 深度: 1324
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_44 深度: 1624
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_45 深度: 1001
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_46 深度: 1108
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_47 深度: 1156
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_48 深度: 1866
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_49 深度: 1955
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 已清空所有数据
[DepthManager] DM1 添加新节点: testClip_0 深度: 1770
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_1 深度: 1756
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_2 深度: 1696
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_3 深度: 1858
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_4 深度: 1206
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_5 深度: 1786
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_6 深度: 1120
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_7 深度: 1411
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_8 深度: 1683
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_9 深度: 1381
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_10 深度: 1747
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_11 深度: 1873
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_12 深度: 1940
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_13 深度: 1435
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_14 深度: 1177
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_15 深度: 1232
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_16 深度: 1526
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_17 深度: 1834
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_18 深度: 1570
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_19 深度: 1540
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_20 深度: 1505
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_21 深度: 1678
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_22 深度: 1667
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_23 深度: 1192
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_24 深度: 1566
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_25 深度: 1570
[DepthManager] DM1 处理了 0 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_26 深度: 1318
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_27 深度: 1927
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_28 深度: 1718
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_29 深度: 1519
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_30 深度: 1773
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_31 深度: 1758
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_32 深度: 1235
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_33 深度: 1995
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_34 深度: 1431
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_35 深度: 1802
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_36 深度: 1398
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_37 深度: 1023
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_38 深度: 1778
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_39 深度: 1543
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_40 深度: 1806
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_41 深度: 1625
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_42 深度: 1852
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_43 深度: 1019
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_44 深度: 1047
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_45 深度: 1004
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_46 深度: 1338
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_47 深度: 1275
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_48 深度: 1563
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_49 深度: 1298
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 已清空所有数据
[DepthManager] DM1 添加新节点: testClip_0 深度: 1292
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_1 深度: 1187
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_2 深度: 1936
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_3 深度: 1212
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_4 深度: 1596
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_5 深度: 1992
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_6 深度: 1295
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_7 深度: 1261
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_8 深度: 1085
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_9 深度: 1071
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_10 深度: 1369
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_11 深度: 1828
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_12 深度: 1174
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_13 深度: 1055
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_14 深度: 1384
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_15 深度: 1109
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_16 深度: 1265
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_17 深度: 1417
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_18 深度: 1712
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_19 深度: 1804
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_20 深度: 1501
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_21 深度: 1178
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_22 深度: 1217
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_23 深度: 1631
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_24 深度: 1150
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_25 深度: 1387
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_26 深度: 1664
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_27 深度: 1614
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_28 深度: 1005
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_29 深度: 1173
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_30 深度: 1599
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_31 深度: 1675
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_32 深度: 1202
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_33 深度: 1402
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_34 深度: 1094
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_35 深度: 1583
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_36 深度: 1624
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_37 深度: 1748
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_38 深度: 1130
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_39 深度: 1217
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_40 深度: 1612
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_41 深度: 1154
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_42 深度: 1372
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_43 深度: 1071
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_44 深度: 1071
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_45 深度: 1411
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_46 深度: 1515
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_47 深度: 1450
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_48 深度: 1614
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_49 深度: 1392
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 已清空所有数据
[DepthManager] DM1 添加新节点: testClip_0 深度: 1561
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_1 深度: 1602
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_2 深度: 1741
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_3 深度: 1588
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_4 深度: 1061
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_5 深度: 1936
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_6 深度: 1357
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_7 深度: 1131
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_8 深度: 1323
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_9 深度: 1536
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_10 深度: 1725
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_11 深度: 1850
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_12 深度: 1733
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_13 深度: 1665
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_14 深度: 1764
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_15 深度: 1170
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_16 深度: 1356
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_17 深度: 1765
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_18 深度: 1201
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_19 深度: 1235
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_20 深度: 1836
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_21 深度: 1051
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_22 深度: 1686
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_23 深度: 1789
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_24 深度: 1830
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_25 深度: 1280
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_26 深度: 1977
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_27 深度: 1925
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_28 深度: 1348
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_29 深度: 1632
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_30 深度: 1826
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_31 深度: 1180
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_32 深度: 1242
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_33 深度: 1941
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_34 深度: 1300
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_35 深度: 1614
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_36 深度: 1338
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_37 深度: 1764
[DepthManager] DM1 处理了 1 个深度更新，耗时: 1ms
[DepthManager] DM1 添加新节点: testClip_38 深度: 1173
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_39 深度: 1349
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_40 深度: 1738
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_41 深度: 1576
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_42 深度: 1551
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_43 深度: 1988
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_44 深度: 1438
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_45 深度: 1129
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_46 深度: 1321
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_47 深度: 1037
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_48 深度: 1533
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManager] DM1 添加新节点: testClip_49 深度: 1121
[DepthManager] DM1 处理了 1 个深度更新，耗时: 0ms
[DepthManagerTest] DepthManager 平均耗时: 5.7 毫秒
[DepthManagerTest] 性能比较结果:
[DepthManagerTest] 深度管理器比原生 swapDepths 慢 11300%
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
[DepthManagerTest] - 原生 swapDepths 平均耗时: 0.05 毫秒
[DepthManagerTest] - DepthManager 平均耗时: 5.7 毫秒
[DepthManagerTest] - 性能退化: -11300%
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