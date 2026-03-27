using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
using Newtonsoft.Json.Linq;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// Rapfi 五子棋引擎桥接。Piskvork 协议通过 stdin/stdout 通信。
    /// 队列化单请求，响应带 "task":"gomoku_eval" 字段。
    /// </summary>
    public class GomokuTask : IDisposable
    {
        private Process _engine;
        private readonly string _enginePath;
        private readonly object _queueLock = new object();
        private bool _engineReady;

        public GomokuTask(string projectRoot)
        {
            // 搜索 Rapfi 引擎
            _enginePath = FindEngine(projectRoot);
            if (_enginePath != null)
                LogManager.Log("[Gomoku] Engine found: " + _enginePath);
            else
                LogManager.Log("[Gomoku] WARNING: Engine not found, gomoku_eval will fail");
        }

        private static string FindEngine(string root)
        {
            // 搜索目录：优先 tools/rapfi/，回退 tools/Local Server/bin/
            string[] searchDirs = new string[] {
                Path.Combine(root, "tools", "rapfi"),
                Path.Combine(root, "tools", "Local Server", "bin")
            };

            string[] patterns = new string[] {
                "pbrain-rapfi-windows-avx2*.exe",
                "pbrain-rapfi*.exe",
                "rapfi*.exe"
            };

            foreach (string dir in searchDirs)
            {
                if (!Directory.Exists(dir))
                    continue;

                foreach (string pattern in patterns)
                {
                    string[] files = Directory.GetFiles(dir, pattern);
                    if (files.Length > 0)
                        return files[0];
                }
            }
            return null;
        }

        public void HandleAsync(JObject message, Action<string> respond)
        {
            ThreadPool.QueueUserWorkItem(delegate
            {
                string result;
                lock (_queueLock)
                {
                    result = Evaluate(message);
                }
                respond(result);
            });
        }

        private string Evaluate(JObject message)
        {
            if (_enginePath == null)
                return Error("Gomoku engine not found");

            JObject payload = message.Value<JObject>("payload");
            if (payload == null)
                return Error("No payload");

            JArray moves = payload.Value<JArray>("moves");
            int timeLimit = payload.Value<int>("timeLimit");
            if (timeLimit <= 0) timeLimit = 5000;

            try
            {
                EnsureEngine();

                // 发送 BOARD 命令
                StringBuilder board = new StringBuilder();
                board.AppendLine("BOARD");
                if (moves != null)
                {
                    foreach (JToken move in moves)
                    {
                        JArray m = (JArray)move;
                        int x = m[0].Value<int>();
                        int y = m[1].Value<int>();
                        int role = m[2].Value<int>();
                        // Piskvork: 1=自己(黑), 2=对手(白)
                        int piece = role == 1 ? 1 : 2;
                        board.AppendLine(x + "," + y + "," + piece);
                    }
                }
                board.AppendLine("DONE");

                // 设置时间限制
                _engine.StandardInput.WriteLine("INFO timeout_turn " + timeLimit);
                _engine.StandardInput.Write(board.ToString());
                _engine.StandardInput.Flush();

                // 读取结果（带硬超时保护）
                int bestX = -1, bestY = -1;
                int score = 0, depth = 0;
                string pv = "";

                int hardTimeout = timeLimit + 3000;
                // 超时后强杀引擎，确保 ReadLine 不会永远阻塞
                Timer killTimer = new Timer(delegate
                {
                    LogManager.Log("[Gomoku] Hard timeout reached, killing engine");
                    KillEngine();
                }, null, hardTimeout, Timeout.Infinite);

                try
                {
                    while (true)
                    {
                        string line = null;
                        try
                        {
                            if (_engine == null || _engine.HasExited) break;
                            line = _engine.StandardOutput.ReadLine();
                        }
                        catch { break; }

                        if (line == null) break;
                        line = line.Trim();

                        if (line.StartsWith("MESSAGE"))
                        {
                            ParseMessageLine(line, ref depth, ref score, ref pv);
                        }
                        else if (line.Contains(",") && !line.StartsWith("MESSAGE"))
                        {
                            string[] parts = line.Split(',');
                            if (parts.Length >= 2)
                            {
                                int.TryParse(parts[0].Trim(), out bestX);
                                int.TryParse(parts[1].Trim(), out bestY);
                            }
                            break;
                        }
                    }
                }
                finally
                {
                    killTimer.Dispose();
                }

                JObject result = new JObject();
                result["x"] = bestX;
                result["y"] = bestY;
                result["score"] = score;
                result["depth"] = depth;
                result["pv"] = pv;

                JObject resp = new JObject();
                resp["success"] = true;
                resp["task"] = "gomoku_eval";
                resp["result"] = result;
                return resp.ToString(Newtonsoft.Json.Formatting.None);
            }
            catch (Exception ex)
            {
                LogManager.Log("[Gomoku] Error: " + ex.Message);
                KillEngine();
                return Error(ex.Message);
            }
        }

        private void ParseMessageLine(string line, ref int depth, ref int score, ref string pv)
        {
            // MESSAGE Depth 18 | Eval 150 | PV J9 J10 ...
            try
            {
                string content = line.Substring("MESSAGE".Length).Trim();
                string[] segments = content.Split('|');
                foreach (string seg in segments)
                {
                    string s = seg.Trim();
                    if (s.StartsWith("Depth"))
                        int.TryParse(s.Substring(5).Trim(), out depth);
                    else if (s.StartsWith("Eval"))
                        int.TryParse(s.Substring(4).Trim(), out score);
                    else if (s.StartsWith("PV"))
                        pv = s.Substring(2).Trim();
                }
            }
            catch { }
        }

        private void EnsureEngine()
        {
            if (_engine != null && !_engine.HasExited)
            {
                if (_engineReady) return;
            }

            KillEngine();

            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = _enginePath;
            psi.UseShellExecute = false;
            psi.RedirectStandardInput = true;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.CreateNoWindow = true;
            psi.WorkingDirectory = Path.GetDirectoryName(_enginePath);

            _engine = Process.Start(psi);
            _engine.StandardInput.WriteLine("START 15");
            _engine.StandardInput.Flush();

            // 等待 OK
            string okLine = _engine.StandardOutput.ReadLine();
            _engineReady = okLine != null && okLine.Trim() == "OK";

            if (_engineReady)
                LogManager.Log("[Gomoku] Engine started OK");
            else
                LogManager.Log("[Gomoku] Engine start response: " + okLine);
        }

        private void KillEngine()
        {
            if (_engine != null)
            {
                try
                {
                    if (!_engine.HasExited)
                    {
                        _engine.StandardInput.WriteLine("END");
                        _engine.StandardInput.Flush();
                        if (!_engine.WaitForExit(1000))
                            _engine.Kill();
                    }
                }
                catch { }
                try { _engine.Dispose(); } catch { }
                _engine = null;
                _engineReady = false;
            }
        }

        private static string Error(string msg)
        {
            JObject resp = new JObject();
            resp["success"] = false;
            resp["error"] = msg;
            return resp.ToString(Newtonsoft.Json.Formatting.None);
        }

        public void Dispose()
        {
            KillEngine();
        }
    }
}
