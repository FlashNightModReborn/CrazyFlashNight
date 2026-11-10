using System;
using System.Collections.Generic;

namespace CF7Launcher.AgentRuntime.Contracts
{
    // Opaque, closed test gestures. They are never native key names and require
    // an independently verified, candidate-only qualification composition.
    internal static class GameQualificationInput
    {
        private static readonly HashSet<string> Gestures = new HashSet<string>(
            new[] { "w", "a", "s", "d", "j", "k", "r", "1", "2", "3", "4", "5", "space",
                "shift+a", "shift+d", "a+j", "d+j", "w+j", "s+j",
                "shift+a+j", "shift+d+j", "a+r", "d+r" }, StringComparer.Ordinal);

        internal static bool TryResolve(string token, out string[] keys)
        {
            keys = null;
            if (token == null || !token.StartsWith("q205:", StringComparison.Ordinal)) return false;
            string gesture = token.Substring(5);
            if (!Gestures.Contains(gesture)) return false;
            keys = gesture.Split('+');
            return true;
        }
    }
}
