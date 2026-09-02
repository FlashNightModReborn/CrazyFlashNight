using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;
using CF7Launcher.Config;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public sealed class SettingsTaskTests
    {
        private static readonly string[] KeyIds = new[]
        {
            "上键", "下键", "左键", "右键", "A键", "B键", "C键",
            "键1", "键2", "键3", "键4", "键5",
            "药剂组切换键",
            "快捷物品栏键1", "快捷物品栏键2", "快捷物品栏键3", "快捷物品栏键4",
            "快捷技能栏键1", "快捷技能栏键2", "快捷技能栏键3", "快捷技能栏键4",
            "快捷技能栏键5", "快捷技能栏键6", "快捷技能栏键7", "快捷技能栏键8",
            "快捷技能栏键9", "快捷技能栏键10", "快捷技能栏键11", "快捷技能栏键12",
            "切换武器键", "互动键", "武器技能键", "飞行键", "武器变形键", "奔跑键", "组合键"
        };

        private sealed class Harness : IDisposable
        {
            public readonly List<string> Flash = new List<string>();
            public readonly List<JObject> Web = new List<JObject>();
            public readonly UserPrefs Prefs;
            public readonly SettingsTask Task;
            public bool SaveResult = true;
            public string PanelInstance = "settings.instance.1";

            public Harness(int timeoutMs = 10000, bool sendResult = true)
            {
                Prefs = new UserPrefs(Path.GetTempPath());
                Task = new SettingsTask(
                    delegate { return true; },
                    delegate(string payload) { Flash.Add(payload); return sendResult; },
                    Prefs,
                    delegate { return SaveResult; },
                    timeoutMs);
                Task.SetPostToWeb(delegate(string json) { Web.Add(JObject.Parse(json)); });
                Assert.True(Task.BindPanelInstance(PanelInstance));
            }

            public JObject Send(string cmd, JObject payload, string callId = "web.settings.1")
            {
                Task.HandleWebRequest(cmd, new JObject
                {
                    ["domain"] = "settings",
                    ["cmd"] = cmd,
                    ["callId"] = callId,
                    ["panelInstanceId"] = PanelInstance,
                    ["payload"] = payload
                });
                if (Flash.Count == 0) return null;
                return JObject.Parse(Flash[Flash.Count - 1].TrimEnd('\0'));
            }

            public void CaptureWebPosts()
            {
                Task.SetPostToWeb(delegate(string json) { Web.Add(JObject.Parse(json)); });
            }

            public void Dispose() { Task.Dispose(); }
        }

        [Fact]
        public void Snapshot_RoutesFlatCommand_AndInjectsAuthoritativeHostPrefs()
        {
            using (var h = new Harness())
            {
                h.Prefs.IntroEnabled = true;
                h.Prefs.SfxEnabled = false;
                h.Prefs.MapDisplayPreference = "compact";
                h.Prefs.HitNumberMode = "detail";
                h.Prefs.HitNumberWorldRowLimit = 0;
                JObject sent = h.Send("snapshot", new JObject { ["v"] = 1 });
                Assert.NotNull(sent);
                Assert.Equal("cmd", sent.Value<string>("task"));
                Assert.Equal("settingsSnapshot", sent.Value<string>("action"));
                Assert.Equal(1, sent.Value<int>("v"));
                Assert.Null(sent["payload"]);

                int fid = sent.Value<int>("callId");
                JObject response = SnapshotResponse(fid);
                h.Task.HandleFlashResponse(response, delegate { });
                JObject web = Assert.Single(h.Web);
                Assert.Equal("panel_resp", web.Value<string>("type"));
                Assert.Equal("settings", web.Value<string>("domain"));
                Assert.Equal("settings.instance.1", web.Value<string>("panelInstanceId"));
                Assert.True(web["hostPrefs"].Value<bool>("introEnabled"));
                Assert.False(web["hostPrefs"].Value<bool>("sfxEnabled"));
                Assert.Equal("compact", web["hostPrefs"].Value<string>("mapDisplayPreference"));
                Assert.Equal("detail", web["hostPrefs"].Value<string>("hitNumberMode"));
                Assert.Equal(0, web["hostPrefs"].Value<int>("hitNumberWorldRowLimit"));
                Assert.Equal(2, web.Value<int>("keySchemaVersion"));
                Assert.Equal(36, ((JArray)web["keys"]).Count);
                Assert.Equal(string.Empty, web.Value<string>("keyMigrationNotice"));
            }
        }

        [Fact]
        public void Snapshot_RequiresSchemaTwoAndAlwaysBoundedMigrationNotice()
        {
            using (var conflict = new Harness())
            {
                JObject sent = conflict.Send("snapshot", new JObject { ["v"] = 1 });
                JObject response = SnapshotResponse(sent.Value<int>("callId"));
                response["keyMigrationNotice"] =
                    "已保留原有数字 6 绑定；药剂组切换已分配为 T。";
                conflict.Task.HandleFlashResponse(response, delegate { });
                Assert.Equal(response.Value<string>("keyMigrationNotice"),
                    Assert.Single(conflict.Web).Value<string>("keyMigrationNotice"));
            }

            using (var missingSchema = new Harness())
            {
                JObject sent = missingSchema.Send("snapshot", new JObject { ["v"] = 1 });
                JObject response = SnapshotResponse(sent.Value<int>("callId"));
                response.Remove("keySchemaVersion");
                missingSchema.Task.HandleFlashResponse(response, delegate { });
                Assert.Equal("malformed_response",
                    Assert.Single(missingSchema.Web).Value<string>("error"));
            }

            using (var missingNotice = new Harness())
            {
                JObject sent = missingNotice.Send("snapshot", new JObject { ["v"] = 1 });
                JObject response = SnapshotResponse(sent.Value<int>("callId"));
                response.Remove("keyMigrationNotice");
                missingNotice.Task.HandleFlashResponse(response, delegate { });
                Assert.Equal("malformed_response",
                    Assert.Single(missingNotice.Web).Value<string>("error"));
            }

            using (var oversizedNotice = new Harness())
            {
                JObject sent = oversizedNotice.Send("snapshot", new JObject { ["v"] = 1 });
                JObject response = SnapshotResponse(sent.Value<int>("callId"));
                response["keyMigrationNotice"] = new string('x', 161);
                oversizedNotice.Task.HandleFlashResponse(response, delegate { });
                Assert.Equal("malformed_response",
                    Assert.Single(oversizedNotice.Web).Value<string>("error"));
            }
        }

        [Fact]
        public void Apply_RequiresSchemaTwoAndAllThirtySixUniqueKeys_AndPerformanceZeroOrOne()
        {
            using (var h = new Harness())
            {
                JObject payload = ApplyPayload();
                JObject sent = h.Send("apply", payload);
                Assert.NotNull(sent);
                Assert.Equal("settingsApply", sent.Value<string>("action"));
                Assert.Equal(2, sent.Value<int>("keySchemaVersion"));
                Assert.Equal(36, ((JArray)sent["keys"]).Count);
                Assert.Equal(1, sent["settings"].Value<int>("性能等级上限"));
                JObject applied = SnapshotResponse(sent.Value<int>("callId"));
                applied["operation"] = "apply";
                applied["applied"] = true;
                applied["durable"] = true;
                applied["migrationPending"] = false;
                h.Task.HandleFlashResponse(applied, delegate { });
                Assert.True(Assert.Single(h.Web).Value<bool>("applied"));

                using (var duplicate = new Harness())
                {
                    JObject invalid = ApplyPayload();
                    invalid["keys"][35]["keyCode"] = invalid["keys"][34]["keyCode"];
                    Assert.Null(duplicate.Send("apply", invalid));
                    Assert.Equal("invalid_payload", Assert.Single(duplicate.Web).Value<string>("error"));
                }
                using (var missingSchema = new Harness())
                {
                    JObject invalid = ApplyPayload();
                    invalid.Remove("keySchemaVersion");
                    Assert.Null(missingSchema.Send("apply", invalid));
                    Assert.Equal("invalid_payload",
                        Assert.Single(missingSchema.Web).Value<string>("error"));
                }
                using (var wrongSchema = new Harness())
                {
                    JObject invalid = ApplyPayload();
                    invalid["keySchemaVersion"] = 1;
                    Assert.Null(wrongSchema.Send("apply", invalid));
                    Assert.Equal("invalid_payload",
                        Assert.Single(wrongSchema.Web).Value<string>("error"));
                }
                using (var legacyPerformance = new Harness())
                {
                    JObject invalid = ApplyPayload();
                    invalid["settings"]["性能等级上限"] = 2;
                    Assert.Null(legacyPerformance.Send("apply", invalid));
                    Assert.Equal("invalid_payload", Assert.Single(legacyPerformance.Web).Value<string>("error"));
                }
            }
        }

        [Fact]
        public void HostSet_SavesImmediately_NotifiesObserver_AndRollsBackOnFailure()
        {
            using (var h = new Harness())
            {
                string appliedKey = null;
                JToken appliedValue = null;
                h.Task.SetHostPreferenceApplied(delegate(string key, JToken value)
                {
                    appliedKey = key;
                    appliedValue = value;
                });
                h.Send("host_set", new JObject
                {
                    ["v"] = 1, ["key"] = "mapDisplayPreference", ["value"] = "expanded"
                });
                Assert.Empty(h.Flash);
                Assert.Equal("expanded", h.Prefs.MapDisplayPreference);
                Assert.Equal("mapDisplayPreference", appliedKey);
                Assert.Equal("expanded", appliedValue.Value<string>());
                Assert.True(Assert.Single(h.Web).Value<bool>("success"));

                h.Send("host_set", new JObject
                {
                    ["v"] = 1, ["key"] = "hitNumberMode", ["value"] = "off"
                }, "web.settings.hit-mode");
                Assert.Equal("off", h.Prefs.HitNumberMode);
                Assert.Equal("off", h.Web[1].Value<string>("currentValue"));

                h.Send("host_set", new JObject
                {
                    ["v"] = 1, ["key"] = "hitNumberWorldRowLimit", ["value"] = 0
                }, "web.settings.hit-limit");
                Assert.Equal(0, h.Prefs.HitNumberWorldRowLimit);
                Assert.Equal(0, h.Web[2].Value<int>("currentValue"));

                h.SaveResult = false;
                h.Send("host_set", new JObject
                {
                    ["v"] = 1, ["key"] = "hitNumberMode", ["value"] = "detail"
                }, "web.settings.hit-rollback");
                Assert.Equal("off", h.Prefs.HitNumberMode);
                Assert.Equal("save_failed", h.Web[3].Value<string>("error"));
                Assert.Equal("off", h.Web[3].Value<string>("currentValue"));
            }
        }

        [Fact]
        public void HostSet_RejectsUnknownHitModeAndOutOfRangeOrFractionalLimit()
        {
            using (var h = new Harness())
            {
                string originalMode = h.Prefs.HitNumberMode;
                int originalLimit = h.Prefs.HitNumberWorldRowLimit;
                JToken[] invalidModes = { new JValue("summary"), new JValue("Balanced"), new JValue(1) };
                for (int i = 0; i < invalidModes.Length; i++)
                {
                    h.Send("host_set", new JObject
                    {
                        ["v"] = 1,
                        ["key"] = "hitNumberMode",
                        ["value"] = invalidModes[i]
                    }, "web.settings.hit-mode-invalid-" + i);
                    Assert.Equal("bad_value", h.Web[i].Value<string>("error"));
                    Assert.Equal(originalMode, h.Prefs.HitNumberMode);
                }

                JToken[] invalidLimits = { new JValue(-1), new JValue(1001), new JValue(2.5), new JValue("24") };
                for (int i = 0; i < invalidLimits.Length; i++)
                {
                    h.Send("host_set", new JObject
                    {
                        ["v"] = 1,
                        ["key"] = "hitNumberWorldRowLimit",
                        ["value"] = invalidLimits[i]
                    }, "web.settings.hit-limit-invalid-" + i);
                    Assert.Equal("bad_value", h.Web[invalidModes.Length + i].Value<string>("error"));
                    Assert.Equal(originalLimit, h.Prefs.HitNumberWorldRowLimit);
                }
            }
        }

        [Theory]
        [InlineData("classic")]
        [InlineData("total")]
        public void HostSet_AcceptsCompatibilityHitNumberModes(string mode)
        {
            using (var h = new Harness())
            {
                h.Send("host_set", new JObject
                {
                    ["v"] = 1,
                    ["key"] = "hitNumberMode",
                    ["value"] = mode
                }, "web.settings.hit-mode-" + mode);

                Assert.Empty(h.Flash);
                Assert.Equal(mode, h.Prefs.HitNumberMode);
                Assert.Equal(mode, Assert.Single(h.Web).Value<string>("currentValue"));
            }
        }

        [Fact]
        public void HitNumberLedger_IsStrictLocalPagedQueryWithoutFlashTraffic()
        {
            using (var h = new Harness())
            {
                int seenOffset = -1;
                int seenLimit = -1;
                h.Task.SetHitNumberLedgerProvider(delegate(int offset, int limit)
                {
                    seenOffset = offset;
                    seenLimit = limit;
                    return new JObject
                    {
                        ["v"] = 1,
                        ["retainedSegments"] = 2,
                        ["droppedSegments"] = 0,
                        ["bursts"] = new JArray(new JObject
                        {
                            ["targetId"] = "boss",
                            ["burstId"] = "shot",
                            ["segments"] = new JArray(
                                new JObject { ["sequence"] = 1, ["damage"] = 43 },
                                new JObject { ["sequence"] = 2, ["damage"] = 60 })
                        })
                    };
                });

                Assert.Null(h.Send("hit_number_ledger", new JObject
                {
                    ["v"] = 1,
                    ["offset"] = 24,
                    ["limit"] = 12
                }, "web.settings.hit-ledger"));

                Assert.Empty(h.Flash);
                Assert.Equal(24, seenOffset);
                Assert.Equal(12, seenLimit);
                JObject response = Assert.Single(h.Web);
                Assert.True(response.Value<bool>("success"));
                Assert.Equal("hit_number_ledger", response.Value<string>("cmd"));
                Assert.Equal(2, response["ledger"].Value<int>("retainedSegments"));
            }
        }

        [Fact]
        public void HitNumberLedger_RejectsUnavailableOrNonExactPayload()
        {
            using (var unavailable = new Harness())
            {
                unavailable.Send("hit_number_ledger", new JObject
                {
                    ["v"] = 1,
                    ["offset"] = 0,
                    ["limit"] = 24
                }, "web.settings.ledger-unavailable");
                Assert.Equal("hit_number_ledger_unavailable",
                    Assert.Single(unavailable.Web).Value<string>("error"));
            }

            using (var invalid = new Harness())
            {
                invalid.Task.SetHitNumberLedgerProvider(delegate { return new JObject(); });
                invalid.Send("hit_number_ledger", new JObject
                {
                    ["v"] = 1,
                    ["offset"] = 0,
                    ["limit"] = 24,
                    ["extra"] = true
                }, "web.settings.ledger-invalid");
                Assert.Equal("invalid_payload",
                    Assert.Single(invalid.Web).Value<string>("error"));
            }
        }

        [Fact]
        public void ExactInstanceAndClose_RetirePendingAndRestorePreviewThroughFlash()
        {
            using (var h = new Harness())
            {
                h.Task.HandleWebRequest("snapshot", new JObject
                {
                    ["domain"] = "settings", ["cmd"] = "snapshot",
                    ["callId"] = "stale.call", ["panelInstanceId"] = "settings.instance.old",
                    ["payload"] = new JObject { ["v"] = 1 }
                });
                Assert.Equal("panel_instance_expired", Assert.Single(h.Web).Value<string>("error"));
                Assert.True(h.Task.HandleAuthoritativePanelClosed("settings.instance.1"));
                Assert.Null(h.Task.PanelInstanceId);
                JObject close = JObject.Parse(Assert.Single(h.Flash).TrimEnd('\0'));
                Assert.Equal("settingsPanelClosed", close.Value<string>("action"));
                Assert.True(h.Task.HandleAuthoritativePanelClosed("settings.instance.1"));
                Assert.Single(h.Flash);
            }
        }

        [Fact]
        public void WebOverlayRoute_RecognizesSettingsAsDedicatedDomain()
        {
            Assert.Equal(WebOverlayForm.PanelDomainRoute.Settings,
                WebOverlayForm.ResolvePanelDomainRoute("snapshot", "settings"));
            Assert.Equal(WebOverlayForm.PanelDomainRoute.Close,
                WebOverlayForm.ResolvePanelDomainRoute("close", "settings"));
        }

        [Fact]
        public void LegacyDuplicateSnapshot_IsForwardedSoWebCanRepairIt()
        {
            using (var h = new Harness())
            {
                JObject sent = h.Send("snapshot", new JObject { ["v"] = 1 });
                JObject response = SnapshotResponse(sent.Value<int>("callId"));
                response["keys"][34]["keyCode"] = response["keys"][33]["keyCode"];
                h.Task.HandleFlashResponse(response, delegate { });
                JObject web = Assert.Single(h.Web);
                Assert.True(web.Value<bool>("success"));
                Assert.Equal(web["keys"][33]["keyCode"], web["keys"][34]["keyCode"]);
            }
        }

        [Fact]
        public void MalformedSuccessfulApply_IsRejectedBeforeWebAdoption()
        {
            using (var h = new Harness())
            {
                JObject sent = h.Send("apply", ApplyPayload());
                h.Task.HandleFlashResponse(new JObject
                {
                    ["task"] = "settings_response",
                    ["callId"] = sent.Value<int>("callId"),
                    ["success"] = true,
                    ["v"] = 1,
                    ["operation"] = "apply",
                    ["applied"] = true,
                    ["durable"] = true,
                    ["migrationPending"] = false
                }, delegate { });
                JObject web = Assert.Single(h.Web);
                Assert.False(web.Value<bool>("success"));
                Assert.Equal("malformed_response", web.Value<string>("error"));
                Assert.True(web.Value<bool>("requiresReconcile"));
            }
        }

        [Fact]
        public void DeliveryUnknownWrite_RequiresAuthorityReconcileWhilePreviewDoesNot()
        {
            using (var write = new Harness(10000, false))
            {
                Assert.NotNull(write.Send("save", new JObject { ["v"] = 1 }));
                JObject response = Assert.Single(write.Web);
                Assert.Equal("delivery_unknown", response.Value<string>("error"));
                Assert.True(response.Value<bool>("requiresReconcile"));
            }

            using (var preview = new Harness(10000, false))
            {
                Assert.NotNull(preview.Send("preview", new JObject
                {
                    ["v"] = 1,
                    ["globalVolume"] = 80,
                    ["bgmVolume"] = 60,
                    ["sample"] = "none"
                }));
                JObject response = Assert.Single(preview.Web);
                Assert.Equal("delivery_unknown", response.Value<string>("error"));
                Assert.Null(response["requiresReconcile"]);
            }
        }

        [Fact]
        public void MalformedSuccessfulCancel_PreservesPartialRestoreAsUnknownWrite()
        {
            using (var h = new Harness())
            {
                JObject sent = h.Send("cancel", new JObject { ["v"] = 1 });
                h.Task.HandleFlashResponse(new JObject
                {
                    ["task"] = "settings_response",
                    ["callId"] = sent.Value<int>("callId"),
                    ["success"] = true,
                    ["v"] = 1,
                    ["operation"] = "cancel",
                    ["previewRestored"] = false,
                    ["previewActive"] = true
                }, delegate { });
                JObject response = Assert.Single(h.Web);
                Assert.Equal("malformed_response", response.Value<string>("error"));
                Assert.True(response.Value<bool>("requiresReconcile"));
            }
        }

        [Fact]
        public void ProjectedUndefinedKeyLabel_IsRejectedBeforeWebAdoption()
        {
            using (var h = new Harness())
            {
                JObject sent = h.Send("snapshot", new JObject { ["v"] = 1 });
                JObject response = SnapshotResponse(sent.Value<int>("callId"));
                response["keys"][0]["label"] = "undefined";
                h.Task.HandleFlashResponse(response, delegate { });
                JObject web = Assert.Single(h.Web);
                Assert.False(web.Value<bool>("success"));
                Assert.Equal("malformed_response", web.Value<string>("error"));
            }
        }

        [Fact]
        public void RescueControls_AreSingleClickExactVersionRequests()
        {
            using (var h = new Harness())
            {
                JObject returned = h.Send("return_base", new JObject { ["v"] = 1 });
                Assert.NotNull(returned);
                Assert.Equal("settingsReturnBase", returned.Value<string>("action"));
                Assert.Null(returned["confirmed"]);

                int flashCount = h.Flash.Count;
                h.Send("try_revive", new JObject
                {
                    ["v"] = 1, ["confirmed"] = true
                }, "web.settings.stale-confirmation");
                Assert.Equal(flashCount, h.Flash.Count);
                Assert.Equal("invalid_payload", h.Web[h.Web.Count - 1].Value<string>("error"));
            }
        }

        [Fact]
        public void SuccessfulTryRevive_AdoptsCurrentAuthorityContract()
        {
            using (var h = new Harness())
            {
                JObject sent = h.Send("try_revive", new JObject { ["v"] = 1 });
                h.Task.HandleFlashResponse(new JObject
                {
                    ["task"] = "settings_response",
                    ["callId"] = sent.Value<int>("callId"),
                    ["success"] = true,
                    ["v"] = 1,
                    ["operation"] = "try_revive",
                    ["revived"] = true,
                    ["reviveCoins"] = 2,
                    ["closePanel"] = true
                }, delegate { });

                JObject response = Assert.Single(h.Web);
                Assert.True(response.Value<bool>("success"));
                Assert.True(response.Value<bool>("revived"));
                Assert.Equal(2, response.Value<int>("reviveCoins"));
                Assert.True(response.Value<bool>("closePanel"));
                Assert.Null(response["requiresReconcile"]);
            }
        }

        [Fact]
        public void TryReviveSuccess_RejectsLegacyAndInvalidAuthorityShapes()
        {
            using (var legacy = new Harness())
            {
                JObject sent = legacy.Send(
                    "try_revive", new JObject { ["v"] = 1 });
                legacy.Task.HandleFlashResponse(new JObject
                {
                    ["task"] = "settings_response",
                    ["callId"] = sent.Value<int>("callId"),
                    ["success"] = true,
                    ["v"] = 1,
                    ["operation"] = "try_revive",
                    ["promptOpened"] = true,
                    ["restrictionActive"] = false,
                    ["closePanel"] = true
                }, delegate { });
                JObject response = Assert.Single(legacy.Web);
                Assert.Equal("malformed_response", response.Value<string>("error"));
                Assert.True(response.Value<bool>("requiresReconcile"));
            }

            using (var invalidCoins = new Harness())
            {
                JObject sent = invalidCoins.Send(
                    "try_revive", new JObject { ["v"] = 1 });
                invalidCoins.Task.HandleFlashResponse(new JObject
                {
                    ["task"] = "settings_response",
                    ["callId"] = sent.Value<int>("callId"),
                    ["success"] = true,
                    ["v"] = 1,
                    ["operation"] = "try_revive",
                    ["revived"] = true,
                    ["reviveCoins"] = -1,
                    ["closePanel"] = true
                }, delegate { });
                JObject response = Assert.Single(invalidCoins.Web);
                Assert.Equal("malformed_response", response.Value<string>("error"));
                Assert.True(response.Value<bool>("requiresReconcile"));
            }
        }

        [Fact]
        public void TimedOutWrite_BlocksFurtherWritesUntilAuthoritativeSnapshot()
        {
            using (var h = new Harness(100))
            {
                Assert.NotNull(h.Send("apply", ApplyPayload(), "web.settings.timeout"));
                Assert.True(SpinWait.SpinUntil(delegate { return h.Web.Count == 1; }, 2000));
                Assert.Equal("timeout", h.Web[0].Value<string>("error"));
                Assert.True(h.Web[0].Value<bool>("requiresReconcile"));

                int flashCount = h.Flash.Count;
                h.Send("save", new JObject { ["v"] = 1 }, "web.settings.after-timeout");
                Assert.Equal(flashCount, h.Flash.Count);
                Assert.Equal("reconcile_required", h.Web[1].Value<string>("error"));
                Assert.True(h.Web[1].Value<bool>("requiresReconcile"));

                JObject snapshot = h.Send("snapshot", new JObject { ["v"] = 1 },
                    "web.settings.reconcile");
                Assert.Equal(2, h.Flash.Count);
                h.Task.HandleFlashResponse(
                    SnapshotResponse(snapshot.Value<int>("callId")), delegate { });
                Assert.True(h.Web[2].Value<bool>("success"));

                h.Send("save", new JObject { ["v"] = 1 }, "web.settings.after-reconcile");
                Assert.Equal(3, h.Flash.Count);
            }
        }

        [Fact]
        public void UnknownWriteLatch_SurvivesCloseAndRebindUntilValidSnapshot()
        {
            using (var h = new Harness())
            {
                JObject apply = h.Send("apply", ApplyPayload(), "web.settings.ambiguous");
                h.Task.SetPostToWeb(null);
                h.Task.HandleFlashResponse(new JObject
                {
                    ["task"] = "settings_response",
                    ["callId"] = apply.Value<int>("callId"),
                    ["success"] = false,
                    ["v"] = 1,
                    ["operation"] = "apply",
                    ["error"] = "apply_ambiguous",
                    ["requiresReconcile"] = true
                }, delegate { });
                Assert.Empty(h.Web);

                Assert.True(h.Task.HandleAuthoritativePanelClosed(h.PanelInstance));
                h.PanelInstance = "settings.instance.2";
                Assert.True(h.Task.BindPanelInstance(h.PanelInstance));
                h.CaptureWebPosts();
                int flashCount = h.Flash.Count;

                h.Send("save", new JObject { ["v"] = 1 }, "web.settings.after-rebind");
                Assert.Equal(flashCount, h.Flash.Count);
                Assert.Equal("reconcile_required", h.Web[0].Value<string>("error"));
                Assert.Equal(h.PanelInstance, h.Web[0].Value<string>("panelInstanceId"));

                JObject snapshot = h.Send("snapshot", new JObject { ["v"] = 1 },
                    "web.settings.rebind-snapshot");
                h.Task.HandleFlashResponse(
                    SnapshotResponse(snapshot.Value<int>("callId")), delegate { });
                Assert.True(h.Web[1].Value<bool>("success"));
                Assert.Equal(h.PanelInstance, h.Web[1].Value<string>("panelInstanceId"));

                h.Send("save", new JObject { ["v"] = 1 },
                    "web.settings.after-rebind-reconcile");
                Assert.Equal(flashCount + 2, h.Flash.Count);
            }
        }

        [Fact]
        public void InFlightWriteClearedByDetach_RequiresSnapshotAfterRebind()
        {
            using (var h = new Harness())
            {
                Assert.NotNull(h.Send("apply", ApplyPayload(),
                    "web.settings.in-flight"));
                Assert.Single(h.Flash);

                h.Task.ClearPending();
                h.PanelInstance = "settings.instance.after-detach";
                Assert.True(h.Task.BindPanelInstance(h.PanelInstance));
                int flashCount = h.Flash.Count;

                h.Send("save", new JObject { ["v"] = 1 },
                    "web.settings.after-detach");
                Assert.Equal(flashCount, h.Flash.Count);
                JObject rejected = Assert.Single(h.Web);
                Assert.Equal("reconcile_required", rejected.Value<string>("error"));
                Assert.True(rejected.Value<bool>("requiresReconcile"));
                Assert.Equal(h.PanelInstance,
                    rejected.Value<string>("panelInstanceId"));

                JObject snapshot = h.Send("snapshot", new JObject { ["v"] = 1 },
                    "web.settings.detach-snapshot");
                h.Task.HandleFlashResponse(
                    SnapshotResponse(snapshot.Value<int>("callId")), delegate { });
                Assert.True(h.Web[1].Value<bool>("success"));

                h.Send("save", new JObject { ["v"] = 1 },
                    "web.settings.after-detach-reconcile");
                Assert.Equal(flashCount + 2, h.Flash.Count);
            }
        }

        [Fact]
        public void SnapshotIssuedBeforeAmbiguousWrite_CannotClearNewReconcileEpoch()
        {
            using (var h = new Harness())
            {
                JObject oldSnapshot = h.Send("snapshot", new JObject { ["v"] = 1 },
                    "web.settings.old-snapshot");
                JObject apply = h.Send("apply", ApplyPayload(),
                    "web.settings.epoch-write");
                Assert.Equal(2, h.Flash.Count);

                h.Task.HandleFlashResponse(new JObject
                {
                    ["task"] = "settings_response",
                    ["callId"] = apply.Value<int>("callId"),
                    ["success"] = false,
                    ["v"] = 1,
                    ["operation"] = "apply",
                    ["error"] = "apply_ambiguous",
                    ["requiresReconcile"] = true
                }, delegate { });
                Assert.True(h.Web[0].Value<bool>("requiresReconcile"));

                h.Task.HandleFlashResponse(
                    SnapshotResponse(oldSnapshot.Value<int>("callId")), delegate { });
                Assert.True(h.Web[1].Value<bool>("success"));
                Assert.True(h.Web[1].Value<bool>("requiresReconcile"));
                int flashCount = h.Flash.Count;

                h.Send("save", new JObject { ["v"] = 1 },
                    "web.settings.after-old-snapshot");
                Assert.Equal(flashCount, h.Flash.Count);
                Assert.Equal("reconcile_required", h.Web[2].Value<string>("error"));

                JObject newSnapshot = h.Send("snapshot", new JObject { ["v"] = 1 },
                    "web.settings.new-snapshot");
                h.Task.HandleFlashResponse(
                    SnapshotResponse(newSnapshot.Value<int>("callId")), delegate { });
                Assert.Null(h.Web[3]["requiresReconcile"]);
                h.Send("save", new JObject { ["v"] = 1 },
                    "web.settings.after-new-snapshot");
                Assert.Equal(flashCount + 2, h.Flash.Count);
            }
        }

        private static JObject ApplyPayload()
        {
            var keys = new JArray();
            int[] codes = {87,83,65,68,74,75,82,49,50,51,52,53,54,55,56,57,48,
                32,85,73,79,80,76,72,71,67,66,78,77,47,69,70,18,81,16,17};
            for (int i = 0; i < KeyIds.Length; i++)
                keys.Add(new JObject { ["id"] = KeyIds[i], ["keyCode"] = codes[i] });
            return new JObject
            {
                ["v"] = 1,
                ["keySchemaVersion"] = 2,
                ["expectedRevision"] = 0,
                ["settings"] = SettingsObject(),
                ["keys"] = keys
            };
        }

        private static JObject SettingsObject()
        {
            return new JObject
            {
                ["setGlobalVolume"] = 80, ["setBGMVolume"] = 60,
                ["性能等级上限"] = 1, ["是否阴影"] = true,
                ["是否视觉元素"] = true,
                ["cameraZoomToggle"] = true, ["basicZoomScale"] = 1.0,
                ["开启昼夜系统"] = true, ["暂停昼夜系统"] = false,
                ["使用滤镜渲染"] = true, ["立绘类型"] = 1,
                ["jukeboxOverride"] = false, ["jukeboxTrueRandom"] = false,
                ["jukeboxPlayMode"] = "albumLoop"
            };
        }

        private static JObject SnapshotResponse(int fid)
        {
            JObject apply = ApplyPayload();
            var keys = new JArray();
            var defaults = new JArray();
            var allowed = new JArray();
            foreach (JObject row in (JArray)apply["keys"])
            {
                keys.Add(new JObject
                {
                    ["index"] = keys.Count,
                    ["id"] = row.Value<string>("id"), ["label"] = row.Value<string>("id"),
                    ["keyCode"] = row.Value<int>("keyCode"), ["keyName"] = "K" + row.Value<int>("keyCode")
                });
                defaults.Add(new JObject
                {
                    ["id"] = row.Value<string>("id"), ["keyCode"] = row.Value<int>("keyCode")
                });
                allowed.Add(new JObject
                {
                    ["code"] = row.Value<int>("keyCode"), ["name"] = "K" + row.Value<int>("keyCode")
                });
            }
            return new JObject
            {
                ["task"] = "settings_response", ["callId"] = fid,
                ["success"] = true, ["v"] = 1,
                ["keySchemaVersion"] = 2, ["operation"] = "snapshot",
                ["revision"] = 0, ["settings"] = SettingsObject(), ["keys"] = keys,
                ["defaultKeys"] = defaults, ["allowedKeyCodes"] = allowed,
                ["challengeMode"] = false, ["modeLabel"] = "困难",
                ["cheatHelp"] = new JArray(), ["forceControls"] = new JObject
                {
                    ["returnBaseAvailable"] = true,
                    ["tryReviveAvailable"] = false,
                    ["resurrectionRestricted"] = false
                },
                ["previewActive"] = false, ["migrationPending"] = false,
                ["keyMigrationNotice"] = string.Empty
            };
        }
    }
}
