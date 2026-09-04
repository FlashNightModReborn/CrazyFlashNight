/**
 * K 店 legacy 待领取批收尾支撑（存盘风暴止血第三轮裁决 A②/A③）。
 *
 * 本类只服务 legacy 存量待领取行的原子收尾，不是长期通用批处理框架：
 * - canonical 五元组 (id,item,type,price,qty) 字节框架：固定字段序、类型标签、
 *   UTF-16 code-unit 长度前缀，不使用裸分隔符拼接。
 * - 双 FNV-1a 32-bit lane（lane A/B 分别以 "A\0"/"B\0" 预喂），每个 UTF-16
 *   code unit 依次喂 low byte、high byte；乘法用移位-加等价并截断 32 bit，
 *   输出 unsigned lowercase 8-hex×2 共 16 hex。仓库既有 fnv1a32Utf16 按整
 *   code unit 单轮喂入，字节序语义不同，故不复用。
 * - rowFingerprint = "kpr1." + tupleDigest16Hex + "." + occurrenceOrdinal；
 *   occurrenceOrdinal 独立于 digest，是同一 canonical 五元组在当前快照内的
 *   0-based 出现序号。完整行 identity 是 (purchasedToken, rowFingerprint)，
 *   fingerprint 只在 token epoch 内有效，不是永久行 ID。
 * - snapshot digest -> canonicalTupleString collision guard：同 digest 同 tuple
 *   只增 ordinal；同 digest 不同 tuple 整个投影 fail-closed。
 * - _root._saveExt.kshopClaimBatch 专用 batch receipt lane：v:1、上限 128、
 *   绝不 FIFO 淘汰；满则新 batch fail-closed（单项 claim 不受影响）；
 *   future/malformed lane 只 quarantine batch 能力，不连带阻断 K bulk、
 *   checkout 或单项 claim；与 Reward receipt 存储不共用故障域。
 */
class org.flashNight.arki.item.KShopLegacyClaimSupport {
    public static var LANE_VERSION:Number = 1;
    public static var MAX_BATCH_ROWS:Number = 40;
    public static var MAX_RECEIPTS:Number = 128;
    public static var MAX_OPERATION_ID_LENGTH:Number = 96;
    public static var MAX_TOKEN_LENGTH:Number = 160;
    private static var FINGERPRINT_PREFIX:String = "kpr1";
    private static var HEX_DIGITS:String = "0123456789abcdef";

    // ==================== canonical tuple 字节框架 ====================

    /** 单字段：类型标签 + UTF-16 code-unit 十进制长度前缀 + 原文。 */
    private static function canonicalField(tag:String, value:String):String {
        return tag + String(value.length) + ":" + value;
    }

    /**
     * 构造 canonical 五元组字节串。price 先走 canonical Number：拒绝
     * NaN/±Infinity，-0 归一为 0；qty 必须是十进制正整数。任一不合法返回 null。
     */
    public static function canonicalTupleString(id, item, type, price, qty):String {
        if (typeof id != "string" || String(id).length < 1 || String(id).length > 128) return null;
        if (typeof item != "string" || String(item).length < 1 || String(item).length > 128) return null;
        if (typeof type != "string" || String(type).length > 128) return null;
        var priceNumber:Number = Number(price);
        if (isNaN(priceNumber) || priceNumber == Infinity || priceNumber == -Infinity) return null;
        if (priceNumber == 0) priceNumber = 0;
        var quantityNumber:Number = Number(qty);
        if (isNaN(quantityNumber) || quantityNumber == Infinity || quantityNumber == -Infinity
                || quantityNumber <= 0 || quantityNumber != Math.floor(quantityNumber)) return null;
        return canonicalField("S", String(id))
            + canonicalField("S", String(item))
            + canonicalField("S", String(type))
            + canonicalField("N", String(priceNumber))
            + canonicalField("N", String(quantityNumber));
    }

    // ==================== 双 FNV-1a lane ====================

    /** FNV-1a 32-bit 单轮：xor 字节后以移位-加等价乘 0x01000193 并截断 32 bit。 */
    private static function fnv1a32Round(hash:Number, byteValue:Number):Number {
        hash = hash ^ byteValue;
        hash = hash + (hash << 1) + (hash << 4) + (hash << 7) + (hash << 8) + (hash << 24);
        return hash | 0;
    }

    /** 每个 UTF-16 code unit 依次喂 low byte、high byte；输出 unsigned 8-hex。 */
    private static function fnv1a32Utf16Bytes(value:String):String {
        return fnv1a32Utf16HexFrom(2166136261, value, 0);
    }

    /**
     * 从指定初始状态逐 code unit 喂 hash。AVM1 的 String.fromCharCode(0)
     * 在拼接中会被吞（实测 lane 退化为 "A"+canonical），因此 0x00 分隔符
     * 必须以 code unit 形式直接喂入，不经字符串拼接。
     */
    private static function fnv1a32Utf16HexFrom(hash:Number, value:String,
                                                start:Number):String {
        for (var i:Number = start; i < value.length; i++) {
            var codeUnit:Number = value.charCodeAt(i);
            hash = fnv1a32Round(hash, codeUnit % 256);
            hash = fnv1a32Round(hash, Math.floor(codeUnit / 256));
        }
        var result:String = "";
        for (var shift:Number = 28; shift >= 0; shift -= 4) {
            result += HEX_DIGITS.charAt((hash >>> shift) & 15);
        }
        return result;
    }

    /** lane = FNV-1a32(lane 字母 + 0x00 code unit + canonical)。 */
    private static function fnv1a32LaneDigest(laneUnit:Number,
                                              canonical:String):String {
        var hash:Number = 2166136261;
        hash = fnv1a32Round(hash, laneUnit % 256);
        hash = fnv1a32Round(hash, Math.floor(laneUnit / 256));
        hash = fnv1a32Round(hash, 0);
        hash = fnv1a32Round(hash, 0);
        return fnv1a32Utf16HexFrom(hash, canonical, 0);
    }

    /** lane A = FNV-1a32("A\0" + canonical)，lane B = FNV-1a32("B\0" + canonical)。 */
    public static function canonicalTupleDigest(canonical:String):String {
        if (typeof canonical != "string") return null;
        return fnv1a32LaneDigest(65, canonical) + fnv1a32LaneDigest(66, canonical);
    }

    // ==================== rowFingerprint 词法 ====================

    /**
     * 词法解析 rowFingerprint，等价于
     * ^kpr1\.[0-9a-f]{16}\.(0|[1-9][0-9]{0,3})$；合法返回
     * {digest:<16 hex>, ordinal:<0..9999>}，否则 null。不做任何哈希计算。
     */
    public static function parseRowFingerprint(value):Object {
        if (typeof value != "string") return null;
        var text:String = String(value);
        if (text.length < 23 || text.length > 26) return null;
        if (text.substring(0, 5) != FINGERPRINT_PREFIX + ".") return null;
        for (var i:Number = 5; i < 21; i++) {
            var code:Number = text.charCodeAt(i);
            var isHex:Boolean = (code >= 48 && code <= 57) || (code >= 97 && code <= 102);
            if (!isHex) return null;
        }
        if (text.charAt(21) != ".") return null;
        var ordinalText:String = text.substring(22);
        if (ordinalText.length < 1 || ordinalText.length > 4) return null;
        if (ordinalText.length > 1 && ordinalText.charAt(0) == "0") return null;
        for (var d:Number = 0; d < ordinalText.length; d++) {
            var digit:Number = ordinalText.charCodeAt(d);
            if (digit < 48 || digit > 57) return null;
        }
        return {digest:text.substring(5, 21), ordinal:Number(ordinalText)};
    }

    public static function buildRowFingerprint(digest:String, ordinal:Number):String {
        return FINGERPRINT_PREFIX + "." + digest + "." + String(ordinal);
    }

    // ==================== snapshot 指纹索引 + collision guard ====================

    /**
     * 为 canonical 五元组行数组构造 rowFingerprint 投影。
     * digest -> canonicalTupleString 同步维护：同 digest 同 tuple 只增 ordinal；
     * 同 digest 不同 tuple 立即 purchased_identity_collision，调用方整批零写。
     */
    public static function buildSnapshotFingerprints(rows:Array):Object {
        var digestTuple:Object = {};
        var digestOrdinal:Object = {};
        var fingerprints:Array = [];
        var indexByFingerprint:Object = {};
        for (var i:Number = 0; i < rows.length; i++) {
            var row:Object = rows[i];
            if (!(row instanceof Array) || row.length != 5) {
                return {success:false, error:"invalid_legacy_purchased"};
            }
            var canonical:String = canonicalTupleString(row[0], row[1], row[2], row[3], row[4]);
            if (canonical == null) return {success:false, error:"invalid_legacy_purchased"};
            var digest:String = canonicalTupleDigest(canonical);
            var knownTuple = digestTuple[digest];
            if (knownTuple != undefined && String(knownTuple) != canonical) {
                return {success:false, error:"purchased_identity_collision"};
            }
            digestTuple[digest] = canonical;
            var ordinal:Number = digestOrdinal[digest] == undefined
                ? 0 : Number(digestOrdinal[digest]);
            digestOrdinal[digest] = ordinal + 1;
            var fingerprint:String = buildRowFingerprint(digest, ordinal);
            fingerprints.push(fingerprint);
            indexByFingerprint[fingerprint] = i;
        }
        return {success:true, fingerprints:fingerprints, indexByFingerprint:indexByFingerprint};
    }

    // ==================== 词法门 ====================

    private static function isTokenChar(code:Number):Boolean {
        return (code >= 48 && code <= 57) || (code >= 65 && code <= 90)
            || (code >= 97 && code <= 122) || code == 46 || code == 95 || code == 45;
    }

    private static function isTokenText(value, maximumLength:Number):Boolean {
        if (typeof value != "string") return false;
        var text:String = String(value);
        if (text.length < 1 || text.length > maximumLength) return false;
        for (var i:Number = 0; i < text.length; i++) {
            if (!isTokenChar(text.charCodeAt(i))) return false;
        }
        return true;
    }

    public static function isValidBatchOperationId(value):Boolean {
        return isTokenText(value, MAX_OPERATION_ID_LENGTH);
    }

    public static function isValidPurchasedToken(value):Boolean {
        return isTokenText(value, MAX_TOKEN_LENGTH);
    }

    // ==================== batch receipt lane ====================

    private static function countOwnKeys(value:Object):Number {
        var count:Number = 0;
        for (var key:String in value) count++;
        return count;
    }

    /** 单条 receipt 的持久化 exact shape；任何漂移只 quarantine batch 能力。 */
    private static function normalizeReceiptEntry(entry:Object):Object {
        if (entry == null || typeof entry != "object" || countOwnKeys(entry) != 6) return null;
        if (!isValidBatchOperationId(entry.operationId)) return null;
        if (entry.kind != "claimBatch" || entry.status != "committed"
                || entry.policy != "atomic") return null;
        if (!isValidPurchasedToken(entry.committedPurchasedToken)) return null;
        var request:Object = entry.request;
        if (request == null || typeof request != "object" || countOwnKeys(request) != 3
                || Number(request.v) != 1
                || !isValidPurchasedToken(request.expectedPurchasedToken)
                || !(request.rows instanceof Array)
                || request.rows.length < 1 || request.rows.length > MAX_BATCH_ROWS) return null;
        var rows:Array = [];
        var seen:Object = {};
        for (var i:Number = 0; i < request.rows.length; i++) {
            if (parseRowFingerprint(request.rows[i]) == null) return null;
            var fingerprint:String = String(request.rows[i]);
            if (seen[fingerprint] === true) return null;
            seen[fingerprint] = true;
            rows.push(fingerprint);
        }
        return {
            operationId:String(entry.operationId),
            kind:"claimBatch",
            status:"committed",
            policy:"atomic",
            request:{
                v:1,
                expectedPurchasedToken:String(request.expectedPurchasedToken),
                rows:rows
            },
            committedPurchasedToken:String(entry.committedPurchasedToken)
        };
    }

    /**
     * lane 纯数据 normalizer。缺失时创建空 lane；v 非 1（future）或任何
     * malformed 条目都 quarantine 整条 lane（只禁 batch，不做破坏性迁移）。
     */
    public static function normalizeLane(raw:Object):Object {
        if (raw == undefined || raw == null) {
            return {ok:true, lane:{v:LANE_VERSION, receipts:[]}};
        }
        if (typeof raw != "object" || Number(raw.v) != LANE_VERSION
                || !(raw.receipts instanceof Array)
                || raw.receipts.length > MAX_RECEIPTS) {
            return {ok:false, quarantined:true, diagnostic:"kshop_claim_batch_lane_malformed"};
        }
        var receipts:Array = [];
        for (var i:Number = 0; i < raw.receipts.length; i++) {
            var normalized:Object = normalizeReceiptEntry(raw.receipts[i]);
            if (normalized == null) {
                return {ok:false, quarantined:true, diagnostic:"kshop_claim_batch_receipt_malformed"};
            }
            receipts.push(normalized);
        }
        return {ok:true, lane:{v:LANE_VERSION, receipts:receipts}};
    }

    /** 读侧懒确保：normalize 并写回 canonical lane；quarantined 时不动原始数据。 */
    public static function ensureLane():Object {
        if (_root._saveExt == null || typeof _root._saveExt != "object") {
            _root._saveExt = {};
        }
        var normalized:Object = normalizeLane(_root._saveExt.kshopClaimBatch);
        if (!normalized.ok) return normalized;
        _root._saveExt.kshopClaimBatch = normalized.lane;
        return normalized;
    }

    public static function lookupReceipt(lane:Object, operationId:String):Object {
        if (lane == null || !(lane.receipts instanceof Array)) return null;
        for (var i:Number = 0; i < lane.receipts.length; i++) {
            var receipt:Object = lane.receipts[i];
            if (receipt != null && String(receipt.operationId) == operationId) return receipt;
        }
        return null;
    }

    /** 128 上限是非淘汰硬顶：满时新 batch 必须 fail-closed，绝不 shift。 */
    public static function canRecordReceipt(lane:Object):Boolean {
        return lane != null && lane.receipts instanceof Array
            && lane.receipts.length < MAX_RECEIPTS;
    }

    public static function buildReceipt(operationId:String, expectedToken:String,
            rows:Array, committedToken:String):Object {
        var storedRows:Array = [];
        for (var i:Number = 0; i < rows.length; i++) storedRows.push(String(rows[i]));
        return {
            operationId:operationId,
            kind:"claimBatch",
            status:"committed",
            policy:"atomic",
            request:{v:1, expectedPurchasedToken:expectedToken, rows:storedRows},
            committedPurchasedToken:committedToken
        };
    }

    /**
     * 写入唯一入口；重复 operationId 或 lane 满都拒绝且不淘汰旧 receipt，
     * 保证每个已接受 batch 的 operation conflict 语义不会因淘汰静默失效。
     */
    public static function recordReceipt(lane:Object, receipt:Object):Boolean {
        if (!canRecordReceipt(lane) || receipt == null
                || lookupReceipt(lane, String(receipt.operationId)) != null) return false;
        lane.receipts.push(receipt);
        return true;
    }

    /** 同 operationId 的 exact request 比对：v/token/rows 顺序全部相同才允许 replay。 */
    public static function receiptMatchesRequest(receipt:Object, expectedToken:String,
            rows:Array):Boolean {
        if (receipt == null || receipt.request == null
                || Number(receipt.request.v) != 1
                || String(receipt.request.expectedPurchasedToken) != expectedToken
                || !(receipt.request.rows instanceof Array)
                || receipt.request.rows.length != rows.length) return false;
        for (var i:Number = 0; i < rows.length; i++) {
            if (String(receipt.request.rows[i]) != String(rows[i])) return false;
        }
        return true;
    }
}
