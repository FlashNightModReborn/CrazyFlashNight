/**
 * U4 健身房目录的只读基础投影。
 * 复用现役器材目录 getter；训练会话和完成结算由 GymTrainingPanelService 负责。
 */
class org.flashNight.arki.ui.GymPreviewProjection {
    private static var EQUIPMENT_SLOTS:Array = [
        "头部装备", "上装装备", "下装装备", "手部装备", "脚部装备", "颈部装备",
        "长枪", "手枪", "手枪2", "刀", "手雷"
    ];
    private static var MAX_SAFE_INTEGER:Number = 9007199254740991;

    /**
     * @param stationId 固定枚举：dummy、dumbbell、squat
     * @return 只读 UI 投影；错误时返回 v/error，不改变业务状态。
     */
    public static function buildPreview(stationId:String):Object {
        if (stationId != "dummy" && stationId != "dumbbell" && stationId != "squat") {
            return fail(stationId, "unsupported_station");
        }
        if (_root.gameworld == undefined || _root.控制目标 == undefined) {
            return fail(stationId, "actor_unavailable");
        }

        var actor:Object = _root.gameworld[_root.控制目标];
        if (actor == undefined || actor == null) return fail(stationId, "actor_unavailable");

        var gender:String = projectedGender();
        if (gender == "") return fail(stationId, "invalid_gender");

        var money:Number = Number(_root.金钱);
        var kpoint:Number = Number(_root.虚拟币);
        if (!isNonnegativeSafeInteger(_root.金钱)
                || !isNonnegativeSafeInteger(_root.虚拟币)) {
            return fail(stationId, "balance_unavailable");
        }

        var projects:Array = buildProjects(stationId);
        if (projects == undefined || projects == null) return fail(stationId, "catalog_unavailable");

        return {
            v:1,
            stationId:stationId,
            balances:{money:money, kpoint:kpoint},
            portrait:buildPortrait(actor, gender),
            projects:projects
        };
    }

    /**
     * 现役 getter 会替换全局临时目录。同步复制后立即恢复原引用，
     * 避免预览查询改变仍可达的旧菜单目录。
     */
    private static function buildProjects(stationId:String):Array {
        if (stationId == "dummy" && typeof _root.获取木人桩训练项 != "function") return null;
        if (stationId == "dumbbell" && typeof _root.获取哑铃训练项 != "function") return null;
        if (stationId == "squat" && typeof _root.获取深蹲杠铃训练项 != "function") return null;

        var previousCatalog:Object = _root.健身房训练类型;
        if (stationId == "dummy") _root.获取木人桩训练项();
        else if (stationId == "dumbbell") _root.获取哑铃训练项();
        else _root.获取深蹲杠铃训练项();

        var source:Array = _root.健身房训练类型;
        if (source == undefined || source == null) {
            _root.健身房训练类型 = previousCatalog;
            return null;
        }

        var projects:Array = [];
        var malformed:Boolean = false;
        for (var i:Number = 0; i < 13; i++) {
            var item:Object = source[i];
            if (item == undefined || item == null) continue;
            if (typeof item.属性名 != "string" || item.属性名 == ""
                    || typeof item.加成名 != "string" || item.加成名 == "") {
                malformed = true;
                break;
            }

            var currency:String = "";
            if (item.货币名 == "金钱") currency = "money";
            else if (item.货币名 == "K点") currency = "kpoint";
            else {
                malformed = true;
                break;
            }

            if (!isPositiveSafeInteger(item.消耗)
                    || !isPositiveSafeInteger(item.加成)
                    || !isPositiveSafeInteger(item.时长)) {
                malformed = true;
                break;
            }

            var currentValue:Object;
            var cap:Object = null;
            if (item.属性名 == "技能点") {
                if (item.上限 != undefined && item.上限 != null) {
                    malformed = true;
                    break;
                }
                currentValue = _root.技能点数;
            } else {
                cap = item.上限;
                if (!isPositiveSafeInteger(cap)) {
                    malformed = true;
                    break;
                }
                currentValue = _root[item.属性名];
            }
            if (!isNonnegativeSafeInteger(currentValue)) {
                malformed = true;
                break;
            }

            projects.push({
                id:stationId + "." + i,
                index:i,
                rewardLabel:String(item.加成名),
                rewardAmount:Number(item.加成),
                currency:currency,
                cost:Number(item.消耗),
                durationMs:Number(item.时长),
                current:Number(currentValue),
                cap:cap == null ? null : Number(cap)
            });
        }

        _root.健身房训练类型 = previousCatalog;
        if (malformed || projects.length == 0) return null;
        return projects;
    }

    private static function projectedGender():String {
        if (typeof _root.性别 != "string") return "";
        if (_root.性别 == "男") return "male";
        if (_root.性别 == "女") return "female";
        return "";
    }

    private static function buildPortrait(actor:Object, gender:String):Object {
        var equipment:Object = {};
        for (var i:Number = 0; i < EQUIPMENT_SLOTS.length; i++) {
            var slot:String = EQUIPMENT_SLOTS[i];
            var item:Object = actor[slot];
            if (item != undefined && item != null && typeof item.name == "string"
                    && item.name.length > 0) {
                equipment[slot] = String(item.name);
            }
        }

        return {
            gender:gender,
            equipment:equipment,
            hair:_root.发型 == undefined || _root.发型 == null ? "" : String(_root.发型),
            face:_root.脸型 == undefined || _root.脸型 == null ? "" : String(_root.脸型)
        };
    }

    private static function isNonnegativeSafeInteger(value):Boolean {
        if (typeof value != "number" || isNaN(value) || !isFinite(value)) return false;
        if (value < 0 || value > MAX_SAFE_INTEGER) return false;
        return Math.floor(value) == value;
    }

    private static function isPositiveSafeInteger(value):Boolean {
        return isNonnegativeSafeInteger(value) && value > 0;
    }

    private static function fail(stationId:String, error:String):Object {
        return {v:1, stationId:stationId, error:error};
    }
}
