using System;
using System.IO;
using System.Text.Json;

namespace CF7Launcher.Tests.AgentRuntime.Contracts
{
    internal static class ContractFixture
    {
        internal static string DirectoryPath
        {
            get
            {
                var current = new DirectoryInfo(AppContext.BaseDirectory);
                while (current != null)
                {
                    string candidate = Path.Combine(
                        current.FullName,
                        "launcher",
                        "contracts",
                        "agent-runtime",
                        "v1");
                    if (Directory.Exists(candidate)) return candidate;
                    current = current.Parent;
                }
                throw new DirectoryNotFoundException(
                    "Could not locate launcher/contracts/agent-runtime/v1 from " +
                    AppContext.BaseDirectory);
            }
        }

        internal static JsonDocument ReadDocument(string fileName)
        {
            return JsonDocument.Parse(
                File.ReadAllBytes(Path.Combine(DirectoryPath, fileName)),
                new JsonDocumentOptions
                {
                    AllowTrailingCommas = false,
                    CommentHandling = JsonCommentHandling.Disallow,
                    MaxDepth = 128
                });
        }

        internal static T Deserialize<T>(JsonElement value)
        {
            T result = JsonSerializer.Deserialize<T>(
                value.GetRawText(),
                CF7Launcher.AgentRuntime.Contracts.AgentProtocolV1.JsonOptions);
            if (result == null) throw new InvalidDataException("Contract vector deserialized to null.");
            return result;
        }

        internal static string EnumText<T>(T value) where T : struct, Enum
        {
            return JsonSerializer.Serialize(
                value,
                CF7Launcher.AgentRuntime.Contracts.AgentProtocolV1.JsonOptions).Trim('"');
        }
    }
}
