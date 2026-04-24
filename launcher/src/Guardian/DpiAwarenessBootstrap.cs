using System;
using System.Runtime.InteropServices;

namespace CF7Launcher.Guardian
{
    public sealed class DpiAwarenessInitResult
    {
        public bool Success;
        public string Method;
        public string Detail;

        public string Describe()
        {
            return "success=" + Success + " method=" + (Method ?? "")
                + " detail=" + (Detail ?? "");
        }
    }

    public static class DpiAwarenessBootstrap
    {
        private static volatile DpiAwarenessInitResult _result;

        private const int ERROR_ACCESS_DENIED = 5;
        private const int PROCESS_PER_MONITOR_DPI_AWARE = 2;
        private static readonly IntPtr DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = new IntPtr(-4);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool SetProcessDpiAwarenessContext(IntPtr dpiContext);

        [DllImport("shcore.dll")]
        private static extern int SetProcessDpiAwareness(int awareness);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool SetProcessDPIAware();

        public static DpiAwarenessInitResult Initialize()
        {
            if (_result != null)
                return _result;

            _result = TryPerMonitorV2();
            if (_result.Success)
                return _result;

            DpiAwarenessInitResult perMonitor = TryPerMonitor();
            if (perMonitor.Success)
            {
                _result = perMonitor;
                return _result;
            }

            DpiAwarenessInitResult systemAware = TrySystemAware();
            if (systemAware.Success)
            {
                _result = systemAware;
                return _result;
            }

            _result = new DpiAwarenessInitResult
            {
                Success = false,
                Method = "none",
                Detail = "PerMonitorV2 failed: " + _result.Detail
                    + "; PerMonitor failed: " + perMonitor.Detail
                    + "; SystemAware failed: " + systemAware.Detail
            };
            return _result;
        }

        public static DpiAwarenessInitResult Result
        {
            get { return _result; }
        }

        private static DpiAwarenessInitResult TryPerMonitorV2()
        {
            try
            {
                if (SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2))
                {
                    return new DpiAwarenessInitResult
                    {
                        Success = true,
                        Method = "SetProcessDpiAwarenessContext(PER_MONITOR_AWARE_V2)",
                        Detail = "ok"
                    };
                }

                int err = Marshal.GetLastWin32Error();
                if (err == ERROR_ACCESS_DENIED)
                {
                    return new DpiAwarenessInitResult
                    {
                        Success = true,
                        Method = "manifest-or-existing-awareness",
                        Detail = "SetProcessDpiAwarenessContext returned ERROR_ACCESS_DENIED; treating as already set"
                    };
                }

                return new DpiAwarenessInitResult
                {
                    Success = false,
                    Method = "SetProcessDpiAwarenessContext(PER_MONITOR_AWARE_V2)",
                    Detail = "Win32Error=" + err
                };
            }
            catch (Exception ex)
            {
                return new DpiAwarenessInitResult
                {
                    Success = false,
                    Method = "SetProcessDpiAwarenessContext(PER_MONITOR_AWARE_V2)",
                    Detail = ex.GetType().Name + ": " + ex.Message
                };
            }
        }

        private static DpiAwarenessInitResult TryPerMonitor()
        {
            try
            {
                int hr = SetProcessDpiAwareness(PROCESS_PER_MONITOR_DPI_AWARE);
                if (hr == 0)
                {
                    return new DpiAwarenessInitResult
                    {
                        Success = true,
                        Method = "SetProcessDpiAwareness(PROCESS_PER_MONITOR_DPI_AWARE)",
                        Detail = "ok"
                    };
                }

                unchecked
                {
                    if (hr == (int)0x80070005)
                    {
                        return new DpiAwarenessInitResult
                        {
                            Success = true,
                            Method = "manifest-or-existing-awareness",
                            Detail = "SetProcessDpiAwareness returned E_ACCESSDENIED; treating as already set"
                        };
                    }
                }

                return new DpiAwarenessInitResult
                {
                    Success = false,
                    Method = "SetProcessDpiAwareness(PROCESS_PER_MONITOR_DPI_AWARE)",
                    Detail = "HRESULT=0x" + hr.ToString("X8")
                };
            }
            catch (Exception ex)
            {
                return new DpiAwarenessInitResult
                {
                    Success = false,
                    Method = "SetProcessDpiAwareness(PROCESS_PER_MONITOR_DPI_AWARE)",
                    Detail = ex.GetType().Name + ": " + ex.Message
                };
            }
        }

        private static DpiAwarenessInitResult TrySystemAware()
        {
            try
            {
                if (SetProcessDPIAware())
                {
                    return new DpiAwarenessInitResult
                    {
                        Success = true,
                        Method = "SetProcessDPIAware",
                        Detail = "ok"
                    };
                }

                int err = Marshal.GetLastWin32Error();
                if (err == ERROR_ACCESS_DENIED)
                {
                    return new DpiAwarenessInitResult
                    {
                        Success = true,
                        Method = "manifest-or-existing-awareness",
                        Detail = "SetProcessDPIAware returned ERROR_ACCESS_DENIED; treating as already set"
                    };
                }

                return new DpiAwarenessInitResult
                {
                    Success = false,
                    Method = "SetProcessDPIAware",
                    Detail = "Win32Error=" + err
                };
            }
            catch (Exception ex)
            {
                return new DpiAwarenessInitResult
                {
                    Success = false,
                    Method = "SetProcessDPIAware",
                    Detail = ex.GetType().Name + ": " + ex.Message
                };
            }
        }
    }
}
