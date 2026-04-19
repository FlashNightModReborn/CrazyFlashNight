// 依赖注入接口：把 SolResolver 对 SolParserNative 的静态依赖抽成契约，
// 允许测试替换为 mock 实现。生产实现是 NativeSolParser。

namespace CF7Launcher.Save
{
    public interface ISolParser
    {
        /// <summary>
        /// 解析一个 .sol 文件，返回 <see cref="SolParseResult"/>。
        /// 该方法不得抛异常：所有错误经 result.ReturnCode + result.Error 回传。
        /// </summary>
        SolParseResult Parse(string path);
    }
}
