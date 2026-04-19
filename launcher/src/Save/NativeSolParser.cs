// 生产 ISolParser 实现：直接转发到 SolParserNative.Parse 的 P/Invoke 入口。

namespace CF7Launcher.Save
{
    public sealed class NativeSolParser : ISolParser
    {
        public SolParseResult Parse(string path)
        {
            return SolParserNative.Parse(path);
        }
    }
}
