// C2-β: BootstrapPanel 修复卡片协议 handler.
//
// 协议 (JS → C#):
//   { type:"bootstrap", cmd:"repair_detect", slot:"alice" }
//     → 读 saves/{slot}.json, 走 RepairPolicy.BuildPlan, 把完整 plan (含每条 fffd 的候选 +
//        policy 自动决议) 序列化回 JS. UI 据此展示 dropdown + 默认采纳建议.
//
//   { type:"bootstrap", cmd:"repair_apply_manual", slot, patches:[...] }
//     → 用户在卡片上挑完候选/手动输入后, JS 整理成 patches 数组发回. handler 加载 fresh
//        shadow → 应用 patches → bump lastSaved → 备份原档 + audit log → 原子写回 →
//        push task=repair_resolved 给 AS2 (cleanedSnapshot 内嵌)
//        patch 形状: { path:[..], spot:"value"|"key",
//                      action:"FixValue"|"RenameKey"|"DropValue"|"ClearValue"|"DropKey",
//                      newValue?, newKey? }
//
//   { type:"bootstrap", cmd:"repair_force_continue", slot }
//     → 用户选择跳过修复直接进游戏 (二次确认过). audit log + push repair_resolved
//        (forced=true, 不带 cleanedSnapshot — AS2 用原 fffd 数据). 下次启动仍会被 SolResolver
//        判定为 Repairable, 直到用户真正修.
//
// 注意:
//   - C2-α 已在 launcher 启动期 inline 跑过自动修复 (RepairPolicy.ApplyHighConfidenceOnly),
//     这里 detect 看到的 fffd 必为 manual_required / preserve_placeholder / 启动后 race
//     残留. 候选数据以 "用户决策" 为目的, 不是再次自动修.
//   - dict 通过 RepairDictionary.LoadFromProjectRoot 现取现读 (JSON 小, 不缓存).
//   - drop_value 在 JArray 上多条同 array 必须按 parentKey 降序应用, 否则索引漂移.
//     ApplyPatches 内部已 sort.

using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using CF7Launcher.Guardian;
using CF7Launcher.Save;
using CF7Launcher.Tasks;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian.Handlers
{
    internal static class RepairCommandHandler
    {
        // ─────────────── public entrypoints ───────────────

        internal static void HandleDetect(JObject msg, BootstrapPanel bootForm, ArchiveTask archiveTask, string projectRoot)
        {
            string slot = msg != null ? msg.Value<string>("slot") : null;
            if (string.IsNullOrEmpty(slot))
            {
                PostDetectError(bootForm, slot, "slot_missing", "repair_detect needs slot");
                return;
            }

            JObject snapshot;
            string loadErr;
            if (!archiveTask.TryLoadShadowSync(slot, out snapshot, out loadErr))
            {
                LogManager.Log("[RepairHandler] detect slot=" + slot + " shadow load failed: " + loadErr);
                PostDetectError(bootForm, slot, "shadow_unavailable",
                    "shadow read failed: " + (loadErr ?? "unknown"));
                return;
            }

            RepairDictionary dict;
            try
            {
                dict = RepairDictionary.LoadFromProjectRoot(projectRoot);
            }
            catch (Exception ex)
            {
                LogManager.Log("[RepairHandler] detect slot=" + slot + " dict load failed: " + ex.Message);
                PostDetectError(bootForm, slot, "dict_unavailable",
                    "dict load failed: " + ex.GetType().Name + ": " + ex.Message);
                return;
            }

            RepairPlan plan;
            try
            {
                plan = RepairPolicy.BuildPlan(snapshot, dict);
            }
            catch (Exception ex)
            {
                LogManager.Log("[RepairHandler] detect slot=" + slot + " plan build failed: " + ex.Message);
                PostDetectError(bootForm, slot, "plan_build_failed",
                    ex.GetType().Name + ": " + ex.Message);
                return;
            }

            JObject planJson = BuildPlanWireJson(plan);
            JObject resp = new JObject();
            resp["type"] = "bootstrap";
            resp["cmd"] = "repair_detect_resp";
            resp["ok"] = true;
            resp["slot"] = slot;
            resp["plan"] = planJson;
            bootForm.PostToWeb(resp.ToString(Formatting.None));

            LogManager.Log("[RepairHandler] detect slot=" + slot
                + " fffd=" + plan.Scan.Total
                + " manual=" + plan.ManualRequired
                + " willBump=" + plan.WillBumpLastSaved);
        }

        internal static void HandleApplyManual(JObject msg, BootstrapPanel bootForm,
            ArchiveTask archiveTask, string projectRoot, GameLaunchFlow launchFlow)
        {
            string slot = msg != null ? msg.Value<string>("slot") : null;
            JArray patches = msg != null ? msg.Value<JArray>("patches") : null;
            if (string.IsNullOrEmpty(slot))
            {
                PostApplyResp(bootForm, slot, false, "slot_missing", "repair_apply_manual needs slot", 0);
                return;
            }
            if (patches == null)
            {
                PostApplyResp(bootForm, slot, false, "patches_missing", "repair_apply_manual needs patches array", 0);
                return;
            }

            JObject snapshot;
            string loadErr;
            if (!archiveTask.TryLoadShadowSync(slot, out snapshot, out loadErr))
            {
                LogManager.Log("[RepairHandler] apply slot=" + slot + " shadow load failed: " + loadErr);
                PostApplyResp(bootForm, slot, false, "shadow_unavailable",
                    "shadow read failed: " + (loadErr ?? "unknown"), 0);
                return;
            }

            // 备份原档 (INV-4) — 即便后续 apply / write 失败也保留 rollback 入口.
            string projectSavesDir = Path.Combine(projectRoot, "saves");
            string ts = RepairBackupStore.FormatTimestamp(DateTime.UtcNow);
            string backupPath;
            try
            {
                string original = JsonConvert.SerializeObject(snapshot, Formatting.None);
                backupPath = RepairBackupStore.WriteBrokenSnapshot(projectSavesDir, slot, ts, original);
            }
            catch (Exception ex)
            {
                LogManager.Log("[RepairHandler] apply slot=" + slot + " backup failed: " + ex.Message);
                PostApplyResp(bootForm, slot, false, "backup_failed",
                    ex.GetType().Name + ": " + ex.Message, 0);
                return;
            }

            // apply patches.
            int applied;
            string applyErr;
            if (!ApplyPatches(snapshot, patches, out applied, out applyErr))
            {
                LogManager.Log("[RepairHandler] apply slot=" + slot + " patch apply failed: " + applyErr);
                PostApplyResp(bootForm, slot, false, "patch_apply_failed", applyErr, 0);
                return;
            }

            // 重扫: 应用后 cleanedSnapshot 仍有 fffd → 用户的 patch 决策不完整 (常见于
            //   ManualRequired 默认走候选 [0] 但目标 key 已存在, ApplyPatches 把这条 RenameKey
            //   skip 了, 残留键仍在). 此时不写盘 / 不 push, 让 web 卡片继续展示问题, 用户重选
            //   drop_key 或换值. backup 已写但保留 (audit 记录已应用了什么, 没修干净也算事件).
            SaveCorruptionReport postReport = SaveCorruptionScanner.Scan(snapshot);
            if (postReport.Total > 0)
            {
                LogManager.Log("[RepairHandler] apply slot=" + slot
                    + " applied=" + applied
                    + " still_corrupt=" + postReport.Total
                    + " (manual decisions left fffd; not writing back, not pushing)");
                JObject resp = new JObject();
                resp["type"] = "bootstrap";
                resp["cmd"] = "repair_apply_manual_resp";
                resp["ok"] = false;
                resp["slot"] = slot;
                resp["error"] = "still_corrupt";
                resp["msg"] = "已应用 " + applied + " 项, 但仍有 " + postReport.Total
                    + " 处 fffd 未消除 (常见于自动选项与现有 key 冲突). "
                    + "请把这些项改成 drop_key / 手动输入后重试.";
                resp["applied"] = applied;
                resp["remaining"] = postReport.Total;
                bootForm.PostToWeb(resp.ToString(Formatting.None));
                return;
            }

            // bump lastSaved (INV-1) — 仅当确实有 patch 应用. 无应用时不动 (与 C2-α 语义一致).
            string newTs = null;
            if (applied > 0)
            {
                newTs = DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm:ss");
                snapshot["lastSaved"] = newTs;
            }

            // audit log.
            try
            {
                StringBuilder sb = new StringBuilder();
                sb.Append("[manual] ts=").Append(ts).Append(" applied=").Append(applied);
                if (newTs != null) sb.Append(" lastSaved=").Append(newTs);
                sb.Append(" patches=").Append(patches.Count);
                RepairBackupStore.WriteAuditLog(projectSavesDir, slot, ts, sb.ToString());
            }
            catch (Exception ex)
            {
                LogManager.Log("[RepairHandler] apply slot=" + slot + " audit write warn: " + ex.Message);
                // 非致命: audit 失败不阻断写盘.
            }

            // 原子写回 (TrySeedShadowSync 内部走 TryWriteShadowAtomic + 更新缓存).
            string targetPath, writeErr;
            if (!archiveTask.TrySeedShadowSync(slot, snapshot, out targetPath, out writeErr))
            {
                LogManager.Log("[RepairHandler] apply slot=" + slot + " write back failed: " + writeErr);
                PostApplyResp(bootForm, slot, false, "write_failed",
                    "shadow write failed: " + (writeErr ?? "unknown"), applied);
                return;
            }
            try { RepairBackupStore.Prune(projectSavesDir, slot); }
            catch (Exception ex) { LogManager.Log("[RepairHandler] prune warn: " + ex.Message); }

            // push repair_resolved 给 AS2 (cleanedSnapshot 嵌入). AS2 在 RepairPending 态等本消息.
            JObject task = new JObject();
            task["task"] = "repair_resolved";
            task["success"] = true;
            task["forced"] = false;
            task["slot"] = slot;
            task["cleanedSnapshot"] = snapshot;
            string taskJson = task.ToString(Formatting.None);
            bool pushed = launchFlow != null && launchFlow.PushRepairResolved(taskJson);

            LogManager.Log("[RepairHandler] apply slot=" + slot
                + " applied=" + applied
                + " bump=" + (newTs ?? "n/a")
                + " backup=" + backupPath
                + " pushed=" + pushed);

            // pushed=false 路径: state 已不在 RepairPending (例如用户已 cancel_launch / launchFlow
            //   被重置). 写盘已成功但 AS2 不会收到 repair_resolved → 不能让 web 进 awaiting-flash 态
            //   等一个永远不会到的 Ready, 否则 30s 后才超时关卡, 用户体感是"假成功".
            //   返回 ok=false 让 web 继续展示卡片, 不切 awaiting 态.
            if (!pushed)
            {
                PostApplyResp(bootForm, slot, false, "push_failed",
                    "存档已修复并写回, 但 launcher 未能向游戏端投递 repair_resolved "
                    + "(状态机已不在 RepairPending). 请返回引导器重新启动, 此时 SOL 将走干净的 shadow.",
                    applied);
                return;
            }

            PostApplyResp(bootForm, slot, true, null, null, applied);
        }

        internal static void HandleForceContinue(JObject msg, BootstrapPanel bootForm,
            ArchiveTask archiveTask, string projectRoot, GameLaunchFlow launchFlow)
        {
            string slot = msg != null ? msg.Value<string>("slot") : null;
            if (string.IsNullOrEmpty(slot))
            {
                PostForceResp(bootForm, slot, false, "slot_missing", "repair_force_continue needs slot");
                return;
            }

            // audit only — 不写存档. 用户已在 UI 二次确认带 fffd 进游戏.
            string projectSavesDir = Path.Combine(projectRoot, "saves");
            string ts = RepairBackupStore.FormatTimestamp(DateTime.UtcNow);
            try
            {
                RepairBackupStore.WriteAuditLog(projectSavesDir, slot, ts,
                    "[forced_continue] ts=" + ts + " user skipped repair, save retains fffd");
            }
            catch (Exception ex)
            {
                LogManager.Log("[RepairHandler] force_continue audit warn: " + ex.Message);
            }

            // push repair_resolved (forced=true, 不带 cleanedSnapshot — AS2 用 handshake 当时的 snapshot).
            JObject task = new JObject();
            task["task"] = "repair_resolved";
            task["success"] = true;
            task["forced"] = true;
            task["slot"] = slot;
            string taskJson = task.ToString(Formatting.None);
            bool pushed = launchFlow != null && launchFlow.PushRepairResolved(taskJson);

            LogManager.Log("[RepairHandler] force_continue slot=" + slot + " pushed=" + pushed);
            // pushed=false: 同 apply 路径, 不能假装 ok 让 web 进 awaiting (永远等不到 Ready).
            if (!pushed)
            {
                PostForceResp(bootForm, slot, false, "push_failed",
                    "launcher 未能向游戏端投递 repair_resolved (状态机已不在 RepairPending). "
                    + "请返回引导器重新启动.");
                return;
            }
            PostForceResp(bootForm, slot, true, null, null);
        }

        // ─────────────── patch application ───────────────

        /// <summary>
        /// 在 snapshot 上应用 patches[]. 关键:
        ///   - drop_value (JArray) 多个 patch 同 array 时必须 parentKey 降序, 否则索引漂移
        ///   - rename_key 不能与目标键冲突 (失败 → 整批回滚, applied=0)
        ///   - patch 引用的路径不存在 → 跳过 (非致命) 并继续
        /// 成功返回 true, applied 为实际修改条数. 失败返回 false (整体不写盘).
        /// </summary>
        internal static bool ApplyPatches(JObject snapshot, JArray patches, out int applied, out string error)
        {
            applied = 0;
            error = null;

            // 解码 patches 到内部结构.
            List<PatchOp> ops = new List<PatchOp>(patches.Count);
            for (int i = 0; i < patches.Count; i++)
            {
                JObject p = patches[i] as JObject;
                if (p == null) { error = "patch[" + i + "] not object"; return false; }
                PatchOp op = ParsePatch(p, i, out error);
                if (op == null) return false;
                ops.Add(op);
            }

            // 排序: drop_value (Array) 排到末尾, 同父按 parentKey 降序.
            ops.Sort(ComparePatchOrder);

            for (int i = 0; i < ops.Count; i++)
            {
                PatchOp op = ops[i];
                JToken parent;
                object parentKey;
                if (!Navigate(snapshot, op.Path, op.Spot, out parent, out parentKey))
                {
                    // 路径不存在: 用户 UI 看到的 plan 与磁盘已 race (e.g. 另一进程写过).
                    // 跳过该 patch, 不计 applied.
                    LogManager.Log("[RepairHandler] patch[" + op.Index + "] path missing: "
                        + string.Join(".", op.Path));
                    continue;
                }
                if (parent == null) continue;

                switch (op.Action)
                {
                    case "FixValue":
                        if (op.NewValue == null) { error = "FixValue without newValue at patch[" + op.Index + "]"; return false; }
                        SetValue(parent, parentKey, op.NewValue);
                        applied++;
                        break;
                    case "RenameKey":
                        if (op.NewKey == null) { error = "RenameKey without newKey at patch[" + op.Index + "]"; return false; }
                        if (parent.Type != JTokenType.Object) { error = "RenameKey on non-object at patch[" + op.Index + "]"; return false; }
                        // collision (target 已存在合法 key, 或同批多条 RenameKey 撞同一 newKey):
                        //   skip 而非 fail, 避免一条 patch 让用户其它决策全部回滚.
                        //   plan 阶段 (DemoteDuplicateRenameKeys + DecideOne 的 collision guard) 已经过滤
                        //   绝大多数 collision; 这里是兜底, 只 log 不 propagate error.
                        bool ok = RenameKeySafe((JObject)parent, (string)parentKey, op.NewKey, out error);
                        if (!ok && error != null && error.IndexOf("collision") >= 0)
                        {
                            LogManager.Log("[RepairHandler] patch[" + op.Index + "] RenameKey collision skipped: "
                                + error + " path=" + string.Join(".", op.Path));
                            error = null;  // 清错误, 让整批继续
                            break;
                        }
                        if (!ok) return false;
                        applied++;
                        break;
                    case "DropValue":
                        if (parent.Type == JTokenType.Array)
                        {
                            JArray arr = (JArray)parent;
                            int idx = (int)parentKey;
                            if (idx >= 0 && idx < arr.Count) { arr.RemoveAt(idx); applied++; }
                        }
                        else if (parent.Type == JTokenType.Object)
                        {
                            ((JObject)parent).Remove((string)parentKey);
                            applied++;
                        }
                        break;
                    case "ClearValue":
                        SetValue(parent, parentKey, "");
                        applied++;
                        break;
                    case "DropKey":
                        if (parent.Type != JTokenType.Object) { error = "DropKey on non-object at patch[" + op.Index + "]"; return false; }
                        ((JObject)parent).Remove((string)parentKey);
                        applied++;
                        break;
                    default:
                        error = "unknown action '" + op.Action + "' at patch[" + op.Index + "]";
                        return false;
                }
            }
            return true;
        }

        private class PatchOp
        {
            public int Index;
            public string[] Path;
            public string Spot;        // "value" | "key"
            public string Action;
            public string NewValue;
            public string NewKey;
        }

        private static PatchOp ParsePatch(JObject p, int idx, out string error)
        {
            error = null;
            JArray pathArr = p["path"] as JArray;
            if (pathArr == null) { error = "patch[" + idx + "] missing path[]"; return null; }
            string[] path = new string[pathArr.Count];
            for (int i = 0; i < pathArr.Count; i++) path[i] = (string)pathArr[i];
            string spot = (string)p["spot"]; if (spot == null) spot = "value";
            string action = (string)p["action"];
            if (string.IsNullOrEmpty(action)) { error = "patch[" + idx + "] missing action"; return null; }
            PatchOp op = new PatchOp();
            op.Index = idx;
            op.Path = path;
            op.Spot = spot;
            op.Action = action;
            op.NewValue = (string)p["newValue"];
            op.NewKey = (string)p["newKey"];
            return op;
        }

        /// <summary>
        /// 沿 path[] 走到 parent + parentKey. spot=="value" 时 path 末段是 value 在 parent 的索引;
        /// spot=="key" 时 path 末段是父 obj 上的目标 key (parent 即父 obj, parentKey 即末段).
        /// path 段对 JArray 解释为整数索引, 对 JObject 解释为 key.
        /// </summary>
        internal static bool Navigate(JObject root, string[] path, string spot, out JToken parent, out object parentKey)
        {
            parent = null;
            parentKey = null;
            if (path == null || path.Length == 0) return false;

            JToken cur = root;
            for (int i = 0; i < path.Length - 1; i++)
            {
                if (cur == null) return false;
                cur = StepInto(cur, path[i]);
            }
            if (cur == null) return false;
            string lastSeg = path[path.Length - 1];
            parent = cur;
            if (cur.Type == JTokenType.Array)
            {
                int idx;
                if (!int.TryParse(lastSeg, out idx)) return false;
                parentKey = idx;
            }
            else if (cur.Type == JTokenType.Object)
            {
                parentKey = lastSeg;
            }
            else
            {
                return false;
            }
            return true;
        }

        private static JToken StepInto(JToken node, string seg)
        {
            if (node.Type == JTokenType.Array)
            {
                int idx;
                if (!int.TryParse(seg, out idx)) return null;
                JArray arr = (JArray)node;
                if (idx < 0 || idx >= arr.Count) return null;
                return arr[idx];
            }
            if (node.Type == JTokenType.Object)
            {
                JObject obj = (JObject)node;
                JToken child = obj[seg];
                return child;
            }
            return null;
        }

        private static int ComparePatchOrder(PatchOp a, PatchOp b)
        {
            // splice (drop_value with array parent) 排末尾.
            // 这里 parent 还没 navigate, 但路径末段是数字时绝大多数是 array 的 index.
            bool aSplice = a.Action == "DropValue" && IsArrayLikePath(a.Path);
            bool bSplice = b.Action == "DropValue" && IsArrayLikePath(b.Path);
            if (aSplice != bSplice) return aSplice ? 1 : -1;
            if (aSplice && bSplice)
            {
                int ai = ParseTrailingInt(a.Path);
                int bi = ParseTrailingInt(b.Path);
                return bi - ai; // 降序
            }
            return 0;
        }

        private static bool IsArrayLikePath(string[] path)
        {
            if (path == null || path.Length == 0) return false;
            int dummy;
            return int.TryParse(path[path.Length - 1], out dummy);
        }

        private static int ParseTrailingInt(string[] path)
        {
            int v;
            if (path == null || path.Length == 0) return 0;
            int.TryParse(path[path.Length - 1], out v);
            return v;
        }

        private static void SetValue(JToken parent, object parentKey, string value)
        {
            if (parent.Type == JTokenType.Array)
            {
                ((JArray)parent)[(int)parentKey] = value;
            }
            else
            {
                ((JObject)parent)[(string)parentKey] = value;
            }
        }

        private static bool RenameKeySafe(JObject obj, string oldKey, string newKey, out string error)
        {
            error = null;
            if (oldKey == newKey) return true;
            if (obj[newKey] != null)
            {
                error = "RenameKey collision: target '" + newKey + "' already exists";
                return false;
            }
            JToken val = obj[oldKey];
            if (val == null) return true;  // 路径已 race, 静默
            obj.Remove(oldKey);
            obj[newKey] = val;
            return true;
        }

        // ─────────────── helpers ───────────────

        /// <summary>
        /// 序列化 RepairPlan 为 wire JSON. 字段稳定, 给 web 端做 UI:
        ///   { totalFffd, byLayer:{L0,L1,L2,L3}, manualRequired, willBumpLastSaved,
        ///     decisions:[
        ///       { path:[..], broken, spot:"value"|"key", layer, kind,
        ///         action:"FixValue"|"RenameKey"|"DropValue"|"ClearValue"|"DropKey"
        ///                |"PreservePlaceholder"|"ManualRequired",
        ///         autoNewValue:?,         // policy 自动选的修复值 (FixValue/RenameKey 时非 null)
        ///         autoSource:?,           // "SelfRef"|"DictUnique"|"Dict"
        ///         candidates:[ {value, source, confidence} ]   // 0 或多
        ///       }
        ///     ]
        ///   }
        /// </summary>
        internal static JObject BuildPlanWireJson(RepairPlan plan)
        {
            JObject root = new JObject();
            root["totalFffd"] = plan.Scan.Total;

            JObject byLayer = new JObject();
            byLayer["L0"] = plan.Scan.L0;
            byLayer["L1"] = plan.Scan.L1;
            byLayer["L2"] = plan.Scan.L2;
            byLayer["L3"] = plan.Scan.L3;
            root["byLayer"] = byLayer;

            root["manualRequired"] = plan.ManualRequired;
            root["willBumpLastSaved"] = plan.WillBumpLastSaved;

            JArray arr = new JArray();
            for (int i = 0; i < plan.Decisions.Count; i++)
            {
                arr.Add(SerializeDecision(plan.Decisions[i]));
            }
            root["decisions"] = arr;
            return root;
        }

        private static JObject SerializeDecision(RepairDecision d)
        {
            JObject obj = new JObject();
            JArray pathArr = new JArray();
            for (int p = 0; p < d.Item.PathSegments.Length; p++) pathArr.Add(d.Item.PathSegments[p]);
            obj["path"] = pathArr;
            obj["broken"] = d.Item.BrokenString;
            obj["spot"] = (d.Item.Spot == SaveCorruptionSpot.Key) ? "key" : "value";
            obj["layer"] = d.Item.Rule.Layer.ToString();
            obj["kind"] = d.Item.Rule.Kind.ToString();
            obj["action"] = d.Action.Kind.ToString();
            if (d.Action.NewValue != null) obj["autoNewValue"] = d.Action.NewValue;
            if (d.Action.Via != null) obj["autoSource"] = d.Action.Via.Source.ToString();

            JArray cands = new JArray();
            if (d.Candidates != null)
            {
                for (int c = 0; c < d.Candidates.Count; c++)
                {
                    RepairCandidate cand = d.Candidates[c];
                    JObject cj = new JObject();
                    cj["value"] = cand.Value;
                    cj["source"] = cand.Source.ToString();
                    cj["confidence"] = cand.Confidence;
                    cands.Add(cj);
                }
            }
            obj["candidates"] = cands;
            return obj;
        }

        private static void PostDetectError(BootstrapPanel bootForm, string slot, string code, string msg)
        {
            JObject obj = new JObject();
            obj["type"] = "bootstrap";
            obj["cmd"] = "repair_detect_resp";
            obj["ok"] = false;
            if (slot != null) obj["slot"] = slot;
            obj["error"] = code;
            obj["msg"] = msg ?? "";
            bootForm.PostToWeb(obj.ToString(Formatting.None));
        }

        private static void PostApplyResp(BootstrapPanel bootForm, string slot, bool ok, string code, string msg, int applied)
        {
            JObject obj = new JObject();
            obj["type"] = "bootstrap";
            obj["cmd"] = "repair_apply_manual_resp";
            obj["ok"] = ok;
            if (slot != null) obj["slot"] = slot;
            if (!ok)
            {
                if (code != null) obj["error"] = code;
                if (msg != null) obj["msg"] = msg;
            }
            obj["applied"] = applied;
            bootForm.PostToWeb(obj.ToString(Formatting.None));
        }

        private static void PostForceResp(BootstrapPanel bootForm, string slot, bool ok, string code, string msg)
        {
            JObject obj = new JObject();
            obj["type"] = "bootstrap";
            obj["cmd"] = "repair_force_continue_resp";
            obj["ok"] = ok;
            if (slot != null) obj["slot"] = slot;
            if (!ok)
            {
                if (code != null) obj["error"] = code;
                if (msg != null) obj["msg"] = msg;
            }
            bootForm.PostToWeb(obj.ToString(Formatting.None));
        }
    }
}
