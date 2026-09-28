# 生命周期战技关系校验

本工具检查已注册物品与插件中的 `lifecycle/attr_*`，包括进阶覆盖，避免新增绑定漏标或把属性写在错误层级。字段定义以[装备函数 schema](../../scripts/逻辑/装备函数/README.md#skill-interaction)为唯一合同。

从仓库根目录运行，依赖 Python 3 标准库：

```powershell
python -X utf8 tools/lifecycle-skill-metadata/validate.py
python -X utf8 tools/lifecycle-skill-metadata/validate.py --json
python -X utf8 -m unittest discover -s tools/lifecycle-skill-metadata -p test_validate.py
```

扫描入口为 `data/items/list.xml` 和 `data/items/equipment_mods/list.xml`。未注册文件不计入运行时覆盖；缺失注册文件、解析失败、缺标、重复标记、非法枚举及错误层级均使校验失败。检查器还拒绝 `independent` 同时声明直接 `<skill>`，以及没有直接 `<skill>` 的 `fallback`。根层装备战技不会自动改变其独立动画 attr 的分类。

插件只接受顶层 `lifecycle`，其中每个 attr 必须为 `independent`，无直接 `skill`/`setGate`，且至少有一个有效的 init/cycle。检查器拒绝空回调、重复 init/cycle 和非 attr 子节点；运行端的合成与拒绝规则见上述 schema。装备本体仍可按实际行为使用四种分类。

纯打标批次可以追加指定基线的字节检查：

```powershell
python -X utf8 tools/lifecycle-skill-metadata/validate.py --verify-against HEAD
```

它移除独占一行的合法 `skillInteraction` 标记后，逐字节比较两份注册表与全部注册 XML。其他字段、注释、BOM、换行变化都会失败。`HEAD` 应指打标前基线；若本批还包含有意的数据变更，应运行普通校验并单独审阅数据差异。仓库 XML 按既有 `.gitattributes` 使用 LF。

检查器只证明结构、覆盖与可选的字节隔离。函数调用链、套装条件、专用战技协议和实际运行兼容性仍需源码审阅及对应运行验证；这里不修改安装规则，也不启动 CS6、构建或发布。
