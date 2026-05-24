// DiagnosticsBootstrap — 集中渲染合成层诊断的启动/停止 wiring.
// 配置读取由 AppConfig 完成 (config.toml + env 双源, env 后赢), 这里只消费已解析的开关。
//
// 调用约定:
//   Init(...)        — Program.Run 中 LogManager.InitFileLog 之后. 启动诊断 + 启动期 LayerAudit dump.
//   ReadySnapshot()  — readyWiring 回调内. 在 overlay 全部构造完后再 dump 一次, 这一份才是稳态参考。
//   Shutdown()       — Application.Run 返回后, LogManager.Shutdown 之前. 安全停掉 ETW 消费线程。
//
// C# 5 / net462.

using System;
using CF7Launcher.Guardian;

namespace CF7Launcher.Diagnostic
{
    public static class DiagnosticsBootstrap
    {
        private static bool _layerAudit;
        private static bool _ulwMonitor;
        private static bool _etwDwm;
        private static int  _intervalSec;
        private static bool _initDone;

        public static bool LayerAuditEnabled { get { return _layerAudit; } }
        public static bool UlwMonitorEnabled { get { return _ulwMonitor; } }
        public static bool EtwDwmEnabled     { get { return _etwDwm; } }

        public static void Init(bool layerAudit, bool ulwMonitor, bool etwDwm, int intervalSec)
        {
            if (_initDone) return;
            _initDone = true;

            _layerAudit  = layerAudit;
            _ulwMonitor  = ulwMonitor;
            _etwDwm      = etwDwm;
            _intervalSec = intervalSec < 1 ? 1 : intervalSec;

            if (!_layerAudit && !_ulwMonitor && !_etwDwm)
                return;  // 全部关 — 一行 log 都不打, 不污染玩家版

            LogManager.Log("[Diag] enabled:"
                + " layerAudit=" + _layerAudit
                + " ulwMonitor=" + _ulwMonitor
                + " etwDwm=" + _etwDwm
                + " interval=" + _intervalSec + "s");

            if (_layerAudit)
            {
                LayerAuditDump.DumpToLog("startup");
            }

            if (_ulwMonitor)
            {
                UlwCommitMonitor.Start(_intervalSec);
            }

            if (_etwDwm)
            {
                DwmEtwMonitor.Start(DwmEtwMonitor.DwmCoreProvider, "Microsoft-Windows-Dwm-Core", _intervalSec);
            }
        }

        /// <summary>readyWiring 内调用; overlay 全部构造后再 snapshot 一次。</summary>
        public static void ReadySnapshot()
        {
            if (_layerAudit)
                LayerAuditDump.DumpToLog("post-ready");
        }

        public static void Shutdown()
        {
            if (_etwDwm)
            {
                try { DwmEtwMonitor.Stop(); } catch { }
            }
            if (_ulwMonitor)
            {
                try { UlwCommitMonitor.Stop(); } catch { }
            }
            if (_layerAudit)
            {
                // 退出前最后一次 snapshot — 帮助看是否有 form 没释放
                try { LayerAuditDump.DumpToLog("shutdown"); } catch { }
            }
        }
    }
}
