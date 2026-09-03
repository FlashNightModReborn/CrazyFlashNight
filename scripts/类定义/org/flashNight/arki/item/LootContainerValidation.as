/** LootContainerService 的纯 payload shape 验证，独立成类以规避 AS2 单类 32K branch 上限。 */
class org.flashNight.arki.item.LootContainerValidation {
    private static var MAX_SAFE_INTEGER:Number = 9007199254740991;

    public static function validateCommandShape(commandName:String, params:Object):Boolean {
        var allowed:Array = ["task", "action", "callId", "v", "chestSessionId",
            "lootContainerId", "containerEpoch", "sourceKind"];
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
            allowed.push("previousTerminalRootOperationId");
        } else if (commandName == "claimBatch") {
            expectedAction = "lootClaimBatch";
            allowed.push("expectedAuthorityRevision"); allowed.push("operationId");
            allowed.push("direction"); allowed.push("sources"); allowed.push("targetContainerId");
            allowed.push("previousTerminalRootOperationId");
        } else if (commandName == "close") {
            expectedAction = "lootClose";
            allowed.push("expectedAuthorityRevision"); allowed.push("operationId");
            allowed.push("closeLease"); allowed.push("abandon");
        } else if (commandName == "query") {
            expectedAction = "lootQuery";
            allowed.push("openAttemptSeq"); allowed.push("recoveryNonce");
            allowed.push("rootOperationId");
            allowed.push("acknowledgeTerminalRootOperationId");
        } else if (commandName == "materials") {
            expectedAction = "lootMaterials";
            allowed.push("expectedAuthorityRevision");
        } else return false;
        if (!hasOnlyKeys(params, allowed) || !hasOwnField(params, "v")) return false;
        if (hasOwnField(params, "sourceKind")
                && (params.sourceKind !== "reward_inbox"
                    || commandName == "materials")) return false;
        if (params.sourceKind === "reward_inbox") {
            if ((commandName == "claim" || commandName == "claimBatch")
                    && !hasOwnField(params, "previousTerminalRootOperationId")) return false;
            if (commandName == "query" && !hasOwnField(params, "rootOperationId")) return false;
        } else if (hasOwnField(params, "previousTerminalRootOperationId")
                || hasOwnField(params, "rootOperationId")
                || hasOwnField(params, "acknowledgeTerminalRootOperationId")) return false;
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
        var initData:Object = {
            v:1,
            chestSessionId:record.chestSessionId,
            lootContainerId:record.lootContainerId,
            containerEpoch:record.containerEpoch,
            openAttemptSeq:record.openAttemptSeq,
            displayName:record.presetName,
            capacity:record.inventory.capacity,
            columns:record.col
        };
        if (source == "stage_settlement") {
            initData.sourceKind = "stage_settlement";
            initData.report = record.report;
        }
        return {
            panel:"loot",
            source:source,
            initData:initData
        };
    }

    /** 关卡结算报告是随 panel admission 冻结的只读投影；奖励写仍只认 loot authority。 */
    public static function validateSettlementReport(report:Object):Boolean {
        var keys:Array = ["v", "runId", "stageName", "difficulty", "outcome",
            "activeFrames", "totalKills", "omittedKillTypes", "totalItemGains",
            "totalItemLosses", "omittedItemFlowTypes", "rewardRollOmissions",
            "kills", "itemFlows"];
        if (!hasOnlyKeys(report, keys)) return false;
        for (var i:Number = 0; i < keys.length; i++) {
            if (!hasOwnField(report, String(keys[i]))) return false;
        }
        if (report.v !== 1
                || typeof report.runId != "string"
                || !isSafeToken(String(report.runId), 96)
                || typeof report.stageName != "string"
                || !isSafeText(String(report.stageName), 96)
                || String(report.stageName).length < 1
                || typeof report.difficulty != "string"
                || !isSafeText(String(report.difficulty), 48)
                || String(report.difficulty).length < 1
                || (report.outcome !== "victory" && report.outcome !== "failure"
                    && report.outcome !== "retreat")
                || !isNonNegativeWhole(report.activeFrames)
                || Number(report.activeFrames) > MAX_SAFE_INTEGER
                || !isNonNegativeWhole(report.totalKills)
                || Number(report.totalKills) > MAX_SAFE_INTEGER
                || !isNonNegativeWhole(report.omittedKillTypes)
                || Number(report.omittedKillTypes) > MAX_SAFE_INTEGER
                || !isNonNegativeWhole(report.totalItemGains)
                || Number(report.totalItemGains) > MAX_SAFE_INTEGER
                || !isNonNegativeWhole(report.totalItemLosses)
                || Number(report.totalItemLosses) > MAX_SAFE_INTEGER
                || !isNonNegativeWhole(report.omittedItemFlowTypes)
                || Number(report.omittedItemFlowTypes) > MAX_SAFE_INTEGER
                || !isNonNegativeWhole(report.rewardRollOmissions)
                || Number(report.rewardRollOmissions) > MAX_SAFE_INTEGER
                || !(report.kills instanceof Array)
                || report.kills.length > 96
                || !(report.itemFlows instanceof Array)
                || report.itemFlows.length > 96) return false;
        var projectedKills:Number = 0;
        for (i = 0; i < report.kills.length; i++) {
            if (!validateSettlementKill(report.kills[i])) return false;
            projectedKills += Number(report.kills[i].count);
            if (projectedKills > Number(report.totalKills)) return false;
        }
        var projectedGains:Number = 0;
        var projectedLosses:Number = 0;
        for (i = 0; i < report.itemFlows.length; i++) {
            var flow:Object = report.itemFlows[i];
            if (!validateSettlementItemFlow(flow)) return false;
            if (flow.direction == "gain") {
                projectedGains += Number(flow.count);
                if (projectedGains > Number(report.totalItemGains)) return false;
            } else {
                projectedLosses += Number(flow.count);
                if (projectedLosses > Number(report.totalItemLosses)) return false;
            }
        }
        return true;
    }

    private static function validateSettlementKill(kill:Object):Boolean {
        var keys:Array = ["key", "displayName", "iconName", "doll", "eliteLevel", "count"];
        if (!hasOnlyKeys(kill, keys)) return false;
        for (var i:Number = 0; i < keys.length; i++) {
            if (!hasOwnField(kill, String(keys[i]))) return false;
        }
        if (typeof kill.key != "string" || !isSafeText(String(kill.key), 128)
                || String(kill.key).length < 1
                || typeof kill.displayName != "string"
                || !isSafeText(String(kill.displayName), 96)
                || String(kill.displayName).length < 1
                || typeof kill.iconName != "string"
                || !isSafeText(String(kill.iconName), 128)
                || !isNonNegativeWhole(kill.eliteLevel)
                || Number(kill.eliteLevel) > 16
                || !isPositiveWhole(kill.count)
                || Number(kill.count) > MAX_SAFE_INTEGER) return false;
        if (kill.doll === null) return true;
        var dollKeys:Array = ["face", "hair", "mask", "head", "body", "leg", "hand",
            "foot", "neck", "gender"];
        if (!hasOnlyKeys(kill.doll, dollKeys)) return false;
        for (i = 0; i < dollKeys.length; i++) {
            var key:String = String(dollKeys[i]);
            if (!hasOwnField(kill.doll, key) || typeof kill.doll[key] != "string"
                    || !isSafeText(String(kill.doll[key]), 128)) return false;
        }
        return true;
    }

    private static function validateSettlementItemFlow(flow:Object):Boolean {
        var keys:Array = ["direction", "kind", "itemKey", "displayName", "iconName",
            "tier", "source", "reason", "count"];
        if (!hasOnlyKeys(flow, keys)) return false;
        for (var i:Number = 0; i < keys.length; i++) {
            if (!hasOwnField(flow, String(keys[i]))) return false;
        }
        var kind:String = String(flow.kind);
        return (flow.direction === "gain" || flow.direction === "loss")
            && (kind == "money" || kind == "kpoint" || kind == "intel"
                || kind == "material" || kind == "item" || kind == "equip")
            && typeof flow.itemKey == "string"
            && isSafeText(String(flow.itemKey), 128)
            && String(flow.itemKey).length > 0
            && typeof flow.displayName == "string"
            && isSafeText(String(flow.displayName), 96)
            && String(flow.displayName).length > 0
            && typeof flow.iconName == "string"
            && isSafeText(String(flow.iconName), 128)
            && typeof flow.tier == "string"
            && isSafeText(String(flow.tier), 48)
            && typeof flow.source == "string"
            && isSafeText(String(flow.source), 48)
            && String(flow.source).length > 0
            && typeof flow.reason == "string"
            && isSafeText(String(flow.reason), 64)
            && isPositiveWhole(flow.count)
            && Number(flow.count) <= MAX_SAFE_INTEGER;
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
            "containerEpoch", "openAttemptSeq", "recoveryNonce", "reason",
            "sourceKind"];
        if (!hasOnlyKeys(params, allowed)) return false;
        for (var index:Number = 0; index < 8; index++) {
            if (!hasOwnField(params, String(allowed[index]))) return false;
        }
        if (hasOwnField(params, "sourceKind")
                && params.sourceKind !== "reward_inbox") return false;
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

    private static function isNonNegativeWhole(value):Boolean {
        return isWhole(value) && Number(value) >= 0;
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

    private static function isSafeText(value:String, maxLength:Number):Boolean {
        if (value == undefined || value.length > maxLength) return false;
        for (var i:Number = 0; i < value.length; i++) {
            var code:Number = value.charCodeAt(i);
            if (code < 32 || code == 127) return false;
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
