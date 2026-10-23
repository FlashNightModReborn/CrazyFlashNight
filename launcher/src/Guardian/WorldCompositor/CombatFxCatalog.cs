using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;
using SkiaSharp;

namespace CF7Launcher.Guardian.WorldCompositor
{
    // One generated whitelist shared with AS2 through capability negotiation.
    internal sealed class CombatFxCatalog
    {
        internal const string RelativePath = "data/combat_visuals/effects.v1.json";
        internal const string AtlasPath = "data/combat_visuals/effects-atlas.png";
        internal const string LightsPath = "data/combat_visuals/local_lights.v1.json";
        internal string Sha256 { get; }
        internal string LightingSha256 { get; private set; }
        internal float MaximumLightResponse { get; private set; }
        internal CombatFxStyle[] Styles { get; }
        internal int Width { get; }
        internal int Height { get; }
        internal float PixelsPerUnit { get; }
        internal byte[] PremultipliedBgra { get; }

        private CombatFxCatalog(string sha, CombatFxStyle[] styles, int width, int height,
            float pixelsPerUnit, byte[] pixels)
        { Sha256=sha; Styles=styles; Width=width; Height=height; PixelsPerUnit=pixelsPerUnit; PremultipliedBgra=pixels; }

        internal static CombatFxCatalog Load(string root)
        {
            byte[] bytes=File.ReadAllBytes(Path.Combine(root,RelativePath));
            if (bytes.Length>2*1024*1024) throw new InvalidDataException("Effect catalog exceeds budget");
            using var doc=JsonDocument.Parse(bytes,new JsonDocumentOptions { MaxDepth=16 });
            JsonElement data=doc.RootElement;
            if (data.GetProperty("schema").GetString()!="cf7-combat-fx.v1"
                || data.GetProperty("ticksPerSecond").GetInt32()!=30)
                throw new InvalidDataException("Unsupported combat effect catalog");
            float ppu=Number(data.GetProperty("pixelsPerUnit"),1,8);
            JsonElement atlas=data.GetProperty("atlas");
            if (atlas.GetProperty("path").GetString()!=AtlasPath)
                throw new InvalidDataException("Invalid atlas path");
            int width=atlas.GetProperty("width").GetInt32(),height=atlas.GetProperty("height").GetInt32();
            if (width<1 || height<1 || width>4096 || height>4096)
                throw new InvalidDataException("Invalid atlas dimensions");
            byte[] png=File.ReadAllBytes(Path.Combine(root,AtlasPath));
            if (png.Length>4*1024*1024 || !HashMatches(png,atlas.GetProperty("sha256").GetString()))
                throw new InvalidDataException("Effect atlas integrity mismatch");
            var libraries=new Dictionary<string,(string Swf,string Library)>(StringComparer.Ordinal) {
                ["stock"]=(BulletVisualCatalog.SourceSwf,"flashswf/arts/原版素材库-子弹/LIBRARY"),
                ["mist"]=("flashswf/arts/new/雾人整合特效.swf","flashswf/arts/new/雾人整合特效/LIBRARY"),
                ["fs"]=("flashswf/arts/new/fs配置素材.swf","flashswf/arts/new/fs配置素材/LIBRARY") };
            var declared=new HashSet<string>(StringComparer.Ordinal) {"stock"};
            if(data.TryGetProperty("sourceLibraries",out JsonElement libraryList))
            {
                declared.Clear();
                if(libraryList.GetArrayLength()<1 || libraryList.GetArrayLength()>3)throw new InvalidDataException("Invalid source libraries");
                foreach(JsonElement entry in libraryList.EnumerateArray())
                {
                    string key=entry.GetProperty("key").GetString();
                    if(key==null || !libraries.TryGetValue(key,out var source) || !declared.Add(key)
                        || entry.GetProperty("swf").GetString()!=source.Swf
                        || entry.GetProperty("libraryRoot").GetString()!=source.Library)
                        throw new InvalidDataException("Unsupported source library");
                }
            }
            var bound=new HashSet<string>(StringComparer.Ordinal);
            var sourceNames=new HashSet<string>(StringComparer.Ordinal);
            foreach (JsonElement source in data.GetProperty("sources").EnumerateArray())
            {
                string path=source.GetProperty("path").GetString();
                string hash=source.GetProperty("sha256").GetString();
                if (path==null || path.Contains("..",StringComparison.Ordinal) || !sourceNames.Add(path)
                    || hash==null || hash.Length!=64 || !IsHex(hash))
                    throw new InvalidDataException("Invalid effect source identity");
                bool supported=false;
                foreach(string key in declared)
                {
                    var library=libraries[key];
                    if(path==library.Swf)
                    {
                        if(!HashMatches(File.ReadAllBytes(Path.Combine(root,path)),hash))
                            throw new InvalidDataException("Effect source SWF differs from catalog");
                        bound.Add(key);supported=true;break;
                    }
                    if(path.StartsWith(library.Library+"/",StringComparison.Ordinal)
                        || path==library.Library.Substring(0,library.Library.Length-"LIBRARY".Length)+"DOMDocument.xml")supported=true;
                }
                if(!supported)throw new InvalidDataException("Unsupported effect source");
            }
            if(!bound.SetEquals(declared) || sourceNames.Count>256)throw new InvalidDataException("Incomplete effect source closure");
            JsonElement rawStyles=data.GetProperty("styles");
            if (rawStyles.GetArrayLength()<1 || rawStyles.GetArrayLength()>64)
                throw new InvalidDataException("Invalid effect style count");
            var styles=new CombatFxStyle[rawStyles.GetArrayLength()];
            var names=new HashSet<string>(StringComparer.Ordinal);
            int index=0;
            foreach (JsonElement s in rawStyles.EnumerateArray())
            {
                string linkage=s.GetProperty("linkage").GetString(),kind=s.GetProperty("kind").GetString();
                if (s.GetProperty("index").GetInt32()!=index || string.IsNullOrEmpty(linkage)
                    || linkage.Length>128 || !names.Add(linkage) || (kind!="casing" && kind!="muzzle" && kind!="impact" && kind!="blood"))
                    throw new InvalidDataException("Invalid effect style identity");
                JsonElement rawFrames=s.GetProperty("frames");
                if (rawFrames.GetArrayLength()<1 || rawFrames.GetArrayLength()>256)
                    throw new InvalidDataException("Invalid animation frame count");
                var frames=new CombatFxImage[rawFrames.GetArrayLength()];
                int frameIndex=0;
                foreach (JsonElement f in rawFrames.EnumerateArray())
                {
                    JsonElement r=f.GetProperty("rect"),o=f.GetProperty("offset");
                    if (r.GetArrayLength()!=4 || o.GetArrayLength()!=2) throw new InvalidDataException("Invalid effect frame");
                    int x=r[0].GetInt32(),y=r[1].GetInt32(),w=r[2].GetInt32(),h=r[3].GetInt32();
                    if (x<0 || y<0 || w<1 || h<1 || w>width || h>height || x>width-w || y>height-h)
                        throw new InvalidDataException("Effect frame leaves atlas");
                    frames[frameIndex++]=new CombatFxImage(x/(float)width,y/(float)height,
                        (x+w)/(float)width,(y+h)/(float)height,Number(o[0],-10000,10000),
                        Number(o[1],-10000,10000),w/ppu,h/ppu);
                }
                JsonElement rawVariants=s.GetProperty("variants");
                if (rawVariants.GetArrayLength()<1 || rawVariants.GetArrayLength()>8)
                    throw new InvalidDataException("Invalid effect variants");
                var variants=new int[rawVariants.GetArrayLength()][];
                int vi=0;
                foreach (JsonElement v in rawVariants.EnumerateArray())
                {
                    if (v.GetArrayLength()<1 || v.GetArrayLength()>60) throw new InvalidDataException("Invalid variant duration");
                    var indices=new int[v.GetArrayLength()];
                    for (int i=0;i<indices.Length;i++)
                    {
                        indices[i]=v[i].GetInt32();
                        if (indices[i]<0 || indices[i]>=frames.Length) throw new InvalidDataException("Invalid variant frame");
                    }
                    variants[vi++]=indices;
                }
                if (kind=="casing" && (frames.Length!=1 || variants.Length!=1 || variants[0].Length!=1))
                    throw new InvalidDataException("A casing must be a static stamp");
                if(kind=="blood" && (variants.Length!=5 || Array.Exists(variants,v=>v.Length!=1)))
                    throw new InvalidDataException("Blood requires five static authored variants");
                styles[index]=new CombatFxStyle(index,linkage,kind,s.GetProperty("worldLit").GetBoolean(),
                    s.GetProperty("skipOriginYZero").GetBoolean(),frames,variants);
                if(s.TryGetProperty("sourceKey",out JsonElement sourceKey) && !declared.Contains(sourceKey.GetString()??""))
                    throw new InvalidDataException("Unknown style source");
                if(s.TryGetProperty("variantSounds",out JsonElement sounds))
                {
                    if(sounds.GetArrayLength()!=0 && sounds.GetArrayLength()!=variants.Length)
                        throw new InvalidDataException("Sound variants differ from animation");
                    var values=new string[sounds.GetArrayLength()];
                    for(int i=0;i<values.Length;i++)
                    {
                        string value=sounds[i].GetString();
                        if(string.IsNullOrEmpty(value)||value.Length>128||value.Contains("..",StringComparison.Ordinal)
                            ||value.IndexOfAny(new[]{'/','\\',':'})>=0)throw new InvalidDataException("Invalid authored sound");
                        values[i]=value;
                    }
                    styles[index].VariantSounds=values;
                }
                if(s.TryGetProperty("soundAtBirth",out JsonElement soundAtBirth))
                    styles[index].SoundAtBirth=soundAtBirth.GetBoolean();
                if(styles[index].SoundAtBirth && (!styles[index].IsImpact || styles[index].VariantSounds.Length!=variants.Length))
                    throw new InvalidDataException("Birth sound requires one cue per impact variant");
                if(s.TryGetProperty("randomRotation",out JsonElement randomRotation))styles[index].RandomRotation=randomRotation.GetBoolean();
                if(s.TryGetProperty("nestedTransform",out JsonElement transform))
                {
                    if(transform.GetArrayLength()!=6)throw new InvalidDataException("Invalid nested transform");
                    var matrix=new float[6];
                    for(int i=0;i<6;i++)matrix[i]=Number(transform[i],-100,100);
                    if(matrix[0]!=1||matrix[1]!=0||matrix[2]!=0||matrix[3]!=1)
                        throw new InvalidDataException("Nested scale must be baked in the authored texture");
                    styles[index].NestedTransform=matrix;
                }
                index++;
            }
            VerifySoundAssets(root,data,styles,declared);
            using var decoded=SKBitmap.Decode(png) ?? throw new InvalidDataException("Invalid atlas PNG");
            if (decoded.Width!=width || decoded.Height!=height) throw new InvalidDataException("Atlas metadata size mismatch");
            using var bitmap=new SKBitmap(new SKImageInfo(width,height,SKColorType.Bgra8888,SKAlphaType.Premul));
            using (var canvas=new SKCanvas(bitmap)) { canvas.Clear(SKColors.Transparent); canvas.DrawBitmap(decoded,0,0); canvas.Flush(); }
            byte[] pixels=new byte[checked(width*height*4)];
            Marshal.Copy(bitmap.GetPixels(),pixels,0,pixels.Length);
            var result=new CombatFxCatalog(Convert.ToHexString(SHA256.HashData(bytes)),styles,width,height,ppu,pixels);
            result.LoadLights(root);return result;
        }

        // Derived timeline sounds live in the existing SFX pack. They retain exact
        // source-SWF identity and never rely on guessing a Flash library item's name.
        private static void VerifySoundAssets(string root,JsonElement data,CombatFxStyle[] styles,HashSet<string> libraries)
        {
            var assets=new Dictionary<string,string>(StringComparer.Ordinal);
            long totalBytes=0;
            if(data.TryGetProperty("soundAssets",out JsonElement list))
            {
                if(list.ValueKind!=JsonValueKind.Array || list.GetArrayLength()>64)
                    throw new InvalidDataException("Invalid derived sound count");
                foreach(JsonElement asset in list.EnumerateArray())
                {
                    string id=asset.GetProperty("id").GetString(),path=asset.GetProperty("path").GetString();
                    string key=asset.GetProperty("sourceKey").GetString();
                    int sourceId=asset.GetProperty("sourceSoundId").GetInt32();
                    long length=asset.GetProperty("bytes").GetInt64();
                    string extension=Path.GetExtension(id??"");
                    if(key==null || !libraries.Contains(key) || sourceId<1 || sourceId>65535
                        || (extension!=".mp3" && extension!=".wav")
                        || id!="cfnfx-"+key+"-"+sourceId.ToString(CultureInfo.InvariantCulture)+extension
                        || path!="sounds/export/特效/"+id || !assets.TryAdd(id,path)
                        || length<1 || length>256*1024 || (totalBytes+=length)>2*1024*1024)
                        throw new InvalidDataException("Invalid derived sound identity or budget");
                    string fullPath=Path.Combine(root,path);
                    if(new FileInfo(fullPath).Length!=length
                        || !HashMatches(File.ReadAllBytes(fullPath),asset.GetProperty("sha256").GetString()))
                        throw new InvalidDataException("Derived effect sound integrity mismatch");
                }
            }
            // Match AudioCoordinator's exact basename keys and override order.
            var available=new Dictionary<string,string>(StringComparer.Ordinal);
            foreach(string pack in new[]{"武器","特效","人物"})
            {
                string directory=Path.Combine(root,"sounds","export",pack);
                if(Directory.Exists(directory))
                    foreach(string file in Directory.GetFiles(directory))available[Path.GetFileName(file)]=file;
            }
            var used=new HashSet<string>(StringComparer.Ordinal);
            foreach(CombatFxStyle style in styles)
            {
                if(!style.SoundAtBirth)continue;
                foreach(string id in style.VariantSounds)
                {
                    if(!available.TryGetValue(id,out string file))
                        throw new InvalidDataException("Effect sound is not registered by its exact SFX filename: "+id);
                    if(id.StartsWith("cfnfx-",StringComparison.Ordinal))
                    {
                        if(!assets.TryGetValue(id,out string path)
                            || !string.Equals(Path.GetFullPath(file),Path.GetFullPath(Path.Combine(root,path)),StringComparison.OrdinalIgnoreCase))
                            throw new InvalidDataException("Derived effect sound missing or overridden");
                        used.Add(id);
                    }
                }
            }
            if(used.Count!=assets.Count)throw new InvalidDataException("Unreferenced derived effect sound");
        }

        private void LoadLights(string root)
        {
            byte[] bytes=File.ReadAllBytes(Path.Combine(root,LightsPath));
            if(bytes.Length>32768)throw new InvalidDataException("Local light presets exceed budget");
            using var doc=JsonDocument.Parse(bytes,new JsonDocumentOptions {MaxDepth=8});
            JsonElement data=doc.RootElement;
            if(data.GetProperty("schema").GetString()!="cf7-combat-local-lights.v1")
                throw new InvalidDataException("Unsupported local light presets");
            MaximumLightResponse=Number(data.GetProperty("maximumResponse"),0,.8f);
            var names=new HashSet<string>(StringComparer.Ordinal);
            foreach(JsonProperty p in data.GetProperty("muzzles").EnumerateObject())
            {
                CombatFxStyle style=Array.Find(Styles,s=>s.Linkage==p.Name && s.IsMuzzle);
                if(style==null || !names.Add(p.Name))throw new InvalidDataException("Unknown or duplicate light source");
                JsonElement value=p.Value;string color=value.GetProperty("color").GetString();
                if(color==null || color.Length!=7 || color[0]!='#'
                    || !uint.TryParse(color.AsSpan(1),NumberStyles.HexNumber,CultureInfo.InvariantCulture,out uint rgb))
                    throw new InvalidDataException("Invalid light color");
                int ticks=value.GetProperty("ticks").GetInt32();
                if(ticks<1 || ticks>6)throw new InvalidDataException("Invalid local light duration");
                style.Light=new CombatFxLightProfile(Number(value.GetProperty("radius"),16,256),
                    Number(value.GetProperty("energy"),0,2),ticks,
                    ((rgb>>16)&255)/255f,((rgb>>8)&255)/255f,(rgb&255)/255f);
            }
            foreach(CombatFxStyle style in Styles)
                if(style.IsMuzzle && !names.Contains(style.Linkage))throw new InvalidDataException("Missing muzzle light preset");
            LightingSha256=Convert.ToHexString(SHA256.HashData(bytes));
        }

        private static bool IsHex(string s) { foreach(char c in s) if(!Uri.IsHexDigit(c)) return false; return true; }
        private static bool HashMatches(byte[] data,string expected) => expected!=null && expected.Length==64
            && string.Equals(Convert.ToHexString(SHA256.HashData(data)),expected,StringComparison.OrdinalIgnoreCase);
        private static float Number(JsonElement e,float min,float max)
        { float v=e.GetSingle();if(!float.IsFinite(v)||v<min||v>max)throw new InvalidDataException("Invalid effect number");return v; }
    }

    internal sealed class CombatFxStyle
    {
        internal readonly int Index;
        internal readonly string Linkage;
        internal readonly bool IsCasing, IsMuzzle, IsImpact, IsBlood, WorldLit, SkipOriginYZero;
        internal bool RandomRotation,SoundAtBirth;
        internal float[] NestedTransform = {1,0,0,1,0,0};
        internal string[] VariantSounds=Array.Empty<string>();
        internal CombatFxLightProfile Light;
        internal readonly CombatFxImage[] Frames;
        internal readonly int[][] Variants;
        internal CombatFxStyle(int index,string linkage,string kind,bool worldLit,bool skipZero,CombatFxImage[] frames,int[][] variants)
        { Index=index;Linkage=linkage;IsCasing=kind=="casing";IsMuzzle=kind=="muzzle";IsImpact=kind=="impact";IsBlood=kind=="blood";
            WorldLit=worldLit;SkipOriginYZero=skipZero;Frames=frames;Variants=variants; }
    }

    internal sealed class CombatFxLightProfile
    {
        internal readonly float Radius,Energy,R,G,B;
        internal readonly int Ticks;
        internal CombatFxLightProfile(float radius,float energy,int ticks,float r,float g,float b)
        { Radius=radius;Energy=energy;Ticks=ticks;R=r;G=g;B=b; }
    }

    internal readonly struct CombatFxImage
    {
        internal readonly float U0,V0,U1,V1,OffsetX,OffsetY,Width,Height;
        internal CombatFxImage(float u0,float v0,float u1,float v1,float x,float y,float w,float h)
        { U0=u0;V0=v0;U1=u1;V1=v1;OffsetX=x;OffsetY=y;Width=w;Height=h; }
    }
}
