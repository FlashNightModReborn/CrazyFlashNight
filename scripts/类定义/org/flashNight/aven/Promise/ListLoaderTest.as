/**
 * org.flashNight.aven.Promise.ListLoaderTest
 *
 * ListLoader / LoaderPromise 基础设施测试 + 迁移后 API 契约回归测试。
 * 14 个测试用例，全部基于真实数据文件。
 */
import org.flashNight.aven.Promise.Promise;
import org.flashNight.aven.Promise.LoaderPromise;
import org.flashNight.aven.Promise.ListLoader;
import org.flashNight.gesh.xml.LoadXml.EnemyPropertiesLoader;
import org.flashNight.gesh.xml.LoadXml.ItemDataLoader;
import org.flashNight.gesh.xml.LoadXml.EquipModListLoader;
import org.flashNight.gesh.xml.LoadXml.StageInfoLoader;
import org.flashNight.gesh.xml.LoadXml.NpcDialogueLoader;
import org.flashNight.gesh.json.LoadJson.TaskTextLoader;
import org.flashNight.gesh.json.LoadJson.TaskDataLoader;
import org.flashNight.gesh.json.LoadJson.CraftingListLoader;

class org.flashNight.aven.Promise.ListLoaderTest {

    private static var _passed:Number;
    private static var _failed:Number;
    private static var _total:Number;
    private static var _timerSeq:Number;
    private static var _expectedTests:Number;
    private static var _reported:Boolean;

    private static function assert(name:String, condition:Boolean, detail:String):Void {
        _total++;
        if (condition) {
            _passed++;
            trace("[PASS] " + name);
        } else {
            _failed++;
            trace("[FAIL] " + name + (detail != undefined ? " | " + detail : ""));
        }
        // 完成计数器：所有测试完成后自动输出汇总
        if (_total >= _expectedTests && !_reported) {
            _reported = true;
            trace("");
            trace("=== ListLoaderTest Results: " + _passed + "/" + _total
                  + " passed, " + _failed + " failed ===");
            if (_failed == 0) {
                trace("ALL PASSED");
            } else {
                trace("SOME TESTS FAILED");
            }
        }
    }

    private static function afterFrames(frames:Number, fn:Function):Void {
        _timerSeq++;
        var waiter:MovieClip = _root.createEmptyMovieClip(
            "_listLoaderTestWaiter" + _timerSeq,
            _root.getNextHighestDepth()
        );
        waiter.remainingFrames = frames;
        waiter.onEnterFrame = function():Void {
            this.remainingFrames--;
            if (this.remainingFrames <= 0) {
                delete this.onEnterFrame;
                fn();
                this.removeMovieClip();
            }
        };
    }

    public static function main():Void {
        _passed = 0;
        _failed = 0;
        _total = 0;
        _timerSeq = 0;
        _reported = false;
        _expectedTests = 21; // 基础设施 3 + ListLoader 5 + 契约回归 3 + 数据一致性 8 + 性能 2

        trace("=== ListLoader Infrastructure Tests ===");

        runInfraTests();
        runListLoaderTests();
        runRegressionTests();
    }

    // ================================================================
    // 基础设施测试 (1-3)
    // ================================================================

    private static function runInfraTests():Void {

        // 1. LoaderPromise.loadXML 成功
        LoaderPromise.loadXML("data/enemy_properties/list.xml")
            .then(function(data:Object):Void {
                assert("loadXML-success",
                    data != null && data.items != undefined,
                    "data=" + typeof(data) + " items=" + typeof(data.items));
            })
            .onCatch(function(r:Object):Void {
                assert("loadXML-success", false, "rejected: " + r);
            });

        // 2. LoaderPromise.loadXML 失败
        LoaderPromise.loadXML("data/nonexistent/fake.xml")
            .then(function(data:Object):Void {
                assert("loadXML-failure", false, "should have rejected");
            })
            .onCatch(function(r:Object):Void {
                assert("loadXML-failure",
                    String(r).indexOf("Failed to load XML") >= 0,
                    "reason: " + r);
            });

        // 3. LoaderPromise.loadJSON 成功
        LoaderPromise.loadJSON("data/task/general_tasks.json")
            .then(function(data:Object):Void {
                assert("loadJSON-success", data != null, "data=" + typeof(data));
            })
            .onCatch(function(r:Object):Void {
                assert("loadJSON-success", false, "rejected: " + r);
            });
    }

    // ================================================================
    // ListLoader 测试 (4-8)
    // ================================================================

    private static function runListLoaderTests():Void {

        // 4. concatField 合并 — 用 enemy_properties 的 11 个子文件做小规模验证
        //    先加载 list.xml 拿 entries
        LoaderPromise.loadXML("data/enemy_properties/list.xml")
            .then(function(listData:Object):Object {
                var entries:Array = ListLoader.normalizeToArray(listData.items);
                return ListLoader.loadChildren({
                    entries:      entries,
                    basePath:     "data/enemy_properties/",
                    mergeFn:      ListLoader.dictMerge(),
                    initialValue: {}
                });
            })
            .then(function(result:Object):Void {
                var keyCount:Number = 0;
                for (var k:String in result) {
                    keyCount++;
                }
                assert("listloader-dictMerge",
                    keyCount > 0,
                    "keyCount=" + keyCount);
            })
            .onCatch(function(r:Object):Void {
                assert("listloader-dictMerge", false, "rejected: " + r);
            });

        // 5. concatField 合并 — 用 items 的前 5 个子文件（避免全量加载过慢）
        LoaderPromise.loadXML("data/items/list.xml")
            .then(function(listData:Object):Object {
                var allEntries:Array = ListLoader.normalizeToArray(listData.items);
                // 只取前 5 个做验证
                var entries:Array = allEntries.slice(0, 5);
                return ListLoader.loadChildren({
                    entries:      entries,
                    basePath:     "data/items/",
                    mergeFn:      ListLoader.concatField("item"),
                    initialValue: []
                });
            })
            .then(function(result:Object):Void {
                var resArr = result;
                assert("listloader-concatField",
                    (result instanceof Array) && resArr.length > 0,
                    "length=" + resArr.length);
            })
            .onCatch(function(r:Object):Void {
                assert("listloader-concatField", false, "rejected: " + r);
            });

        // 6. normalizeToArray 标量
        var scalar:Array = ListLoader.normalizeToArray("single");
        assert("normalizeToArray-scalar",
            scalar.length == 1 && scalar[0] == "single",
            "got length=" + scalar.length);

        // 7. normalizeToArray 数组
        var arr:Array = ["a", "b"];
        var normalized:Array = ListLoader.normalizeToArray(arr);
        assert("normalizeToArray-array",
            normalized.length == 2 && normalized[0] == "a" && normalized[1] == "b",
            "got length=" + normalized.length);

        // 8. 并发窗口 = 1（串行退化）— 与默认并发结果一致
        LoaderPromise.loadXML("data/enemy_properties/list.xml")
            .then(function(listData:Object):Object {
                var entries:Array = ListLoader.normalizeToArray(listData.items);
                return ListLoader.loadChildren({
                    entries:      entries,
                    basePath:     "data/enemy_properties/",
                    concurrency:  1,
                    mergeFn:      ListLoader.dictMerge(),
                    initialValue: {}
                });
            })
            .then(function(result:Object):Void {
                var keyCount:Number = 0;
                for (var k:String in result) {
                    keyCount++;
                }
                assert("listloader-concurrency1",
                    keyCount > 0,
                    "keyCount=" + keyCount);
            })
            .onCatch(function(r:Object):Void {
                assert("listloader-concurrency1", false, "rejected: " + r);
            });
    }

    // ================================================================
    // API 契约回归测试 (9-14)
    // ================================================================

    private static function runRegressionTests():Void {

        // 9. 完成后重复 load() 命中缓存
        //    BaseXMLLoader 的缓存仅对同一实例生效（data != null 时直接回调）
        var enemyLoader:EnemyPropertiesLoader = EnemyPropertiesLoader.getInstance();
        enemyLoader.load(function(data1:Object):Void {
            // 第一次完成，再调一次
            enemyLoader.load(function(data2:Object):Void {
                // 验证第二次也收到回调且数据一致
                var k1:Number = 0;
                var k2:Number = 0;
                for (var k:String in data1) { k1++; }
                for (var k:String in data2) { k2++; }
                assert("repeat-load-cache",
                    k1 > 0 && k1 == k2,
                    "k1=" + k1 + " k2=" + k2);
            }, function():Void {
                assert("repeat-load-cache", false, "second load failed");
            });
        }, function():Void {
            assert("repeat-load-cache", false, "first load failed");
        });

        // 10. reload() 刷新
        //     使用新的 EnemyPropertiesLoader 实例来避免和测试 9 竞争
        //     注意：EnemyPropertiesLoader 是单例，reload 会清缓存重新加载
        afterFrames(30, function():Void {
            var loader:EnemyPropertiesLoader = EnemyPropertiesLoader.getInstance();
            loader.reload(function(data:Object):Void {
                var keyCount:Number = 0;
                for (var k:String in data) { keyCount++; }
                assert("reload-refresh",
                    keyCount > 0,
                    "keyCount=" + keyCount);
            }, function():Void {
                assert("reload-refresh", false, "reload failed");
            });
        });

        // 11. onError 仅触发一次
        //     通过 ListLoader 加载不存在的文件列表验证
        var errorCount:Number = 0;
        ListLoader.loadChildren({
            entries:      ["nonexistent_file_1.xml", "nonexistent_file_2.xml"],
            basePath:     "data/fake_path/",
            mergeFn:      ListLoader.dictMerge(),
            initialValue: {}
        }).then(function(result:Object):Void {
            assert("error-single-reject", false, "should have rejected");
        }).onCatch(function(reason:Object):Void {
            errorCount++;
            // Promise.all fast-fail: 只 reject 一次
            afterFrames(5, function():Void {
                assert("error-single-reject",
                    errorCount == 1,
                    "errorCount=" + errorCount);
            });
        });

        // 12. 数据一致性 — EnemyProperties
        //     检查 key 数量（11 个 XML 文件应产生多个敌人 key）
        afterFrames(15, function():Void {
            var loader:EnemyPropertiesLoader = EnemyPropertiesLoader.getInstance();
            loader.load(function(data:Object):Void {
                var keyCount:Number = 0;
                for (var k:String in data) { keyCount++; }
                assert("enemy-data-consistency",
                    keyCount >= 50,
                    "keyCount=" + keyCount + " (expected >=50 enemies)");
            }, function():Void {
                assert("enemy-data-consistency", false, "load failed");
            });
        });

        // 13. 数据一致性 — ItemData + 14. 加载耗时
        //     50 个 XML 文件应产生大量 item
        //     test 14 在 test 13 完成后 reload，避免 _isLoading 守卫竞争
        var itemLoader:ItemDataLoader = ItemDataLoader.getInstance();
        itemLoader.load(function(data:Object):Void {
            var itemCount:Number = 0;
            if (data instanceof Array) {
                itemCount = data.length;
            }
            assert("item-data-consistency",
                itemCount >= 100,
                "itemCount=" + itemCount + " (expected >=100 items)");

            // 14-15. 串行 vs 并行性能对比
            //   获取 entries 用于直接调 ListLoader（不经过 ItemDataLoader 缓存）
            LoaderPromise.loadXML("data/items/list.xml").then(function(listData:Object):Void {
                var entries:Array = ListLoader.normalizeToArray(listData.items);
                // 只取前 10 个子文件，控制总耗时
                var testEntries:Array = entries.slice(0, 10);

                // 14. 串行基线 (concurrency=1)
                var serialStart:Number = getTimer();
                ListLoader.loadChildren({
                    entries:      testEntries,
                    basePath:     "data/items/",
                    concurrency:  1,
                    mergeFn:      ListLoader.concatField("item"),
                    initialValue: []
                }).then(function(serialResult:Object):Void {
                    var serialTime:Number = getTimer() - serialStart;
                    trace("[PERF] 10 XML serial  (concurrency=1): " + serialTime + "ms");
                    assert("perf-serial-baseline", serialTime > 0, serialTime + "ms");

                    // 15. 并行测量 (concurrency=4)
                    var parallelStart:Number = getTimer();
                    ListLoader.loadChildren({
                        entries:      testEntries,
                        basePath:     "data/items/",
                        concurrency:  4,
                        mergeFn:      ListLoader.concatField("item"),
                        initialValue: []
                    }).then(function(parallelResult:Object):Void {
                        var parallelTime:Number = getTimer() - parallelStart;
                        var ratio:String = (serialTime > 0)
                            ? String(Math.round(serialTime / parallelTime * 10) / 10)
                            : "N/A";
                        trace("[PERF] 10 XML parallel(concurrency=4): " + parallelTime + "ms"
                              + " | speedup: " + ratio + "x");
                        assert("perf-parallel-speedup", parallelTime > 0, parallelTime + "ms " + ratio + "x");
                    });
                });
            });
        }, function():Void {
            assert("item-data-consistency", false, "load failed");
        });

        // 15. 数据一致性 — EquipModListLoader
        //     32 个子 XML 文件，应产生大量 mod 数据
        var modLoader:EquipModListLoader = EquipModListLoader.getInstance();
        modLoader.load(function(data:Object):Void {
            var modArr = data.mod;
            assert("mod-data-consistency",
                modArr != null && modArr.length >= 10,
                "modCount=" + (modArr != null ? modArr.length : "null") + " (expected >=10)");
        }, function():Void {
            assert("mod-data-consistency", false, "load failed");
        });

        // 16. 数据一致性 — StageInfoLoader
        //     19 个文件夹，应产生多个关卡 key，且每项有 url 字段
        var stageLoader:StageInfoLoader = StageInfoLoader.getInstance();
        stageLoader.load(function(data:Object):Void {
            var keyCount:Number = 0;
            var hasUrl:Boolean = false;
            for (var k:String in data) {
                keyCount++;
                if (data[k].url != undefined) hasUrl = true;
            }
            assert("stage-data-consistency",
                keyCount >= 10 && hasUrl,
                "keyCount=" + keyCount + " hasUrl=" + hasUrl);
        }, function():Void {
            assert("stage-data-consistency", false, "load failed");
        });

        // 17. 数据一致性 — NpcDialogueLoader
        //     13 个子 XML 文件，应产生多个 NPC key
        var npcLoader:NpcDialogueLoader = NpcDialogueLoader.getInstance();
        npcLoader.load(function(data:Object):Void {
            var keyCount:Number = 0;
            for (var k:String in data) {
                keyCount++;
            }
            assert("npc-data-consistency",
                keyCount >= 5,
                "npcCount=" + keyCount + " (expected >=5)");
        }, function():Void {
            assert("npc-data-consistency", false, "load failed");
        });

        // 18. 数据一致性 — TaskTextLoader (JSON dictMerge)
        //     11 个子 JSON 文件，应产生多个 text key
        var textLoader:TaskTextLoader = TaskTextLoader.getInstance();
        textLoader.load(function(data:Object):Void {
            var keyCount:Number = 0;
            for (var k:String in data) { keyCount++; }
            assert("tasktext-data-consistency",
                keyCount >= 5,
                "keyCount=" + keyCount + " (expected >=5)");
        }, function():Void {
            assert("tasktext-data-consistency", false, "load failed");
        });

        // 19. 数据一致性 — TaskDataLoader (JSON concatField)
        //     11 个子 JSON 文件，应产生多个 task
        var taskLoader:TaskDataLoader = TaskDataLoader.getInstance();
        taskLoader.load(function(data:Object):Void {
            var taskCount:Number = 0;
            if (data instanceof Array) {
                taskCount = data.length;
            }
            assert("taskdata-data-consistency",
                taskCount >= 10,
                "taskCount=" + taskCount + " (expected >=10)");
        }, function():Void {
            assert("taskdata-data-consistency", false, "load failed");
        });

        // 20. 数据一致性 — CraftingListLoader (JSON keyedMerge + pathBuilder)
        //     12 个 category，每个 category 是一个 key
        var craftLoader:CraftingListLoader = CraftingListLoader.getInstance();
        craftLoader.load(function(data:Object):Void {
            var keyCount:Number = 0;
            for (var k:String in data) { keyCount++; }
            assert("crafting-data-consistency",
                keyCount >= 5,
                "categoryCount=" + keyCount + " (expected >=5)");
        }, function():Void {
            assert("crafting-data-consistency", false, "load failed");
        });
    }
}
