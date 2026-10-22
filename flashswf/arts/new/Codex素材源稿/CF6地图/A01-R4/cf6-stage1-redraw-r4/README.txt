CF6 第一可玩正式关 a1 / R4 土地材质返修候选

基于冻结R3，仅替换01-night-soil中的土底。金属→宽混合覆盖→纯沙土三层边界、三盏双槽青灯与蓝晕保持R3；墙、废车、炮台、箱和黄灯不改。
土底采用source/soil_material.py 2.1.0多尺度确定性砂砾配方；细颗粒亮暗侧、中频压痕与宽缓阴影分别生成。第一关使用独立斜坡/暗洼光照，不直接套第二关纵向渐层。2×PNG内嵌SVG，保持800×452原坐标及原土地轮廓。新土不是原图像素复制；其余层仍沿用R3向量编辑源。

重建：Python3、Pillow、NumPy、SciPy、Inkscape、DejaVu Sans。执行python source/rebuild.py。无需SWF、网络或其他工程；reference包含所需参考。完整配方接口见source/soil-material-README.txt。

游戏使用建议：baked/background-1580-r4-800x452.png；另提供无青光晕底图和独立透明青晕PNG。分层SVG用于编辑，黄色灯1410/1411独立。注册见baked/registration.json。不承诺全向量实时性能，未接入生产或执行ActionScript。

保留差距：颗粒仍略同质，局部有斜向串连；原版更碎散。钢纹规律、沙舌较平、灯框干净是R3已知剩余项，本轮未扩大修改。废车堆沿用参考色域简化描摹与结构校准，不称完全手绘恢复。炮台18帧运行/全关卡动态未验，开火特效复用原，箱碎片仍按原clip复用新材质。
