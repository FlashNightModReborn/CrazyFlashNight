using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Save;
using CF7Launcher.Tasks;
using CF7Launcher.Tests.Save;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class GameLaunchFlowCharacterCreateTests
    {
        private const string OpenRequestId = "open-request-character-create-tests";

        private static bool OpenCharacterCreate(
            GameLaunchFlow flow,
            string mode,
            string slotKey,
            out string attemptId,
            out string openedSlotKey,
            out string error)
        {
            return flow.OpenCharacterCreate(
                mode,
                slotKey,
                OpenRequestId,
                out attemptId,
                out openedSlotKey,
                out error);
        }

        private static bool SubmitCharacterCreate(
            GameLaunchFlow flow,
            string attemptId,
            string slotKey,
            string displayName,
            JObject draft,
            out string error)
        {
            return flow.SubmitCharacterCreate(
                OpenRequestId,
                attemptId,
                slotKey,
                true,
                displayName,
                draft,
                out error);
        }

        private static bool SubmitCharacterCreateFollowingCharacterName(
            GameLaunchFlow flow,
            string attemptId,
            string slotKey,
            JObject draft,
            out string error)
        {
            return flow.SubmitCharacterCreate(
                OpenRequestId,
                attemptId,
                slotKey,
                false,
                null,
                draft,
                out error);
        }

        [Fact]
        public void StartFreshGame_UsesEmptyOverrideWithoutDeletingShadowOrSol()
        {
            using var harness = new Harness();
            const string slot = "slot_fresh";
            harness.SeedShadow(slot, "旧角色", 8);
            string solPath = harness.CreateSolFile(slot);
            harness.PreparePrewarmAttempt("attempt-fresh");

            harness.Flow.StartFreshGame(slot, false, true);

            SolResolveResult resolved = GetPrivateField<SolResolveResult>(
                harness.Flow, "_resolvedSave");
            Assert.NotNull(resolved);
            Assert.Equal("empty", resolved.WireDecision);
            Assert.True(File.Exists(Path.Combine(
                harness.Archive.SavesDir, slot + ".json")));
            Assert.True(File.Exists(solPath));
        }

        [Fact]
        public void CreateFlow_LateDurableConvergesOnce_AndScenePacketIsFinalGate()
        {
            using var harness = new Harness();
            const string attempt = "attempt-create";
            harness.PreparePrewarmAttempt(attempt);

            string openedAttempt;
            string slotKey;
            string error;
            Assert.True(OpenCharacterCreate(harness.Flow,
                "new", null, out openedAttempt, out slotKey, out error), error);
            Assert.Equal(attempt, openedAttempt);
            Assert.True(SaveSlotKey.IsValid(slotKey));
            Assert.Equal("starting", harness.LastStatePhase());
            JObject starting = harness.Web.Last(x => x.Value<string>("phase") == "starting");
            Assert.Equal(OpenRequestId, starting.Value<string>("openRequestId"));

            harness.SetState(GameLaunchFlow.State.WaitingGameReady);
            harness.SendBootstrap("bootstrap_ready", attempt);
            Assert.Equal(GameLaunchFlow.State.Ready.ToString(), harness.Flow.CurrentState);
            Assert.False(harness.Flow.RevealPerformed);
            Assert.NotNull(GetPrivateField<Timer>(
                harness.Flow, "_flashRevealWatchdog"));

            harness.SendBootstrap("bootstrap_reveal_ready", attempt);
            Assert.Null(GetPrivateField<Timer>(
                harness.Flow, "_flashRevealWatchdog"));
            JObject snapshotRequest = Assert.Single(
                harness.As2.Where(x => x.Value<string>("action")
                    == "characterCreationSnapshot"));
            Assert.Equal(attempt, snapshotRequest.Value<string>("attemptId"));
            Assert.Equal(slotKey, snapshotRequest.Value<string>("slotKey"));
            string snapshotCallId = snapshotRequest.Value<string>("callId");
            Assert.False(string.IsNullOrEmpty(snapshotCallId));
            Assert.Null(snapshotRequest["payload"]);
            Assert.False(harness.Flow.RevealPerformed);
            Assert.Null(GetPrivateField<Timer>(
                harness.Flow, "_frontdoorSceneWatchdog"));

            harness.Send(BuildSnapshotResponse(
                attempt, slotKey, "wrong-snapshot-call-id"));
            Assert.DoesNotContain(
                harness.Web,
                x => x.Value<string>("cmd") == "character_create_snapshot");
            harness.Send(BuildSnapshotResponse(attempt, slotKey, snapshotCallId));
            JObject snapshot = Assert.Single(
                harness.Web.Where(x => x.Value<string>("cmd")
                    == "character_create_snapshot"));
            Assert.Equal(OpenRequestId, snapshot.Value<string>("openRequestId"));
            Assert.IsType<JObject>(snapshot["appearanceCatalog"]["faces"]["male"]);
            Assert.IsType<JObject>(snapshot["appearanceCatalog"]["faces"]["female"]);
            Assert.Null(snapshot["payload"]);

            JObject draft = BuildDraft();
            Assert.True(SubmitCharacterCreate(harness.Flow,
                attempt, slotKey, " 一周目 ", draft, out error), error);
            Assert.Empty(harness.LastPlayed);
            Assert.False(SubmitCharacterCreate(harness.Flow,
                attempt, slotKey, "一周目", draft, out error));
            Assert.Equal("submit_already_pending", error);
            JObject createRequest = Assert.Single(
                harness.As2.Where(x => x.Value<string>("action")
                    == "characterCreate"));
            string createCallId = createRequest.Value<string>("callId");
            Assert.False(string.IsNullOrEmpty(createCallId));
            Assert.NotEqual(snapshotCallId, createCallId);

            InvokePrivate(
                harness.Flow,
                "OnCharacterCreateDefinitiveTimeout",
                attempt,
                slotKey);
            Assert.Equal("unknown", harness.LastStatePhase());
            Assert.Null(GetPrivateField<Timer>(
                harness.Flow, "_characterCreateDefinitiveTimer"));
            Assert.Equal(createCallId, GetPrivateField<string>(
                harness.Flow, "_characterCreateCallId"));
            InvokePrivate(
                harness.Flow,
                "OnCharacterCreateDefinitiveTimeout",
                attempt,
                slotKey);
            Assert.Single(harness.Web.Where(x =>
                x.Value<string>("phase") == "unknown"
                && x.Value<string>("error") == "definitive_response_timeout"));

            harness.Send(BuildCreateResponse(
                attempt, slotKey, createCallId, "durable", true, false));
            Assert.Empty(harness.LastPlayed);
            harness.Send(BuildCreateResponse(
                attempt, slotKey, "wrong-call-id", "durable", true, true));
            Assert.Empty(harness.LastPlayed);
            harness.Send(BuildCreateResponse(
                "attempt-stale", slotKey, createCallId, "durable", true, true));
            Assert.Empty(harness.LastPlayed);
            harness.Send(BuildCreateResponse(
                attempt, slotKey, createCallId, "durable", true, true));
            harness.Send(BuildCreateResponse(
                attempt, slotKey, createCallId, "durable", true, true));
            Assert.Empty(harness.LastPlayed);
            Assert.Equal("durable", harness.LastStatePhase());
            Assert.Equal("一周目", harness.Archive.SlotCatalog.ReadAll()[slotKey]);
            Assert.NotNull(GetPrivateField<Timer>(
                harness.Flow, "_frontdoorSceneWatchdog"));

            harness.Flow.ObserveUiData(new UiDataPacket(
                "s:1|ga:attempt-stale"));
            Assert.False(harness.Flow.RevealPerformed);
            harness.Flow.ObserveUiData(new UiDataPacket(
                "s:1|ga:" + attempt + "|s:0"));
            Assert.False(harness.Flow.RevealPerformed);
            harness.Flow.ObserveUiData(new UiDataPacket(
                "s:0|s:1|ga:" + attempt));
            Assert.True(harness.Flow.RevealPerformed);
            Assert.Null(GetPrivateField<Timer>(
                harness.Flow, "_flashRevealWatchdog"));
            Assert.Null(GetPrivateField<Timer>(
                harness.Flow, "_frontdoorSceneWatchdog"));
            Assert.Equal("scene_ready", harness.LastStatePhase());
            Assert.Equal(new string[] { slotKey }, harness.LastPlayed);
        }

        [Fact]
        public void CreateFlow_DefaultDisplayName_RemainsCharacterNameFollower()
        {
            using var harness = new Harness();
            const string attempt = "attempt-display-follow";
            harness.PreparePrewarmAttempt(attempt);

            string openedAttempt;
            string slotKey;
            string error;
            Assert.True(OpenCharacterCreate(harness.Flow,
                "new", null, out openedAttempt, out slotKey, out error), error);
            harness.SetState(GameLaunchFlow.State.WaitingGameReady);
            harness.SendBootstrap("bootstrap_ready", attempt);
            harness.SendBootstrap("bootstrap_reveal_ready", attempt);
            JObject snapshotRequest = Assert.Single(
                harness.As2.Where(x => x.Value<string>("action")
                    == "characterCreationSnapshot"));
            harness.Send(BuildSnapshotResponse(
                attempt,
                slotKey,
                snapshotRequest.Value<string>("callId")));
            Assert.True(SubmitCharacterCreateFollowingCharacterName(
                harness.Flow,
                attempt,
                slotKey,
                BuildDraft(),
                out error), error);
            JObject createRequest = Assert.Single(
                harness.As2.Where(x => x.Value<string>("action")
                    == "characterCreate"));

            harness.Send(BuildCreateResponse(
                attempt,
                slotKey,
                createRequest.Value<string>("callId"),
                "durable",
                true,
                true));
            Assert.Empty(harness.LastPlayed);

            Assert.False(harness.Archive.SlotCatalog.ReadAll().ContainsKey(slotKey));
            JObject durableState = harness.Web.Last(x => x.Value<string>("phase")
                == "durable");
            Assert.False(durableState.Value<bool>("displayNameCustomized"));
            Assert.True(durableState.Value<bool>("metadataSaved"));
            Assert.Empty(harness.LastPlayed);
            harness.Flow.ObserveUiData(new UiDataPacket("s:1|ga:" + attempt));
            Assert.Equal(new string[] { slotKey }, harness.LastPlayed);
        }

        [Fact]
        public void Rebuild_DefaultDisplayName_RemovesPriorOverrideOnlyAfterDurable()
        {
            using var harness = new Harness();
            const string attempt = "attempt-rebuild-display-follow";
            const string slot = "slot_rebuild_display_follow";
            harness.SeedShadow(slot, "旧角色", 8);
            string normalized;
            string error;
            Assert.True(harness.Archive.SlotCatalog.TrySetDisplayName(
                slot,
                "旧自定义名",
                out normalized,
                out error), error);
            harness.PreparePrewarmAttempt(attempt);

            string openedAttempt;
            string openedSlot;
            Assert.True(OpenCharacterCreate(harness.Flow,
                "rebuild", slot, out openedAttempt, out openedSlot, out error), error);
            harness.SetState(GameLaunchFlow.State.WaitingGameReady);
            harness.SendBootstrap("bootstrap_ready", attempt);
            harness.SendBootstrap("bootstrap_reveal_ready", attempt);
            JObject snapshotRequest = Assert.Single(
                harness.As2.Where(x => x.Value<string>("action")
                    == "characterCreationSnapshot"));
            harness.Send(BuildSnapshotResponse(
                attempt,
                slot,
                snapshotRequest.Value<string>("callId")));
            Assert.True(SubmitCharacterCreateFollowingCharacterName(
                harness.Flow,
                attempt,
                slot,
                BuildDraft(),
                out error), error);
            Assert.Equal("旧自定义名", harness.Archive.SlotCatalog.ReadAll()[slot]);
            JObject createRequest = Assert.Single(
                harness.As2.Where(x => x.Value<string>("action")
                    == "characterCreate"));

            harness.Send(BuildCreateResponse(
                attempt,
                slot,
                createRequest.Value<string>("callId"),
                "durable",
                true,
                true));

            Assert.False(harness.Archive.SlotCatalog.ReadAll().ContainsKey(slot));
            JObject backup;
            Assert.True(harness.Archive.RebuildBackups.TryReadLatest(
                slot,
                out backup,
                out error), error);
            Assert.Equal("旧自定义名", backup.Value<string>("displayName"));
            Assert.Empty(harness.LastPlayed);
        }

        [Theory]
        [InlineData("extra_field")]
        [InlineData("missing_field")]
        [InlineData("short_empty")]
        [InlineData("short_control")]
        [InlineData("short_oversized")]
        [InlineData("html_control")]
        [InlineData("html_oversized")]
        [InlineData("row_not_object")]
        public void Snapshot_MalformedRichAppearanceRow_IsRejected(
            string malformedCase)
        {
            using var harness = new Harness();
            const string attempt = "attempt-malformed-appearance";
            harness.PreparePrewarmAttempt(attempt);

            string openedAttempt;
            string slotKey;
            string error;
            Assert.True(OpenCharacterCreate(harness.Flow,
                "new", null, out openedAttempt, out slotKey, out error), error);
            harness.SendBootstrap("bootstrap_reveal_ready", attempt);
            JObject snapshotRequest = Assert.Single(
                harness.As2.Where(x => x.Value<string>("action")
                    == "characterCreationSnapshot"));
            JObject response = BuildSnapshotResponse(
                attempt,
                slotKey,
                snapshotRequest.Value<string>("callId"));
            JArray rows = (JArray)response["appearanceCatalog"]["upper"]["male"];
            JObject row = rows[0] as JObject;
            switch (malformedCase)
            {
                case "extra_field":
                    row["unexpected"] = true;
                    break;
                case "missing_field":
                    row.Remove("iconName");
                    break;
                case "short_empty":
                    row["name"] = "";
                    break;
                case "short_control":
                    row["itemType"] = "服装\n注入";
                    break;
                case "short_oversized":
                    row["identifier"] = new string('x', 161);
                    break;
                case "html_control":
                    row["descHTML"] = "说明\u0001注入";
                    break;
                case "html_oversized":
                    row["introHTML"] = new string('x', 131073);
                    break;
                case "row_not_object":
                    rows[0] = "not-an-object";
                    break;
                default:
                    throw new InvalidOperationException(malformedCase);
            }

            harness.Send(response);

            Assert.DoesNotContain(
                harness.Web,
                x => x.Value<string>("cmd") == "character_create_snapshot");
            JObject rejected = harness.Web.Last(x => x.Value<string>("cmd")
                == "character_create_state");
            Assert.Equal("rejected", rejected.Value<string>("phase"));
            Assert.Equal("snapshot_projection_invalid", rejected.Value<string>("error"));
            Assert.Equal(OpenRequestId, rejected.Value<string>("openRequestId"));
            Assert.False(SubmitCharacterCreate(harness.Flow,
                attempt, slotKey, "畸形目录", BuildDraft(), out error));
            Assert.Equal("snapshot_not_ready", error);
        }

        [Theory]
        [InlineData("upper", "male")]
        [InlineData("upper", "female")]
        [InlineData("lower", "male")]
        [InlineData("lower", "female")]
        [InlineData("footwear", "male")]
        [InlineData("footwear", "female")]
        public void Snapshot_AllRichAppearanceCatalogsAndGenders_AreHostValidated(
            string catalog,
            string gender)
        {
            using var harness = new Harness();
            const string attempt = "attempt-rich-catalog-matrix";
            harness.PreparePrewarmAttempt(attempt);

            string openedAttempt;
            string slotKey;
            string error;
            Assert.True(OpenCharacterCreate(harness.Flow,
                "new", null, out openedAttempt, out slotKey, out error), error);
            harness.SendBootstrap("bootstrap_reveal_ready", attempt);
            JObject request = Assert.Single(
                harness.As2.Where(x => x.Value<string>("action")
                    == "characterCreationSnapshot"));
            JObject response = BuildSnapshotResponse(
                attempt,
                slotKey,
                request.Value<string>("callId"));
            ((JObject)response["appearanceCatalog"][catalog][gender][0])
                ["unexpected"] = true;

            harness.Send(response);

            Assert.DoesNotContain(
                harness.Web,
                x => x.Value<string>("cmd") == "character_create_snapshot");
            JObject rejected = harness.Web.Last(x => x.Value<string>("cmd")
                == "character_create_state");
            Assert.Equal("snapshot_projection_invalid", rejected.Value<string>("error"));
            Assert.Equal(OpenRequestId, rejected.Value<string>("openRequestId"));
        }

        [Fact]
        public void Rebuild_BackupFailureLeavesShadowAndNeverPushesCreate()
        {
            using var harness = new Harness();
            const string attempt = "attempt-rebuild";
            const string slot = "slot_rebuild";
            harness.SeedShadow(slot, "旧角色", 9);
            string shadowPath = Path.Combine(
                harness.Archive.SavesDir, slot + ".json");
            string before = File.ReadAllText(shadowPath);
            harness.PreparePrewarmAttempt(attempt);

            string openedAttempt;
            string openedSlot;
            string error;
            Assert.True(OpenCharacterCreate(harness.Flow,
                "rebuild", slot, out openedAttempt, out openedSlot, out error), error);
            Assert.Equal(attempt, openedAttempt);
            Assert.Equal(slot, openedSlot);
            SolResolveResult resolved = GetPrivateField<SolResolveResult>(
                harness.Flow, "_resolvedSave");
            Assert.Equal("empty", resolved.WireDecision);

            harness.SetState(GameLaunchFlow.State.WaitingGameReady);
            harness.SendBootstrap("bootstrap_ready", attempt);
            harness.SendBootstrap("bootstrap_reveal_ready", attempt);
            JObject snapshotRequest = Assert.Single(
                harness.As2.Where(x => x.Value<string>("action")
                    == "characterCreationSnapshot"));
            harness.Send(BuildSnapshotResponse(
                attempt,
                slot,
                snapshotRequest.Value<string>("callId")));
            File.WriteAllText(
                Path.Combine(
                    harness.Archive.SavesDir,
                    RebuildBackupStore.DirectoryName),
                "blocks-directory-creation");

            Assert.False(SubmitCharacterCreate(harness.Flow,
                attempt, slot, "重建槽", BuildDraft(), out error));
            Assert.StartsWith("backup_failed:", error, StringComparison.Ordinal);
            Assert.True(File.Exists(shadowPath));
            Assert.Equal(before, File.ReadAllText(shadowPath));
            Assert.False(File.Exists(Path.Combine(
                harness.Archive.SavesDir, slot + ".tombstone")));
            Assert.Empty(harness.As2.Where(x => x.Value<string>("action")
                == "characterCreate"));
        }

        [Fact]
        public void Rebuild_MalformedDiscoveredShadowFailsBeforeLaunchOrMutation()
        {
            using var harness = new Harness();
            const string slot = "slot_corrupt";
            string shadowPath = Path.Combine(
                harness.Archive.SavesDir, slot + ".json");
            File.WriteAllText(shadowPath, "{malformed");
            harness.PreparePrewarmAttempt("attempt-corrupt");

            string attemptId;
            string openedSlot;
            string error;
            Assert.False(OpenCharacterCreate(harness.Flow,
                "rebuild", slot, out attemptId, out openedSlot, out error));
            Assert.Equal("rebuild_snapshot_unverifiable", error);
            Assert.Null(attemptId);
            Assert.True(File.Exists(shadowPath));
            Assert.Equal("{malformed", File.ReadAllText(shadowPath));
            Assert.Empty(harness.As2);
            Assert.Empty(harness.Web);
        }

        [Fact]
        public void Rebuild_TombstoneOnly_IsAdmittedWithoutInventingOldBackup()
        {
            using var harness = new Harness();
            const string attempt = "attempt-tombstone-only";
            const string slot = "slot_tombstone_only";
            string tombstonePath = harness.CreateTombstone(slot);
            harness.PreparePrewarmAttempt(attempt);

            string openedAttempt;
            string openedSlot;
            string error;
            Assert.True(OpenCharacterCreate(harness.Flow,
                "rebuild", slot, out openedAttempt, out openedSlot, out error), error);
            Assert.True(File.Exists(tombstonePath));
            harness.SetState(GameLaunchFlow.State.WaitingGameReady);
            harness.SendBootstrap("bootstrap_ready", attempt);
            harness.SendBootstrap("bootstrap_reveal_ready", attempt);
            JObject snapshotRequest = Assert.Single(
                harness.As2.Where(x => x.Value<string>("action")
                    == "characterCreationSnapshot"));
            harness.Send(BuildSnapshotResponse(
                attempt,
                slot,
                snapshotRequest.Value<string>("callId")));

            Assert.True(SubmitCharacterCreate(harness.Flow,
                attempt, slot, "重建已删除槽", BuildDraft(), out error), error);

            Assert.False(File.Exists(tombstonePath));
            Assert.False(File.Exists(
                harness.Archive.RebuildBackups.GetBackupPath(slot)));
            Assert.Single(harness.As2, x => x.Value<string>("action")
                == "characterCreate");
        }

        [Fact]
        public void Rebuild_TombstonedValidShadow_IsBackedUpBeforeReset()
        {
            using var harness = new Harness();
            const string attempt = "attempt-tombstone-shadow";
            const string slot = "slot_tombstone_shadow";
            harness.SeedShadow(slot, "旧角色", 13);
            string shadowPath = Path.Combine(
                harness.Archive.SavesDir,
                slot + ".json");
            string tombstonePath = harness.CreateTombstone(slot);
            harness.PreparePrewarmAttempt(attempt);

            string openedAttempt;
            string openedSlot;
            string error;
            Assert.True(OpenCharacterCreate(harness.Flow,
                "rebuild", slot, out openedAttempt, out openedSlot, out error), error);
            Assert.True(File.Exists(shadowPath));
            Assert.True(File.Exists(tombstonePath));
            harness.SetState(GameLaunchFlow.State.WaitingGameReady);
            harness.SendBootstrap("bootstrap_ready", attempt);
            harness.SendBootstrap("bootstrap_reveal_ready", attempt);
            JObject snapshotRequest = Assert.Single(
                harness.As2.Where(x => x.Value<string>("action")
                    == "characterCreationSnapshot"));
            harness.Send(BuildSnapshotResponse(
                attempt,
                slot,
                snapshotRequest.Value<string>("callId")));

            Assert.True(SubmitCharacterCreate(harness.Flow,
                attempt, slot, "重建不一致槽", BuildDraft(), out error), error);

            JObject backup;
            Assert.True(harness.Archive.RebuildBackups.TryReadLatest(
                slot,
                out backup,
                out error), error);
            Assert.Equal("旧角色", backup["snapshot"]["0"][0].Value<string>());
            Assert.Equal("json_shadow_tombstoned", backup.Value<string>("source"));
            Assert.False(File.Exists(shadowPath));
            Assert.False(File.Exists(tombstonePath));
        }

        [Fact]
        public void Rebuild_TombstonedMalformedShadow_FailsWithoutMutation()
        {
            using var harness = new Harness();
            const string slot = "slot_tombstone_malformed";
            string shadowPath = Path.Combine(
                harness.Archive.SavesDir,
                slot + ".json");
            File.WriteAllText(shadowPath, "{malformed");
            string tombstonePath = harness.CreateTombstone(slot);
            harness.PreparePrewarmAttempt("attempt-tombstone-malformed");

            string attemptId;
            string openedSlot;
            string error;
            Assert.False(OpenCharacterCreate(harness.Flow,
                "rebuild", slot, out attemptId, out openedSlot, out error));

            Assert.Equal("rebuild_snapshot_unverifiable", error);
            Assert.True(File.Exists(shadowPath));
            Assert.True(File.Exists(tombstonePath));
            Assert.Empty(harness.As2);
        }

        [Fact]
        public void Rebuild_MissingSafeSlotCannotBypassHostKeyAllocation()
        {
            using var harness = new Harness();
            harness.PreparePrewarmAttempt("attempt-missing-rebuild");

            string attemptId;
            string openedSlot;
            string error;
            Assert.False(OpenCharacterCreate(harness.Flow,
                "rebuild",
                "caller_chosen_slot",
                out attemptId,
                out openedSlot,
                out error));
            Assert.Equal("slot_not_found", error);
            Assert.Null(attemptId);
            Assert.Empty(harness.As2);
            Assert.Empty(harness.Web);
        }

        [Fact]
        public void Rebuild_ResetFailureKeepsShadowAndNeverPushesCreate()
        {
            using var harness = new Harness();
            const string attempt = "attempt-reset-failure";
            const string slot = "slot_reset_failure";
            harness.SeedShadow(slot, "旧角色", 11);
            string shadowPath = Path.Combine(
                harness.Archive.SavesDir, slot + ".json");
            harness.PreparePrewarmAttempt(attempt);

            string openedAttempt;
            string openedSlot;
            string error;
            Assert.True(OpenCharacterCreate(harness.Flow,
                "rebuild", slot, out openedAttempt, out openedSlot, out error), error);
            harness.SetState(GameLaunchFlow.State.WaitingGameReady);
            harness.SendBootstrap("bootstrap_ready", attempt);
            harness.SendBootstrap("bootstrap_reveal_ready", attempt);
            JObject snapshotRequest = Assert.Single(
                harness.As2.Where(x => x.Value<string>("action")
                    == "characterCreationSnapshot"));
            harness.Send(BuildSnapshotResponse(
                attempt,
                slot,
                snapshotRequest.Value<string>("callId")));

            using (new FileStream(
                shadowPath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.None))
            {
                Assert.False(SubmitCharacterCreate(harness.Flow,
                    attempt, slot, "重建槽位", BuildDraft(), out error));
            }

            Assert.StartsWith("reset_failed:IOException", error, StringComparison.Ordinal);
            Assert.True(File.Exists(shadowPath));
            Assert.True(File.Exists(harness.Archive.RebuildBackups.GetBackupPath(slot)));
            Assert.Empty(harness.As2.Where(x => x.Value<string>("action")
                == "characterCreate"));
        }

        [Fact]
        public void TitleBeforeReady_DraftEditingHasNoSceneDeadline()
        {
            using var harness = new Harness();
            const string attempt = "attempt-long-draft";
            harness.PreparePrewarmAttempt(attempt);

            string openedAttempt;
            string slotKey;
            string error;
            Assert.True(OpenCharacterCreate(harness.Flow,
                "new", null, out openedAttempt, out slotKey, out error), error);
            harness.SendBootstrap("bootstrap_reveal_ready", attempt);
            Assert.Null(GetPrivateField<Timer>(
                harness.Flow, "_flashRevealWatchdog"));

            harness.SetState(GameLaunchFlow.State.WaitingGameReady);
            harness.SendBootstrap("bootstrap_ready", attempt);
            Assert.Null(GetPrivateField<Timer>(
                harness.Flow, "_flashRevealWatchdog"));
            Assert.Null(GetPrivateField<Timer>(
                harness.Flow, "_frontdoorSceneWatchdog"));

            InvokePrivate(
                harness.Flow,
                "OnFrontdoorSceneWatchdogFired",
                attempt);

            Assert.Equal(GameLaunchFlow.State.Ready.ToString(), harness.Flow.CurrentState);
            Assert.False(harness.Flow.RevealPerformed);
            Assert.Null(GetPrivateField<Timer>(
                harness.Flow, "_flashRevealWatchdog"));
            Assert.Null(GetPrivateField<Timer>(
                harness.Flow, "_frontdoorSceneWatchdog"));
        }

        [Fact]
        public void DurableBeforeReady_ArmsSceneDeadlineOnlyWhenReady()
        {
            using var harness = new Harness();
            const string attempt = "attempt-durable-before-ready";
            harness.PreparePrewarmAttempt(attempt);

            string openedAttempt;
            string slotKey;
            string error;
            Assert.True(OpenCharacterCreate(harness.Flow,
                "new", null, out openedAttempt, out slotKey, out error), error);
            harness.SendBootstrap("bootstrap_reveal_ready", attempt);
            JObject snapshotRequest = Assert.Single(
                harness.As2.Where(x => x.Value<string>("action")
                    == "characterCreationSnapshot"));
            harness.Send(BuildSnapshotResponse(
                attempt, slotKey, snapshotRequest.Value<string>("callId")));
            Assert.True(SubmitCharacterCreate(harness.Flow,
                attempt, slotKey, "提前持久化", BuildDraft(), out error), error);
            JObject createRequest = Assert.Single(
                harness.As2.Where(x => x.Value<string>("action")
                    == "characterCreate"));
            harness.Send(BuildCreateResponse(
                attempt,
                slotKey,
                createRequest.Value<string>("callId"),
                "durable",
                true,
                true));

            Assert.Null(GetPrivateField<Timer>(
                harness.Flow, "_frontdoorSceneWatchdog"));
            Assert.Equal("durable", harness.LastStatePhase());

            harness.SetState(GameLaunchFlow.State.WaitingGameReady);
            harness.SendBootstrap("bootstrap_ready", attempt);

            Assert.Equal(GameLaunchFlow.State.Ready.ToString(), harness.Flow.CurrentState);
            Assert.NotNull(GetPrivateField<Timer>(
                harness.Flow, "_frontdoorSceneWatchdog"));
            Assert.False(harness.Flow.RevealPerformed);
        }

        [Fact]
        public void FrontdoorTitleWatchdog_TimesOutBeforeTitleReceipt()
        {
            using var harness = new Harness();
            const string attempt = "attempt-title-timeout";
            harness.PreparePrewarmAttempt(attempt);

            string openedAttempt;
            string slotKey;
            string error;
            Assert.True(OpenCharacterCreate(harness.Flow,
                "new", null, out openedAttempt, out slotKey, out error), error);
            harness.SetState(GameLaunchFlow.State.WaitingGameReady);
            harness.SendBootstrap("bootstrap_ready", attempt);
            Assert.NotNull(GetPrivateField<Timer>(
                harness.Flow, "_flashRevealWatchdog"));
            Assert.Null(GetPrivateField<Timer>(
                harness.Flow, "_frontdoorSceneWatchdog"));

            InvokePrivate(harness.Flow, "OnFlashRevealWatchdogFired", attempt);

            Assert.Equal(GameLaunchFlow.State.Error.ToString(), harness.Flow.CurrentState);
            Assert.Null(GetPrivateField<Timer>(
                harness.Flow, "_flashRevealWatchdog"));
            Assert.Null(GetPrivateField<Timer>(
                harness.Flow, "_frontdoorSceneWatchdog"));
            Assert.DoesNotContain(
                harness.Web,
                x => x.Value<string>("phase") == "durable_scene_error");

            harness.SendBootstrap("bootstrap_reveal_ready", attempt);
            Assert.Empty(harness.As2);
            Assert.Equal(GameLaunchFlow.State.Error.ToString(), harness.Flow.CurrentState);
        }

        [Fact]
        public void SnapshotDeadline_RejectsOnceAndIgnoresLateExactSnapshot()
        {
            using var harness = new Harness();
            const string attempt = "attempt-snapshot-timeout";
            harness.PreparePrewarmAttempt(attempt);

            string openedAttempt;
            string slotKey;
            string error;
            Assert.True(OpenCharacterCreate(harness.Flow,
                "new", null, out openedAttempt, out slotKey, out error), error);
            harness.SetState(GameLaunchFlow.State.WaitingGameReady);
            harness.SendBootstrap("bootstrap_ready", attempt);
            harness.SendBootstrap("bootstrap_reveal_ready", attempt);
            JObject snapshotRequest = Assert.Single(
                harness.As2.Where(x => x.Value<string>("action")
                    == "characterCreationSnapshot"));
            string callId = snapshotRequest.Value<string>("callId");
            Assert.NotNull(GetPrivateField<Timer>(
                harness.Flow, "_characterCreateSnapshotTimer"));

            InvokePrivate(
                harness.Flow,
                "OnCharacterCreateSnapshotTimeout",
                attempt,
                slotKey,
                callId);
            InvokePrivate(
                harness.Flow,
                "OnCharacterCreateSnapshotTimeout",
                attempt,
                slotKey,
                callId);

            JObject rejected = Assert.Single(harness.Web.Where(x =>
                x.Value<string>("phase") == "rejected"
                && x.Value<string>("error") == "snapshot_response_timeout"));
            Assert.Equal(OpenRequestId, rejected.Value<string>("openRequestId"));
            Assert.Null(GetPrivateField<Timer>(
                harness.Flow, "_characterCreateSnapshotTimer"));
            Assert.Equal(GameLaunchFlow.State.Ready.ToString(), harness.Flow.CurrentState);
            Assert.Empty(harness.LastPlayed);

            int webCountAtTimeout = harness.Web.Count;
            harness.Send(BuildSnapshotResponse(attempt, slotKey, callId));
            Assert.Equal(webCountAtTimeout, harness.Web.Count);
            Assert.DoesNotContain(
                harness.Web,
                x => x.Value<string>("cmd") == "character_create_snapshot");
        }

        [Fact]
        public void ResetInvalidatesQueuedSnapshotDeadlineCallback()
        {
            using var harness = new Harness();
            const string attempt = "attempt-reset-snapshot-deadline";
            harness.PreparePrewarmAttempt(attempt);

            string openedAttempt;
            string slotKey;
            string error;
            Assert.True(OpenCharacterCreate(harness.Flow,
                "new", null, out openedAttempt, out slotKey, out error), error);
            harness.SetState(GameLaunchFlow.State.WaitingGameReady);
            harness.SendBootstrap("bootstrap_ready", attempt);
            harness.SendBootstrap("bootstrap_reveal_ready", attempt);
            JObject snapshotRequest = Assert.Single(
                harness.As2.Where(x => x.Value<string>("action")
                    == "characterCreationSnapshot"));
            string callId = snapshotRequest.Value<string>("callId");
            Assert.NotNull(GetPrivateField<Timer>(
                harness.Flow, "_characterCreateSnapshotTimer"));

            harness.Flow.Reset(null, "snapshot_deadline_test_reset");
            Assert.Null(GetPrivateField<Timer>(
                harness.Flow, "_characterCreateSnapshotTimer"));
            int webCountAtReset = harness.Web.Count;
            InvokePrivate(
                harness.Flow,
                "OnCharacterCreateSnapshotTimeout",
                attempt,
                slotKey,
                callId);
            harness.Send(BuildSnapshotResponse(attempt, slotKey, callId));

            Assert.Equal(webCountAtReset, harness.Web.Count);
            Assert.Empty(harness.LastPlayed);
            Assert.False(harness.Flow.RevealPerformed);
        }

        [Fact]
        public void FrontdoorLoad_CannotDisableMandatoryTitleWatchdog()
        {
            using var harness = new Harness();
            const string attempt = "attempt-title-required";
            const string slot = "slot_title_required";
            harness.SeedShadow(slot, "标题门测试", 3);
            harness.PreparePrewarmAttempt(attempt);

            harness.Flow.StartGameFromBootstrap(slot, false, false);
            harness.SetState(GameLaunchFlow.State.WaitingGameReady);
            harness.SendBootstrap("bootstrap_ready", attempt);

            Assert.NotNull(GetPrivateField<Timer>(
                harness.Flow,
                "_flashRevealWatchdog"));
            Assert.Empty(harness.As2);
            InvokePrivate(harness.Flow, "OnFlashRevealWatchdogFired", attempt);
            Assert.Equal(GameLaunchFlow.State.Error.ToString(), harness.Flow.CurrentState);
            Assert.Empty(harness.LastPlayed);
        }

        [Fact]
        public void TerminalError_IgnoresLateExactCreateReceipts()
        {
            using var harness = new Harness();
            const string attempt = "attempt-late-after-error";
            harness.PreparePrewarmAttempt(attempt);

            string openedAttempt;
            string slotKey;
            string error;
            Assert.True(OpenCharacterCreate(harness.Flow,
                "new", null, out openedAttempt, out slotKey, out error), error);
            harness.SetState(GameLaunchFlow.State.WaitingGameReady);
            harness.SendBootstrap("bootstrap_ready", attempt);
            harness.SendBootstrap("bootstrap_reveal_ready", attempt);
            JObject snapshotRequest = Assert.Single(
                harness.As2.Where(x => x.Value<string>("action")
                    == "characterCreationSnapshot"));
            harness.Send(BuildSnapshotResponse(
                attempt,
                slotKey,
                snapshotRequest.Value<string>("callId")));
            Assert.True(SubmitCharacterCreate(harness.Flow,
                attempt, slotKey, "迟到回执", BuildDraft(), out error), error);
            JObject createRequest = Assert.Single(
                harness.As2.Where(x => x.Value<string>("action")
                    == "characterCreate"));
            string createCallId = createRequest.Value<string>("callId");

            InvokePrivate(harness.Flow, "TransitionToError", "forced_test_error");
            int webCountAtError = harness.Web.Count;
            harness.Send(BuildCreateResponse(
                attempt, slotKey, createCallId, "durable", true, true));
            JObject rejected = BuildCreateResponse(
                attempt, slotKey, createCallId, "rejected", false, false);
            rejected["error"] = "late_rejection";
            harness.Send(rejected);
            harness.Flow.ObserveUiData(new UiDataPacket("s:1|ga:" + attempt));

            Assert.Equal(GameLaunchFlow.State.Error.ToString(), harness.Flow.CurrentState);
            Assert.Equal(webCountAtError, harness.Web.Count);
            Assert.False(harness.Archive.SlotCatalog.ReadAll().ContainsKey(slotKey));
            Assert.Empty(harness.LastPlayed);
            Assert.False(harness.Flow.RevealPerformed);
        }

        [Fact]
        public void TerminalError_IgnoresLateExactSnapshot()
        {
            using var harness = new Harness();
            const string attempt = "attempt-late-snapshot-error";
            harness.PreparePrewarmAttempt(attempt);

            string openedAttempt;
            string slotKey;
            string error;
            Assert.True(OpenCharacterCreate(harness.Flow,
                "new", null, out openedAttempt, out slotKey, out error), error);
            harness.SetState(GameLaunchFlow.State.WaitingGameReady);
            harness.SendBootstrap("bootstrap_ready", attempt);
            harness.SendBootstrap("bootstrap_reveal_ready", attempt);
            JObject snapshotRequest = Assert.Single(
                harness.As2.Where(x => x.Value<string>("action")
                    == "characterCreationSnapshot"));

            InvokePrivate(harness.Flow, "TransitionToError", "forced_snapshot_error");
            int webCountAtError = harness.Web.Count;
            harness.Send(BuildSnapshotResponse(
                attempt,
                slotKey,
                snapshotRequest.Value<string>("callId")));

            Assert.Equal(webCountAtError, harness.Web.Count);
            Assert.DoesNotContain(
                harness.Web,
                x => x.Value<string>("cmd") == "character_create_snapshot");
            Assert.Equal(GameLaunchFlow.State.Error.ToString(), harness.Flow.CurrentState);
        }

        [Fact]
        public void DurableCreate_ArmsSceneDeadlineAndTimesOutFailClosed()
        {
            using var harness = new Harness();
            const string attempt = "attempt-durable-scene-timeout";
            harness.PreparePrewarmAttempt(attempt);

            string openedAttempt;
            string slotKey;
            string error;
            Assert.True(OpenCharacterCreate(harness.Flow,
                "new", null, out openedAttempt, out slotKey, out error), error);
            harness.SetState(GameLaunchFlow.State.WaitingGameReady);
            harness.SendBootstrap("bootstrap_ready", attempt);
            harness.SendBootstrap("bootstrap_reveal_ready", attempt);
            JObject snapshotRequest = Assert.Single(
                harness.As2.Where(x => x.Value<string>("action")
                    == "characterCreationSnapshot"));
            harness.Send(BuildSnapshotResponse(
                attempt, slotKey, snapshotRequest.Value<string>("callId")));
            Assert.True(SubmitCharacterCreate(harness.Flow,
                attempt, slotKey, "超时测试", BuildDraft(), out error), error);
            JObject createRequest = Assert.Single(
                harness.As2.Where(x => x.Value<string>("action")
                    == "characterCreate"));
            harness.Send(BuildCreateResponse(
                attempt,
                slotKey,
                createRequest.Value<string>("callId"),
                "durable",
                true,
                true));
            Assert.NotNull(GetPrivateField<Timer>(
                harness.Flow, "_frontdoorSceneWatchdog"));

            InvokePrivate(
                harness.Flow,
                "OnFrontdoorSceneWatchdogFired",
                attempt);

            Assert.Equal(GameLaunchFlow.State.Error.ToString(), harness.Flow.CurrentState);
            Assert.False(harness.Flow.RevealPerformed);
            Assert.Null(GetPrivateField<Timer>(
                harness.Flow, "_frontdoorSceneWatchdog"));
            JObject sceneError = Assert.Single(
                harness.Web.Where(x => x.Value<string>("phase")
                    == "durable_scene_error"));
            Assert.Equal("timeout", sceneError.Value<string>("error"));
            Assert.Equal(OpenRequestId, sceneError.Value<string>("openRequestId"));
            Assert.Empty(harness.LastPlayed);
        }

        [Fact]
        public void DurableStageRejected_EmitsOneDurableSceneErrorAndNeverReplaysCreate()
        {
            using var harness = new Harness();
            const string attempt = "attempt-stage-rejected";
            harness.PreparePrewarmAttempt(attempt);

            string openedAttempt;
            string slotKey;
            string error;
            Assert.True(OpenCharacterCreate(harness.Flow,
                "new", null, out openedAttempt, out slotKey, out error), error);
            harness.SetState(GameLaunchFlow.State.WaitingGameReady);
            harness.SendBootstrap("bootstrap_ready", attempt);
            harness.SendBootstrap("bootstrap_reveal_ready", attempt);
            JObject snapshotRequest = Assert.Single(
                harness.As2.Where(x => x.Value<string>("action")
                    == "characterCreationSnapshot"));
            harness.Send(BuildSnapshotResponse(
                attempt,
                slotKey,
                snapshotRequest.Value<string>("callId")));
            Assert.True(SubmitCharacterCreate(harness.Flow,
                attempt, slotKey, "教学失败槽位", BuildDraft(), out error), error);
            JObject createRequest = Assert.Single(
                harness.As2.Where(x => x.Value<string>("action")
                    == "characterCreate"));
            string createCallId = createRequest.Value<string>("callId");
            harness.Send(BuildCreateResponse(
                attempt, slotKey, createCallId, "durable", true, true));

            JObject rejected = BuildCreateResponse(
                attempt, slotKey, createCallId, "rejected", false, false);
            rejected["durable"] = true;
            rejected["error"] = "tutorial_stage_failed";
            harness.Send(rejected);
            harness.Send(rejected);

            Assert.Equal(GameLaunchFlow.State.Error.ToString(), harness.Flow.CurrentState);
            JObject sceneError = Assert.Single(
                harness.Web.Where(x => x.Value<string>("phase")
                    == "durable_scene_error"));
            Assert.Equal("load", sceneError.Value<string>("error"));
            Assert.Equal("tutorial_stage_failed", sceneError.Value<string>("detail"));
            Assert.Equal(OpenRequestId, sceneError.Value<string>("openRequestId"));
            Assert.Single(harness.As2.Where(x => x.Value<string>("action")
                == "characterCreate"));
            Assert.Empty(harness.LastPlayed);
            Assert.Null(GetPrivateField<Timer>(
                harness.Flow, "_flashRevealWatchdog"));
        }

        [Fact]
        public void NormalBootstrapStart_PushesResolvedEntryAndWaitsForExactScene()
        {
            using var harness = new Harness();
            const string attempt = "attempt-load";
            const string slot = "slot_load";
            harness.SeedShadow(slot, "读取角色", 12);
            harness.PreparePrewarmAttempt(attempt);

            harness.Flow.StartGameFromBootstrap(slot, false, true);
            SolResolveResult resolved = GetPrivateField<SolResolveResult>(
                harness.Flow, "_resolvedSave");
            Assert.Equal("snapshot", resolved.WireDecision);
            Assert.Empty(harness.LastPlayed);

            harness.SetState(GameLaunchFlow.State.WaitingGameReady);
            harness.SendBootstrap("bootstrap_ready", attempt);
            harness.SendBootstrap("bootstrap_reveal_ready", attempt);
            JObject entry = Assert.Single(
                harness.As2.Where(x => x.Value<string>("action")
                    == "frontdoorEnterResolvedSave"));
            Assert.Equal(slot, entry.Value<string>("slotKey"));
            Assert.False(string.IsNullOrEmpty(entry.Value<string>("callId")));
            Assert.False(harness.Flow.RevealPerformed);
            Assert.Empty(harness.LastPlayed);
            Assert.NotNull(GetPrivateField<Timer>(
                harness.Flow, "_frontdoorSceneWatchdog"));

            harness.Flow.ObserveUiData(new UiDataPacket("s:1|ga:stale"));
            Assert.False(harness.Flow.RevealPerformed);
            harness.Flow.ObserveUiData(new UiDataPacket(
                "s:1|ga:" + attempt));
            Assert.True(harness.Flow.RevealPerformed);
            Assert.Equal(new string[] { slot }, harness.LastPlayed);
            Assert.Null(GetPrivateField<Timer>(
                harness.Flow, "_frontdoorSceneWatchdog"));

            InvokePrivate(
                harness.Flow,
                "OnFrontdoorSceneWatchdogFired",
                attempt);
            InvokePrivate(
                harness.Flow,
                "OnFlashRevealWatchdogFired",
                attempt);
            Assert.Equal(GameLaunchFlow.State.Ready.ToString(), harness.Flow.CurrentState);
            Assert.True(harness.Flow.RevealPerformed);
            Assert.Equal(new string[] { slot }, harness.LastPlayed);
        }

        [Fact]
        public void NormalBootstrapSceneWatchdog_TimesOutFailClosed()
        {
            using var harness = new Harness();
            const string attempt = "attempt-load-timeout";
            const string slot = "slot_load_timeout";
            harness.SeedShadow(slot, "读取超时", 12);
            harness.PreparePrewarmAttempt(attempt);

            harness.Flow.StartGameFromBootstrap(slot, false, true);
            harness.SetState(GameLaunchFlow.State.WaitingGameReady);
            harness.SendBootstrap("bootstrap_ready", attempt);
            harness.SendBootstrap("bootstrap_reveal_ready", attempt);
            Assert.NotNull(GetPrivateField<Timer>(
                harness.Flow, "_frontdoorSceneWatchdog"));

            InvokePrivate(
                harness.Flow,
                "OnFrontdoorSceneWatchdogFired",
                attempt);

            Assert.Equal(GameLaunchFlow.State.Error.ToString(), harness.Flow.CurrentState);
            Assert.False(harness.Flow.RevealPerformed);
            Assert.Empty(harness.LastPlayed);
            Assert.Null(GetPrivateField<Timer>(
                harness.Flow, "_frontdoorSceneWatchdog"));

            harness.Flow.ObserveUiData(new UiDataPacket(
                "s:1|ga:" + attempt));
            Assert.Equal(GameLaunchFlow.State.Error.ToString(), harness.Flow.CurrentState);
            Assert.False(harness.Flow.RevealPerformed);
            Assert.Empty(harness.LastPlayed);
        }

        [Fact]
        public void ResetInvalidatesQueuedSceneWatchdogCallback()
        {
            using var harness = new Harness();
            const string attempt = "attempt-reset-watchdog";
            const string slot = "slot_reset_watchdog";
            harness.SeedShadow(slot, "重置测试", 12);
            harness.PreparePrewarmAttempt(attempt);

            harness.Flow.StartGameFromBootstrap(slot, false, true);
            harness.SetState(GameLaunchFlow.State.WaitingGameReady);
            harness.SendBootstrap("bootstrap_ready", attempt);
            harness.SendBootstrap("bootstrap_reveal_ready", attempt);
            Assert.NotNull(GetPrivateField<Timer>(
                harness.Flow, "_frontdoorSceneWatchdog"));

            harness.Flow.Reset(null, "watchdog_test_reset");
            Assert.Null(GetPrivateField<Timer>(
                harness.Flow, "_frontdoorSceneWatchdog"));
            InvokePrivate(
                harness.Flow,
                "OnFrontdoorSceneWatchdogFired",
                attempt);

            Assert.NotEqual(GameLaunchFlow.State.Error.ToString(), harness.Flow.CurrentState);
            Assert.False(harness.Flow.RevealPerformed);
            Assert.Empty(harness.LastPlayed);

            harness.Flow.ObserveUiData(new UiDataPacket(
                "s:1|ga:" + attempt));
            harness.SendBootstrap("bootstrap_reveal_ready", attempt);
            Assert.NotEqual(GameLaunchFlow.State.Error.ToString(), harness.Flow.CurrentState);
            Assert.False(harness.Flow.RevealPerformed);
            Assert.Empty(harness.LastPlayed);
        }

        private static JObject BuildSnapshotResponse(
            string attemptId,
            string slotKey,
            string callId)
        {
            JObject defaults = new JObject
            {
                ["height"] = 170,
                ["faceIdentifier"] = "face_a",
                ["hairIdentifier"] = "hair_a",
                ["upperIdentifier"] = "upper_a",
                ["lowerIdentifier"] = "lower_a",
                ["footwearIdentifier"] = "foot_a",
                ["difficulty"] = "normal"
            };
            return new JObject
            {
                ["task"] = "character_create_response",
                ["callId"] = callId,
                ["v"] = 1,
                ["operation"] = "snapshot",
                ["phase"] = "snapshot",
                ["success"] = true,
                ["attemptId"] = attemptId,
                ["slotKey"] = slotKey,
                ["constraints"] = new JObject
                {
                    ["displayNameMin"] = 1,
                    ["displayNameMax"] = 32,
                    ["characterNameMin"] = 1,
                    ["characterNameMax"] = 12,
                    ["heightMin"] = 150,
                    ["heightMax"] = 200
                },
                ["defaults"] = new JObject
                {
                    ["male"] = defaults.DeepClone(),
                    ["female"] = defaults.DeepClone()
                },
                ["appearanceCatalog"] = new JObject
                {
                    ["faces"] = new JObject
                    {
                        ["male"] = new JObject
                        {
                            ["identifier"] = "face_a",
                            ["name"] = "男脸"
                        },
                        ["female"] = new JObject
                        {
                            ["identifier"] = "face_b",
                            ["name"] = "女脸"
                        }
                    },
                    ["upper"] = BuildAppearanceCatalog(
                        "upper_a", "上装"),
                    ["lower"] = BuildAppearanceCatalog(
                        "lower_a", "下装"),
                    ["footwear"] = BuildAppearanceCatalog(
                        "foot_a", "鞋靴")
                },
                ["hairCatalog"] = new JArray(),
                ["difficulties"] = new JArray("normal")
            };
        }

        private static JObject BuildAppearanceCatalog(
            string identifier,
            string name)
        {
            return new JObject
            {
                ["male"] = new JArray(BuildAppearanceRow(identifier, name + "男")),
                ["female"] = new JArray(BuildAppearanceRow(identifier, name + "女"))
            };
        }

        private static JObject BuildAppearanceRow(
            string identifier,
            string name)
        {
            return new JObject
            {
                ["identifier"] = identifier,
                ["name"] = name,
                ["iconName"] = name + "图标",
                ["itemType"] = "服装",
                ["introHTML"] = "<b>权威简介</b>\r\n\t可换装",
                ["descHTML"] = "权威说明\r\n可免费选择"
            };
        }

        private static JObject BuildCreateResponse(
            string attemptId,
            string slotKey,
            string callId,
            string phase,
            bool success,
            bool localFlush)
        {
            return new JObject
            {
                ["task"] = "character_create_response",
                ["callId"] = callId,
                ["v"] = 1,
                ["operation"] = "create",
                ["phase"] = phase,
                ["success"] = success,
                ["localFlush"] = localFlush,
                ["attemptId"] = attemptId,
                ["slotKey"] = slotKey
            };
        }

        private static JObject BuildDraft()
        {
            return new JObject
            {
                ["characterName"] = "新角色",
                ["gender"] = "male",
                ["height"] = 170,
                ["faceIdentifier"] = "face_a",
                ["hairIdentifier"] = "hair_a",
                ["upperIdentifier"] = "upper_a",
                ["lowerIdentifier"] = "lower_a",
                ["footwearIdentifier"] = "foot_a",
                ["difficulty"] = "normal"
            };
        }

        private static T GetPrivateField<T>(object target, string name)
        {
            FieldInfo field = target.GetType().GetField(
                name,
                BindingFlags.Instance | BindingFlags.NonPublic);
            Assert.NotNull(field);
            return (T)field.GetValue(target);
        }

        private static void SetPrivateField<T>(object target, string name, T value)
        {
            FieldInfo field = target.GetType().GetField(
                name,
                BindingFlags.Instance | BindingFlags.NonPublic);
            Assert.NotNull(field);
            field.SetValue(target, value);
        }

        private static void InvokePrivate(
            object target,
            string name,
            params object[] arguments)
        {
            MethodInfo method = target.GetType().GetMethod(
                name,
                BindingFlags.Instance | BindingFlags.NonPublic);
            Assert.NotNull(method);
            method.Invoke(target, arguments);
        }

        private sealed class Harness : IDisposable
        {
            private readonly string _root;
            private readonly string _shareRoot;
            private readonly string _swfPath;
            private readonly ProcessManager _processManager;
            private readonly XmlSocketServer _server;
            private readonly MessageRouter _router;

            internal Harness()
            {
                _root = Path.Combine(
                    Path.GetTempPath(),
                    "cf7-frontdoor-" + Guid.NewGuid().ToString("N"));
                Directory.CreateDirectory(_root);
                _shareRoot = Path.Combine(_root, "shared-objects");
                Directory.CreateDirectory(_shareRoot);
                _swfPath = Path.Combine(_root, "game", "main.swf");
                Directory.CreateDirectory(Path.GetDirectoryName(_swfPath));

                Archive = new ArchiveTask(_root);
                var locator = new SolFileLocator(_shareRoot);
                var resolver = new SolResolver(
                    locator,
                    Archive,
                    new NativeSolParser(),
                    Archive);
                var saveContext = new SaveResolutionContext(
                    locator,
                    resolver,
                    Archive,
                    _swfPath,
                    _root);

                _router = new MessageRouter();
                _server = new XmlSocketServer(
                    _router,
                    AllowLoopbackXmlSocketPeerAuthority.Instance);
                _processManager = new ProcessManager(
                    "unused-flash.exe",
                    "unused.swf");
                Flow = new GameLaunchFlow(
                    _server,
                    _router,
                    _processManager,
                    new WindowManager(),
                    null,
                    null,
                    null,
                    null,
                    saveContext,
                    60000,
                    delegate(string slot) { LastPlayed.Add(slot); });
                Flow.CharacterCreateWebPostForTests = delegate(JObject value)
                {
                    Web.Add(value);
                };
                Flow.CharacterCreateAs2PushForTests = delegate(JObject value)
                {
                    As2.Add(value);
                };
            }

            internal ArchiveTask Archive { get; }
            internal GameLaunchFlow Flow { get; }
            internal List<JObject> Web { get; } = new List<JObject>();
            internal List<JObject> As2 { get; } = new List<JObject>();
            internal List<string> LastPlayed { get; } = new List<string>();

            internal void PreparePrewarmAttempt(string attemptId)
            {
                SetPrivateField(
                    Flow,
                    "_state",
                    GameLaunchFlow.State.WaitingConnect);
                SetPrivateField(Flow, "_currentAttemptId", attemptId);
                SetPrivateField<string>(Flow, "_pendingSlot", null);
            }

            internal void SetState(GameLaunchFlow.State state)
            {
                SetPrivateField(Flow, "_state", state);
            }

            internal void SeedShadow(string slot, string characterName, int level)
            {
                string target;
                string error;
                Assert.True(Archive.TrySeedShadowSync(
                    slot,
                    RebuildBackupStoreTests.BuildSnapshot(characterName, level),
                    out target,
                    out error), error);
            }

            internal string CreateSolFile(string slot)
            {
                string hash = Path.Combine(_shareRoot, "hash-a");
                string root = Path.GetPathRoot(_swfPath);
                string rest = _swfPath.Substring(root != null ? root.Length : 0);
                string path = Path.Combine(hash, "localhost");
                string[] parts = rest.Split(
                    new char[] { '\\', '/' },
                    StringSplitOptions.RemoveEmptyEntries);
                for (int i = 0; i < parts.Length; i++)
                    path = Path.Combine(path, parts[i]);
                Directory.CreateDirectory(path);
                string solPath = Path.Combine(path, slot + ".sol");
                File.WriteAllBytes(solPath, new byte[] { 1, 2, 3 });
                Assert.NotNull(new SolFileLocator(_shareRoot).FindSolFile(
                    slot, _swfPath));
                return solPath;
            }

            internal string CreateTombstone(string slot)
            {
                string path = Path.Combine(
                    Archive.SavesDir,
                    slot + ".tombstone");
                File.WriteAllText(path, "deleted");
                Assert.True(Archive.IsTombstoned(slot));
                return path;
            }

            internal void SendBootstrap(string task, string attemptId)
            {
                Send(new JObject
                {
                    ["task"] = task,
                    ["attemptId"] = attemptId
                });
            }

            internal void Send(JObject message)
            {
                _router.ProcessMessage(
                    message.ToString(Formatting.None),
                    null);
            }

            internal string LastStatePhase()
            {
                return Web.Last(x => x.Value<string>("cmd")
                    == "character_create_state").Value<string>("phase");
            }

            public void Dispose()
            {
                DisposeTimer("_characterCreateSnapshotTimer");
                DisposeTimer("_characterCreateDefinitiveTimer");
                DisposeTimer("_flashRevealWatchdog");
                DisposeTimer("_frontdoorSceneWatchdog");
                _processManager.Dispose();
                _server.Dispose();
                try { Directory.Delete(_root, true); }
                catch { }
            }

            private void DisposeTimer(string fieldName)
            {
                Timer timer = GetPrivateField<Timer>(Flow, fieldName);
                if (timer != null) timer.Dispose();
            }
        }
    }
}
