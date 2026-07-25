# 新 asLoader 源代码

## 更改说明

- 将任务系统、佣兵系统、关卡系统、兵种系统、商店系统、K点商城系统、物品系统的数据加载与接口定义独立为.as文件

- 将asLoader中原有的加载过程改变为统一的“逻辑系统分区”分块。各系统的.as文件可以以#include的方法直接添加到“逻辑系统分区”的加载过程中。

## 文件变动

### 历史新增文件（现行归属以 `tools/assemble-collapsed-frame.js` 的 `BOOT_SOURCES` 为准）

1. 任务系统_兼容.as

2. 佣兵系统_兼容.as

3. 关卡系统_兼容.as

4. 兵种系统_兼容.as

5. 商店系统_兼容.as

6. 商城系统_兼容.as

7. 物品系统_兼容.as

8. 逻辑系统分区_初始化.as

9. 逻辑系统分区_最终化1.as

10. ~~逻辑系统分区_最终化2.as~~（历史 f26 时间切片源；现由 `BootSequencer.stepSyncSys()` 复刻并持有，活跃文件已删除，追溯走 Git）

11. 逻辑系统分区_最终化3.as

### 更改的原有文件

1. asLoader.fla (及asLoader.swf)

## 额外说明

现行 asLoader 已是单帧 + `BootSequencer`：顶层 live source、顺序与阶段只由 `tools/assemble-collapsed-frame.js` 的 `BOOT_SOURCES` 管理，生成物为 `scripts/asLoaderManifest/_collapsed_frame.as`。不要按本页历史清单直接复制旧文件或另建平行 frame 清单；迁移来源追溯统一走 Git。
