// CF7:ME save-resolution DI container. Bundles the resolver + archive +
// swfPath that StartGame(slot) needs for per-launch SOL resolution.
// C# 5 syntax.

using CF7Launcher.Tasks;

namespace CF7Launcher.Save
{
    public class SaveResolutionContext
    {
        public readonly SolFileLocator Locator;
        public readonly SolResolver Resolver;
        public readonly ArchiveTask Archive;
        public readonly string SwfPath;

        public SaveResolutionContext(SolFileLocator locator, SolResolver resolver, ArchiveTask archive, string swfPath)
        {
            Locator = locator;
            Resolver = resolver;
            Archive = archive;
            SwfPath = swfPath;
        }
    }
}
