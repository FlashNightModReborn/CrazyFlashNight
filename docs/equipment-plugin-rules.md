# 装备配件规则与恢复边界

配件定义来自 `data/items/equipment_mods/list.xml` 的现役子文件，在 `ModRegistry.loadModData` 一次规范化。普通属性与两类 hitBehavior 均使用同一加载/隔离入口；查询不再登记 schema 或 identity。数量与完整性以 `node tools/validate-equipment-mod-ui.js` 输出为准。

`TagManager` 共享兼容谓词，发现目录与严格安装分别编排。目录保留满槽、已装和互斥项以支持展示/替换；安装和替换新增项仍严格准入。raw 身份、选择进阶后的无插件 base、含插件的 current 各有用途。原生 hitBehavior 只读无插件 base，不能把当前插件产生的行为重复计为原生来源。

类型资格含 `grantsUse/grantsWeapontype`，useSwitch 分支集合保留原始 use/weapontype 与 grantsUse；授予武器类型不自动触发其他 useSwitch。拆卸按直接依赖优先、否则 cascade、否则单件处理；直接依赖包括丢失类型资格。最终集合再检查本次新增的类型/结构破坏、容量、穿戴等级和 hitBehavior，不递归扩大拆卸，不清洗普通历史非法组合。

请求内普通对象复用 lookup/base/current 和拆卸态；无跨请求缓存。最终校验结果供前后属性投影复用。背包装备提交保留既有 value transaction receipt；材料失败时只精确补偿仍属本事务的装备值。补偿异常或不完整继续要求对账，不能自动重放或把未知结果说成零写。

任一已装定义缺失或被隔离都使 `BaseItem.getData()` 失败。`getIdentityData()` 只提供名称、图标、分类和原始 mods，库存可据此辨认；严格产物回执不得借身份投影生成有效装备属性。恢复方式是修复/恢复定义后重新加载并打开，不能自动删件、退款或猜价格。显式空定义集合会清空旧注册表，null 加载失败不冒充成功载入。

候选 wire 不携 `availabilityCode`。Host 每次成功回包只净化一次候选，采用时建立独立冻结副本；失败路径来自实际校验位置。Web 保留独立 strict 验证。`available/installed/owned/replaceableFrom` 是展示和意图门，最终提交仍核 exact source、token、材料与前后证明；未知原因文本不构成安装授权。预览绑定只有一项最新状态，未送达恢复也须仍属同一最新意图。

AS2、Host、Web 同版本重新启动交付。验证入口为 `run-gray-goo-tests.ps1`、`run-equipment-tuning-tests.ps1`、三模块 publish、Host 定向及全量测试、装备调制 Node/浏览器门；实际 clone-only preview/commit、保存和重启另按 `tools/equipment-tuning/README.md` 取证。正式发布独立遵循 runtime v2 双故障域和唯一 promotion writer，自动证据不代替玩家实战体验验收。
