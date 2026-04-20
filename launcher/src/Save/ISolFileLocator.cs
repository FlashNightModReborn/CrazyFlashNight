// 窄接口：SolResolver 只需要 FindSolFile，不需要 DeleteAllSolFiles。
// 抽出接口便于测试替换。生产实现是 SolFileLocator。

namespace CF7Launcher.Save
{
    public interface ISolFileLocator
    {
        /// <summary>
        /// 返回 (slot, swfPath) 对应的 SOL 文件完整路径；不存在时返回 null。
        /// </summary>
        string FindSolFile(string slot, string swfPath);
    }
}
