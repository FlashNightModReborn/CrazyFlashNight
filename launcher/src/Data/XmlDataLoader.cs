using System;
using System.Collections.Generic;
using System.IO;
using System.Xml;
using Newtonsoft.Json.Linq;
using CF7Launcher.Guardian;

namespace CF7Launcher.Data
{
    /// <summary>
    /// NPC 对话中一个 Dialogue 节点解析后的结构。
    /// </summary>
    public class DialogueGroup
    {
        public int TaskRequirement;
        public JArray SubDialogues;
    }

    /// <summary>
    /// 从项目 data/ 目录解析 XML 文件，生成与 Flash AS2 运行时一致的数据结构。
    ///
    /// NPC 对话：字段名全 lowercase（name, title, char, text, id, target, imageurl）。
    /// 佣兵 bundle：teams 用中文属性名，dialogues 用 PascalCase，Value 序列化为 string。
    /// </summary>
    public static class XmlDataLoader
    {
        // ===================== NPC 对话 =====================

        /// <summary>
        /// 加载所有 NPC 对话数据，按 NPC 名分组。
        /// 复刻 NpcDialogueLoader.mergeDialogues (AS2) 的输出结构。
        /// </summary>
        public static Dictionary<string, List<DialogueGroup>> LoadNpcDialogues(string projectRoot)
        {
            string dataDir = Path.Combine(projectRoot, "data", "dialogues");
            string listPath = Path.Combine(dataDir, "list.xml");

            Dictionary<string, List<DialogueGroup>> index =
                new Dictionary<string, List<DialogueGroup>>();

            // list.xml 缺失 = 整体失败（匹配 AS2 Promise.all 语义）
            if (!File.Exists(listPath))
                throw new FileNotFoundException("list.xml not found: " + listPath);

            XmlDocument listDoc = new XmlDocument();
            listDoc.Load(listPath);

            XmlNodeList items = listDoc.SelectNodes("//items");
            if (items == null || items.Count == 0)
                throw new InvalidOperationException("list.xml contains no <items> entries");

            // 任一子文件缺失/解析失败 = 整体失败（匹配 AS2 NpcDialogueLoader 的 Promise.all 语义）
            foreach (XmlNode item in items)
            {
                string fileName = item.InnerText;
                if (string.IsNullOrEmpty(fileName)) continue;

                string filePath = Path.Combine(dataDir, fileName);
                if (!File.Exists(filePath))
                    throw new FileNotFoundException("NPC dialogue file missing: " + fileName);

                ParseNpcDialogueFile(filePath, index);
                // ParseNpcDialogueFile 内部不 catch — 解析异常直接冒泡
            }

            LogManager.Log("[XmlDataLoader] NPC dialogues loaded: " + index.Count + " NPCs");
            return index;
        }

        private static void ParseNpcDialogueFile(
            string filePath, Dictionary<string, List<DialogueGroup>> index)
        {
            XmlDocument doc = new XmlDocument();
            doc.Load(filePath);

            // root > Dialogues (可能多个 Dialogues 节点)
            XmlNodeList dialoguesNodes = doc.SelectNodes("//Dialogues");
            if (dialoguesNodes == null) return;

            foreach (XmlNode dialoguesNode in dialoguesNodes)
            {
                // Dialogues > Name = NPC 名
                XmlNode nameNode = dialoguesNode.SelectSingleNode("Name");
                if (nameNode == null) continue;
                string npcName = nameNode.InnerText;
                if (string.IsNullOrEmpty(npcName)) continue;

                List<DialogueGroup> groups;
                if (!index.TryGetValue(npcName, out groups))
                {
                    groups = new List<DialogueGroup>();
                    index[npcName] = groups;
                }

                // Dialogues > Dialogue (每个是一组对话)
                XmlNodeList dialogueNodes = dialoguesNode.SelectNodes("Dialogue");
                if (dialogueNodes == null) continue;

                foreach (XmlNode dialogueNode in dialogueNodes)
                {
                    DialogueGroup group = new DialogueGroup();

                    // TaskRequirement (Dialogue 的子元素, 可选, 默认 0)
                    XmlNode trNode = dialogueNode.SelectSingleNode("TaskRequirement");
                    if (trNode != null)
                    {
                        int tr;
                        if (int.TryParse(trNode.InnerText, out tr))
                            group.TaskRequirement = tr;
                    }

                    // SubDialogue 数组
                    XmlNodeList subNodes = dialogueNode.SelectNodes("SubDialogue");
                    JArray subs = new JArray();

                    if (subNodes != null)
                    {
                        foreach (XmlNode subNode in subNodes)
                        {
                            JObject sub = new JObject();

                            // id 来自 XML 属性，非子元素
                            XmlElement subElem = subNode as XmlElement;
                            if (subElem != null)
                                sub["id"] = subElem.GetAttribute("id");

                            // PascalCase → lowercase 映射
                            sub["name"] = GetChildText(subNode, "Name");
                            sub["title"] = GetChildText(subNode, "Title");
                            sub["char"] = GetChildText(subNode, "Char");
                            sub["text"] = GetChildText(subNode, "Text");

                            // target / imageurl：当前 XML 无此字段，输出 null
                            string target = GetChildText(subNode, "Target");
                            sub["target"] = target != null ? (JToken)target : JValue.CreateNull();

                            string imageurl = GetChildText(subNode, "ImageUrl");
                            sub["imageurl"] = imageurl != null ? (JToken)imageurl : JValue.CreateNull();

                            subs.Add(sub);
                        }
                    }

                    group.SubDialogues = subs;
                    groups.Add(group);
                }
            }
        }

        private static string GetChildText(XmlNode parent, string childName)
        {
            XmlNode child = parent.SelectSingleNode(childName);
            if (child == null) return null;
            return child.InnerText;
        }

        // ===================== 佣兵 Bundle =====================

        /// <summary>
        /// 加载佣兵 bundle (teams + names + dialogues + pool)。
        /// 字段名精确匹配 AS2 运行时变量的属性名。
        /// </summary>
        public static JObject LoadMercBundle(string projectRoot)
        {
            string dataDir = Path.Combine(projectRoot, "data", "hybrid_mercenaries");

            JArray teams = LoadTeams(Path.Combine(dataDir, "teams.xml"));
            JArray names = LoadNames(Path.Combine(dataDir, "name.xml"));
            JArray dialogues;
            JObject pool;
            LoadDialoguesAndPool(Path.Combine(dataDir, "dialogues.xml"), out dialogues, out pool);

            // 匹配 AS2 legacy 语义：三份 XML 全部成功且非空才算 loaded
            // 任一为空 = 加载失败，Flash 端走 fallback legacy
            if (teams.Count == 0)
                throw new InvalidOperationException("teams.xml loaded 0 entries");
            if (names.Count == 0)
                throw new InvalidOperationException("name.xml loaded 0 entries");
            if (dialogues.Count == 0)
                throw new InvalidOperationException("dialogues.xml loaded 0 entries");

            // 发型库由 Flash 本地 asLoader frame 54 加载（会话常驻，不走 Launcher）

            JObject bundle = new JObject();
            bundle["teams"] = teams;
            bundle["names"] = names;
            bundle["dialogues"] = dialogues;
            bundle["pool"] = pool;

            LogManager.Log("[XmlDataLoader] Merc bundle loaded: teams=" + teams.Count
                + " names=" + names.Count + " dialogues=" + dialogues.Count);
            return bundle;
        }

        /// <summary>
        /// teams.xml → [{战队抬头, 战队名, 权重(number), 战队项链}, ...]
        /// </summary>
        private static JArray LoadTeams(string path)
        {
            if (!File.Exists(path))
                throw new FileNotFoundException("teams.xml not found: " + path);
            JArray teams = new JArray();

            XmlDocument doc = new XmlDocument();
            doc.Load(path);

            XmlNodeList teamNodes = doc.SelectNodes("//Team");
            if (teamNodes == null) return teams;

            foreach (XmlNode teamNode in teamNodes)
            {
                JObject team = new JObject();
                team["战队抬头"] = GetChildText(teamNode, "Title");    // 战队抬头
                team["战队名"] = GetChildText(teamNode, "Name");            // 战队名

                string weightStr = GetChildText(teamNode, "Weight");
                int weight;
                if (weightStr != null && int.TryParse(weightStr, out weight))
                    team["权重"] = weight;                                       // 权重 (number)
                else
                    team["权重"] = 1;

                team["战队项链"] = GetChildText(teamNode, "Necklace");  // 战队项链
                teams.Add(team);
            }

            return teams;
        }

        /// <summary>
        /// name.xml → ["影行者", "荒野猎手", ...]
        /// </summary>
        private static JArray LoadNames(string path)
        {
            if (!File.Exists(path))
                throw new FileNotFoundException("name.xml not found: " + path);
            JArray names = new JArray();

            XmlDocument doc = new XmlDocument();
            doc.Load(path);

            XmlNodeList nameNodes = doc.SelectNodes("//Name");
            if (nameNodes == null) return names;

            foreach (XmlNode node in nameNodes)
            {
                string text = node.InnerText;
                if (!string.IsNullOrEmpty(text))
                    names.Add(text);
            }

            return names;
        }

        /// <summary>
        /// dialogues.xml → dialogues 数组 + pool 对象。
        /// 注意：Value 字段必须序列化为 string（AS2 line 762 dialogue[nodeName] = nodeValue 全部是字符串）。
        /// </summary>
        private static void LoadDialoguesAndPool(
            string path, out JArray dialogues, out JObject pool)
        {
            if (!File.Exists(path))
                throw new FileNotFoundException("dialogues.xml not found: " + path);

            dialogues = new JArray();
            pool = new JObject();

            XmlDocument doc = new XmlDocument();
            doc.Load(path);

            XmlNodeList dialogueNodes = doc.SelectNodes("//Dialogue");
            if (dialogueNodes == null) return;

            foreach (XmlNode dialogueNode in dialogueNodes)
            {
                JObject dialogue = new JObject();

                // PascalCase 保留（匹配 AS2 的 dialogue[nodeName] = nodeValue）
                foreach (XmlNode child in dialogueNode.ChildNodes)
                {
                    if (child.NodeType != XmlNodeType.Element) continue;
                    // 全部存为 string（含 Value），匹配 AS2 行为
                    dialogue[child.Name] = child.InnerText;
                }

                dialogues.Add(dialogue);

                // 按 Personality 分池
                JToken personalityToken;
                if (dialogue.TryGetValue("Personality", out personalityToken))
                {
                    string personality = personalityToken.ToString();
                    JArray bucket;
                    JToken existing;
                    if (pool.TryGetValue(personality, out existing))
                    {
                        bucket = (JArray)existing;
                    }
                    else
                    {
                        bucket = new JArray();
                        pool[personality] = bucket;
                    }
                    bucket.Add(dialogue);
                }
            }
        }

        // ===================== 发型库 =====================

        /// <summary>
        /// hairstyle.xml → {identifiers: [...], names: [...], prices: [...]}
        /// 三个平行数组，按 Hair id 索引。匹配 AS2 的 _root.发型库/发型名称库/发型价格。
        /// </summary>
        public static JObject LoadHairstyles(string path)
        {
            if (!File.Exists(path))
                throw new FileNotFoundException("hairstyle.xml not found: " + path);

            XmlDocument doc = new XmlDocument();
            doc.Load(path);

            XmlNodeList hairNodes = doc.SelectNodes("//Hair");
            if (hairNodes == null || hairNodes.Count == 0)
                throw new InvalidOperationException("hairstyle.xml contains no <Hair> entries");

            JArray identifiers = new JArray();
            JArray names = new JArray();
            JArray prices = new JArray();

            foreach (XmlNode hairNode in hairNodes)
            {
                string identifier = GetChildText(hairNode, "Identifier");
                identifiers.Add(identifier != null ? identifier : "");

                string name = GetChildText(hairNode, "Name");
                names.Add(name != null ? name : "");

                string priceStr = GetChildText(hairNode, "Price");
                int price;
                if (priceStr != null && int.TryParse(priceStr, out price))
                    prices.Add(price);
                else
                    prices.Add(0);
            }

            JObject result = new JObject();
            result["identifiers"] = identifiers;
            result["names"] = names;
            result["prices"] = prices;
            return result;
        }

        // ===================== 非人形佣兵对话 =====================

        /// <summary>
        /// enemy_dialogues.xml → { "身份": [{Text, MinIntention, MaxIntention}, ...], ... }
        /// 按 Identity 分组，一个 Group 的多个 Identity 共享同一组 Dialogue。
        /// 匹配 AS2 的 _root.非人形佣兵随机对话[身份] 结构。
        /// </summary>
        public static JObject LoadEnemyDialogues(string path)
        {
            if (!File.Exists(path))
                throw new FileNotFoundException("enemy_dialogues.xml not found: " + path);

            XmlDocument doc = new XmlDocument();
            doc.Load(path);

            JObject result = new JObject();

            XmlNodeList groupNodes = doc.SelectNodes("//Group");
            if (groupNodes == null || groupNodes.Count == 0)
                throw new InvalidOperationException("enemy_dialogues.xml contains no <Group> entries");

            foreach (XmlNode groupNode in groupNodes)
            {
                // 解析该 Group 的所有 Dialogue
                XmlNodeList dialogueNodes = groupNode.SelectNodes("Dialogue");
                JArray dialogues = new JArray();
                if (dialogueNodes != null)
                {
                    foreach (XmlNode dNode in dialogueNodes)
                    {
                        JObject d = new JObject();
                        d["Text"] = GetChildText(dNode, "Text");

                        string minStr = GetChildText(dNode, "MinIntention");
                        int minVal;
                        d["MinIntention"] = (minStr != null && int.TryParse(minStr, out minVal)) ? minVal : 0;

                        string maxStr = GetChildText(dNode, "MaxIntention");
                        int maxVal;
                        d["MaxIntention"] = (maxStr != null && int.TryParse(maxStr, out maxVal)) ? maxVal : 0;

                        dialogues.Add(d);
                    }
                }

                // 一个 Group 可有多个 Identity，共享同一组 Dialogue
                XmlNodeList identityNodes = groupNode.SelectNodes("Identity");
                if (identityNodes != null)
                {
                    foreach (XmlNode idNode in identityNodes)
                    {
                        string identity = idNode.InnerText;
                        if (!string.IsNullOrEmpty(identity))
                            result[identity] = dialogues;
                    }
                }
            }

            LogManager.Log("[XmlDataLoader] Enemy dialogues loaded: " + result.Count + " identities");
            return result;
        }
    }
}
