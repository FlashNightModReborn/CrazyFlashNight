using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tasks
{
    /// <summary>hairdresser domain 的严格 WebView↔Flash callId 桥与发型写对账门。</summary>
    public sealed class HairdresserTask : IDisposable
    {
        private sealed class PendingRequest
        {
            public string WebCmd;
            public bool IsWrite;
            public string ExpectedHairIdentifier;
            public string ReconcileExpectedHairIdentifier;
        }

        private const int DefaultTimeoutMs = 10000;
        private static readonly Regex ValidCallId =
            new Regex("^[A-Za-z0-9._-]{1,96}$", RegexOptions.Compiled);
        private static readonly HashSet<string> DefinitiveWriteErrors =
            new HashSet<string>(StringComparer.Ordinal)
            {
                "unsupported_cmd",
                "unsupported_version",
                "catalog_invalid",
                "pricing_unsupported",
                "invalid_payload",
                "hair_not_found",
                "actor_unavailable",
                "save_unavailable",
                "refresh_unavailable"
            };

        private readonly PanelPendingCallTracker<PendingRequest> _pendingCalls;
        private readonly object _lock = new object();
        private Action<string> _postToWeb;
        private Action<Action> _invokeOnUI;
        private string _writeState = "idle";
        private string _reconcileExpectedHairIdentifier;

        public HairdresserTask(XmlSocketServer socket)
            : this(
                delegate { return socket != null && socket.IsClientReady; },
                delegate(string payload) { return socket != null && socket.TrySend(payload); },
                DefaultTimeoutMs)
        {
        }

        public HairdresserTask(
            Func<bool> isClientReady,
            Func<string, bool> trySend,
            int timeoutMs = DefaultTimeoutMs)
        {
            _pendingCalls = new PanelPendingCallTracker<PendingRequest>(
                isClientReady,
                trySend,
                timeoutMs,
                HandlePendingEnded);
        }

        public void SetPostToWeb(Action<string> post)
        {
            _postToWeb = post;
        }

        public void SetInvoker(Action<Action> invoker)
        {
            _invokeOnUI = invoker;
        }

        internal string WriteState
        {
            get { lock (_lock) return _writeState; }
        }

        public void Dispose()
        {
            lock (_lock) { _pendingCalls.Dispose(); }
        }

        public void HandleWebRequest(string cmd, JObject parsed)
        {
            string callId = parsed != null ? parsed.Value<string>("callId") : null;
            if (string.IsNullOrEmpty(callId)) return;
            if (!ValidCallId.IsMatch(callId))
            {
                RespondError(callId, cmd, "invalid_call_id");
                return;
            }
            if (!string.Equals(
                parsed.Value<string>("domain"),
                "hairdresser",
                StringComparison.Ordinal))
            {
                RejectAndRemember(callId, cmd, "unsupported_domain");
                return;
            }

            string action;
            bool isWrite;
            if (!TryResolveCommand(cmd, out action, out isWrite))
            {
                RejectAndRemember(callId, cmd, "unsupported_cmd");
                return;
            }

            JObject normalized;
            if (!TryNormalizePayload(cmd, parsed["payload"] as JObject, out normalized))
            {
                RejectAndRemember(callId, cmd, "invalid_payload");
                return;
            }
            if (!_pendingCalls.IsReady())
            {
                RejectAndRemember(callId, cmd, "disconnected");
                return;
            }

            int fid;
            lock (_lock)
            {
                if (_pendingCalls.IsKnownWebCallId(callId)) return;
                if (isWrite && _writeState != "idle")
                {
                    if (!_pendingCalls.TryRememberRejected(callId)) return;
                    RespondError(
                        callId,
                        cmd,
                        _writeState == "needs_reconcile" ? "reconcile_required" : "busy");
                    return;
                }

                string expectedHairIdentifier =
                    isWrite ? normalized.Value<string>("hairIdentifier") : null;
                string reconcileExpectedHairIdentifier =
                    !isWrite && _writeState == "needs_reconcile"
                        ? _reconcileExpectedHairIdentifier
                        : null;
                if (!_pendingCalls.TryBegin(
                    callId,
                    new PendingRequest
                    {
                        WebCmd = cmd,
                        IsWrite = isWrite,
                        ExpectedHairIdentifier = expectedHairIdentifier,
                        ReconcileExpectedHairIdentifier = reconcileExpectedHairIdentifier
                    },
                    out fid))
                {
                    return;
                }
                if (isWrite) _writeState = "write_pending";
            }

            string json =
                PanelBridge.BuildFlashCommand(action, fid, normalized).ToString(Formatting.None);
            LogManager.Log("[HairdresserTask] -> Flash: " + json);
            _pendingCalls.Send(fid, json + "\0");
        }

        public void HandleFlashResponse(JObject msg, Action<string> respond)
        {
            int fid = 0;
            JToken callIdToken = msg != null ? msg["callId"] : null;
            if (callIdToken != null && callIdToken.Type == JTokenType.Integer)
            {
                long candidate = callIdToken.Value<long>();
                if (candidate > 0 && candidate <= int.MaxValue) fid = (int)candidate;
            }
            PanelPendingCall<PendingRequest> pendingCall;
            PendingRequest entry;
            bool malformed;
            bool definitiveWrite;
            bool reconciled = false;
            bool writeApplied = false;
            lock (_lock)
            {
                if (!_pendingCalls.TryComplete(fid, out pendingCall))
                {
                    if (respond != null) respond(null);
                    return;
                }

                entry = pendingCall.Context;
                malformed = IsMalformedResponse(msg, entry);
                definitiveWrite = entry.IsWrite
                    && !malformed
                    && IsDefinitiveWriteResponse(msg, entry.ExpectedHairIdentifier);

                if (entry.IsWrite)
                {
                    if (definitiveWrite)
                    {
                        _writeState = "idle";
                        _reconcileExpectedHairIdentifier = null;
                    }
                    else
                    {
                        _writeState = "needs_reconcile";
                        _reconcileExpectedHairIdentifier = entry.ExpectedHairIdentifier;
                    }
                }
                else if (entry.WebCmd == "snapshot"
                    && !malformed
                    && msg.Value<bool?>("success") == true
                    && _writeState == "needs_reconcile"
                    && !string.IsNullOrEmpty(entry.ReconcileExpectedHairIdentifier)
                    && string.Equals(
                        entry.ReconcileExpectedHairIdentifier,
                        _reconcileExpectedHairIdentifier,
                        StringComparison.Ordinal))
                {
                    reconciled = true;
                    writeApplied = string.Equals(
                        msg.Value<string>("currentHair"),
                        entry.ReconcileExpectedHairIdentifier,
                        StringComparison.Ordinal);
                    _writeState = "idle";
                    _reconcileExpectedHairIdentifier = null;
                }
            }

            JObject web = malformed
                ? new JObject { ["success"] = false, ["error"] = "malformed_response" }
                : (JObject)msg.DeepClone();
            web.Remove("task");
            web["type"] = "panel_resp";
            web["domain"] = "hairdresser";
            web["cmd"] = entry.WebCmd;
            web["callId"] = pendingCall.WebCallId;
            if (entry.IsWrite && !definitiveWrite) web["requiresReconcile"] = true;
            if (reconciled)
            {
                web["reconciled"] = true;
                web["writeApplied"] = writeApplied;
            }
            PostToWeb(web.ToString(Formatting.None));
            if (respond != null) respond(null);
        }

        public void ClearPending()
        {
            lock (_lock) { _pendingCalls.Clear(); }
        }

        private static bool TryResolveCommand(
            string cmd,
            out string action,
            out bool isWrite)
        {
            isWrite = false;
            switch (cmd)
            {
                case "snapshot":
                    action = "hairdresserSnapshot";
                    return true;
                case "commit":
                    action = "hairdresserCommit";
                    isWrite = true;
                    return true;
                default:
                    action = null;
                    return false;
            }
        }

        private static bool TryNormalizePayload(
            string cmd,
            JObject payload,
            out JObject normalized)
        {
            normalized = null;
            if (payload == null
                || payload["v"] == null
                || payload["v"].Type != JTokenType.Integer
                || payload["v"].Value<long>() != 1)
            {
                return false;
            }

            if (cmd == "snapshot")
            {
                if (!HasExactProperties(payload, "v")) return false;
                normalized = new JObject { ["v"] = 1 };
                return true;
            }
            if (cmd == "commit")
            {
                string hairIdentifier;
                if (!HasExactProperties(payload, "v", "hairIdentifier")
                    || !TryReadSafeString(
                        payload["hairIdentifier"],
                        160,
                        false,
                        out hairIdentifier))
                {
                    return false;
                }
                normalized = new JObject
                {
                    ["v"] = 1,
                    ["hairIdentifier"] = hairIdentifier
                };
                return true;
            }
            return false;
        }

        private static bool IsMalformedResponse(JObject msg, PendingRequest entry)
        {
            if (msg == null
                || !string.Equals(
                    msg.Value<string>("task"),
                    "hairdresser_response",
                    StringComparison.Ordinal)
                || msg["success"] == null
                || msg["success"].Type != JTokenType.Boolean)
            {
                return true;
            }

            if (!msg.Value<bool>("success"))
            {
                string error;
                return !TryReadSafeString(msg["error"], 96, false, out error);
            }
            if (entry.WebCmd == "snapshot") return !IsAuthoritativeSnapshot(msg);
            return !IsAuthoritativeCommit(msg, entry.ExpectedHairIdentifier);
        }

        private static bool IsAuthoritativeSnapshot(JObject msg)
        {
            if (!HasProtocolVersion(msg)) return false;
            string gender;
            string face;
            string currentHair;
            if (!TryReadSafeString(msg["gender"], 8, false, out gender)
                || !TryReadSafeString(msg["face"], 160, false, out face)
                || !TryReadSafeString(msg["currentHair"], 160, false, out currentHair))
            {
                return false;
            }

            JArray catalog = msg["catalog"] as JArray;
            if (catalog == null || catalog.Count == 0) return false;
            bool currentHairFound = false;
            foreach (JToken token in catalog)
            {
                JObject row = token as JObject;
                string identifier;
                string name;
                if (row == null
                    || !HasExactProperties(row, "identifier", "name")
                    || !TryReadSafeString(row["identifier"], 160, false, out identifier)
                    || !TryReadSafeString(row["name"], 160, false, out name))
                {
                    return false;
                }
                if (string.Equals(identifier, currentHair, StringComparison.Ordinal))
                    currentHairFound = true;
            }
            return currentHairFound;
        }

        private static bool IsAuthoritativeCommit(
            JObject msg,
            string expectedHairIdentifier)
        {
            string currentHair;
            return HasProtocolVersion(msg)
                && string.Equals(msg.Value<string>("operation"), "commit", StringComparison.Ordinal)
                && TryReadSafeString(msg["currentHair"], 160, false, out currentHair)
                && string.Equals(currentHair, expectedHairIdentifier, StringComparison.Ordinal);
        }

        private static bool IsDefinitiveWriteResponse(
            JObject msg,
            string expectedHairIdentifier)
        {
            if (msg.Value<bool?>("success") == true)
                return IsAuthoritativeCommit(msg, expectedHairIdentifier);
            return DefinitiveWriteErrors.Contains(msg.Value<string>("error"));
        }

        private static bool HasProtocolVersion(JObject value)
        {
            return value != null
                && value["v"] != null
                && value["v"].Type == JTokenType.Integer
                && value["v"].Value<long>() == 1;
        }

        private static bool HasExactProperties(JObject value, params string[] names)
        {
            if (value == null || value.Count != names.Length) return false;
            foreach (string name in names)
            {
                if (value.Property(name) == null) return false;
            }
            return true;
        }

        private static bool TryReadSafeString(
            JToken token,
            int maxLength,
            bool allowEmpty,
            out string value)
        {
            value = null;
            if (token == null || token.Type != JTokenType.String) return false;
            value = token.Value<string>();
            if ((!allowEmpty && string.IsNullOrEmpty(value))
                || value == null
                || value.Length > maxLength)
            {
                return false;
            }
            for (int i = 0; i < value.Length; i++)
            {
                if (char.IsControl(value[i])) return false;
            }
            return true;
        }

        private void HandlePendingEnded(
            PanelPendingCall<PendingRequest> pendingCall,
            PanelPendingCallEndReason reason)
        {
            PendingRequest entry = pendingCall.Context;
            lock (_lock)
            {
                if (entry.IsWrite)
                {
                    _writeState = "needs_reconcile";
                    _reconcileExpectedHairIdentifier = entry.ExpectedHairIdentifier;
                }
            }
            if (reason == PanelPendingCallEndReason.Cleared) return;
            RespondError(
                pendingCall.WebCallId,
                entry.WebCmd,
                reason == PanelPendingCallEndReason.Timeout ? "timeout" : "disconnected",
                entry.IsWrite);
        }

        private void RejectAndRemember(string callId, string cmd, string error)
        {
            if (!_pendingCalls.TryRememberRejected(callId)) return;
            RespondError(callId, cmd, error);
        }

        private void RespondError(
            string callId,
            string cmd,
            string error,
            bool requiresReconcile = false)
        {
            var response = new JObject
            {
                ["type"] = "panel_resp",
                ["domain"] = "hairdresser",
                ["cmd"] = cmd ?? "",
                ["callId"] = callId ?? "",
                ["success"] = false,
                ["error"] = error
            };
            if (requiresReconcile) response["requiresReconcile"] = true;
            PostToWeb(response.ToString(Formatting.None));
        }

        private void PostToWeb(string json)
        {
            if (_invokeOnUI != null)
            {
                _invokeOnUI(delegate
                {
                    if (_postToWeb != null) _postToWeb(json);
                });
            }
            else if (_postToWeb != null)
            {
                _postToWeb(json);
            }
        }
    }
}
