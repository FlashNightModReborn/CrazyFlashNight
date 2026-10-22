M134 项目原生矢量参考
固定提交：951145190cd45646abdfd4ebde1fbe68a4dd38ff
仓库：FlashNightModReborn/CrazyFlashNight
权威源：flashswf/arts/things/LIBRARY/1.枪械相关/长枪/枪-长枪-M134.xml
图标-M134.xml只是同一枪的变换引用，不代表第二机位。
源文件字节快照与git blob SHA见source-snapshot.json。

枪口标记：name=枪口位置，是非显示定位节点，本次参考导出排除。
原生转管动画：无AS链接/Symbol 3838，共36帧；本次固定frameIndex=2（Flash第3帧）。它在整枪内部的矩阵是translate(98.7,25.7)。
独立枪管：render/m134-native-barrel-only-phase3.svg，原局部注册(0,0)，VB约[-3.4,-2.4,241.206,59.85]。

上游早期render/m134-native-barrelphase3.svg/png（本包不收录）有渲染器渐变数值断填，不可作为可用美术。诊断证明几何完整，梯度坐标归一后保持数学等价，恢复机匣/电机填面。最终文件以m134-native-complete-phase3命名。
没有Flash Player运行验收、没有全36帧动画复建；禁止把单相位导出描述成全武器动画完成。

赛车适配：可以使用原生枪管并按同源机匣/电机识别结构重构车载形态，省略手持握把、重新制作底座；需明确记录“原生枪管+同源车载适配”，不能宣称整枪原样导入。双枪透视、比例、底座和车体遮挡由车绘工程负责。
