using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// 数组求和。响应：{success:true, result:<sum>}
    /// </summary>
    public static class ComputationTask
    {
        public static string Handle(JObject message)
        {
            JObject extra = message.Value<JObject>("extra");
            if (extra == null)
                return Error("No extra provided");

            JArray data = extra.Value<JArray>("data");
            if (data == null)
                return Error("No data array provided for computation");

            double sum = 0;
            foreach (JToken item in data)
            {
                sum += item.Value<double>();
            }

            JObject resp = new JObject();
            resp["success"] = true;
            resp["result"] = sum;
            return resp.ToString(Newtonsoft.Json.Formatting.None);
        }

        private static string Error(string msg)
        {
            JObject resp = new JObject();
            resp["success"] = false;
            resp["error"] = msg;
            return resp.ToString(Newtonsoft.Json.Formatting.None);
        }
    }
}
