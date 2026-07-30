using System;
using CF7Launcher.AgentRuntime.Security;

namespace CF7Launcher.Tests.AgentRuntime.Security
{
    internal sealed class ManualAgentRuntimeClock : IAgentRuntimeClock
    {
        public long MonotonicMilliseconds { get; private set; }

        public DateTimeOffset UtcNow { get; private set; } =
            new DateTimeOffset(
                2026,
                7,
                30,
                0,
                0,
                0,
                TimeSpan.Zero);

        public void Advance(TimeSpan duration)
        {
            if (duration < TimeSpan.Zero)
            {
                throw new ArgumentOutOfRangeException(nameof(duration));
            }
            MonotonicMilliseconds += (long)duration.TotalMilliseconds;
            UtcNow = UtcNow.Add(duration);
        }
    }
}
