# 两犬口腔结构修正

两侧颊壁从嘴角向后构成口腔侧壁，不能画成始终覆盖前牙开口的平整皮膜。本次保留嘴角后方弯曲的颊壁和深处暗区，沿上颌画窄腭面与褶皱，沿下颌画口底及收回的舌面；此侧面视角的前部牙间空隙可透出背景。

结构依据：[IMAIOS 犬颊部解剖](https://www.imaios.cn/en/vet-anatomy/anatomical-structures/cheek-11073761760)、[明尼苏达大学犬猫口腔解剖](https://open.lib.umn.edu/dogcatanatomylabguide/chapter/oral-cavity/)。这是适配现有侧面画风的矢量表达，具体遮挡仍取决于视角和姿势。

唯一编辑源仍为 Codex XFL 的两犬元件。只改原有口腔层，不修改头部/下颌/攻击点矩阵、帧数、AS2、属性、原僵尸犬或其他作者素材。原交付 SVG 保持冻结。

核验：`python -X utf8 tools/two-dogs-assets/refine-mouth.py`、`verify.py`；实际 CS6 发布后运行 `scripts/run-two-dogs-asset-tests.ps1`，再用 `export-previews.py` 从本轮 trace 生成 18 张原生关键帧与张口/咬合对照图；连续 GIF 使用另行标识的高清 XFL 源稿预览。机器像素检查防止旧三角形封口回归，不代替人类审美验收。
