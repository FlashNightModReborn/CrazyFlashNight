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
        public readonly LegacyPresetSlotSeeder LegacySeeder;
        // ProjectRoot: 由 diagnostic / audio_preview 等 BMH 命令使用。在 v1 加入；
        // 老调用方不传时设为 null，相关命令自行降级（diagnostic 直接报错）。
        public readonly string ProjectRoot;

        public SaveResolutionContext(SolFileLocator locator, SolResolver resolver, ArchiveTask archive, string swfPath)
            : this(locator, resolver, archive, swfPath, null) { }

        public SaveResolutionContext(SolFileLocator locator, SolResolver resolver, ArchiveTask archive, string swfPath, string projectRoot)
        {
            Locator = locator;
            Resolver = resolver;
            Archive = archive;
            SwfPath = swfPath;
            ProjectRoot = projectRoot;
            LegacySeeder = new LegacyPresetSlotSeeder(archive, resolver, swfPath);
        }
    }
}
