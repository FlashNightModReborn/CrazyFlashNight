// CF7:ME save-resolution DI container. Bundles the resolver + archive +
// swfPath that StartGame(slot) needs for per-launch SOL resolution.
// C# 5 syntax.

using CF7Launcher.Tasks;

namespace CF7Launcher.Save
{
    public class SaveResolutionContext
    {
        public readonly SolResolver Resolver;
        public readonly ArchiveTask Archive;
        public readonly string SwfPath;

        public SaveResolutionContext(SolResolver resolver, ArchiveTask archive, string swfPath)
        {
            Resolver = resolver;
            Archive = archive;
            SwfPath = swfPath;
        }
    }
}
