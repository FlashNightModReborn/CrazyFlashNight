using System;
using System.Collections.Generic;
using System.Threading;

namespace CF7Launcher.Guardian.Hud
{
    /// <summary>
    /// 为“只保留最新请求”的后台工作提供轻量代次门。已开始的单项不会被强行中断，
    /// 但旧工作集会在下一项前退出。
    /// </summary>
    internal sealed class LatestWorkGeneration
    {
        private int _generation;

        internal int Advance()
        {
            return Interlocked.Increment(ref _generation);
        }

        internal bool IsCurrent(int generation)
        {
            return Volatile.Read(ref _generation) == generation;
        }

        internal int Process<T>(IList<T> workset, int generation, Action<T> action)
        {
            if (workset == null) throw new ArgumentNullException(nameof(workset));
            if (action == null) throw new ArgumentNullException(nameof(action));
            int processed = 0;
            for (int i = 0; i < workset.Count; i++)
            {
                if (!IsCurrent(generation)) break;
                action(workset[i]);
                processed++;
            }
            return processed;
        }
    }
}
