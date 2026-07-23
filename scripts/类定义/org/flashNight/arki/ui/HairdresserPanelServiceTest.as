

import org.flashNight.arki.ui.HairdresserPanelService;

/** HairdresserPanelService 的目录、免费门、原子写与 wire 回归测试。 */
class org.flashNight.arki.ui.HairdresserPanelServiceTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;

    public static function runAllTests():Void {
        passed = 0;
        failed = 0;
        setup();
        testSnapshotPreservesAuthorityCatalog();
        testVersionAndCommandGate();
        testPricingGateHasNoWrite();
        testCatalogGateHasNoWrite();
        testCommitPreconditionsHaveNoWrite();
        testCommitWritesAndRefreshesOnce();
        testResponseEnvelope();
        trace("HairdresserPanelServiceTest Tests Passed: " + passed);
        trace("HairdresserPanelServiceTest Tests Failed: " + failed);
    }

    private static function setup():Void {
        if (_root.gameCommands == undefined) _root.gameCommands = {};
        HairdresserPanelService.install();
        resetState();
    }

    private static function resetState():Void {
        _root.发型库 = [];
        _root.发型名称库 = [];
        _root.发型价格 = [];
        for (var i:Number = 0; i < 77; i++) {
            _root.发型库.push("测试发型-" + i);
            _root.发型名称库.push("测试发型名称-" + i);
            _root.发型价格.push(0);
        }
        _root.发型库[0] = "光头";
        _root.发型名称库[0] = "光头";
        // 生产目录当前也存在重复项；测试明确冻结顺序与重复行，不允许去重。
        _root.发型库[20] = "发型-男式-平头";
        _root.发型名称库[20] = "平头";
        _root.发型库[32] = "发型-男式-平头";
        _root.发型名称库[32] = "平头";
        _root.性别 = "女";
        _root.脸型 = "女变装-基本脸型";
        _root.发型 = "测试发型-7";
        _root.控制目标 = "testHero";
        _root.gameworld = {};
        var actor:Object = {
            发型:"测试发型-7",
            refreshCount:0,
            lastRefresh:"",
            gotoAndPlay:function(label):Void {
                this.refreshCount++;
                this.lastRefresh = String(label);
            }
        };
        _root.gameworld[_root.控制目标] = actor;
        _root.存档系统 = {
            dirtyMark:false,
            saveCalls:0,
            save:function():Void { this.saveCalls++; }
        };
        _root.金钱 = 1234;
        _root.虚拟币 = 567;
    }

    private static function actor():Object {
        return _root.gameworld[_root.控制目标];
    }

    private static function testSnapshotPreservesAuthorityCatalog():Void {
        resetState();
        var result:Object = HairdresserPanelService.execute("snapshot", {v:1});
        check(result.success && result.v == 1 && result.gender == "女"
            && result.face == "女变装-基本脸型" && result.currentHair == "测试发型-7",
            "snapshot projects version, appearance and current hair");
        check(result.catalog.length == 77
            && result.catalog[0].identifier == "光头"
            && result.catalog[76].identifier == "测试发型-76",
            "snapshot projects all 77 authority rows, including bald, in source order");
        check(result.catalog[20].identifier == "发型-男式-平头"
            && result.catalog[32].identifier == "发型-男式-平头"
            && result.catalog[20].name == "平头" && result.catalog[32].name == "平头",
            "snapshot preserves duplicate authority rows without deduplication");
        check(result.catalog[0].price == undefined,
            "snapshot does not expose or invent a payment protocol");

        _root.性别 = "未知";
        var unusualGender:Object = HairdresserPanelService.execute("snapshot", {v:1});
        check(unusualGender.gender == "未知",
            "snapshot preserves authority gender text instead of guessing a binary value");
    }

    private static function testVersionAndCommandGate():Void {
        resetState();
        var badSnapshot:Object = HairdresserPanelService.execute("snapshot", {v:2});
        var badCommit:Object = HairdresserPanelService.execute("commit", {
            hairIdentifier:"测试发型-9"
        });
        var unsupported:Object = HairdresserPanelService.execute("preview", {v:1});
        check(!badSnapshot.success && badSnapshot.error == "unsupported_version"
            && !badCommit.success && badCommit.error == "unsupported_version",
            "snapshot and commit require protocol v1");
        check(!unsupported.success && unsupported.error == "unsupported_cmd",
            "service exposes only snapshot and commit");
        check(_root.发型 == "测试发型-7" && actor().发型 == "测试发型-7"
            && !_root.存档系统.dirtyMark && actor().refreshCount == 0,
            "version and command rejection perform no write");
    }

    private static function testPricingGateHasNoWrite():Void {
        resetState();
        _root.发型价格[40] = 1;
        var snapshot:Object = HairdresserPanelService.execute("snapshot", {v:1});
        var commit:Object = HairdresserPanelService.execute("commit", {
            v:1, hairIdentifier:"测试发型-9"
        });
        check(!snapshot.success && snapshot.error == "pricing_unsupported"
            && !commit.success && commit.error == "pricing_unsupported",
            "any nonzero authority price blocks both snapshot and commit");
        check(_root.发型 == "测试发型-7" && actor().发型 == "测试发型-7"
            && !_root.存档系统.dirtyMark && actor().refreshCount == 0
            && _root.金钱 == 1234 && _root.虚拟币 == 567,
            "pricing rejection changes no appearance, dirty flag or currency");
    }

    private static function testCatalogGateHasNoWrite():Void {
        resetState();
        _root.发型名称库.pop();
        var mismatch:Object = HairdresserPanelService.execute("commit", {
            v:1, hairIdentifier:"测试发型-9"
        });
        check(!mismatch.success && mismatch.error == "catalog_invalid",
            "mismatched authority arrays fail closed");
        check(_root.发型 == "测试发型-7" && actor().发型 == "测试发型-7"
            && !_root.存档系统.dirtyMark && actor().refreshCount == 0,
            "invalid catalog performs no write");

        resetState();
        _root.发型价格[3] = Number("not-a-number");
        var invalidPrice:Object = HairdresserPanelService.execute("snapshot", {v:1});
        check(!invalidPrice.success && invalidPrice.error == "catalog_invalid",
            "nonnumeric authority price fails closed instead of becoming free");
    }

    private static function testCommitPreconditionsHaveNoWrite():Void {
        resetState();
        var unknown:Object = HairdresserPanelService.execute("commit", {
            v:1, hairIdentifier:"不存在的发型"
        });
        check(!unknown.success && unknown.error == "hair_not_found"
            && _root.发型 == "测试发型-7" && actor().发型 == "测试发型-7"
            && !_root.存档系统.dirtyMark && actor().refreshCount == 0,
            "unknown hair is rejected before any write");

        resetState();
        var originalActor:Object = actor();
        _root.gameworld[_root.控制目标] = undefined;
        var missingActor:Object = HairdresserPanelService.execute("commit", {
            v:1, hairIdentifier:"测试发型-9"
        });
        check(!missingActor.success && missingActor.error == "actor_unavailable"
            && _root.发型 == "测试发型-7" && originalActor.发型 == "测试发型-7"
            && !(_root.存档系统.dirtyMark),
            "missing live actor is rejected before root or save write");

        resetState();
        var liveActor:Object = actor();
        _root.存档系统 = undefined;
        var missingSave:Object = HairdresserPanelService.execute("commit", {
            v:1, hairIdentifier:"测试发型-9"
        });
        check(!missingSave.success && missingSave.error == "save_unavailable"
            && _root.发型 == "测试发型-7" && liveActor.发型 == "测试发型-7"
            && liveActor.refreshCount == 0,
            "missing save authority is rejected before appearance write");

        resetState();
        var noRefreshActor:Object = actor();
        noRefreshActor.gotoAndPlay = undefined;
        var missingRefresh:Object = HairdresserPanelService.execute("commit", {
            v:1, hairIdentifier:"测试发型-9"
        });
        check(!missingRefresh.success && missingRefresh.error == "refresh_unavailable"
            && _root.发型 == "测试发型-7" && noRefreshActor.发型 == "测试发型-7"
            && !_root.存档系统.dirtyMark,
            "missing dressup refresh entry is rejected before any write");
    }

    private static function testCommitWritesAndRefreshesOnce():Void {
        resetState();
        var result:Object = HairdresserPanelService.execute("commit", {
            v:1, hairIdentifier:"测试发型-9"
        });
        check(result.success && result.v == 1 && result.operation == "commit"
            && result.currentHair == "测试发型-9",
            "commit returns the written hair identifier");
        check(_root.发型 == "测试发型-9" && actor().发型 == "测试发型-9"
            && actor().refreshCount == 1 && actor().lastRefresh == "刷新装扮"
            && _root.存档系统.dirtyMark,
            "commit writes root and live actor, refreshes once and marks save dirty");
        check(_root.金钱 == 1234 && _root.虚拟币 == 567
            && _root.存档系统.saveCalls == 0,
            "commit does not charge currency or autosave");
    }

    private static function testResponseEnvelope():Void {
        resetState();
        _root.server = {sent:""};
        _root.server.sendSocketMessage = function(message:String):Boolean {
            this.sent = message;
            return true;
        };
        _root.gameCommands["hairdresserSnapshot"]({v:1, callId:41});
        var snapshot:Object = new LiteJSON().parse(String(_root.server.sent));
        check(snapshot.task == "hairdresser_response" && snapshot.callId == 41
            && snapshot.success && snapshot.v == 1 && snapshot.catalog.length == 77,
            "snapshot handler emits parseable task and callId envelope");

        _root.gameCommands["hairdresserCommit"]({
            v:1, callId:42, hairIdentifier:"测试发型-11"
        });
        var commit:Object = new LiteJSON().parse(String(_root.server.sent));
        check(commit.task == "hairdresser_response" && commit.callId == 42
            && commit.success && commit.operation == "commit"
            && commit.currentHair == "测试发型-11",
            "commit handler preserves task and callId in response envelope");
    }

    private static function check(ok:Boolean, label:String):Void {
        if (ok) {
            passed++;
            trace("[PASS] " + label);
        } else {
            failed++;
            trace("[TEST_FAIL] " + label);
        }
    }
}
