# NPC 物品商店配置

`list.xml` 引用 `npcs/*.json`，每个文件描述一个 `npc-shop.v2` 商店。商品索引是旧 Flash 商店与 Web 交易协议共同使用的稳定身份，调整展示分组时不要重排 `catalog` 键。

## 默认自动分类

通常只维护 `schema`、`shopId`、`title` 和 `catalog`，不要配置 `sections`。Web 会根据 `data/items` 已有字段，只为当前商店实际存在的商品建立分类树：

| 大类 | 二级分类 | 三级分类 |
|---|---|---|
| 武器 | `use`：刀 / 手枪 / 长枪 | 刀使用 `actiontype`；手枪、长枪使用 `weapontype` |
| 防具 | `use`：头部 / 颈部 / 上装 / 手部 / 下装 / 脚部 | 无 |
| 消耗品 | `use`：药剂 / 弹夹 / 手雷 / 材料 / 货币 | 无 |
| 收集品 | `use`：材料 / 情报 | 无 |

未知值进入“其他”，不会隐藏商品。分类只影响浏览，不参与价格、情报门槛、购买落点或交易权威。

```json
{
  "schema": "npc-shop.v2",
  "shopId": "示例商人",
  "title": "示例商人",
  "catalog": {
    "0": "示例长枪",
    "8": { "name": "受限商品", "requiredInfo": "示例情报", "purchaseLimit": 5 }
  }
}
```

`catalog` 对象值支持：

- 字符串：物品名。
- `name`：对象写法中的物品名。
- `requiredInfo`：持有指定情报后才可购买。
- `purchaseLimit`：单笔采购上限，整数 `1..100`；装备默认 50，其他物品默认 100。

## 人工分组（谨慎使用）

只有“科技武器”“剧情商品”“限时商品”等无法从物品属性推导的经营语义，才应配置人工分组。只要存在 `sections`，它就会完整替代默认分类树，因此必须覆盖目录全部索引；`defaultSection` 必须引用已声明的 section。

```json
{
  "schema": "npc-shop.v2",
  "shopId": "示例商人",
  "title": "示例商人",
  "catalog": {
    "0": "示例长枪",
    "8": "剧情纪念品"
  },
  "defaultSection": "featured",
  "sections": [
    { "id": "featured", "label": "本期精选", "entries": [0] },
    { "id": "story", "label": "剧情纪念品", "entries": [8] }
  ]
}
```

约束：

- `id` 只能使用 ASCII 字母、数字、点、下划线和连字符；`all` 为保留值。
- `label` 最长 16 字符。
- 一个 section 内不得重复索引；所有 `catalog` 索引必须至少被一个 section 覆盖。
- 人工分组不得复制价格、物品类型或购买落点等权威数据。
- 修改后运行 `node tools/validate-npc-shops.js`。

## 防具套装边界

现有防具稳定标注了装备位，但没有可靠的套装 ID。物品名、描述、`dressup` 和配方只能生成待人工复核的候选，不能在运行时直接推断“整套购买”：套装可能少于五件，同一装备位也可能有多个可选变体。

在建立经过审核的套装清单前，商店只按防具装备位自动分类。候选审计可以使用名称词干、不同 `use` 装备位、等级接近、同商店共现、外观与配方作为证据；任何结果都不得自动写回商品目录或生成批量购买意图。

运行 `node tools/audit-equipment-set-candidates.js` 查看同商店、同名称词干且跨多个装备位的候选；追加 `--json` 可输出供人工评审的结构化结果，`--check` 只验证候选生成契约。该工具有意允许漏报和误报，输出固定标记为 `runtimeAuthoritative:false`。
