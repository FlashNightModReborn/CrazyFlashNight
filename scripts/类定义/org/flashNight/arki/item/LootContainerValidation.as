/** LootContainerService 的纯 payload shape 验证，独立成类以规避 AS2 单类 32K branch 上限。 */
class org.flashNight.arki.item.LootContainerValidation {
    private static var MAX_SAFE_INTEGER:Number = 9007199254740991;

    public static function validateCommandShape(commandName:String, params:Object):Boolean {
        var allowed:Array = ["task", "action", "callId", "v", "chestSessionId",
            "lootContainerId", "containerEpoch"];
        var expectedAction:String = "";
        if (commandName == "snapshot") {
            expectedAction = "lootSnapshot";
            allowed.push("loot"); allowed.push("backpack");
        } else if (commandName == "tooltip") {
            expectedAction = "lootTooltip";
            allowed.push("expectedAuthorityRevision"); allowed.push("source");
        } else if (commandName == "claim") {
            expectedAction = "lootClaim";
            allowed.push("expectedAuthorityRevision"); allowed.push("operationId");
            allowed.push("direction"); allowed.push("source"); allowed.push("targetContainerId");
        } else if (commandName == "close") {
            expectedAction = "lootClose";
            allowed.push("expectedAuthorityRevision"); allowed.push("operationId");
            allowed.push("closeLease"); allowed.push("abandon");
        } else if (commandName == "query") {
            expectedAction = "lootQuery";
            allowed.push("openAttemptSeq"); allowed.push("recoveryNonce");
        } else return false;
        if (!hasOnlyKeys(params, allowed) || !hasOwnField(params, "v")) return false;
        var hasTask:Boolean = hasOwnField(params, "task");
        var hasAction:Boolean = hasOwnField(params, "action");
        var hasCallId:Boolean = hasOwnField(params, "callId");
        if (commandName == "query") {
            // Wire 上是普通 7 键或 proof 9 键；execute 的同步测试入口仍允许
            // 去掉 task/action/callId 的 4/6 键 body。proof 字段必须原子出现。
            if (!hasOwnField(params, "chestSessionId")
                    || !hasOwnField(params, "lootContainerId")
                    || !hasOwnField(params, "containerEpoch")) return false;
            var hasAttempt:Boolean = hasOwnField(params, "openAttemptSeq");
            var hasRecoveryNonce:Boolean = hasOwnField(params, "recoveryNonce");
            if (hasAttempt != hasRecoveryNonce) return false;
            if (hasTask || hasAction || hasCallId) {
                if (!hasTask || !hasAction || !hasCallId
                        || params.task !== "cmd" || params.action !== expectedAction
                        || !isPositiveWhole(params.callId)
                        || Number(params.callId) > 2147483647) return false;
            }
            if (hasAttempt && (!isPositiveWhole(params.openAttemptSeq)
                    || Number(params.openAttemptSeq) > 2147483647
                    || typeof params.recoveryNonce != "string"
                    || !isSafeOpaque(String(params.recoveryNonce), 128))) return false;
            return true;
        }
        if (hasTask || hasAction || hasCallId) {
            if (!hasTask || !hasAction || !hasCallId
                    || params.task !== "cmd" || params.action !== expectedAction
                    || !isPositiveWhole(params.callId)
                    || Number(params.callId) > 2147483647) return false;
        }
        return true;
    }

    public static function hasOnlyKeys(value:Object, allowed:Array):Boolean {
        if (value == null || typeof value != "object" || value instanceof Array) return false;
        for (var key:String in value) {
            if (typeof value.hasOwnProperty == "function" && !value.hasOwnProperty(key)) continue;
            var found:Boolean = false;
            for (var i:Number = 0; i < allowed.length; i++) {
                if (key == allowed[i]) {
                    found = true;
                    break;
                }
            }
            if (!found) return false;
        }
        return true;
    }

    /** sendTaskWithCallback 的 payload body；外层 task/callId 由 ServerManager 生成。 */
    public static function buildPanelRequest(record:Object, source:String):Object {
        return {
            panel:"loot",
            source:source,
            initData:{
                v:1,
                chestSessionId:record.chestSessionId,
                lootContainerId:record.lootContainerId,
                containerEpoch:record.containerEpoch,
                openAttemptSeq:record.openAttemptSeq,
                displayName:record.presetName,
                capacity:record.inventory.capacity,
                columns:record.col
            }
        };
    }

    /**
     * panel_request callback disposition。Host 的 accepted 只表示 tracked open 已入队，
     * bound 在此阶段固定为 false；任何 shape 漂移都属于投递结果不确定，不能冒充明确拒绝。
     */
    public static function classifyPanelOpenResponse(response:Object):String {
        if (isDefinitePanelOpenNoSend(response)) return "definite_no_send";
        if (!isExactPanelOpenAck(response)) return "delivery_uncertain";
        return response.accepted === true ? "queued" : "definite_rejection";
    }

    public static function panelOpenFailureReason(response:Object):String {
        var errorCode:String = response == null ? "" : String(response.error);
        if (errorCode == "callback timeout") return "panel_open_timeout";
        if (errorCode == "socket not connected" || errorCode == "socket closed"
                || errorCode == "stringify failed") return "panel_open_unavailable";
        if (classifyPanelOpenResponse(response) == "delivery_uncertain") {
            return "panel_open_protocol_uncertain";
        }
        return "panel_open_rejected";
    }

    private static function isDefinitePanelOpenNoSend(response:Object):Boolean {
        if (!hasOnlyKeys(response, ["success", "error"])
                || !hasOwnField(response, "success") || !hasOwnField(response, "error")
                || response.success !== false || typeof response.error != "string") return false;
        return response.error === "stringify failed"
            || response.error === "socket not connected";
    }

    private static function isExactPanelOpenAck(response:Object):Boolean {
        var allowed:Array = ["success", "accepted", "bound", "panel", "error", "callId"];
        if (!hasOnlyKeys(response, allowed)
                || !hasOwnField(response, "success")
                || !hasOwnField(response, "accepted")
                || !hasOwnField(response, "bound")
                || !hasOwnField(response, "panel")
                || !hasOwnField(response, "callId")
                || typeof response.success != "boolean"
                || typeof response.accepted != "boolean"
                || response.bound !== false || response.panel !== "loot") return false;
        if (!isWhole(response.callId) || Number(response.callId) < 0
                || Number(response.callId) > 2147483647) return false;
        if (response.accepted === true) {
            return response.success === true && !hasOwnField(response, "error");
        }
        return response.success === false && typeof response.error == "string"
            && isDefinitePanelOpenRejection(String(response.error));
    }

    private static function isDefinitePanelOpenRejection(errorCode:String):Boolean {
        return errorCode == "invalid_request" || errorCode == "coordinator_disposed"
            || errorCode == "panel_unavailable" || errorCode == "panel_busy"
            || errorCode == "identity_unavailable" || errorCode == "flow_busy"
            || errorCode == "open_not_queued";
    }

    /** Host accepted 后的 Web mount/open watchdog 走扁平 cmd envelope 回告 AS2。 */
    public static function validatePanelRecoveryEnvelope(params:Object):Boolean {
        var allowed:Array = ["task", "action", "chestSessionId", "lootContainerId",
            "containerEpoch", "openAttemptSeq", "recoveryNonce", "reason"];
        if (!hasOnlyKeys(params, allowed)) return false;
        for (var index:Number = 0; index < allowed.length; index++) {
            if (!hasOwnField(params, String(allowed[index]))) return false;
        }
        if (params.task !== "cmd" || params.action !== "lootPanelRecovery"
                || typeof params.chestSessionId != "string"
                || !isSafeToken(String(params.chestSessionId), 96)
                || typeof params.lootContainerId != "string"
                || !isSafeToken(String(params.lootContainerId), 96)
                || !isPositiveWhole(params.containerEpoch)
                || !isPositiveWhole(params.openAttemptSeq)
                || Number(params.openAttemptSeq) > 2147483647
                || typeof params.recoveryNonce != "string"
                || !isSafeOpaque(String(params.recoveryNonce), 128)) return false;
        return params.reason === "web_mount_failed" || params.reason === "web_open_failed";
    }

    private static function hasOwnField(target:Object, key:String):Boolean {
        return target != null && typeof target.hasOwnProperty == "function"
            && target.hasOwnProperty(key);
    }

    private static function isWhole(value):Boolean {
        return typeof value == "number" && (value - value) == 0 && Math.floor(value) == value;
    }

    private static function isPositiveWhole(value):Boolean {
        return isWhole(value) && Number(value) > 0 && Number(value) <= MAX_SAFE_INTEGER;
    }

    private static function isSafeToken(value:String, maxLength:Number):Boolean {
        if (value == undefined || value.length < 1 || value.length > maxLength) return false;
        for (var i:Number = 0; i < value.length; i++) {
            var code:Number = value.charCodeAt(i);
            var valid:Boolean = (code >= 48 && code <= 57)
                || (code >= 65 && code <= 90) || (code >= 97 && code <= 122)
                || code == 45 || code == 46 || code == 58 || code == 95;
            if (!valid) return false;
        }
        return true;
    }

    /** Host 生成的不透明 correlation token；与 C# IsOpaque 字符集保持一致。 */
    private static function isSafeOpaque(value:String, maxLength:Number):Boolean {
        if (value == undefined || value.length < 1 || value.length > maxLength) return false;
        for (var i:Number = 0; i < value.length; i++) {
            var code:Number = value.charCodeAt(i);
            var valid:Boolean = (code >= 48 && code <= 57)
                || (code >= 65 && code <= 90) || (code >= 97 && code <= 122)
                || code == 45 || code == 46 || code == 95 || code == 126;
            if (!valid) return false;
        }
        return true;
    }
}
