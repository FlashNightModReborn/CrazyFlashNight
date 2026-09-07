using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Text;

namespace CF7Launcher.Data
{
    /// <summary>只读 SWF Import/ExportAssets，不编辑 SWF，也不把数字 CharacterId 当持久身份。</summary>
    public sealed class MapSwfLinkages
    {
        public readonly Dictionary<string, List<int>> Exports = new Dictionary<string, List<int>>(StringComparer.Ordinal);
        public readonly List<(string Url, string Name, int CharacterId)> Imports = new List<(string, string, int)>();
        public readonly Dictionary<int, int> SpriteFrames = new Dictionary<int, int>();
        public string Digest { get; private set; }
        public static MapSwfLinkages Read(string root, string relative)
        {
            byte[] encoded = MapProjectFiles.Read(root, relative, 64 * 1024 * 1024);
            MapRuleEvaluator.Need(encoded.Length >= 12 && encoded[1] == 'W' && encoded[2] == 'S', "来源不是受支持的 SWF。");
            uint length = BitConverter.ToUInt32(encoded, 4);
            MapRuleEvaluator.Need(length >= 12 && length <= 128 * 1024 * 1024, "SWF 解压尺寸超出边界。");
            byte[] body = new byte[checked((int)length - 8)];
            if (encoded[0] == 'F')
            {
                MapRuleEvaluator.Need(encoded.Length == length, "SWF 声明长度与字节不一致。");
                Buffer.BlockCopy(encoded, 8, body, 0, body.Length);
            }
            else
            {
                MapRuleEvaluator.Need(encoded[0] == 'C', "仅支持 FWS / CWS 来源；请通过原工具发布受支持的 SWF。");
                using var input = new MemoryStream(encoded, 8, encoded.Length - 8, false);
                using var stream = new ZLibStream(input, CompressionMode.Decompress);
                stream.ReadExactly(body); MapRuleEvaluator.Need(stream.ReadByte() == -1, "SWF 解压内容超过声明长度。");
            }
            var result = new MapSwfLinkages { Digest = MapDefinition.Hash(encoded) };
            int bits = body[0] >> 3, offset = (5 + bits * 4 + 7) / 8 + 4, tags = 0;
            while (offset < body.Length)
            {
                MapRuleEvaluator.Need(++tags < 100000 && offset + 2 <= body.Length, "SWF 标签目录不完整。");
                ushort header = BitConverter.ToUInt16(body, offset); offset += 2;
                int type = header >> 6; uint size = (uint)(header & 63);
                if (size == 63) { MapRuleEvaluator.Need(offset + 4 <= body.Length, "SWF 长标签不完整。"); size = BitConverter.ToUInt32(body, offset); offset += 4; }
                MapRuleEvaluator.Need(size <= body.Length - offset, "SWF 标签长度越界。");
                int end = offset + (int)size;
                if (type == 39)
                {
                    MapRuleEvaluator.Need(size >= 4, "SWF 元件头不完整。");
                    int id = BitConverter.ToUInt16(body, offset), frames = BitConverter.ToUInt16(body, offset + 2);
                    MapRuleEvaluator.Need(!result.SpriteFrames.ContainsKey(id), "SWF 元件标识重复。"); result.SpriteFrames[id] = frames;
                }
                if (type == 56 || type == 57 || type == 71)
                {
                    int position = offset; string url = "";
                    if (type != 56) { url = ReadString(body, ref position, end); if (type == 71) position += 2; }
                    MapRuleEvaluator.Need(position + 2 <= end, "SWF 链接表不完整。");
                    int count = BitConverter.ToUInt16(body, position); position += 2;
                    for (int i = 0; i < count; i++)
                    {
                        MapRuleEvaluator.Need(position + 2 <= end, "SWF 链接条目不完整。");
                        int id = BitConverter.ToUInt16(body, position); position += 2;
                        string name = ReadString(body, ref position, end);
                        if (type == 56)
                        {
                            if (!result.Exports.TryGetValue(name, out var ids)) { ids = new List<int>(); result.Exports[name] = ids; }
                            ids.Add(id);
                        }
                        else result.Imports.Add((url, name, id));
                    }
                    MapRuleEvaluator.Need(position == end, "SWF 链接表含未解释内容。");
                }
                offset = end;
                if (type == 0) break;
            }
            return result;
        }
        private static string ReadString(byte[] bytes, ref int position, int end)
        {
            int start = position;
            while (position < end && bytes[position] != 0) position++;
            MapRuleEvaluator.Need(position < end && position - start <= 4096, "SWF 链接字符串不完整或过长。");
            string value = new UTF8Encoding(false, true).GetString(bytes, start, position - start); position++; return value;
        }
    }
}
