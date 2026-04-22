using Newtonsoft.Json.Linq;

namespace CF7Launcher.Save
{
    public interface IArchiveShadowWriter
    {
        bool TrySeedShadowSync(string slot, JObject data, out string targetPath, out string error);
    }
}
