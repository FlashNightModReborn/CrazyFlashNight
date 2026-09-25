using System;
using System.IO;
using System.Security.Cryptography;

namespace CF7Launcher.Guardian.WorldCompositor
{
    // CF7LUTSET v1 读取器（格式权威注释见 tools/lut-lab/lib/lutset.js 头注）：
    // 48 字节头（magic "CF7L" / u32le version=1 / u32le size=32 / u32le levels=10 /
    // 数据段 SHA-256）+ levels × 32^3 × 4 RGBA8（R 最快，alpha 恒 255）。
    // 任何不符（缺文件/长度/魔数/版本/尺寸/档数/哈希）都抛 InvalidDataException，
    // 由 WorldLightingPreset 捕获并回退 legacy 矩阵——绝不允许带坏数据进入渲染链。
    internal sealed class WorldLutSet
    {
        internal const int LutSize = 32;
        internal const int LevelCount = 10;
        internal const int LevelBytes = LutSize * LutSize * LutSize * 4;
        internal const int HeaderBytes = 48;
        internal const int TotalBytes = HeaderBytes + LevelCount * LevelBytes;

        private readonly byte[] _data; // LevelCount × LevelBytes，节点序 R 最快

        private WorldLutSet(byte[] data, string sha256) { _data = data; DataSha256 = sha256; }

        internal string DataSha256 { get; private set; }

        internal static WorldLutSet Load(string path) => Parse(File.ReadAllBytes(path), path);

        internal static WorldLutSet Parse(byte[] fileBytes, string sourceName)
        {
            if (fileBytes == null || fileBytes.Length != TotalBytes)
                throw new InvalidDataException($"lutset 长度不符（{sourceName}）：期望 {TotalBytes} 字节");
            if (fileBytes[0] != 'C' || fileBytes[1] != 'F' || fileBytes[2] != '7' || fileBytes[3] != 'L')
                throw new InvalidDataException($"lutset 魔数不符（{sourceName}）");
            int version = BitConverter.ToInt32(fileBytes, 4);
            int size = BitConverter.ToInt32(fileBytes, 8);
            int levels = BitConverter.ToInt32(fileBytes, 12);
            if (version != 1 || size != LutSize || levels != LevelCount)
                throw new InvalidDataException($"lutset 头字段不支持（{sourceName}）：version={version} size={size} levels={levels}");
            var data = new byte[LevelCount * LevelBytes];
            Buffer.BlockCopy(fileBytes, HeaderBytes, data, 0, data.Length);
            byte[] actual;
            using (var sha = SHA256.Create()) actual = sha.ComputeHash(data);
            for (int i = 0; i < 32; i++)
                if (actual[i] != fileBytes[16 + i])
                    throw new InvalidDataException($"lutset 数据段 SHA-256 校验不符（{sourceName}）");
            return new WorldLutSet(data, Convert.ToHexString(actual).ToLowerInvariant());
        }

        // 生产语义：连续 light 取相邻整数档逐字节线性混合；light>9 钳到 9（集合模型 0–9，
        // 9 以上钉 L9，不做 XML 路径的 8/9 外推），light<0 钳到 0，非有限值回 7（白天恒等档）。
        internal static double ClampLight(double light)
        {
            if (!double.IsFinite(light)) return 7;
            return light < 0 ? 0 : light > 9 ? 9 : light;
        }

        internal byte[] Level(int level)
        {
            if (level < 0 || level >= LevelCount) throw new ArgumentOutOfRangeException(nameof(level));
            var result = new byte[LevelBytes];
            Buffer.BlockCopy(_data, level * LevelBytes, result, 0, LevelBytes);
            return result;
        }

        internal byte[] BlendLevel(double light)
        {
            double clamped = ClampLight(light);
            int first = (int)Math.Floor(clamped);
            int last = Math.Min(LevelCount - 1, first + 1);
            double ratio = clamped - first;
            if (first == last || ratio <= 0) return Level(first);
            int a0 = first * LevelBytes, b0 = last * LevelBytes;
            var result = new byte[LevelBytes];
            for (int i = 0; i < LevelBytes; i++)
                result[i] = (byte)Math.Floor(_data[a0 + i] + (_data[b0 + i] - _data[a0 + i]) * ratio + 0.5);
            return result;
        }
    }
}
