# NPC 小头像增量补齐

现有 Native 交付栏、任务页与合成跳转共用 `flashswf/portraits/profiles/{npcName}.png`。本工具只维护 sources.json 明列的 15 张新增文件，原有 66 张手工头像保持原字节。

从项目根运行：

```powershell
python tools/bake-npc-profiles.py --output-dir tmp/npc-profiles-preview
python tools/bake-npc-profiles.py
python tools/bake-npc-profiles.py --check
```

预览通过后再执行默认输出。生成器先准备全部图像，验证来源 SHA、裁图边界、非空像素、400×400 画布、单图 512 KiB/总计 8 MiB 上限，然后写 PNG 与 generated-manifest.json。未登记为此生成器所有的既有目标文件拒绝覆盖。`--check` 不写文件，比较重建字节、manifest 和正式任务/地图登记人物的缺图及空图；Pillow 版本、生成器与配方 SHA 同时记录。

生成器、sources.json 与 generated-manifest.json 在 `.gitattributes` 固定为 LF，避免 Windows checkout 的自动换行改写使同一 Git tree 的来源 SHA 失效。

来源选择优先复用现有对话肖像和商店肖像，不重烘焙整套对话立绘。sources.json 明列像素裁图与源 SHA；来源变动时先复核人物和构图再更新。头部尽量占满头像框，无人机保留完整可识别主体。

- 神秘男人：原 `npc_dialogue_彩蛋.xml` 的 Char 明确为文天。
- heeho 君：使用现有商店肖像，其中已包含场景中的帽子和墨镜。
- 杀马特：现有地图驻点使用 `∞天ㄙ★使的剪∞` 头像，复用其小头像字节。
- 室友：原泛称立绘 PNG 为透明帧，具体男女小头像均已存在；通用头像组合两种既有肖像，不固定成某一性别。具体男女文件继续保留。
- 排骨、机哥、阿波：使用当前已发布的 44×44 地图小头像，新增文件不会增加原图细节。

2026-09-11 当前静态覆盖：正式加载目录 244 项任务的 53 个交付 NPC 名称、地图登记 74 个 NPC 名称，缺图/空图均为 0。这不代表所有人物在当前剧情可达，也不代替实际界面人物辨识的人验。回归协议与隔离地点行为见 [关卡结果 ADR §0E](../../docs/关卡结果与基地结算-CSharp-Web-ADR-2026-08-27.md#0e-2026-09-11-明确任务选择单次返回与到达确认隔离候选)。
