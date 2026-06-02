using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Xml;
using Newtonsoft.Json.Linq;
using CF7Launcher.Guardian;

namespace CF7Launcher.Data
{
    /// <summary>
    /// 战宠静态目录加载器：从 data/merc/pets.xml 解析出
    ///   - 商城分类（名称 + 网格行，行内为宠物 id，支持 null 占位）
    ///   - 宠物定义（id → 名称/兵种/身高/初始等级/解锁门槛/唯一性/价格/进阶方案名）
    ///
    /// 这是 AS2 `_root.加载并配置宠物信息`（<PetStore>/<Pet>）+ `handleAdoptList` + snapshot.petLib
    /// 的 C# 等价物。纯静态配置、无存档态——由 PetTask 直答 Web，不经 Flash（参照 IntelligenceTask）。
    ///
    /// 注意：宠物 Price 的「IncreasePrice 每次购买涨价」是 AS2 会话内运行态（改写 _root.宠物库.Price，
    /// 不入存档、重启复位）。本类只提供 XML 基础价；涨价后的当前价仍以 AS2 为准（见迁移方案 §9）。
    /// </summary>
    public sealed class PetDef
    {
        public int Id;
        public string Name = "";
        public string Identifier = "";
        public int Height;
        public int InitialLevel;
        public int UnlockLevel;
        public int UnlockTask;
        public bool Unique;
        public int Price;
        public int KPrice;
        public int IncreasePrice;
        public readonly List<string> Promotions = new List<string>();

        // 商城可领养条目（字段名匹配 AS2 旧 handleAdoptList 下发 + JS 商城网格读取）。
        public JObject ToAdoptJObject()
        {
            var o = new JObject();
            o["petId"] = Id;
            o["name"] = Name;
            o["identifier"] = Identifier;
            o["height"] = Height;
            o["price"] = Price;
            o["kprice"] = KPrice;
            o["unlockLevel"] = UnlockLevel;
            o["unlockTask"] = UnlockTask;
            o["unique"] = Unique;
            return o;
        }

        // 宠物库条目（字段名匹配 AS2 旧 snapshot.petLib + JS getPetLibDef，用 id 键）。
        public JObject ToLibJObject()
        {
            var o = new JObject();
            o["id"] = Id;
            o["name"] = Name;
            o["identifier"] = Identifier;
            o["height"] = Height;
            o["initialLevel"] = InitialLevel;
            o["unlockLevel"] = UnlockLevel;
            o["unlockTask"] = UnlockTask;
            o["unique"] = Unique;
            o["price"] = Price;
            o["kprice"] = KPrice;
            o["increasePrice"] = IncreasePrice;
            var promos = new JArray();
            for (int i = 0; i < Promotions.Count; i++) promos.Add(Promotions[i]);
            o["promotions"] = promos;
            return o;
        }
    }

    public sealed class PetCatalog
    {
        // 分类顺序与 pets.xml <PetStore> 一致。
        public readonly List<PetCategory> Categories = new List<PetCategory>();
        // id → 宠物定义。
        public readonly Dictionary<int, PetDef> PetsById = new Dictionary<int, PetDef>();

        public sealed class PetCategory
        {
            public string Name = "";
            // 网格行，行内元素为宠物 id；null 表示占位空格（对齐 AS2 <List> 的 null）。
            public readonly List<List<int?>> Rows = new List<List<int?>>();
        }

        // 按 id 升序的宠物库（等价 AS2 `for pid 0..宠物库.length`）。
        public List<PetDef> PetsOrderedById()
        {
            var ids = new List<int>(PetsById.Keys);
            ids.Sort();
            var list = new List<PetDef>(ids.Count);
            for (int i = 0; i < ids.Count; i++) list.Add(PetsById[ids[i]]);
            return list;
        }
    }

    public static class PetCatalogLoader
    {
        /// <summary>
        /// 解析 pets.xml。文件缺失/无法解析时抛异常，由调用方缓存错误并回 fallback。
        /// </summary>
        public static PetCatalog Load(string projectRoot)
        {
            string path = Path.Combine(
                string.IsNullOrEmpty(projectRoot) ? AppDomain.CurrentDomain.BaseDirectory : projectRoot,
                "data", "merc", "pets.xml");
            if (!File.Exists(path))
                throw new FileNotFoundException("pets.xml not found: " + path);

            var doc = new XmlDocument();
            doc.Load(path);

            var catalog = new PetCatalog();

            // ── <Pet> 定义 ─────────────────────────────────────────────────
            XmlNodeList petNodes = doc.SelectNodes("/Pets/Pet");
            if (petNodes != null)
            {
                foreach (XmlNode pet in petNodes)
                {
                    int id;
                    if (!int.TryParse(ChildText(pet, "id"), NumberStyles.Integer, CultureInfo.InvariantCulture, out id))
                        continue;

                    var def = new PetDef();
                    def.Id = id;
                    def.Name = ChildText(pet, "Name");
                    def.Identifier = ChildText(pet, "Identifier");
                    def.Height = ParseNum(ChildText(pet, "Height"));
                    def.InitialLevel = ParseNum(ChildText(pet, "InitialLevel"));
                    def.UnlockLevel = ParseNum(ChildText(pet, "UnlockLevel"));
                    def.UnlockTask = ParseNum(ChildText(pet, "UnlockTask"));
                    def.Unique = string.Equals(ChildText(pet, "Unique"), "true", StringComparison.OrdinalIgnoreCase);
                    def.Price = ParseNum(ChildText(pet, "Price"));
                    def.KPrice = ParseNum(ChildText(pet, "KPrice"));
                    def.IncreasePrice = ParseNum(ChildText(pet, "IncreasePrice"));

                    XmlNode promo = SelectChild(pet, "Promotion");
                    if (promo != null)
                    {
                        foreach (XmlNode item in promo.ChildNodes)
                        {
                            if (item.NodeType == XmlNodeType.Element && item.Name == "Item")
                            {
                                string nm = item.InnerText ?? "";
                                if (nm.Length > 0) def.Promotions.Add(nm);
                            }
                        }
                    }

                    catalog.PetsById[id] = def;
                }
            }

            // ── <PetStore><Category> 分类与网格 ─────────────────────────────
            XmlNodeList catNodes = doc.SelectNodes("/Pets/PetStore/Category");
            if (catNodes != null)
            {
                foreach (XmlNode cat in catNodes)
                {
                    var category = new PetCatalog.PetCategory();
                    category.Name = ChildText(cat, "Name");
                    foreach (XmlNode child in cat.ChildNodes)
                    {
                        if (child.NodeType != XmlNodeType.Element || child.Name != "List") continue;
                        var row = new List<int?>();
                        string raw = child.InnerText ?? "";
                        string[] cells = raw.Split(',');
                        for (int i = 0; i < cells.Length; i++)
                        {
                            string cell = cells[i].Trim();
                            int v;
                            if (int.TryParse(cell, NumberStyles.Integer, CultureInfo.InvariantCulture, out v))
                                row.Add(v);
                            else
                                row.Add(null); // "null" 占位 / 空白
                        }
                        category.Rows.Add(row);
                    }
                    catalog.Categories.Add(category);
                }
            }

            LogManager.Log("[PetCatalogLoader] loaded: pets=" + catalog.PetsById.Count
                + " categories=" + catalog.Categories.Count);
            return catalog;
        }

        private static int ParseNum(string raw)
        {
            int v;
            if (int.TryParse(raw, NumberStyles.Integer, CultureInfo.InvariantCulture, out v)) return v;
            return 0;
        }

        private static XmlNode SelectChild(XmlNode node, string name)
        {
            foreach (XmlNode child in node.ChildNodes)
                if (child.NodeType == XmlNodeType.Element && child.Name == name)
                    return child;
            return null;
        }

        private static string ChildText(XmlNode node, string name)
        {
            XmlNode child = SelectChild(node, name);
            return child == null ? "" : (child.InnerText ?? "");
        }
    }
}
