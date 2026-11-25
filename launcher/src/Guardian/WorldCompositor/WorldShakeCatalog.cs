using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text.Json;

namespace CF7Launcher.Guardian.WorldCompositor
{
    internal sealed class WorldShakeProfile
    {
        internal int Id { get; }
        internal string Name { get; }
        internal int Priority { get; }
        internal float Amplitude { get; }
        internal int Ticks { get; }
        internal float Frequency { get; }
        internal float Radius { get; }
        internal bool IsScreenWide => Radius == 0f;

        internal WorldShakeProfile(int id, string name, int priority, float amplitude, int ticks, float frequency, float radius)
        {
            Id = id;
            Name = name;
            Priority = priority;
            Amplitude = amplitude;
            Ticks = ticks;
            Frequency = frequency;
            Radius = radius;
        }
    }

    // Authored screen-shake curves and producer bindings live outside immutable native binaries.
    // Its SHA-256 is logged at startup and shared with AS2 via combat_fx_caps.
    internal sealed class WorldShakeCatalog
    {
        internal const string RelativePath = "data/combat_visuals/screen_shake.v1.json";
        internal const int MaxBytes = 65536;
        internal const int MaxProfiles = 16;
        internal const int DefaultProfileCount = 7;
        internal const int MaxBindings = 256;
        internal const int DefaultTailTicks = 31;

        internal string Sha256 { get; }
        internal float MaxTotalOffsetStagePx { get; }
        internal WorldShakeProfile[] Profiles { get; }
        internal int MaxProfileId => Profiles.Length;
        internal int TailTicks { get; }
        internal int[] Priorities { get; }
        internal int[] ScreenWideProfileIds { get; }
        internal IReadOnlyDictionary<string, int> BulletBindings { get; }
        internal IReadOnlyDictionary<string, int> EffectBindings { get; }

        internal static WorldShakeCatalog Default { get; } = CreateDefault();

        private WorldShakeCatalog(string sha256, float maxOffset, WorldShakeProfile[] profiles,
            Dictionary<string, int> bullets, Dictionary<string, int> effects)
        {
            Sha256 = sha256;
            MaxTotalOffsetStagePx = maxOffset;
            Profiles = profiles;
            BulletBindings = bullets;
            EffectBindings = effects;
            int maxTicks = 0;
            Priorities = new int[profiles.Length + 1];
            var screenWide = new List<int>();
            for (int i = 0; i < profiles.Length; i++)
            {
                WorldShakeProfile p = profiles[i];
                Priorities[p.Id] = p.Priority;
                if (p.Ticks > maxTicks) maxTicks = p.Ticks;
                if (p.IsScreenWide) screenWide.Add(p.Id);
            }
            TailTicks = Math.Clamp(Math.Max(DefaultTailTicks, maxTicks + 1), 2, 121);
            ScreenWideProfileIds = screenWide.ToArray();
        }

        internal float[] PackNativeProfiles()
        {
            var packed = new float[Profiles.Length * 5];
            for (int i = 0; i < Profiles.Length; i++)
            {
                WorldShakeProfile p = Profiles[i];
                int offset = i * 5;
                packed[offset] = p.Priority;
                packed[offset + 1] = p.Amplitude;
                packed[offset + 2] = p.Ticks;
                packed[offset + 3] = p.Frequency;
                packed[offset + 4] = p.Radius;
            }
            return packed;
        }

        internal object BuildCapsPayload() => new
        {
            digest = Sha256,
            maxProfile = MaxProfileId,
            tailTicks = TailTicks,
            priorities = Priorities,
            screenWide = ScreenWideProfileIds,
            bullets = BulletBindings,
            effects = EffectBindings
        };

        internal static WorldShakeCatalog Load(string projectRoot, Action<string> warn = null)
        {
            string fullPath = Path.Combine(projectRoot, RelativePath.Replace('/', Path.DirectorySeparatorChar));
            try
            {
                return LoadStrict(fullPath);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or InvalidDataException
                or JsonException or KeyNotFoundException or InvalidOperationException or FormatException or OverflowException)
            {
                warn?.Invoke("event=world_shake_catalog_fallback reason=" + error.Message);
                return Default;
            }
        }

        internal static WorldShakeCatalog LoadStrict(string path)
        {
            byte[] bytes = File.ReadAllBytes(path);
            if (bytes.Length > MaxBytes) throw new InvalidDataException("Screen shake catalog exceeds byte budget");
            string sha = Convert.ToHexString(SHA256.HashData(bytes));
            ReadOnlyMemory<byte> jsonBytes = bytes.Length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF
                ? bytes.AsMemory(3)
                : bytes;
            using var doc = JsonDocument.Parse(jsonBytes, new JsonDocumentOptions { MaxDepth = 12 });
            JsonElement root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Object) throw new InvalidDataException("Root must be an object");
            if (root.GetProperty("schema").GetString() != "cf7-screen-shake.v1"
                || root.GetProperty("ticksPerSecond").GetInt32() != 30)
                throw new InvalidDataException("Unsupported screen shake catalog schema");
            float maxOffset = Number(root.GetProperty("maxTotalOffsetStagePx"), 0.0001f, 64f);
            JsonElement rawProfiles = root.GetProperty("profiles");
            if (rawProfiles.ValueKind != JsonValueKind.Array || rawProfiles.GetArrayLength() < 1
                || rawProfiles.GetArrayLength() > MaxProfiles)
                throw new InvalidDataException("Invalid shake profile count");

            var profiles = new WorldShakeProfile[rawProfiles.GetArrayLength()];
            var byName = new Dictionary<string, int>(StringComparer.Ordinal);
            int index = 0;
            foreach (JsonElement item in rawProfiles.EnumerateArray())
            {
                int expectedId = index + 1;
                if (item.ValueKind != JsonValueKind.Object) throw new InvalidDataException("Profile entry must be an object");
                int id = Int(item.GetProperty("id"), expectedId, expectedId);
                string name = item.GetProperty("name").GetString();
                if (string.IsNullOrEmpty(name) || name.Length > 64 || byName.ContainsKey(name))
                    throw new InvalidDataException("Invalid or duplicate shake profile name");
                int priority = Int(item.GetProperty("priority"), 1, 100);
                float amplitude = Number(item.GetProperty("amplitude"), 0f, 64f);
                int ticks = Int(item.GetProperty("ticks"), 1, 120);
                float frequency = Number(item.GetProperty("frequency"), 0.5f, 60f);
                float radius = Number(item.GetProperty("radius"), 0f, 100000f);
                if (radius != 0f && radius < 1f) throw new InvalidDataException("Shake radius must be 0 or >= 1");
                profiles[index++] = new WorldShakeProfile(id, name, priority, amplitude, ticks, frequency, radius);
                byName[name] = id;
            }

            JsonElement bindings = root.GetProperty("bindings");
            if (bindings.ValueKind != JsonValueKind.Object) throw new InvalidDataException("Invalid shake bindings");
            var bullets = ReadBindings(bindings.GetProperty("bullets"), byName, "bullets");
            var effects = ReadBindings(bindings.GetProperty("effects"), byName, "effects");
            if (bullets.Count + effects.Count > MaxBindings)
                throw new InvalidDataException("Shake bindings exceed cap");
            if (bindings.TryGetProperty("exemptBullets", out JsonElement exempt))
            {
                if (exempt.ValueKind != JsonValueKind.Array) throw new InvalidDataException("Invalid exemptBullets");
                var seenExempt = new HashSet<string>(StringComparer.Ordinal);
                foreach (JsonElement item in exempt.EnumerateArray())
                {
                    string key = item.GetString();
                    if (string.IsNullOrEmpty(key) || key.Length > 128 || !seenExempt.Add(key) || bullets.ContainsKey(key))
                        throw new InvalidDataException("Invalid or overlapping exemptBullets entry");
                }
            }

            return new WorldShakeCatalog(sha, maxOffset, profiles, bullets, effects);
        }

        private static Dictionary<string, int> ReadBindings(JsonElement obj, Dictionary<string, int> byName, string group)
        {
            if (obj.ValueKind != JsonValueKind.Object) throw new InvalidDataException("Invalid shake bindings." + group);
            var map = new Dictionary<string, int>(StringComparer.Ordinal);
            foreach (JsonProperty prop in obj.EnumerateObject())
            {
                if (string.IsNullOrEmpty(prop.Name) || prop.Name.Length > 128 || map.ContainsKey(prop.Name))
                    throw new InvalidDataException("Invalid or duplicate shake binding key in " + group);
                string target = prop.Value.GetString();
                if (target == null || !byName.TryGetValue(target, out int profileId))
                    throw new InvalidDataException("Unknown shake profile reference in " + group + ": " + prop.Name);
                map[prop.Name] = profileId;
            }
            return map;
        }

        private static int Int(JsonElement e, int min, int max)
        {
            if (e.ValueKind != JsonValueKind.Number || !e.TryGetInt32(out int value) || value < min || value > max)
                throw new InvalidDataException("Invalid shake integer");
            return value;
        }

        private static float Number(JsonElement e, float min, float max)
        {
            if (e.ValueKind != JsonValueKind.Number) throw new InvalidDataException("Invalid shake number");
            float value = e.GetSingle();
            if (!float.IsFinite(value) || value < min || value > max)
                throw new InvalidDataException("Shake number out of range");
            return value;
        }

        private static WorldShakeCatalog CreateDefault()
        {
            var profiles = new[]
            {
                new WorldShakeProfile(1, "light",        1, 3.5f,  8, 22f,  900f),
                new WorldShakeProfile(2, "standard",     2, 5.0f, 10, 20f, 1000f),
                new WorldShakeProfile(3, "support",      5, 6.0f, 12, 18f, 1100f),
                new WorldShakeProfile(4, "asura",        3, 5.5f, 10, 24f,  950f),
                new WorldShakeProfile(5, "heavy",        6, 8.5f, 18, 15f, 1500f),
                new WorldShakeProfile(6, "quantum",      7, 9.5f, 24, 14f, 1600f),
                new WorldShakeProfile(7, "quake_screen", 4, 5.5f, 14, 17f,    0f),
            };
            var bullets = new Dictionary<string, int>(StringComparer.Ordinal)
            {
                ["小火焰爆炸"] = 1, ["空中小火焰爆炸"] = 1, ["普通霹雷"] = 1, ["联弹爆炸"] = 1,
                ["紫色小爆炸"] = 1, ["空中爆炸1"] = 1, ["铁血弹爆炸"] = 1,
                ["爆炸"] = 2, ["普通爆炸"] = 2, ["火球爆炸"] = 2, ["等离子爆炸"] = 2,
                ["定向爆破"] = 2, ["集束连环爆炸"] = 2, ["高压爆炸"] = 2,
                ["火焰集束手雷爆炸"] = 2, ["火焰集束爆炸声"] = 2, ["火焰集束爆炸"] = 2,
                ["烈焰集束爆炸"] = 2, ["墨绿集束爆炸"] = 2, ["苍紫爆炸"] = 2,
                ["绿色爆炸"] = 2, ["血爆炸"] = 2, ["高爆爆炸"] = 2, ["地面爆炸"] = 2,
                ["气功弹爆炸"] = 2, ["波动拳爆炸"] = 2, ["穿刺爆炸"] = 2,
                ["支援飞弹爆炸"] = 3,
                ["阿修罗闪空"] = 4,
                ["巨大物理爆炸"] = 5, ["核弹爆炸"] = 5,
            };
            var effects = new Dictionary<string, int>(StringComparer.Ordinal)
            {
                ["小地震"] = 7,
            };
            return new WorldShakeCatalog("", 14f, profiles, bullets, effects);
        }
    }
}
