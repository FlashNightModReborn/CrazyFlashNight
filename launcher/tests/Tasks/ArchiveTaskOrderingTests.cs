// ArchiveTask R3a 顺序门 / tombstone TOCTOU / accepted-state 基线测试。
//
// 背景（第二次 GPT Pro 裁决 §4.1 / §4.4）：
//   - 旧 HandleAsync 对每条消息独立 ThreadPool.QueueUserWorkItem，lock 只串行
//     写文件不保证按到达顺序 → completion-order-wins 而非 latest-wins。
//   - 普通 shadow 曾用 clearTombstone:true 主动删墓碑。
//   - userEdit 的 tombstone 检查在 _lock 外（检查后到写入前有竞态）。
//   - RunConsistencyCheck 在物理写成功前更新 _prevSnapshots，失败/被拒候选
//     会污染下一次比较基线。
// 本文件用 ShadowWriteGateForTests 强制"后到消息先完成"的乱序条件，证明
// 单 FIFO executor 顺序门与同一临界区语义。

using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Threading;
using CF7Launcher.Tasks;
using CF7Launcher.Tests.Save;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public class ArchiveTaskOrderingTests : IDisposable
    {
        private readonly string _projectRoot;
        private readonly string _savesDir;
        private readonly ArchiveTask _archive;
        private int _completionSeq;

        public ArchiveTaskOrderingTests()
        {
            _projectRoot = Path.Combine(Path.GetTempPath(), "cf7-archive-order-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(_projectRoot);
            _savesDir = Path.Combine(_projectRoot, "saves");
            Directory.CreateDirectory(_savesDir);
            _archive = new ArchiveTask(_projectRoot);
        }

        public void Dispose()
        {
            try { if (Directory.Exists(_projectRoot)) Directory.Delete(_projectRoot, true); }
            catch { }
        }

        // ==================== 顺序门 ====================

        [Fact]
        public void Fifo_StalledFirstShadow_LaterShadowCannotOvertake()
        {
            // 强制"S1 慢、S2 快"：S1 在写入临界区前被钩住。旧线程池模型下 S2 会
            // 先完成（先响应、且因 S1 后拿到 lock 而最终覆写文件）；FIFO 下 S2
            // 必须严格排在 S1 之后执行。
            const string slot = "slot_r3a_overtake";
            ManualResetEventSlim gateEntered = new ManualResetEventSlim(false);
            ManualResetEventSlim release = new ManualResetEventSlim(false);
            int gateHits = 0;
            _archive.ShadowWriteGateForTests = delegate(string s)
            {
                if (Interlocked.CompareExchange(ref gateHits, 1, 0) == 0)
                {
                    gateEntered.Set();
                    release.Wait(TimeSpan.FromSeconds(10));
                }
            };

            PendingResponse s1 = SendShadow(slot, "角色甲", 1);
            Assert.True(gateEntered.Wait(TimeSpan.FromSeconds(5)), "S1 未进入写入闸门");
            PendingResponse s2 = SendShadow(slot, "角色甲", 2);

            Assert.False(
                s2.Wait(TimeSpan.FromMilliseconds(300)),
                "S1 被钩住期间 S2 不得完成（不得超车）");

            release.Set();
            JObject r1 = s1.Result(TimeSpan.FromSeconds(5));
            JObject r2 = s2.Result(TimeSpan.FromSeconds(5));
            Assert.True(r1.Value<bool>("success"));
            Assert.True(r2.Value<bool>("success"));
            Assert.True(
                s1.CompletionSeq < s2.CompletionSeq,
                "响应顺序必须等于到达顺序（S1 先于 S2）");

            // latest-arrival-wins：最终落盘内容必须是最后到达的 S2。
            JObject written = ReadSlotJson(slot);
            Assert.Equal(2, (int)((JArray)written["0"])[3]);
        }

        [Fact]
        public void Fifo_DeleteWaitsBehindStalledShadow_NoResurrection()
        {
            // delete 必须与 shadow 进同一顺序门：若 delete 旁路，S1 被钩住期间
            // tombstone 就会出现，且 S1 放行后会把 .json 重新写回（复活）。
            const string slot = "slot_r3a_deletegate";
            ManualResetEventSlim gateEntered = new ManualResetEventSlim(false);
            ManualResetEventSlim release = new ManualResetEventSlim(false);
            int gateHits = 0;
            _archive.ShadowWriteGateForTests = delegate(string s)
            {
                if (Interlocked.CompareExchange(ref gateHits, 1, 0) == 0)
                {
                    gateEntered.Set();
                    release.Wait(TimeSpan.FromSeconds(10));
                }
            };

            PendingResponse s1 = SendShadow(slot, "角色乙", 3);
            Assert.True(gateEntered.Wait(TimeSpan.FromSeconds(5)), "S1 未进入写入闸门");
            PendingResponse del = SendOp("delete", slot);

            Assert.False(
                del.Wait(TimeSpan.FromMilliseconds(300)),
                "S1 被钩住期间 delete 不得完成（不得旁路顺序门）");
            Assert.False(File.Exists(TombPath(slot)), "delete 未执行前不得出现 tombstone");

            release.Set();
            JObject r1 = s1.Result(TimeSpan.FromSeconds(5));
            JObject rd = del.Result(TimeSpan.FromSeconds(5));
            Assert.True(r1.Value<bool>("success"));
            Assert.True(rd.Value<bool>("success"));
            Assert.True(rd.Value<bool>("tombstoned"));

            // 到达顺序 shadow→delete：最终必须是墓碑留存、无 .json 复活。
            Assert.False(File.Exists(JsonPath(slot)), "delete 后不得残留/复活 .json");
            Assert.True(File.Exists(TombPath(slot)));
        }

        [Fact]
        public void Fifo_LoadSeesPrecedingShadow()
        {
            // load 与 shadow 同门：先到的 shadow 对后到的 load 必须可见
            // （load-after-write 语义，AS2 preload 依赖）。
            const string slot = "slot_r3a_loadgate";
            ManualResetEventSlim gateEntered = new ManualResetEventSlim(false);
            ManualResetEventSlim release = new ManualResetEventSlim(false);
            int gateHits = 0;
            _archive.ShadowWriteGateForTests = delegate(string s)
            {
                if (Interlocked.CompareExchange(ref gateHits, 1, 0) == 0)
                {
                    gateEntered.Set();
                    release.Wait(TimeSpan.FromSeconds(10));
                }
            };

            PendingResponse s1 = SendShadow(slot, "角色丙", 8);
            Assert.True(gateEntered.Wait(TimeSpan.FromSeconds(5)), "S1 未进入写入闸门");
            PendingResponse load = SendOp("load", slot);

            Assert.False(
                load.Wait(TimeSpan.FromMilliseconds(300)),
                "S1 被钩住期间 load 不得完成（不得旁路顺序门）");

            release.Set();
            Assert.True(s1.Result(TimeSpan.FromSeconds(5)).Value<bool>("success"));
            JObject rl = load.Result(TimeSpan.FromSeconds(5));
            Assert.True(rl.Value<bool>("success"));
            JObject loaded = JObject.Parse(rl.Value<string>("data"));
            Assert.Equal(8, (int)((JArray)loaded["0"])[3]);
        }

        [Fact]
        public void Fifo_DeleteResetShadow_RecreateOnlyThroughReset()
        {
            // 全链路顺序语义：shadow→delete→reset→shadow 连发不等响应，
            // FIFO 必须按到达顺序产出：delete 立墓碑、reset 显式撤销墓碑
            // （唯一合法 recreate 路径）、后续 shadow 重新被接受。
            const string slot = "slot_r3a_recreate";
            PendingResponse s1 = SendShadow(slot, "角色丁", 4);
            PendingResponse del = SendOp("delete", slot);
            PendingResponse rst = SendOp("reset", slot);
            PendingResponse s2 = SendShadow(slot, "角色丁", 5);

            Assert.True(s1.Result(TimeSpan.FromSeconds(5)).Value<bool>("success"));
            Assert.True(del.Result(TimeSpan.FromSeconds(5)).Value<bool>("success"));
            JObject rr = rst.Result(TimeSpan.FromSeconds(5));
            Assert.True(rr.Value<bool>("success"));
            Assert.True(rr.Value<bool>("reset"));
            JObject r2 = s2.Result(TimeSpan.FromSeconds(5));
            Assert.True(r2.Value<bool>("success"), "reset 后的 shadow 必须被接受: " + r2);

            Assert.False(File.Exists(TombPath(slot)));
            JObject written = ReadSlotJson(slot);
            Assert.Equal(5, (int)((JArray)written["0"])[3]);
        }

        [Fact]
        public void Fifo_ResetSlotSyncWaitsBehindQueuedShadow()
        {
            // 同步入口 ResetSlotSync（rebuild 重建）同样过门：S1 被钩住期间
            // reset 线程必须阻塞等待，放行后按 shadow→reset 顺序生效。
            const string slot = "slot_r3a_resetsync";
            ManualResetEventSlim gateEntered = new ManualResetEventSlim(false);
            ManualResetEventSlim release = new ManualResetEventSlim(false);
            int gateHits = 0;
            _archive.ShadowWriteGateForTests = delegate(string s)
            {
                if (Interlocked.CompareExchange(ref gateHits, 1, 0) == 0)
                {
                    gateEntered.Set();
                    release.Wait(TimeSpan.FromSeconds(10));
                }
            };

            PendingResponse s1 = SendShadow(slot, "角色戊", 6);
            Assert.True(gateEntered.Wait(TimeSpan.FromSeconds(5)), "S1 未进入写入闸门");

            Exception resetFailure = null;
            ManualResetEventSlim resetDone = new ManualResetEventSlim(false);
            Thread resetThread = new Thread(() =>
            {
                try { _archive.ResetSlotSync(slot); }
                catch (Exception ex) { resetFailure = ex; }
                finally { resetDone.Set(); }
            });
            resetThread.IsBackground = true;
            resetThread.Start();

            Assert.False(
                resetDone.Wait(TimeSpan.FromMilliseconds(300)),
                "ResetSlotSync 不得越过已入队的 shadow 提前完成");

            release.Set();
            Assert.True(s1.Result(TimeSpan.FromSeconds(5)).Value<bool>("success"));
            Assert.True(resetDone.Wait(TimeSpan.FromSeconds(5)), "ResetSlotSync 未在放行后完成");
            Assert.Null(resetFailure);
            Assert.False(File.Exists(JsonPath(slot)), "reset 后不得残留 .json");
            Assert.False(File.Exists(TombPath(slot)), "reset 后不得残留 tombstone");
        }

        // ==================== tombstone 语义（不清墓碑 + TOCTOU） ====================

        [Fact]
        public void Shadow_TombstonedSlot_Rejected_TombstoneKept()
        {
            // 普通 shadow 不得清 tombstone（旧行为：clearTombstone:true 会删墓碑并
            // 覆写槽位，delete 后迟到的 shadow 可复活旧档）。
            const string slot = "slot_r3a_tombshadow";
            File.WriteAllText(TombPath(slot), "{\"deletedAt\":\"x\"}", new UTF8Encoding(false));

            JObject resp = SendShadow(slot, "角色己", 7).Result(TimeSpan.FromSeconds(5));

            Assert.False(resp.Value<bool>("success"));
            Assert.Equal("slot_tombstoned", resp.Value<string>("error"));
            Assert.True(File.Exists(TombPath(slot)), "tombstone 必须保留");
            Assert.False(File.Exists(JsonPath(slot)), "被拒 shadow 不得落盘");
        }

        [Fact]
        public void UserEditShadow_TombstonedSlot_Rejected_TombstoneKept()
        {
            // userEdit 的 tombstone 检查与写入在同一临界区（修复 _lock 外检查的
            // TOCTOU）；用户态编辑同样不得清墓碑。
            const string slot = "slot_r3a_tombuseredit";
            File.WriteAllText(TombPath(slot), "{\"deletedAt\":\"x\"}", new UTF8Encoding(false));

            JObject resp = SendShadow(slot, "角色庚", 7, userEdit: true).Result(TimeSpan.FromSeconds(5));

            Assert.False(resp.Value<bool>("success"));
            Assert.Equal("slot_tombstoned", resp.Value<string>("error"));
            Assert.True(File.Exists(TombPath(slot)));
            Assert.False(File.Exists(JsonPath(slot)));
        }

        [Fact]
        public void DeleteThenUserEdit_DeterministicRejection()
        {
            // 到达顺序 delete→userEdit：tombstone 先立，userEdit 必被拒。
            // 检查+写入同临界区，不存在"检查后墓碑才落"的撕裂态。
            const string slot = "slot_r3a_del_edit";
            PendingResponse del = SendOp("delete", slot);
            PendingResponse edit = SendShadow(slot, "角色辛", 9, userEdit: true);

            Assert.True(del.Result(TimeSpan.FromSeconds(5)).Value<bool>("success"));
            JObject re = edit.Result(TimeSpan.FromSeconds(5));
            Assert.False(re.Value<bool>("success"));
            Assert.Equal("slot_tombstoned", re.Value<string>("error"));
            Assert.True(File.Exists(TombPath(slot)));
            Assert.False(File.Exists(JsonPath(slot)));
        }

        [Fact]
        public void UserEditThenDelete_DeterministicApplyThenTombstone()
        {
            // 到达顺序 userEdit→delete：编辑先完整落盘，delete 再立墓碑删档。
            const string slot = "slot_r3a_edit_del";
            PendingResponse edit = SendShadow(slot, "角色壬", 9, userEdit: true);
            PendingResponse del = SendOp("delete", slot);

            Assert.True(edit.Result(TimeSpan.FromSeconds(5)).Value<bool>("success"));
            JObject rd = del.Result(TimeSpan.FromSeconds(5));
            Assert.True(rd.Value<bool>("success"));
            Assert.True(rd.Value<bool>("tombstoned"));
            Assert.True(File.Exists(TombPath(slot)));
            Assert.False(File.Exists(JsonPath(slot)));
        }

        [Fact]
        public void Seed_TombstonedSlot_FailsAndKeepsTombstone()
        {
            // seed/repair 同步入口同样不得清 tombstone。
            const string slot = "slot_r3a_seedtomb";
            File.WriteAllText(TombPath(slot), "{\"deletedAt\":\"x\"}", new UTF8Encoding(false));

            string targetPath;
            string error;
            bool ok = _archive.TrySeedShadowSync(
                slot,
                RebuildBackupStoreTests.BuildSnapshot("角色癸", 3),
                out targetPath,
                out error);

            Assert.False(ok);
            Assert.Equal("slot_tombstoned", error);
            Assert.Null(targetPath);
            Assert.True(File.Exists(TombPath(slot)));
            Assert.False(File.Exists(JsonPath(slot)));
        }

        // ==================== accepted-state 基线 ====================

        [Fact]
        public void FailedWrite_DoesNotPolluteConsistencyBaseline()
        {
            // 物理写失败的候选不得更新 _prevSnapshots：A(10) 接受；B(5) 因 .tmp
            // 路径被目录占用而写失败；C(7) 必须与 A 比较 → 报"等级 倒退: 10 -> 7"。
            // 若 B 污染基线（旧行为：写前更新），C 对比 5 不会报倒退。
            const string slot = "slot_r3a_writefail";
            Assert.True(SendShadow(slot, "角色子", 10).Result(TimeSpan.FromSeconds(5)).Value<bool>("success"));

            string tmpBlock = JsonPath(slot) + ".tmp";
            Directory.CreateDirectory(tmpBlock);
            try
            {
                JObject rb = SendShadow(slot, "角色子", 5).Result(TimeSpan.FromSeconds(5));
                Assert.False(rb.Value<bool>("success"), "tmp 路径被占用时写入必须失败");
            }
            finally
            {
                Directory.Delete(tmpBlock);
            }
            Assert.Equal(10, (int)((JArray)ReadSlotJson(slot)["0"])[3]);

            JObject rc = SendShadow(slot, "角色子", 7).Result(TimeSpan.FromSeconds(5));
            Assert.True(rc.Value<bool>("success"));
            AssertLevelRegression(rc, "10 -> 7");
        }

        [Fact]
        public void RejectedInvalidShadow_DoesNotPolluteConsistencyBaseline()
        {
            // 校验被拒的候选同样不得污染基线。
            const string slot = "slot_r3a_rejectprev";
            Assert.True(SendShadow(slot, "角色丑", 10).Result(TimeSpan.FromSeconds(5)).Value<bool>("success"));

            JObject invalid = RebuildBackupStoreTests.BuildSnapshot("角色丑", 5);
            ((JArray)invalid["0"])[0] = JValue.CreateNull();
            JObject rb = SendShadowRaw(slot, invalid, userEdit: false).Result(TimeSpan.FromSeconds(5));
            Assert.False(rb.Value<bool>("success"));
            Assert.Equal("shadow_snapshot_invalid", rb.Value<string>("error"));

            JObject rc = SendShadow(slot, "角色丑", 9).Result(TimeSpan.FromSeconds(5));
            Assert.True(rc.Value<bool>("success"));
            AssertLevelRegression(rc, "10 -> 9");
        }

        [Fact]
        public void Seed_UpdatesBaselineForNextConsistencyCheck()
        {
            // seed 被接受后在同一临界区更新基线：后续 shadow 与 seed 快照比较。
            const string slot = "slot_r3a_seedprev";
            string targetPath;
            string error;
            Assert.True(_archive.TrySeedShadowSync(
                slot,
                RebuildBackupStoreTests.BuildSnapshot("角色寅", 10),
                out targetPath,
                out error), error);

            JObject rc = SendShadow(slot, "角色寅", 9).Result(TimeSpan.FromSeconds(5));
            Assert.True(rc.Value<bool>("success"));
            AssertLevelRegression(rc, "10 -> 9");
        }

        // ==================== helpers ====================

        private sealed class PendingResponse
        {
            private readonly ManualResetEventSlim _done = new ManualResetEventSlim(false);
            private string _json;
            public int CompletionSeq;

            public void Set(string json, int seq)
            {
                _json = json;
                CompletionSeq = seq;
                _done.Set();
            }

            public bool Wait(TimeSpan timeout)
            {
                return _done.Wait(timeout);
            }

            public JObject Result(TimeSpan timeout)
            {
                Assert.True(_done.Wait(timeout), "Timed out waiting for archive response");
                return JObject.Parse(_json);
            }
        }

        private PendingResponse Dispatch(JObject msg)
        {
            PendingResponse pending = new PendingResponse();
            _archive.HandleAsync(msg, delegate(string r)
            {
                pending.Set(r, Interlocked.Increment(ref _completionSeq));
            });
            return pending;
        }

        private PendingResponse SendShadow(string slot, string name, int level, bool userEdit = false)
        {
            return SendShadowRaw(slot, RebuildBackupStoreTests.BuildSnapshot(name, level), userEdit);
        }

        private PendingResponse SendShadowRaw(string slot, JObject data, bool userEdit)
        {
            JObject msg = new JObject();
            JObject payload = new JObject();
            payload["op"] = "shadow";
            payload["slot"] = slot;
            payload["data"] = data.ToString(Formatting.None);
            if (userEdit) payload["userEdit"] = true;
            msg["payload"] = payload;
            return Dispatch(msg);
        }

        private PendingResponse SendOp(string op, string slot)
        {
            JObject msg = new JObject();
            JObject payload = new JObject();
            payload["op"] = op;
            payload["slot"] = slot;
            msg["payload"] = payload;
            return Dispatch(msg);
        }

        private string JsonPath(string slot)
        {
            return Path.Combine(_savesDir, slot + ".json");
        }

        private string TombPath(string slot)
        {
            return Path.Combine(_savesDir, slot + ".tombstone");
        }

        private JObject ReadSlotJson(string slot)
        {
            return JObject.Parse(File.ReadAllText(JsonPath(slot), Encoding.UTF8));
        }

        private static void AssertLevelRegression(JObject response, string expectedTransition)
        {
            JArray warnings = response.Value<JArray>("warnings");
            Assert.NotNull(warnings);
            string text = warnings.ToString(Formatting.None);
            Assert.Contains("等级 倒退", text);
            Assert.Contains(expectedTransition, text);
        }
    }
}
