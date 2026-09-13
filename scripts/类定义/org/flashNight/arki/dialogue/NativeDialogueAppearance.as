/**
 * =============================================================================
 *  NativeDialogueAppearance — native_dialogue 行内 portrait 裁决与外观快照
 * -----------------------------------------------------------------------------
 *  职责（纯函数、无会话状态）：
 *    1) 把 7 元组对话行的 char 字段裁决成 Host 契约的 portrait 对象：
 *         kind:"doll"   —— char 解析（getDialogueSpecialString 后）为
 *                          "玩家"/"主角模板"/"$PC_CHAR"；key 给 "hero" 占位名，
 *                          appearance 携带白名单外观快照。
 *         kind:"static" —— 其余 char 一律静态立绘，key=char 原文，
 *                          appearance 置空。
 *    2) doll 外观快照按身份裁决：
 *       · target 是 gameworld[控制目标]（同引用，或 gameworld 亲生的同名真
 *         MovieClip）/ 缺省 → 主角权威源：MC 已填字段逐字段优先，空字段回落
 *         _root.性别/脸型/发型 与 _root.物品栏.装备栏 物品名（与
 *         DressupInitializer.loadHeroEquipment 同一供给，不依赖被暂停的
 *         enterFrame 初始化）。异父同名 MC 与带 _name 的裸对象不得冒充主角。
 *       · target 是非 MovieClip 且无身份字段（对白行元数据——
 *         StageInfo.parseSingleDialogue 恒把 SubDialogue 属性对象放进
 *         target，生产 XML 从不写外观字段，故恒为全 "" 形态）→ char 已是
 *         主角占位，仍走主角权威源；src 取 hero，attrObj 残留的
 *         长枪/手枪/刀 武器名字段不得进入 keyMap。
 *       · target 带非空身份字段（佣兵 MC：MercSpawner.as:359-386；或作者
 *         写了外观属性的关卡属性对象）→ 冻结该单位自身字段，绝不回落玩家。
 *       · target 是无身份 MovieClip（真实单位壳，如未初始化佣兵）→
 *         appearance=null 明确缺图，绝不拿玩家数据补、不画默认裸模。
 *    3) appearance 字段严格限 C# DialoguePortraitService.NormalizeAppearance
 *       白名单：gender/face/hair/mask/head/body/leg/hand/foot/neck 为 String，
 *       keyMap 为 String→String 字典。绝不序列化 MovieClip / 深对象过桥。
 *
 *  字段映射（与 TaskPanelService.buildHeroPortraitState、MercSpawner MC 契约同口径）：
 *    gender←性别  face←脸型  hair←发型  mask←面具
 *    head←头部装备  body←上装装备  leg←下装装备  hand←手部装备
 *    foot←脚部装备  neck←颈部装备
 *    keyMap←换装 holder 皮肤键：面具/身体/上臂/左下臂/右下臂/左手/右手/屁股/
 *                            左大腿/右大腿/小腿/脚/刀/长枪/手枪/手枪2
 * =============================================================================
 */
class org.flashNight.arki.dialogue.NativeDialogueAppearance {

    private static var HOLDER_FIELDS:Array = [
        "面具", "身体", "上臂", "左下臂", "右下臂", "左手", "右手",
        "屁股", "左大腿", "右大腿", "小腿", "脚", "刀", "长枪", "手枪", "手枪2"
    ];

    /** char 基础名是否主角纸娃娃（"$PC_CHAR" 必须先经 getDialogueSpecialString 解析）。 */
    public static function isDollChar(charBase:String):Boolean {
        return charBase == "玩家" || charBase == "主角模板" || charBase == "$PC_CHAR";
    }

    /**
     * 由对话行构造 portrait 负载。
     * @param charField   行[2]，可能为 "key#表情" 或已拆出的 key
     * @param expression  行[4]，可能为空
     * @param target      行[5]，佣兵 MC / 关卡属性对象 / undefined
     * @param speakerName 行[0]，Andy Law 表情后缀判定用
     */
    public static function build(charField, expression, target, speakerName:String):Object {
        var rawChar:String = (charField != undefined) ? String(charField) : "";
        var parts:Array = rawChar.split("#");
        var charBase:String = (parts.length > 0 && parts[0] != undefined) ? String(parts[0]) : "";
        var expr:String = (parts.length > 1 && parts[1] != undefined)
            ? String(parts[1])
            : (expression != undefined ? String(expression) : "普通");
        if (expr == "") expr = "普通";
        // 兼容旧 UI 刷新内容：Andy Law 立绘类型后缀（_root.立绘类型 !=1 时拼接）
        if (speakerName == "Andy Law" && _root.立绘类型 != undefined
                && _root.立绘类型 && _root.立绘类型 != 1) {
            expr = expr + _root.立绘类型.toString();
        }
        if (isDollChar(charBase)) {
            var appearance:Object = snapshot(target);
            // Host 的 doll 协议要求有效对象；无身份用空静态槽保留正文，不能拒掉整句。
            if (appearance == null) return {kind:"static", key:"", expression:expr};
            return {
                kind: "doll",
                key: "hero",
                expression: expr,
                appearance: appearance
            };
        }
        // SWF 内 sprite6 按玩家自身性别跳帧，显式使用同源导出的两个分支。
        if (charBase == "室友") charBase = "室友-" + (_root.性别 == "女" ? "女" : "男");
        return { kind: "static", key: charBase, expression: expr };
    }

    /**
     * 外观快照（见类注 2 的身份裁决）。
     * @return appearance 白名单对象；无身份返回 null，由 build 转为空静态槽。
     */
    public static function snapshot(target):Object {
        var hero:Object = null;
        if (_root.gameworld != undefined && _root.控制目标 != undefined) {
            var h = _root.gameworld[_root.控制目标];
            if (h != undefined && h != null) hero = h;
        }
        // 主角身份只认：无 target / target===hero / gameworld 亲生的同名真
        // MovieClip。异父同名 MC 与带 _name 的普通对象不得冒充主角。
        var isHero:Boolean = (target == null || target === hero
            || (typeof target == "movieclip" && _root.gameworld != undefined
                && target._parent === _root.gameworld
                && _root.控制目标 != undefined && target._name === _root.控制目标));
        var src:Object = null;
        var heroPath:Boolean = false;
        if (isHero) {
            src = (target != null) ? target : hero;
            heroPath = true;
        } else if (hasIdentity(target)) {
            // 佣兵 MC / 带外观属性的关卡属性对象：自身字段
            src = target;
        } else if (typeof target == "movieclip") {
            // 无身份 MovieClip = 真实单位壳（未初始化佣兵等）：明确缺图
            return null;
        } else {
            // 非 MC 且无身份 = 对白行元数据（attrObj 恒为此形）：
            // char 已是主角占位 → 主角权威；src 必须 hero，attrObj 的
            // 武器名字段不进 keyMap
            src = hero;
            heroPath = true;
        }

        var ap:Object = {};
        if (heroPath) {
            // 身份门：MC 与 _root 都没有性别/脸型 → 明确缺图而非默认裸模
            if (fieldOf(src, "性别") == "" && fieldOf(_root, "性别") == ""
                    && fieldOf(src, "脸型") == "" && fieldOf(_root, "脸型") == "") {
                return null;
            }
            ap.gender = pick(fieldOf(src, "性别"), fieldOf(_root, "性别"), "男");
            ap.face = pick(fieldOf(src, "脸型"), fieldOf(_root, "脸型"), "");
            ap.hair = pick(fieldOf(src, "发型"), fieldOf(_root, "发型"), "");
            ap.mask = fieldOf(src, "面具");
            ap.head = pick(fieldOf(src, "头部装备"), heroEquipName("头部装备"), "");
            ap.body = pick(fieldOf(src, "上装装备"), heroEquipName("上装装备"), "");
            ap.leg = pick(fieldOf(src, "下装装备"), heroEquipName("下装装备"), "");
            ap.hand = pick(fieldOf(src, "手部装备"), heroEquipName("手部装备"), "");
            ap.foot = pick(fieldOf(src, "脚部装备"), heroEquipName("脚部装备"), "");
            ap.neck = pick(fieldOf(src, "颈部装备"), heroEquipName("颈部装备"), "");
        } else {
            // 陌生单位（佣兵）：只用 target 自身字段，任何情况下不回落玩家
            ap.gender = pick(fieldOf(src, "性别"), "", "男");
            ap.face = fieldOf(src, "脸型");
            ap.hair = fieldOf(src, "发型");
            ap.mask = fieldOf(src, "面具");
            ap.head = fieldOf(src, "头部装备");
            ap.body = fieldOf(src, "上装装备");
            ap.leg = fieldOf(src, "下装装备");
            ap.hand = fieldOf(src, "手部装备");
            ap.foot = fieldOf(src, "脚部装备");
            ap.neck = fieldOf(src, "颈部装备");
        }
        if (src != null) {
            var keyMap:Object = {};
            for (var i:Number = 0; i < HOLDER_FIELDS.length; i++) {
                var f:String = String(HOLDER_FIELDS[i]);
                var v = src[f];
                if (v != undefined && v != "") keyMap[f] = String(v);
            }
            var has:Boolean = false;
            for (var k:String in keyMap) { has = true; break; }
            if (has) ap.keyMap = keyMap;
        }
        return ap;
    }

    /** 字段读取并归一成 String；BaseItem 等对象取 .name（toString 同义）。 */
    private static function fieldOf(src:Object, name:String):String {
        if (src == null) return "";
        var v = src[name];
        if (v == undefined || v == null) return "";
        if (typeof v == "object") v = v.name;
        var s:String = String(v);
        return (s == "undefined") ? "" : s;
    }

    /** 非空身份判定：空串与 undefined 同样视为未初始化（空壳不算有人）。 */
    private static function hasIdentity(o:Object):Boolean {
        return o != null && (fieldOf(o, "性别") != "" || fieldOf(o, "脸型") != ""
            || fieldOf(o, "发型") != "" || fieldOf(o, "头部装备") != "");
    }

    /**
     * 主角权威装备名：_root.物品栏.装备栏，与 loadHeroEquipment 同一供给，
     * 随存档/背包状态就绪，不等 MC 初始化链。
     */
    private static function heroEquipName(slot:String):String {
        var inv:Object = _root.物品栏;
        var bar:Object = (inv != null) ? inv.装备栏 : null;
        if (bar == null) return "";
        if (typeof bar.getNameString == "function") {
            var s = bar.getNameString(slot);
            if (s != undefined && s != null && String(s) != "") return String(s);
        }
        if (typeof bar.getItem == "function") {
            var it = bar.getItem(slot);
            if (it != null) {
                var n = (it.name != undefined) ? it.name : it;
                var ns:String = String(n);
                if (ns != "" && ns != "undefined") return ns;
            }
        }
        return "";
    }

    /** 双源择值：a 非空取 a，否则 b，再否则默认。 */
    private static function pick(a:String, b:String, dflt:String):String {
        if (a != "") return a;
        if (b != "") return b;
        return dflt;
    }
}
