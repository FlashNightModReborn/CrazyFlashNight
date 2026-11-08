using System;

namespace CF7Launcher.Guardian
{
    // Shared data classes log to stderr in the CLI; stdout remains its JSON protocol.
    internal static class LogManager
    {
        public static void Log(string message) => Console.Error.WriteLine(message);
    }
}
