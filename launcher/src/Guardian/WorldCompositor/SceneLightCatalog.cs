using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian.WorldCompositor
{
    // Authored defaults live only in scene_lights.v1.json. Each scene may override
    // every supported presentation field; AS2 supplies identity and resolved pose.
    internal sealed class SceneLightCatalog
    {
        internal const int Limit = 128;
        internal const string RelativePath = "data/environment/scene_lights.v1.json";
        private readonly JObject _presets;
        internal readonly int SceneReserve;
        internal readonly float MaximumResponse;
        internal SceneLightCatalog(JObject root)
        {
            if (root?.Value<string>("schema") != "cf7-scene-lights.v1" || root["presets"] is not JObject presets)
                throw new InvalidDataException("Invalid scene light catalog");
            _presets = (JObject)presets.DeepClone();
            SceneReserve = (int)Number(root,"sceneReserve",2,0,8);
            if (Number(root,"sceneReserve",2,0,8) != SceneReserve) throw new InvalidDataException("Fractional scene reserve");
            MaximumResponse = (float)Number(root,"maximumResponse",.78,0,.8);
            foreach (var p in _presets.Properties()) Resolve(new JObject { ["Key"]="validate", ["Preset"]=p.Name }, 1);
        }
        internal static SceneLightCatalog Load(string root) => new(JObject.Parse(File.ReadAllText(Path.Combine(root,RelativePath))));
        private static readonly HashSet<string> Fields = new(StringComparer.Ordinal) {
            "Key","Preset","Shape","RenderMode","BudgetPool","Priority","X","Y","OffsetX","OffsetY","Angle",
            "Radius","Length","HalfWidth","Energy","BaseEnergy","Color","Color2","Animation","Amplitude","Rate","Phase","SweepAngle",
            "AttachTo","Anchor","FollowRotation","FollowScale","FollowVisibility","FrameCurve","StatePath","Enabled"
        };
        internal SceneLightDefinition Resolve(JObject input, int id)
        {
            if (input == null || input.Properties().Any(p=>!Fields.Contains(p.Name))) throw new InvalidDataException("Unknown scene light field");
            string key = Text(input,"Key",null,128);
            if (string.IsNullOrWhiteSpace(key)) throw new InvalidDataException("Missing scene light Key");
            string preset = Text(input,"Preset","lamp",64);
            if (_presets[preset] is not JObject defaults) throw new InvalidDataException("Unknown scene light preset: "+preset);
            var data = (JObject)defaults.DeepClone();
            foreach (var p in input.Properties()) data[p.Name]=p.Value.DeepClone();
            if (data.Properties().Any(p=>!Fields.Contains(p.Name))) throw new InvalidDataException("Unknown preset field");
            string shape=Text(data,"Shape","point",16), mode=Text(data,"RenderMode","cached",16), pool=Text(data,"BudgetPool","scene",16);
            int kind=shape switch {"point"=>0,"cone"=>1,"beam"=>2,_=>throw new InvalidDataException("Invalid scene light shape")};
            if (mode!="cached" && mode!="realtime" && mode!="hybrid" && mode!="visualOnly") throw new InvalidDataException("Invalid light RenderMode");
            if (pool!="scene" && pool!="shared") throw new InvalidDataException("Invalid light BudgetPool");
            string animation=Text(data,"Animation","constant",16);
            if (animation!="constant" && animation!="flicker" && animation!="pulse" && animation!="sweep") throw new InvalidDataException("Invalid light animation");
            float energy=(float)Number(data,"Energy",.8,0,2), amplitude=(float)Number(data,"Amplitude",0,0,.8);
            float baseEnergy=(float)Number(data,"BaseEnergy",0,0,2);
            int color=Color(data["Color"]??"#FFE0AD"), color2=Color(data["Color2"]??data["Color"]??"#FFE0AD");
            if (mode=="cached" && (animation!="constant" || color!=color2)) throw new InvalidDataException("Animated lights require realtime or hybrid mode");
            if (mode=="hybrid" && (baseEnergy>energy*(1-amplitude)+.00001f || color!=color2 || animation=="sweep"))
                throw new InvalidDataException("Hybrid base must stay below the animated minimum and keep its color/shape");
            int priority=(int)Number(data,"Priority",45,0,100);
            if (priority!=Number(data,"Priority",45,0,100)) throw new InvalidDataException("Fractional light priority");
            return new SceneLightDefinition(id,key,kind,mode,pool=="scene",priority,
                (float)Number(data,kind==0?"Radius":"Length",180,1,1024), (float)Number(data,"HalfWidth",100,.5,512),
                energy,baseEnergy,color,color2,animation,amplitude,(float)Number(data,"Rate",1,0,30),
                (float)Number(data,"Phase",0,-36000,36000), (float)Number(data,"SweepAngle",0,0,180),
                (float)Number(data,"X",0,-1000000,1000000),(float)Number(data,"Y",0,-1000000,1000000),
                (float)Number(data,"Angle",0,-36000,36000),Bool(data,"Enabled",true));
        }
        private static string Text(JObject o,string key,string fallback,int max)
        { var t=o[key];if(t==null)return fallback;if(t.Type!=JTokenType.String || t.Value<string>().Length>max)throw new InvalidDataException("Invalid "+key);return t.Value<string>(); }
        internal static double Number(JObject o,string key,double fallback,double min,double max)
        {
            var t=o[key];if(t==null)return fallback;
            if(t.Type!=JTokenType.Integer && t.Type!=JTokenType.Float)throw new InvalidDataException("Invalid numeric "+key);
            double n=t.Value<double>();if(!double.IsFinite(n)||n<min||n>max)throw new InvalidDataException("Out of range "+key);return n;
        }
        internal static bool Bool(JObject o,string key,bool fallback)
        {var t=o[key];if(t==null)return fallback;if(t.Type!=JTokenType.Boolean)throw new InvalidDataException("Invalid boolean "+key);return t.Value<bool>();}
        internal static int Color(JToken t)
        {
            if(t.Type==JTokenType.Integer){int n=t.Value<int>();if(n>=0 && n<=0xffffff)return n;}
            if(t.Type==JTokenType.String){string s=t.Value<string>();if(s.StartsWith("#"))s=s[1..];else if(s.StartsWith("0x",StringComparison.OrdinalIgnoreCase))s=s[2..];
                if(s.Length==6 && int.TryParse(s,NumberStyles.HexNumber,CultureInfo.InvariantCulture,out int n))return n;}
            throw new InvalidDataException("Invalid light color");
        }
    }
    internal sealed record SceneLightDefinition(int Id,string Key,int Kind,string Mode,bool Reserved,int Priority,
        float Extent,float HalfWidth,float Energy,float BaseEnergy,int Color,int Color2,string Animation,float Amplitude,float Rate,
        float Phase,float SweepAngle,float X,float Y,float Angle,bool Enabled);
}
