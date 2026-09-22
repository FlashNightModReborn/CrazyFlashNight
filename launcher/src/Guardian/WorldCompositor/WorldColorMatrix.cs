using System;
using System.IO;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian.WorldCompositor
{
    // Preserve ColorEngine.composeColorMatrix multiplication order, including its hue coefficients.
    // Preset format is intentionally small; future curves/LUT algorithms require a new version.
    internal sealed class WorldColorMatrix
    {
        internal float Gamma { get; private set; } = 1;
        internal static WorldColorMatrix Load(string path)
        {
            var result = new WorldColorMatrix();
            var json = JObject.Parse(File.ReadAllText(path));
            if (json.Value<int?>("version") != 1 || json.Value<string>("algorithm") != "legacy-matrix-v1")
                throw new InvalidDataException("Unsupported world lighting preset");
            double gamma = json.Value<double?>("gamma") ?? 1;
            if (!double.IsFinite(gamma) || gamma < 0.25 || gamma > 4) throw new InvalidDataException("Invalid gamma");
            result.Gamma = (float)gamma;
            return result;
        }
        internal static double[] Identity() => new double[] {1,0,0,0,0, 0,1,0,0,0, 0,0,1,0,0, 0,0,0,1,0};
        internal static double[] Compose(double[] basis, double[] overlay)
        {
            var result = new double[20];
            for (int i=0; i<4; i++) {
                int index=i*5;
                for (int j=0; j<4; j++)
                    for (int k=0; k<4; k++) result[index+j] += basis[index+k]*overlay[k*5+j];
                result[index+4]=basis[index+4];
                for (int k=0; k<4; k++) result[index+4] += basis[index+k]*overlay[k*5+4];
            }
            return result;
        }
        internal static double[] Generate(double[] p)
        {
            if (p == null || p.Length != 8) throw new ArgumentException("Eight legacy parameters required");
            var m=Identity(); m[0]=p[0]; m[6]=p[1]; m[12]=p[2]; m[18]=p[3];
            var brightness=Identity(); brightness[4]=brightness[9]=brightness[14]=p[4]; m=Compose(m,brightness);
            var contrast=Identity(); double scale=1+p[5]*0.01;
            contrast[0]=contrast[6]=contrast[12]=scale;
            contrast[4]=contrast[9]=contrast[14]=128*(1-scale); m=Compose(m,contrast);
            double saturation=1+p[6]*0.01, inverse=1-saturation;
            double r=inverse*0.2126, g=inverse*0.7152, b=inverse*0.0722;
            m=Compose(m,new double[]{r+saturation,g,b,0,0, r,g+saturation,b,0,0, r,g,b+saturation,0,0, 0,0,0,1,0});
            double angle=p[7]*Math.PI/180, c=Math.Cos(angle), s=Math.Sin(angle), v=1-c;
            return Compose(m,new double[]{c+v*.213,v*.715-s*.715,v*.072+s*.928,0,0,
                v*.213+s*.143,c+v*.715,v*.072-s*.283,0,0,
                v*.213-s*.787,v*.715+s*.715,c+v*.072,0,0, 0,0,0,1,0});
        }
        internal float[] ShaderSettings(double[] matrix)
        {
            var settings = new float[16];
            for (int row=0;row<3;row++) {
                for (int column=0;column<4;column++) settings[row*4+column]=(float)matrix[row*5+column];
                settings[12+row]=(float)(matrix[row*5+4]/255.0);
            }
            settings[15]=Gamma;
            return settings;
        }
    }
}
