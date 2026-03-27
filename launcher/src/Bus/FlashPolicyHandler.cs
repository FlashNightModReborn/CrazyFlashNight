namespace CF7Launcher.Bus
{
    /// <summary>
    /// Flash 安全策略处理：检测 policy-file-request 并返回跨域策略 XML。
    /// </summary>
    public static class FlashPolicyHandler
    {
        private static readonly string PolicyRequest = "<policy-file-request/>";
        private static readonly string PolicyResponse =
            "<cross-domain-policy><allow-access-from domain=\"*\" to-ports=\"*\" /></cross-domain-policy>\0";

        public static bool IsPolicyRequest(string data)
        {
            return data != null && data.Contains(PolicyRequest);
        }

        public static string GetPolicyResponse()
        {
            return PolicyResponse;
        }
    }
}
