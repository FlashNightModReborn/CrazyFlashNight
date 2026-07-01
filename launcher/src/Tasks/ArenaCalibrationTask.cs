using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tasks
{
    public sealed class ArenaCalibrationTask
    {
        private sealed class CalibrationCase
        {
            public string CaseId;
            public string CaseHash;
            public JArray BlueRoster;
            public JArray RedRoster;
            public int Repeat;
            public int TimeoutFrames;
        }

        private sealed class BatchManifest
        {
            public string BatchId;
            public string ManifestHash;
            public JObject Frozen;
            public List<CalibrationCase> Cases;
            public int TotalRuns;
        }

        private sealed class PendingRun
        {
            public ManualResetEventSlim Done;
            public JObject Response;
            public CalibrationCase TestCase;
            public int RepeatIndex;
            public string RunId;
            public DateTime StartedAtUtc;
            public bool Aborted;
        }

        private readonly string _projectRoot;
        private readonly Func<bool> _isClientReady;
        private readonly Action<string> _send;
        private readonly Func<int, int> _timeoutMsFromFrames;
        private readonly object _lock = new object();
        private readonly Dictionary<int, PendingRun> _pending = new Dictionary<int, PendingRun>();
        private static readonly Regex BatchIdPattern = new Regex("^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$", RegexOptions.Compiled);

        private int _seq;
        private volatile bool _abortRequested;
        private string _state = "idle";
        private string _batchId;
        private string _manifestHash;
        private string _manifestPath;
        private string _frozenManifestPath;
        private string _resultPath;
        private string _currentCaseId;
        private string _currentRunId;
        private string _lastError;
        private int _totalRuns;
        private int _completedRuns;

        public ArenaCalibrationTask(XmlSocketServer socket, string projectRoot)
            : this(
                projectRoot,
                delegate { return socket != null && socket.IsClientReady; },
                delegate(string payload) { if (socket != null) socket.Send(payload); },
                null)
        {
        }

        public ArenaCalibrationTask(
            string projectRoot,
            Func<bool> isClientReady,
            Action<string> send,
            Func<int, int> timeoutMsFromFrames)
        {
            _projectRoot = string.IsNullOrEmpty(projectRoot)
                ? AppDomain.CurrentDomain.BaseDirectory
                : Path.GetFullPath(projectRoot);
            _isClientReady = isClientReady ?? delegate { return false; };
            _send = send ?? delegate { };
            _timeoutMsFromFrames = timeoutMsFromFrames ?? DefaultTimeoutMsFromFrames;
        }

        public string HandleControl(JObject msg)
        {
            string action = msg.Value<string>("action") ?? "status";
            try
            {
                switch (action)
                {
                    case "startBatch":
                        return StartBatch(msg).ToString(Formatting.None);
                    case "status":
                        return BuildStatus(true, null).ToString(Formatting.None);
                    case "abort":
                        return AbortBatch(msg).ToString(Formatting.None);
                    default:
                        return BuildError("unsupported_action", "unsupported action: " + action).ToString(Formatting.None);
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[ArenaCalibrationTask] control exception: " + ex);
                return BuildError("exception", ex.Message).ToString(Formatting.None);
            }
        }

        public void HandleFlashResponse(JObject msg, Action<string> respond)
        {
            int fid = msg.Value<int?>("callId") ?? 0;
            PendingRun pending = null;
            lock (_lock)
            {
                if (_pending.TryGetValue(fid, out pending))
                    _pending.Remove(fid);
            }

            if (pending != null)
            {
                pending.Response = msg;
                pending.Done.Set();
            }

            respond(null);
        }

        private JObject StartBatch(JObject msg)
        {
            if (!_isClientReady())
                return BuildError("disconnected", "Flash socket client is not ready");

            string manifestPath = ResolveManifestPath(msg.Value<string>("manifestPath"));
            BatchManifest manifest = LoadAndNormalizeManifest(manifestPath);

            lock (_lock)
            {
                if (_state == "running")
                    return BuildError("batch_already_running", "arena calibration batch is already running");

                string batchDir = ResolveBatchDir(manifest.BatchId);
                Directory.CreateDirectory(batchDir);
                _frozenManifestPath = Path.Combine(batchDir, "case_manifest.json");
                File.WriteAllText(_frozenManifestPath, manifest.Frozen.ToString(Formatting.Indented) + Environment.NewLine, new UTF8Encoding(false));

                string logDir = Path.GetFullPath(Path.Combine(_projectRoot, "logs", "arena-calibration"));
                Directory.CreateDirectory(logDir);
                _resultPath = ResolveResultPath(manifest.BatchId);
                if (File.Exists(_resultPath))
                    File.Delete(_resultPath);

                _abortRequested = false;
                _state = "running";
                _batchId = manifest.BatchId;
                _manifestHash = manifest.ManifestHash;
                _manifestPath = manifestPath;
                _currentCaseId = null;
                _currentRunId = null;
                _lastError = null;
                _totalRuns = manifest.TotalRuns;
                _completedRuns = 0;
            }

            ThreadPool.QueueUserWorkItem(delegate { RunBatch(manifest); });
            return BuildStatus(true, "started");
        }

        private JObject AbortBatch(JObject msg)
        {
            string batchId = msg.Value<string>("batchId");
            lock (_lock)
            {
                if (!string.IsNullOrEmpty(batchId) && !string.IsNullOrEmpty(_batchId) && batchId != _batchId)
                    return BuildError("batch_mismatch", "requested batchId does not match active batch");

                _abortRequested = true;
                foreach (PendingRun pending in _pending.Values)
                {
                    pending.Aborted = true;
                    pending.Done.Set();
                }

                if (_state == "idle" || _state == "completed" || _state == "failed")
                    return BuildStatus(true, "not_running");
            }

            return BuildStatus(true, "abort_requested");
        }

        private void RunBatch(BatchManifest manifest)
        {
            try
            {
                foreach (CalibrationCase testCase in manifest.Cases)
                {
                    for (int repeatIndex = 1; repeatIndex <= testCase.Repeat; repeatIndex++)
                    {
                        if (_abortRequested)
                            break;
                        RunSingleCase(manifest, testCase, repeatIndex);
                    }
                    if (_abortRequested)
                        break;
                }

                lock (_lock)
                {
                    if (_abortRequested && _state == "running")
                        _state = "aborted";
                    else if (_state == "running")
                        _state = "completed";
                    _currentCaseId = null;
                    _currentRunId = null;
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[ArenaCalibrationTask] batch exception: " + ex);
                lock (_lock)
                {
                    _state = "failed";
                    _lastError = ex.Message;
                    _currentCaseId = null;
                    _currentRunId = null;
                }
            }
        }

        private void RunSingleCase(BatchManifest manifest, CalibrationCase testCase, int repeatIndex)
        {
            string runId = testCase.CaseId + "-r" + repeatIndex.ToString("D3");
            DateTime startedAt = DateTime.UtcNow;
            PendingRun pending = new PendingRun
            {
                Done = new ManualResetEventSlim(false),
                TestCase = testCase,
                RepeatIndex = repeatIndex,
                RunId = runId,
                StartedAtUtc = startedAt
            };

            int fid;
            lock (_lock)
            {
                fid = ++_seq;
                _pending[fid] = pending;
                _currentCaseId = testCase.CaseId;
                _currentRunId = runId;
            }

            if (!_isClientReady())
            {
                RemovePending(fid);
                AppendResultRow(BuildSyntheticResult(manifest, testCase, repeatIndex, runId, startedAt,
                    "bridge_lost", "none", "Flash socket client disconnected before run dispatch"));
                MarkCompleted();
                return;
            }

            JObject command = BuildFlashCommand(manifest, testCase, repeatIndex, runId, fid);
            _send(command.ToString(Formatting.None) + "\0");

            int timeoutMs = _timeoutMsFromFrames(testCase.TimeoutFrames);
            bool completed = pending.Done.Wait(timeoutMs);
            RemovePending(fid);

            JObject row;
            if (pending.Aborted || _abortRequested)
            {
                row = BuildSyntheticResult(manifest, testCase, repeatIndex, runId, startedAt,
                    "aborted", "none", "batch aborted");
            }
            else if (!completed || pending.Response == null)
            {
                row = BuildSyntheticResult(manifest, testCase, repeatIndex, runId, startedAt,
                    "timeout", "timeout", "AS2 arena calibration response timed out");
            }
            else
            {
                row = BuildResultFromFlash(manifest, testCase, repeatIndex, runId, startedAt, pending.Response);
            }

            AppendResultRow(row);
            MarkCompleted();
        }

        private JObject BuildFlashCommand(BatchManifest manifest, CalibrationCase testCase, int repeatIndex, string runId, int fid)
        {
            JObject command = new JObject();
            command["task"] = "cmd";
            command["action"] = "arenaCalibrationRun";
            command["callId"] = fid;
            command["batchId"] = manifest.BatchId;
            command["manifestHash"] = manifest.ManifestHash;
            command["caseId"] = testCase.CaseId;
            command["caseHash"] = testCase.CaseHash;
            command["runId"] = runId;
            command["repeatIndex"] = repeatIndex;
            command["timeoutFrames"] = testCase.TimeoutFrames;
            command["blueRoster"] = ToFlashRoster(testCase.BlueRoster);
            command["redRoster"] = ToFlashRoster(testCase.RedRoster);
            return command;
        }

        private JObject BuildResultFromFlash(
            BatchManifest manifest,
            CalibrationCase testCase,
            int repeatIndex,
            string runId,
            DateTime startedAtUtc,
            JObject response)
        {
            JObject result = response.Value<JObject>("result") ?? response;
            string status = result.Value<string>("status");
            if (string.IsNullOrEmpty(status))
                status = result.Value<bool?>("success") == false ? "error" : "finished";

            string winner = result.Value<string>("winner");
            if (string.IsNullOrEmpty(winner))
                winner = status == "timeout" ? "timeout" : "none";

            JObject row = BuildResultEnvelope(manifest, testCase, repeatIndex, runId, startedAtUtc, status, winner);
            CopyOptionalNumber(result, row, "frames");
            CopyOptionalNumber(result, row, "durationMs");
            row["blue"] = NormalizeSideSummary(result.Value<JObject>("blue"));
            row["red"] = NormalizeSideSummary(result.Value<JObject>("red"));
            row["errors"] = NormalizeErrors(result["errors"]);
            return row;
        }

        private JObject BuildSyntheticResult(
            BatchManifest manifest,
            CalibrationCase testCase,
            int repeatIndex,
            string runId,
            DateTime startedAtUtc,
            string status,
            string winner,
            string message)
        {
            JObject row = BuildResultEnvelope(manifest, testCase, repeatIndex, runId, startedAtUtc, status, winner);
            row["frames"] = null;
            row["durationMs"] = null;
            row["blue"] = NormalizeSideSummary(null);
            row["red"] = NormalizeSideSummary(null);
            JArray errors = new JArray();
            JObject error = new JObject();
            error["code"] = status;
            error["message"] = message;
            errors.Add(error);
            row["errors"] = errors;
            return row;
        }

        private JObject BuildResultEnvelope(
            BatchManifest manifest,
            CalibrationCase testCase,
            int repeatIndex,
            string runId,
            DateTime startedAtUtc,
            string status,
            string winner)
        {
            JObject row = new JObject();
            row["schema"] = "arena-calibration.result.v1";
            row["batchId"] = manifest.BatchId;
            row["manifestHash"] = manifest.ManifestHash;
            row["caseId"] = testCase.CaseId;
            row["caseHash"] = testCase.CaseHash;
            row["runId"] = runId;
            row["repeatIndex"] = repeatIndex;
            row["status"] = status;
            row["winner"] = winner;
            row["startedAt"] = startedAtUtc.ToString("o");
            row["completedAt"] = DateTime.UtcNow.ToString("o");
            return row;
        }

        private void AppendResultRow(JObject row)
        {
            string resultPath;
            lock (_lock) { resultPath = _resultPath; }
            File.AppendAllText(resultPath, row.ToString(Formatting.None) + Environment.NewLine, new UTF8Encoding(false));
        }

        private void MarkCompleted()
        {
            lock (_lock)
            {
                _completedRuns++;
                _currentCaseId = null;
                _currentRunId = null;
            }
        }

        private void RemovePending(int fid)
        {
            lock (_lock)
            {
                _pending.Remove(fid);
            }
        }

        private JObject BuildStatus(bool success, string note)
        {
            lock (_lock)
            {
                JObject status = new JObject();
                status["success"] = success;
                status["ok"] = success;
                status["task"] = "arena_calibration";
                status["state"] = _state;
                status["note"] = note;
                status["batchId"] = _batchId;
                status["manifestHash"] = _manifestHash;
                status["manifestPath"] = ToProjectRelative(_manifestPath);
                status["frozenManifestPath"] = ToProjectRelative(_frozenManifestPath);
                status["resultPath"] = ToProjectRelative(_resultPath);
                status["totalRuns"] = _totalRuns;
                status["completedRuns"] = _completedRuns;
                status["currentCaseId"] = _currentCaseId;
                status["currentRunId"] = _currentRunId;
                status["lastError"] = _lastError;
                return status;
            }
        }

        private JObject BuildError(string code, string message)
        {
            JObject error = BuildStatus(false, null);
            error["error"] = code;
            error["message"] = message;
            return error;
        }

        private string ResolveManifestPath(string manifestPath)
        {
            if (string.IsNullOrEmpty(manifestPath))
                throw new InvalidOperationException("missing manifestPath");

            if (Path.IsPathRooted(manifestPath))
                throw new InvalidOperationException("manifestPath must be a project-relative path under tmp/arena-calibration");

            string full = Path.GetFullPath(Path.Combine(_projectRoot, manifestPath));
            string allowedRoot = Path.GetFullPath(Path.Combine(_projectRoot, "tmp", "arena-calibration"));
            string allowedPrefix = allowedRoot.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
                + Path.DirectorySeparatorChar;

            if (!full.StartsWith(allowedPrefix, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("manifestPath must stay under tmp/arena-calibration");
            if (!File.Exists(full))
                throw new FileNotFoundException("manifestPath not found", full);
            return full;
        }

        private BatchManifest LoadAndNormalizeManifest(string manifestPath)
        {
            JObject input = JObject.Parse(File.ReadAllText(manifestPath, Encoding.UTF8));
            RejectEconomyKeys(input, "$");

            string schema = input.Value<string>("schema");
            if (schema != "arena-calibration.case-manifest.v1")
                throw new InvalidOperationException("unsupported manifest schema: " + schema);

            string batchId = ValidateBatchId(RequiredString(input, "batchId"));
            int repeat = PositiveInt(input["repeat"], "repeat", 5);
            int timeoutFrames = PositiveInt(input["timeoutFrames"], "timeoutFrames", 5400);
            JArray cases = input.Value<JArray>("cases");
            if (cases == null || cases.Count == 0)
                throw new InvalidOperationException("manifest cases must be non-empty");

            JObject frozen = new JObject();
            frozen["schema"] = schema;
            frozen["batchId"] = batchId;
            frozen["createdAt"] = input.Value<string>("createdAt") ?? DateTime.UtcNow.ToString("o");
            frozen["buildCommit"] = input.Value<string>("buildCommit") ?? "unknown";
            frozen["planner"] = input["planner"] != null ? input["planner"].DeepClone() : new JObject();
            frozen["arenaMode"] = input.Value<string>("arenaMode") ?? "calibration";
            frozen["repeat"] = repeat;
            frozen["timeoutFrames"] = timeoutFrames;
            frozen["blueBench"] = input["blueBench"] != null ? input["blueBench"].DeepClone() : JValue.CreateNull();

            if ((string)frozen["arenaMode"] != "calibration")
                throw new InvalidOperationException("arenaMode must be calibration");

            JArray frozenCases = new JArray();
            List<CalibrationCase> normalizedCases = new List<CalibrationCase>();
            HashSet<string> caseIds = new HashSet<string>(StringComparer.Ordinal);

            for (int i = 0; i < cases.Count; i++)
            {
                JObject sourceCase = cases[i] as JObject;
                if (sourceCase == null)
                    throw new InvalidOperationException("case entry must be an object at index " + i);

                string caseId = RequiredString(sourceCase, "caseId");
                if (!caseIds.Add(caseId))
                    throw new InvalidOperationException("duplicate caseId: " + caseId);

                int caseRepeat = PositiveInt(sourceCase["repeat"], "cases[" + i + "].repeat", repeat);
                int caseTimeout = PositiveInt(sourceCase["timeoutFrames"], "cases[" + i + "].timeoutFrames", timeoutFrames);
                JArray blueRoster = NormalizeRoster(sourceCase["blueRoster"] as JArray, "cases[" + i + "].blueRoster");
                JArray redRoster = NormalizeRoster(sourceCase["redRoster"] as JArray, "cases[" + i + "].redRoster");

                JObject frozenCase = new JObject();
                frozenCase["caseId"] = caseId;
                frozenCase["blueRoster"] = blueRoster.DeepClone();
                frozenCase["redRoster"] = redRoster.DeepClone();
                frozenCase["repeat"] = caseRepeat;
                frozenCase["timeoutFrames"] = caseTimeout;
                frozenCase["tags"] = sourceCase["tags"] != null ? sourceCase["tags"].DeepClone() : new JArray();
                frozenCase["plannerReason"] = sourceCase.Value<string>("plannerReason") ?? "";

                JObject hashInput = new JObject();
                hashInput["caseId"] = caseId;
                hashInput["blueRoster"] = blueRoster.DeepClone();
                hashInput["redRoster"] = redRoster.DeepClone();
                hashInput["repeat"] = caseRepeat;
                hashInput["timeoutFrames"] = caseTimeout;
                string caseHash = Sha256OfToken(hashInput);
                frozenCase["caseHash"] = caseHash;

                string suppliedCaseHash = sourceCase.Value<string>("caseHash");
                if (!string.IsNullOrEmpty(suppliedCaseHash) && suppliedCaseHash != caseHash)
                    throw new InvalidOperationException("caseHash mismatch for " + caseId);

                frozenCases.Add(frozenCase);
                normalizedCases.Add(new CalibrationCase
                {
                    CaseId = caseId,
                    CaseHash = caseHash,
                    BlueRoster = blueRoster,
                    RedRoster = redRoster,
                    Repeat = caseRepeat,
                    TimeoutFrames = caseTimeout
                });
            }

            frozen["cases"] = frozenCases;
            JObject manifestHashInput = new JObject();
            manifestHashInput["schema"] = frozen["schema"].DeepClone();
            manifestHashInput["batchId"] = frozen["batchId"].DeepClone();
            manifestHashInput["buildCommit"] = frozen["buildCommit"].DeepClone();
            manifestHashInput["planner"] = frozen["planner"].DeepClone();
            manifestHashInput["arenaMode"] = frozen["arenaMode"].DeepClone();
            manifestHashInput["repeat"] = frozen["repeat"].DeepClone();
            manifestHashInput["timeoutFrames"] = frozen["timeoutFrames"].DeepClone();
            manifestHashInput["blueBench"] = frozen["blueBench"].DeepClone();
            manifestHashInput["cases"] = frozenCases.DeepClone();
            string manifestHash = Sha256OfToken(manifestHashInput);
            frozen["manifestHash"] = manifestHash;

            string suppliedManifestHash = input.Value<string>("manifestHash");
            if (!string.IsNullOrEmpty(suppliedManifestHash) && suppliedManifestHash != manifestHash)
                throw new InvalidOperationException("manifestHash mismatch");

            int totalRuns = 0;
            foreach (CalibrationCase testCase in normalizedCases)
                totalRuns += testCase.Repeat;

            return new BatchManifest
            {
                BatchId = batchId,
                ManifestHash = manifestHash,
                Frozen = frozen,
                Cases = normalizedCases,
                TotalRuns = totalRuns
            };
        }

        private static JArray NormalizeRoster(JArray roster, string fieldName)
        {
            if (roster == null || roster.Count == 0)
                throw new InvalidOperationException(fieldName + " must be a non-empty array");

            JArray normalized = new JArray();
            for (int i = 0; i < roster.Count; i++)
            {
                JObject entry = roster[i] as JObject;
                if (entry == null)
                    throw new InvalidOperationException(fieldName + "[" + i + "] must be an object");

                string type = entry.Value<string>("type") ?? entry.Value<string>("兵种");
                if (string.IsNullOrEmpty(type) || !Regex.IsMatch(type, "^兵种[0-9]+$"))
                    throw new InvalidOperationException(fieldName + "[" + i + "].type must use 兵种N");

                JToken levelToken = entry["level"] ?? entry["等级"];
                int level = PositiveInt(levelToken, fieldName + "[" + i + "].level", 0);
                JObject normalizedEntry = new JObject();
                normalizedEntry["type"] = type;
                normalizedEntry["level"] = level;
                normalized.Add(normalizedEntry);
            }
            return normalized;
        }

        private static JArray ToFlashRoster(JArray roster)
        {
            JArray result = new JArray();
            foreach (JObject entry in roster)
            {
                JObject normalized = new JObject();
                normalized["兵种"] = entry.Value<string>("type");
                normalized["等级"] = entry.Value<int>("level");
                result.Add(normalized);
            }
            return result;
        }

        private static JObject NormalizeSideSummary(JObject input)
        {
            JObject side = new JObject();
            side["maxHp"] = NonNegativeNumber(input != null ? input["maxHp"] : null);
            side["remainHp"] = NonNegativeNumber(input != null ? input["remainHp"] : null);
            side["aliveCount"] = NonNegativeNumber(input != null ? input["aliveCount"] : null);
            side["startMaxHp"] = NonNegativeNumber(input != null ? input["startMaxHp"] : side["maxHp"]);
            side["startCount"] = NonNegativeNumber(input != null ? input["startCount"] : side["aliveCount"]);
            return side;
        }

        private static JArray NormalizeErrors(JToken token)
        {
            if (token is JArray)
                return (JArray)token.DeepClone();
            return new JArray();
        }

        private static void CopyOptionalNumber(JObject source, JObject target, string fieldName)
        {
            if (source[fieldName] == null || source[fieldName].Type == JTokenType.Null)
                target[fieldName] = null;
            else
                target[fieldName] = NonNegativeNumber(source[fieldName]);
        }

        private static int DefaultTimeoutMsFromFrames(int frames)
        {
            double ms = Math.Ceiling(frames * (1000.0 / 30.0));
            if (ms < 1000.0)
                ms = 1000.0;
            if (ms > 300000.0)
                ms = 300000.0;
            return (int)ms;
        }

        private static int PositiveInt(JToken token, string fieldName, int defaultValue)
        {
            if (token == null || token.Type == JTokenType.Null)
            {
                if (defaultValue > 0)
                    return defaultValue;
                throw new InvalidOperationException(fieldName + " must be a positive integer");
            }

            int value;
            if (!int.TryParse(token.ToString(), out value) || value <= 0)
                throw new InvalidOperationException(fieldName + " must be a positive integer");
            return value;
        }

        private static double NonNegativeNumber(JToken token)
        {
            if (token == null || token.Type == JTokenType.Null)
                return 0.0;
            double value;
            if (!double.TryParse(token.ToString(), out value) || value < 0.0)
                return 0.0;
            return value;
        }

        private static string RequiredString(JObject obj, string fieldName)
        {
            string value = obj.Value<string>(fieldName);
            if (string.IsNullOrEmpty(value))
                throw new InvalidOperationException(fieldName + " is required");
            return value;
        }

        private static string ValidateBatchId(string batchId)
        {
            if (!BatchIdPattern.IsMatch(batchId))
                throw new InvalidOperationException("batchId must match ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$");
            return batchId;
        }

        private string ResolveBatchDir(string batchId)
        {
            string root = Path.GetFullPath(Path.Combine(_projectRoot, "tmp", "arena-calibration", "batches"));
            string full = Path.GetFullPath(Path.Combine(root, batchId));
            EnsurePathUnderDirectory(full, root, "batchDir");
            return full;
        }

        private string ResolveResultPath(string batchId)
        {
            string root = Path.GetFullPath(Path.Combine(_projectRoot, "logs", "arena-calibration"));
            string full = Path.GetFullPath(Path.Combine(root, batchId + "-results.jsonl"));
            EnsurePathUnderDirectory(full, root, "resultPath");
            return full;
        }

        private static void EnsurePathUnderDirectory(string fullPath, string directoryRoot, string fieldName)
        {
            string root = Path.GetFullPath(directoryRoot).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
                + Path.DirectorySeparatorChar;
            string full = Path.GetFullPath(fullPath);
            if (!full.StartsWith(root, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException(fieldName + " must stay under " + directoryRoot);
        }

        private static void RejectEconomyKeys(JToken token, string path)
        {
            if (token is JObject)
            {
                JObject obj = (JObject)token;
                foreach (JProperty property in obj.Properties())
                {
                    string lower = property.Name.ToLowerInvariant();
                    if (lower == "money" || lower == "cash" || lower == "gold" || lower == "coin"
                        || lower == "coins" || lower == "reward" || lower == "rewards"
                        || lower == "drop" || lower == "drops" || lower == "loot"
                        || lower == "item" || lower == "items" || lower == "equipment"
                        || lower == "equip" || lower == "exp" || lower == "xp"
                        || lower == "kpoint" || lower == "kpoints")
                        throw new InvalidOperationException(path + "." + property.Name + " is not allowed in arena calibration manifest");
                    RejectEconomyKeys(property.Value, path + "." + property.Name);
                }
            }
            else if (token is JArray)
            {
                JArray array = (JArray)token;
                for (int i = 0; i < array.Count; i++)
                    RejectEconomyKeys(array[i], path + "[" + i + "]");
            }
        }

        private static string Sha256OfToken(JToken token)
        {
            string canonicalJson = Canonicalize(token).ToString(Formatting.None);
            byte[] bytes = Encoding.UTF8.GetBytes(canonicalJson);
            using (SHA256 sha = SHA256.Create())
            {
                byte[] hash = sha.ComputeHash(bytes);
                StringBuilder sb = new StringBuilder("sha256:");
                foreach (byte b in hash)
                    sb.Append(b.ToString("x2"));
                return sb.ToString();
            }
        }

        private static JToken Canonicalize(JToken token)
        {
            if (token is JObject)
            {
                JObject source = (JObject)token;
                JObject result = new JObject();
                List<JProperty> properties = new List<JProperty>(source.Properties());
                properties.Sort(delegate(JProperty a, JProperty b)
                {
                    return string.CompareOrdinal(a.Name, b.Name);
                });
                foreach (JProperty property in properties)
                    result[property.Name] = Canonicalize(property.Value);
                return result;
            }
            if (token is JArray)
            {
                JArray source = (JArray)token;
                JArray result = new JArray();
                foreach (JToken item in source)
                    result.Add(Canonicalize(item));
                return result;
            }
            return token.DeepClone();
        }

        private string ToProjectRelative(string fullPath)
        {
            if (string.IsNullOrEmpty(fullPath))
                return null;
            try
            {
                return Path.GetRelativePath(_projectRoot, fullPath).Replace('\\', '/');
            }
            catch
            {
                return fullPath;
            }
        }
    }
}
