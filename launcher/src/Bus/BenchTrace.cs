using System.Diagnostics;
using CF7Launcher.Guardian;

namespace CF7Launcher.Bus
{
    internal static class BenchTrace
    {
        private static readonly double TicksToMicroseconds = 1000000.0 / Stopwatch.Frequency;

        public static long NowUs()
        {
            return (long)(Stopwatch.GetTimestamp() * TicksToMicroseconds);
        }

        public static void LogEcho(string path, string token, long recvUs, long sendUs)
        {
            LogManager.Log("[BenchTrace] path=" + path
                + " token=" + token
                + " recvUs=" + recvUs
                + " sendUs=" + sendUs
                + " procUs=" + (sendUs - recvUs));
        }
    }
}
