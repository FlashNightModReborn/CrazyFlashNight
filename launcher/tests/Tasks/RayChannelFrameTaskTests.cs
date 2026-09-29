using System;
using System.Globalization;
using System.IO;
using System.Linq;
using CF7Launcher.Guardian.HitNumbers;
using CF7Launcher.Guardian.WorldCompositor;
using CF7Launcher.Tasks;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public sealed class RayChannelFrameTaskTests
    {
        [Fact]
        public void CapabilityRevokeAndRejectedBindingsCannotRestoreAQueuedOldChannelOrLight()
        {
            var task=new FrameTask(null,null);
            task.ConfigureProjectileVisuals(BulletVisualCatalog.Load(ProjectRoot()));
            task.ConfigureRayLighting(RayLightingCatalog.Load(ProjectRoot()));
            int count=0,lights=0,rejected=0;long lightKey=0;float end=0;
            task.RayVisualObserved=(draw,x,y,scale)=> {
                count=draw.Count;lights=draw.LightCount;
                if(lights>0)lightKey=draw.Lights[0].Key;
                if(count>0)end=draw.Data[2];
            };
            task.RayVisualCleared=()=> {count=lights=0;};
            task.RayVisualRejected=()=>rejected++;
            void Feed(int epoch,int seq,int tick,string events,int generation=7) =>
                task.ObserveProjectileVisuals($"{epoch}|{seq}|{tick}|0;o,0,0;"+events,null,generation,new HitNumberCamera(0,0,1));
            Feed(3,1,0,Config()+";"+Spawn());
            Assert.Equal(1,count);Assert.Equal(1,lights);long retired=lightKey;
            Feed(3,2,1,Spawn(serial:2,born:1,operation:"u",end:350));
            Assert.Equal(350,end);Assert.Equal(retired,lightKey);
            task.InvalidateRayVisuals();Assert.Equal(0,count);Assert.Equal(0,lights);
            Feed(3,3,2,Spawn(serial:3,born:2,operation:"u",end:900));
            Assert.Equal(0,count);Assert.Equal(0,lights);Assert.Equal(0,rejected);
            Feed(4,1,0,Config()+";"+Spawn(end:400));
            Assert.Equal(1,count);Assert.Equal(1,lights);Assert.NotEqual(retired,lightKey);
            Feed(4,2,1,Spawn(serial:2,born:1,operation:"u",key:8));
            Assert.Equal(1,rejected);Assert.Equal(0,count);Assert.Equal(0,lights);
            Feed(4,3,2,Spawn(serial:3,born:2,operation:"u"));
            Assert.Equal(0,count);
            Feed(5,1,0,Config()+";"+Spawn(end:500));
            Assert.Equal(1,count);Assert.Equal(500,end);
            Feed(6,1,0,Config()+";"+Spawn(end:999),generation:6);
            Assert.Equal(500,end);Assert.Equal(1,lights);
            task.ResetProjectileVisualsForGeneration(7);
            Assert.Equal(0,count);Assert.Equal(0,lights);
        }

        private static string Config()
        {
            var values=Enumerable.Repeat(1f,RayVisualCatalog.FieldNames.Length).ToArray();
            values[0]=0xFF8800;values[1]=0xFFFFFF;values[2]=4;values[3]=5;values[4]=3;values[5]=0;
            return "c,1,0,"+string.Join(',',values.Select(v=>v.ToString(CultureInfo.InvariantCulture)))+",-";
        }
        private static string Spawn(int serial=1,int born=0,string operation="s",int key=7,int end=200) =>
            $"{operation},1,1,{born},0,100,50,{end},50,0,0,1,0,123,{key},{serial},500,0,0,2,-,-,0";
        private static string ProjectRoot()
        {
            for(var path=new DirectoryInfo(AppContext.BaseDirectory);path!=null;path=path.Parent)
                if(File.Exists(Path.Combine(path.FullName,RayLightingCatalog.RelativePath)))return path.FullName;
            throw new DirectoryNotFoundException(RayLightingCatalog.RelativePath);
        }
    }
}
