# 书架内容

`catalog.json` 维护目录、书名、类型和阅读索引。可玩关卡的配置已迁至 `data/stages/books/`。

- 《尘都诡谈》《光明巴比伦》保留原有各 15 页 SVG，来源与完整性见运行资源中的 `manifest.json`。
- 《守护之力》来自“跨页二轮-30MB画质优先”压缩包：1,227 页，AVIF/JPEG 图片与 17 段 AV1 WebM。图片和编码帧原样复制，按索引定位后裁切展示，不播放成连续视频。原包哈希、每页来源和质量数据保存在 `sources/guardian-import.json` 与 `sources/guardian-index.json`。
- 《风帆双子》作者 Forever爱牛，四份官网正文存档合并为 28 章；原始文本及来源地址保存在 `sources/sail-twins/`，不与单章转载重复收录。生成时只整理标题、段落与分隔线，不改写正文。

运行 `python tools/import-bookshelf-library.py` 生成 `launcher/web/assets/bookshelf/` 中的目录、阅读索引和 `library-manifest.json`；`--check` 重算元数据并检查全部资源哈希、体积和精确文件集合。初次素材导入使用 `--comic-bundle <zip>`、`--novel-texts <目录>`、`--original-swf <原作 SWF>`，后续索引再生不依赖原 ZIP 或下载目录。

阅读进度、字号、缩放与配色属于浏览器本地阅读偏好，不写入玩家存档。阅读器只保留三个已解码页面，换书和关闭时取消解码与网络请求。运行资源通过现有 WebView2 虚拟目录提供，内容不依赖在线官网。

书架默认铺满 WebPanel 内容区，沿用共享 `inset:0` 与 `PanelScale` 的 1024×576 画布。书名、目录、翻页合并为一排 40px 工具栏；字号、缩放、配色收在“设置”内。可收起工具栏继续用方向键翻页，并从画面右上角展开。藏书目录浮在正文之上，不挤窄画面；普通 SP 提示在阅读时隐藏，错误与核对提示保留。首次阅读图片书使用“整页”，保证完整显示；双击画面切换“整页 / 适合宽度”，也可手动缩放、拖动查看。已有书签的缩放选择继续保留。

修理大学提供两个入口：原版为 `flashswf/originals/crazy-flasher-1.swf`，复用本地 `_ruffle`；重制版为现有七图肉鸽，只有重制版提供配给与 SP。原作 SWF 原样导入，身份见 `sources/crazy-flasher-1-import.json`，由同一 `--check` 验证。原版放在只有 `allow-scripts` 的隔离 iframe 内，禁用脚本访问、外链及网络调用；控制通道只接受同一 frame/session 的暂停和继续，不连接书架存档协议。返回、关闭、重绑与重新开始均销毁原播放器；重制版旅程未结束或待核对时先处理原旅程。原版重新进入从头开始，不生成 CF7 角色档案，也不提供原版存盘。

Web 验证入口为 `launcher/web/modules/bookshelf/dev/harness.html`（`?trace=1` 可查看模拟 Host 操作记录）；原版的沙箱需要静态服务允许跨源资源读取，对应正式 Host 的 `cfn-assets.local` 映射。边界及迟到消息测试为 `node tools/test-bookshelf-original.js`，原有书架消息/资源测试为 `node tools/test-bookshelf-runtime.js`。这些测试不替代正式 Host 下的输入、音频及存档 E2E 验收。
