using System;
using System.Globalization;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using CF7Launcher.Bus;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.ArenaWorker;

// Session-fixed consumers are admitted only by the verified Worker launch path.
// D1/D2 retain real presentation, scene light and equipment light ownership.
internal sealed class WorkerProjectionPolicy
{
    internal static readonly string[] ConsumerNames = { "playerHud", "ordinaryBullet", "ray", "chain",
        "combatDecoration", "sceneLighting", "equipmentLighting" };
    internal static readonly string[] CatalogNames = { "bulletStyles", "combatFxStyles", "rayStyles", "sceneLights" };
    private readonly JObject _consumers;
    internal int SessionVisualSeed { get; }
    internal const string VisualRevision = "visual-event-v1";
    internal const string SimulationRevision = "legacy-global-consume-v1";

    private WorkerProjectionPolicy(JObject consumers, int seed)
    { _consumers = (JObject)consumers.DeepClone(); SessionVisualSeed = seed; }

    internal static WorkerProjectionPolicy FromConfiguration(JObject config)
    {
        string schema = config.Value<string>("schema");
        string[] fields = { "presentationPolicy", "projectionConsumers", "controlFrameFormat",
            "visualSeedRevision", "simulationRngConsumptionRevision", "sessionVisualSeed" };
        if (schema == "arena-worker.launch.v1" || schema == null)
        {
            if (fields.Any(name => config[name] != null)) throw new InvalidOperationException("v1 Worker cannot request projection policy.");
            return null;
        }
        if (schema != "arena-worker.launch.v2") throw new InvalidOperationException("Unsupported Worker launch schema.");
        if (!Text(config, "presentationPolicy", "full") || !Text(config, "controlFrameFormat", "f-visual-v1")
            || !Text(config, "visualSeedRevision", VisualRevision) || !Text(config, "simulationRngConsumptionRevision", SimulationRevision)
            || config["projectionConsumers"] is not JObject consumers || !VisualWireNegotiator.Exact(consumers, ConsumerNames)
            || !Integer(config["sessionVisualSeed"], 1, 2147483646, out int seed))
            throw new InvalidOperationException("Invalid D1/D2 Worker projection policy.");
        foreach (string name in ConsumerNames)
            if (consumers[name]?.Type != JTokenType.String || ((string)consumers[name] != "full" && (string)consumers[name] != "none"))
                throw new InvalidOperationException("Invalid Worker consumer.");
        if ((string)consumers["sceneLighting"] != "full" || (string)consumers["equipmentLighting"] != "full")
            throw new InvalidOperationException("D1/D2 requires both lighting consumers.");
        return new WorkerProjectionPolicy(consumers, seed);
    }

    internal bool IsNone(string consumer) => (string)_consumers[consumer] == "none";
    internal JObject Consumers => (JObject)_consumers.DeepClone();
    internal static JObject BindCatalogs(string bullet, string combat, string ray, string scene)
    {
        string[] values = { bullet, combat, ray, scene };
        var bindings = new JObject();
        for (int i = 0; i < CatalogNames.Length; i++)
        {
            string text = values[i]?.ToLowerInvariant();
            if (text != null && !text.StartsWith("sha256:", StringComparison.Ordinal)) text = "sha256:" + text;
            if (!Hash(text == null ? null : new JValue(text))) throw new InvalidOperationException("Worker catalog digest is invalid: " + CatalogNames[i]);
            bindings[CatalogNames[i]] = text;
        }
        return bindings;
    }
    internal JObject Payload(JObject bindings)
    {
        if (!VisualWireNegotiator.Exact(bindings, CatalogNames) || CatalogNames.Any(name => !Hash(bindings[name])))
            throw new InvalidOperationException("Worker projection catalogs are unavailable.");
        var consumers = new JObject();
        foreach (string name in ConsumerNames) consumers[name] = _consumers[name].DeepClone();
        var catalogs = new JObject();
        foreach (string name in CatalogNames) catalogs[name] = bindings[name].DeepClone();
        return new JObject { ["presentation"] = "full", ["readinessKind"] = "arena.presented.v1",
            ["projectionConsumers"] = consumers, ["controlFrameFormat"] = "f-visual-v1",
            ["ownership"] = "as2-gameplay-native-model-v1", ["catalogBindings"] = catalogs,
            ["visualSeedRevision"] = VisualRevision, ["simulationRngConsumptionRevision"] = SimulationRevision,
            ["sessionVisualSeed"] = SessionVisualSeed };
    }
    internal static string Digest(JObject payload) => "sha256:" + Convert.ToHexStringLower(
        SHA256.HashData(Encoding.UTF8.GetBytes(payload.ToString(Formatting.None))));
    internal static bool Hash(JToken value) => value?.Type == JTokenType.String && value.ToString().Length == 71
        && value.ToString().StartsWith("sha256:", StringComparison.Ordinal)
        && value.ToString().Skip(7).All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f');
    internal static bool Integer(JToken value, int min, int max, out int result)
    {
        result = 0;
        return value?.Type == JTokenType.Integer && int.TryParse(value.ToString(Formatting.None),
            NumberStyles.None, CultureInfo.InvariantCulture, out result) && result >= min && result <= max;
    }
    private static bool Text(JObject value, string key, string expected)
        => value[key]?.Type == JTokenType.String && (string)value[key] == expected;
}
