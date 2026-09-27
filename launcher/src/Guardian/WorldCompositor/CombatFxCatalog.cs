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
            bool boundSwf=false;
            var sourceNames=new HashSet<string>(StringComparer.Ordinal);
            foreach (JsonElement source in data.GetProperty("sources").EnumerateArray())
            {
                string path=source.GetProperty("path").GetString();
                string hash=source.GetProperty("sha256").GetString();
                if (path==null || path.Contains("..",StringComparison.Ordinal) || !sourceNames.Add(path)
                    || hash==null || hash.Length!=64 || !IsHex(hash))
                    throw new InvalidDataException("Invalid effect source identity");
                if (path==BulletVisualCatalog.SourceSwf)
                {
                    if (!HashMatches(File.ReadAllBytes(Path.Combine(root,path)),hash))
                        throw new InvalidDataException("Effect source SWF differs from catalog");
                    boundSwf=true;
                }
                else if (!path.StartsWith("flashswf/arts/原版素材库-子弹/LIBRARY/",StringComparison.Ordinal))
                    throw new InvalidDataException("Unsupported effect source");
            }
            if (!boundSwf || sourceNames.Count>256) throw new InvalidDataException("Incomplete effect source closure");
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
                    || linkage.Length>128 || !names.Add(linkage) || (kind!="casing" && kind!="muzzle" && kind!="impact"))
                    throw new InvalidDataException("Invalid effect style identity");
                JsonElement rawFrames=s.GetProperty("frames");
                if (rawFrames.GetArrayLength()<1 || rawFrames.GetArrayLength()>120)
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
                styles[index]=new CombatFxStyle(index,linkage,kind,s.GetProperty("worldLit").GetBoolean(),
                    s.GetProperty("skipOriginYZero").GetBoolean(),frames,variants);
                index++;
            }
            using var decoded=SKBitmap.Decode(png) ?? throw new InvalidDataException("Invalid atlas PNG");
            if (decoded.Width!=width || decoded.Height!=height) throw new InvalidDataException("Atlas metadata size mismatch");
            using var bitmap=new SKBitmap(new SKImageInfo(width,height,SKColorType.Bgra8888,SKAlphaType.Premul));
            using (var canvas=new SKCanvas(bitmap)) { canvas.Clear(SKColors.Transparent); canvas.DrawBitmap(decoded,0,0); canvas.Flush(); }
            byte[] pixels=new byte[checked(width*height*4)];
            Marshal.Copy(bitmap.GetPixels(),pixels,0,pixels.Length);
            var result=new CombatFxCatalog(Convert.ToHexString(SHA256.HashData(bytes)),styles,width,height,ppu,pixels);
            result.LoadLights(root);return result;
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
        internal readonly bool IsCasing, IsMuzzle, IsImpact, WorldLit, SkipOriginYZero;
        internal CombatFxLightProfile Light;
        internal readonly CombatFxImage[] Frames;
        internal readonly int[][] Variants;
        internal CombatFxStyle(int index,string linkage,string kind,bool worldLit,bool skipZero,CombatFxImage[] frames,int[][] variants)
        { Index=index;Linkage=linkage;IsCasing=kind=="casing";IsMuzzle=kind=="muzzle";IsImpact=kind=="impact";
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
