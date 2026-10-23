using System.Collections.Generic;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public sealed class MeridiansProjectionTests
    {
        [Theory]
        [InlineData("applied")]
        [InlineData("unchanged")]
        [InlineData("pending")]
        [InlineData("failed")]
        public void PublicResponsePreservesCommittedMemoryAndPendingSave(string status)
        {
            string sent=null, posted=null;
            using var task=new MeridiansTask(()=>true,text=>sent=text);
            task.SetPostToWeb(text=>posted=text);
            task.HandleWebRequest("light",new JObject{["callId"]="meridian.test.1",["nodeId"]="node"});
            int call=JObject.Parse(sent.TrimEnd('\0')).Value<int>("callId");
            task.HandleFlashResponse(new JObject{
                ["callId"]=call,["task"]="meridians_response",["success"]=false,["v"]=1,
                ["applied"]=true,["savePending"]=true,["error"]="save_pending",
                ["projection"]=new JObject{["status"]=status,["reason"]="injected"}
            },null);
            var response=JObject.Parse(posted);
            Assert.True(response.Value<bool>("applied"));Assert.True(response.Value<bool>("savePending"));
            Assert.False(response.Value<bool>("success"));Assert.Equal("save_pending",response.Value<string>("error"));
            Assert.Equal(status,response["projection"].Value<string>("status"));
            Assert.Equal("meridian.test.1",response.Value<string>("callId"));
        }
        public static IEnumerable<object[]> InvalidProjection()
        {
            yield return new object[]{JValue.CreateNull()};
            yield return new object[]{new JObject{["status"]="failed",["reason"]="",["extra"]=1}};
            yield return new object[]{new JObject{["status"]="clean",["reason"]=""}};
            yield return new object[]{new JObject{["status"]="applied",["reason"]=1}};
            yield return new object[]{new JObject{["status"]="failed",["reason"]=new string('x',161)}};
        }
        [Theory]
        [MemberData(nameof(InvalidProjection))]
        public void MalformedProjectionCannotForwardAFalseCleanResult(JToken value)
        {
            Assert.False(MeridiansTask.ValidProjection(new JObject{["projection"]=value}));
        }
    }
}
