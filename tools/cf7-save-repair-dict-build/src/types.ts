/**
 * Output schema for launcher/data/save_repair_dict.json.
 *
 * Single source for both:
 *   - launcher C# (RepairDictionary.cs reads this at startup)
 *   - tools/cf7-save-repair (TS dict-loader.ts reads this)
 *
 * Each closed-set field listed here corresponds to a layer L1/L2/L3 field
 * path in launcher/data/save_field_layers.json (see plan INV-1, H2).
 */
export interface SaveRepairDict {
  /** Schema version. Bump when output shape changes. */
  schemaVersion: number;

  /** Generation metadata. */
  generated: {
    /** ISO timestamp. */
    at: string;
    /** Tool version (package.json version). */
    tool: string;
    /** Source file inventory used for diff stability. */
    sourceFiles: string[];
  };

  /** Item names from data/items/*.xml (武器/防具/收集品/消耗品). Used for inventory.*.name. */
  items: string[];

  /** Mod names from data/items/equipment_mods/*.xml. Used for inventory.*.value.mods[*]. */
  mods: string[];

  /**
   * Enemy element names from data/enemy_properties/*.xml top-level element names.
   * Element name itself is the key (e.g. "敌人-黑铁会大叔").
   * Used for byType keys, discoveredEnemies entries.
   */
  enemies: string[];

  /** Hair Identifier values from data/items/hairstyle.xml. Used for $[1][N]. */
  hairstyles: string[];

  /** Skill names. Source: AS2 SaveManager.REPAIR_DICT_SKILLS literal. Used for $[5][N][0]. */
  skills: string[];

  /** Task chain category names. Source: AS2 SaveManager.REPAIR_DICT_TASK_CHAINS. */
  taskChains: string[];

  /** Stage names. Source: AS2 SaveManager.REPAIR_DICT_STAGES (manually maintained). */
  stages: string[];
}

export interface BuildOptions {
  /** Project root (CrazyFlashNight/), used to resolve data/ and scripts/ paths. */
  projectRoot: string;
  /** Output path. Defaults to <projectRoot>/launcher/data/save_repair_dict.json. */
  outputPath?: string;
  /** Verify mode: do not write, only check that current dict matches what would be generated. */
  verify?: boolean;
}

export interface BuildResult {
  dict: SaveRepairDict;
  /** When verify=true, true means existing file matches generated. */
  verified?: boolean;
  /** Diff summary when verify=true and verified=false. */
  diff?: string;
}
