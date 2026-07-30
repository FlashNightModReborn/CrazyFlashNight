using System;
using System.Diagnostics;

namespace CF7Launcher.AgentRuntime.Security
{
    /// <summary>
    /// Runtime security decisions use monotonic time. UTC is retained only for
    /// human-readable receipts and must never be used for expiry comparisons.
    /// </summary>
    public interface IAgentRuntimeClock
    {
        long MonotonicMilliseconds { get; }

        DateTimeOffset UtcNow { get; }
    }

    public sealed class SystemAgentRuntimeClock : IAgentRuntimeClock
    {
        public long MonotonicMilliseconds
        {
            get
            {
                return (long)(Stopwatch.GetTimestamp()
                    * (1000.0 / Stopwatch.Frequency));
            }
        }

        public DateTimeOffset UtcNow
        {
            get { return DateTimeOffset.UtcNow; }
        }
    }
}
