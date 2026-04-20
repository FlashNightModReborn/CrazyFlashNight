// 窄接口：SolResolver 只需要 tombstone / shadow 读取，不关心 ArchiveTask 其他职责。
// 抽出便于测试替换。生产实现是 ArchiveTask。

using Newtonsoft.Json.Linq;

namespace CF7Launcher.Save
{
    public interface IArchiveStateProbe
    {
        bool IsTombstoned(string slot);

        /// <summary>
        /// 同步读 shadow JSON。返回 false 且 error 为 "not_found" 表示不存在；
        /// 其他 false 情况表示读/解析错误。
        /// </summary>
        bool TryLoadShadowSync(string slot, out JObject data, out string error);
    }
}
