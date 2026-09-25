using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text.Json;

namespace CF7Launcher.Guardian.WorldCompositor
{
    // The authored visual tuning file lives outside the immutable native payload.
    // Its hash is logged at load time, so data-only changes have a separate identity.
    internal sealed class WorldPresentationCatalog
    {
        internal const string RelativePath="data/environment/presentation_presets.v1.json";
        private readonly Dictionary<string,AtmosphereLook> _atmosphere;
        private readonly WeatherLook[] _weather;
        internal string Sha256 { get; }
        private WorldPresentationCatalog(Dictionary<string,AtmosphereLook> atmosphere,WeatherLook[] weather,string sha)
        { _atmosphere=atmosphere; _weather=weather; Sha256=sha; }
        internal AtmosphereLook Atmosphere(string name) =>
            _atmosphere.TryGetValue(name,out var look) ? look
                : throw new InvalidDataException("Unknown atmosphere preset: "+name);
        internal WeatherLook Weather(int type) =>
            type>0 && type<_weather.Length && _weather[type]!=null ? _weather[type]
                : throw new InvalidDataException("Unknown weather look type: "+type);

        internal static WorldPresentationCatalog Load(string path)
        {
            byte[] bytes=File.ReadAllBytes(path);
            using var json=JsonDocument.Parse(bytes,new JsonDocumentOptions { MaxDepth=12 });
            JsonElement root=json.RootElement;
            Fields(root,"version","atmosphere","weather");
            if (root.GetProperty("version").ValueKind!=JsonValueKind.Number
                || !root.GetProperty("version").TryGetInt32(out int version) || version!=1)
                throw new InvalidDataException("Unsupported world presentation catalog version");
            var named=root.GetProperty("atmosphere");
            if (named.ValueKind!=JsonValueKind.Array || named.GetArrayLength()<1 || named.GetArrayLength()>64)
                throw new InvalidDataException("Invalid atmosphere catalog size");
            var atmosphere=new Dictionary<string,AtmosphereLook>(StringComparer.Ordinal);
            foreach (JsonElement item in named.EnumerateArray())
            {
                Fields(item,"name","family","primary","secondary","base","edge","motion",
                    "rate","frequency","focus","falloff","mix");
                string name=Name(item.GetProperty("name"));
                if (name is "none" or "custom" or "雨" or "雪" or "沙尘" || atmosphere.ContainsKey(name))
                    throw new InvalidDataException("Duplicate or reserved atmosphere name: "+name);
                int family=Family(Name(item.GetProperty("family")));
                float[] primary=Vector(item.GetProperty("primary"),3,0,1);
                float[] secondary=Vector(item.GetProperty("secondary"),3,0,1);
                float[] frequency=Vector(item.GetProperty("frequency"),2,0,16);
                float[] focus=Vector(item.GetProperty("focus"),2,0,1);
                float falloff=Number(item.GetProperty("falloff"),0.05,2);
                if (family==2 && focus[0]>=focus[1])
                    throw new InvalidDataException(name+": medical color stops reversed");
                if ((family==4 || family==5) && focus[1]>=falloff)
                    throw new InvalidDataException(name+": haze falloff reversed");
                var tuning=new float[] {
                    primary[0],primary[1],primary[2],Number(item.GetProperty("base"),0,0.5),
                    secondary[0],secondary[1],secondary[2],Number(item.GetProperty("edge"),0,0.5),
                    Number(item.GetProperty("motion"),0,0.5),Number(item.GetProperty("rate"),0,20),
                    frequency[0],frequency[1],focus[0],focus[1],
                    falloff,Number(item.GetProperty("mix"),0,0.5)
                };
                atmosphere.Add(name,new AtmosphereLook(name,family,tuning));
            }
            var weatherObject=root.GetProperty("weather");
            Fields(weatherObject,"rain","snow","dust","fog","slash");
            var weather=new WeatherLook[6];
            string[] names={"rain","snow","dust","fog","slash"};
            for(int type=1;type<=5;type++)
            {
                JsonElement item=weatherObject.GetProperty(names[type-1]);
                Fields(item,"count","primary","secondary","size","alpha","speed","wind",
                    "splashSize","splashAlpha","splashStart","edgeFade");
                int count=Count(item.GetProperty("count"));
                float[] primary=Vector(item.GetProperty("primary"),3,0,1);
                float[] secondary=Vector(item.GetProperty("secondary"),3,0,1);
                var tuning=new float[] {
                    primary[0],primary[1],primary[2],Number(item.GetProperty("size"),0.25,4),
                    secondary[0],secondary[1],secondary[2],Number(item.GetProperty("alpha"),0,2),
                    Number(item.GetProperty("speed"),0.1,4),Number(item.GetProperty("wind"),0,4),
                    Number(item.GetProperty("splashSize"),0.25,4),Number(item.GetProperty("splashAlpha"),0,2),
                    Number(item.GetProperty("splashStart"),0.5,0.95),Number(item.GetProperty("edgeFade"),0.1,4),0,0
                };
                weather[type]=new WeatherLook(type,count,tuning);
            }
            string sha=Convert.ToHexString(SHA256.HashData(bytes));
            return new WorldPresentationCatalog(atmosphere,weather,sha);
        }
        private static void Fields(JsonElement value,params string[] names)
        {
            if(value.ValueKind!=JsonValueKind.Object) throw new InvalidDataException("Expected preset object");
            var expected=new HashSet<string>(names,StringComparer.Ordinal);
            var seen=new HashSet<string>(StringComparer.Ordinal);
            foreach(var property in value.EnumerateObject())
                if(!expected.Contains(property.Name) || !seen.Add(property.Name))
                    throw new InvalidDataException("Unknown or duplicate preset field: "+property.Name);
            if(seen.Count!=expected.Count)
                throw new InvalidDataException("Missing preset fields: "+string.Join(",",expected.Except(seen)));
        }
        private static string Name(JsonElement value)
        {
            if(value.ValueKind!=JsonValueKind.String) throw new InvalidDataException("Preset name must be a string");
            string? name=value.GetString();
            if(string.IsNullOrWhiteSpace(name) || name.Length>48 || name.Any(char.IsControl))
                throw new InvalidDataException("Invalid preset name");
            return name;
        }
        private static int Family(string name) => name switch {
            "alert"=>1,"medical"=>2,"industrial"=>3,"toxic"=>4,"corrosion"=>5,
            "cold-iron"=>6,"ambush"=>7,"banquet"=>8,"blood-moon"=>9,"incense"=>10,
            _=>throw new InvalidDataException("Unknown atmosphere family: "+name)
        };
        private static float[] Vector(JsonElement value,int count,double min,double max)
        {
            if(value.ValueKind!=JsonValueKind.Array || value.GetArrayLength()!=count)
                throw new InvalidDataException("Invalid preset vector length");
            var result=new float[count];int i=0;
            foreach(JsonElement element in value.EnumerateArray()) result[i++]=Number(element,min,max);
            return result;
        }
        private static float Number(JsonElement value,double min,double max)
        {
            if(value.ValueKind!=JsonValueKind.Number || !value.TryGetDouble(out double n)
                || !double.IsFinite(n) || n<min || n>max)
                throw new InvalidDataException("Preset number outside bounds");
            return (float)n;
        }
        private static int Count(JsonElement value)
        {
            if(value.ValueKind!=JsonValueKind.Number || !value.TryGetInt32(out int count)
                || count<0 || count>512) throw new InvalidDataException("Invalid weather count");
            return count;
        }
    }
    internal sealed class AtmosphereLook
    {
        internal string Name { get; }
        internal int Family { get; }
        internal float[] Tuning { get; }
        internal AtmosphereLook(string name,int family,float[] tuning)
        { Name=name;Family=family;Tuning=tuning; }
    }
    internal sealed class WeatherLook
    {
        internal int Type { get; }
        internal int Count { get; }
        internal float[] Tuning { get; }
        internal WeatherLook(int type,int count,float[] tuning)
        { Type=type;Count=count;Tuning=tuning; }
    }
}
