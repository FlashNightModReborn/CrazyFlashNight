/**
 * SynthesisIndex - 合成配方索引（domain 层）
 *
 * 唯一访问 _root.改装清单对象 的入口；正反双向都在这里。
 *
 * 数据约定：
 *   - _root.改装清单对象 是一张 product → recipe 字典（key 为合成键，
 *     一般等同于产物的 item.synthesis 字段）
 *   - recipe.materials 是 String[]，每项形如 "材料名#参数" 或 "材料名##数量"
 *   - 同一配方 materials 数组里同名材料只视作一次（去重见 ensureCraftToIndex）
 *
 * 接口：
 *   - getRecipe(synthesisKey) → recipe Object | null   （正向：产物 → 配方）
 *   - getRecipesUsing(inputName) → String[]            （反向：材料 → 产物名列表，字典序）
 *   - reset() → Void                                   （测试钩子，重建反向索引）
 *
 * 反向索引由懒加载构建，O(配方数 × 平均材料数)。CF7:ME 不支持运行时
 * 热加载配方，构建一次后只读；测试通过 reset() 强制重建。
 *
 * 历史：原本 getSynthesisData / getRecipesUsing 住在 TooltipBridge，
 * 但 Bridge 的本职是"为 tooltip 屏蔽 _root 全局访问"，反向索引这种
 * 衍生数据结构属于 domain 层而非展示层桥接。2026-05 上移到此。
 */
class org.flashNight.arki.item.synthesis.SynthesisIndex {

    private static var _craftToIndex:Object = null;

    /**
     * 正向：根据合成键取配方对象。
     * @param synthesisKey 合成键（一般是物品的 item.synthesis 字段）
     * @return 配方对象 { name, materials, ... }，不存在或字典未加载时返回 null
     */
    public static function getRecipe(synthesisKey:String):Object {
        if (!_root.改装清单对象) return null;
        return _root.改装清单对象[synthesisKey];
    }

    /**
     * 反向：返回以 inputName 为材料的所有配方产物名数组（已字典序排序）。
     * @param inputName 物品名
     * @return 产物名数组（不存在时返回空数组，绝不返回 null）
     */
    public static function getRecipesUsing(inputName:String):Array {
        ensureCraftToIndex();
        var arr:Array = _craftToIndex[inputName];
        return arr ? arr : [];
    }

    /** 测试钩子：清空反向索引，下次 getRecipesUsing 触发懒加载重建。 */
    public static function reset():Void {
        _craftToIndex = null;
    }

    /**
     * 懒加载构建 input → [products] 反向索引。
     *
     * 单配方内同材料去重：若一个配方 materials 数组里出现两次同名材料
     * （如 ["X#1", "X#2"]），只把 productName 记一次，避免下游显示重复行。
     *
     * 跨配方字典序排序：for-in 不保证顺序，构建末尾对每个 bucket 排序，
     * 让"可升"段截断后展示的前 N 名稳定，玩家两次悬停看到一致结果。
     */
    private static function ensureCraftToIndex():Void {
        if (_craftToIndex != null) return;
        _craftToIndex = {};
        if (!_root.改装清单对象) return;
        for (var productName:String in _root.改装清单对象) {
            var recipe:Object = _root.改装清单对象[productName];
            if (!recipe || !recipe.materials) continue;
            var seen:Object = {};
            for (var i:Number = 0; i < recipe.materials.length; i++) {
                var matName:String = String(recipe.materials[i]).split("#")[0];
                if (seen[matName]) continue;
                seen[matName] = true;
                if (!_craftToIndex[matName]) _craftToIndex[matName] = [];
                _craftToIndex[matName].push(productName);
            }
        }
        for (var key:String in _craftToIndex) {
            _craftToIndex[key].sort();
        }
    }
}