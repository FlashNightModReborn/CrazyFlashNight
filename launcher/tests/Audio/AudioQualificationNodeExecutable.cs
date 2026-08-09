using System;
using System.IO;

namespace CF7Launcher.Tests.Audio
{
    internal static class AudioQualificationNodeExecutable
    {
        internal const string EnvironmentVariableName = "CF7_NODE_EXE";

        internal static string ResolveFromEnvironment()
        {
            return Resolve(Environment.GetEnvironmentVariable(
                EnvironmentVariableName));
        }

        internal static string Resolve(string value)
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                throw new InvalidOperationException(
                    EnvironmentVariableName + " is required for Audio v2 qualification tests.");
            }
            if (!Path.IsPathFullyQualified(value))
            {
                throw new InvalidOperationException(
                    EnvironmentVariableName + " must be an absolute path.");
            }

            string fullPath = Path.GetFullPath(value);
            if (!string.Equals(value, fullPath, StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException(
                    EnvironmentVariableName + " must use its canonical absolute path.");
            }
            var file = new FileInfo(fullPath);
            if (!file.Exists ||
                (file.Attributes & FileAttributes.ReparsePoint) != 0 ||
                !string.Equals(file.Extension, ".exe", StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException(
                    EnvironmentVariableName + " must name a regular non-link executable.");
            }
            return fullPath;
        }
    }
}
