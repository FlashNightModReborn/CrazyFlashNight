using System.Threading;

namespace CF7Launcher.Guardian
{
    /// <summary>Process-wide lifecycle flags shared by top-level exception handling and shutdown code.</summary>
    public static class GuardianLifecycle
    {
        private static int _shuttingDown;

        public static bool IsShuttingDown
        {
            get { return Interlocked.CompareExchange(ref _shuttingDown, 0, 0) != 0; }
        }

        public static void MarkShuttingDown()
        {
            Interlocked.Exchange(ref _shuttingDown, 1);
        }
    }
}
