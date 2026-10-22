CF6 a12 R2 独立返修源包

本轮按用户反馈修改素材：[1828]。
原批准/冻结R1另行保留，本包为独立R2。
运行 python source/rebuild.py，从本包source/reference重建可编辑SVG、预览PNG与验证记录；需要Python3、Pillow、numpy、scipy及Inkscape，字体随reference或系统DejaVuSans。无需原SWF或网络。
素材为原生可编辑SVG和程序化烘焙纹理混合源，不是全部纯矢量。原角色、武器、特效保留项按各JSON记录。
场景预览是固定相机/固定时间相位示意，不是游戏运行截图；保留原depth/matrix/color/clip及碰撞/玩法，仅本轮明确授权的视觉结构/接缝修正改变绘制内容。工业格栅使用连续全区域相位并集，原片外边界保留，去除内部错误拼口。
本轮实际解压冷构建验证见包外cold-build-report.json；旧QA仅为上游历史，不能视为本轮运行验收。本包不作Windows/生产接入。
