# 统合金币 R4 共享源稿

本目录接收已确认的 `side-reeds-restored-v2` 候选：R3 B 币体、R4 黄色配色、原始 node 徽记、模型 64 齿侧纹。原图样来源为本机 `Tonghe_Gold_R4.zip`，原工程保留为 `R3_B_original_unchanged.blend`。

- `.blend` / `model.json`：原始几何及其相机、网格和徽记位置导出。
- `style.json`：全尺寸共用的配色与侧纹对比度。
- `original_node.svg`：原始徽记，路径保持不变，由模型合同的 SHA-256 防止错配。
- `svg/`：由同一投影器生成的 32 帧；禁止逐帧人工另画网页版本。
- `native-manifest.json`：输入、SVG、目标 XFL 的哈希与体积、帧数和坐标合同。

生成及编译入口为 `tools/tonghe-gold-assets/README.md`。现有 linkage 为 `图标-金钱`，不新增独立运行时库，不改金币物品身份或拾取逻辑。
