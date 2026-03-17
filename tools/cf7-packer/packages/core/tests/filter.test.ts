import { describe, it, expect } from "vitest";
import { filterFiles } from "../src/filter.js";
import type { PackConfig } from "../src/types.js";

function makeConfig(overrides: Partial<PackConfig> = {}): PackConfig {
  return {
    version: 1,
    meta: { name: "test" },
    source: { mode: "worktree", repoRoot: "." },
    output: { dir: "./out", clean: true },
    layers: [
      { name: "data", source: "data/", include: ["**/*"], exclude: [] }
    ],
    globalExclude: [],
    ...overrides
  };
}

describe("filterFiles", () => {
  // --- 基本匹配 ---

  it("includes files matching layer source + include", () => {
    const config = makeConfig();
    const result = filterFiles(["data/items/weapon.xml", "data/stages/1.xml"], config);
    expect(result.included).toHaveLength(2);
    expect(result.included.every((f) => f.layer === "data")).toBe(true);
  });

  it("excludes files not matching any layer", () => {
    const config = makeConfig();
    const result = filterFiles(["music/bgm.mp3", "tools/pack.ps1"], config);
    expect(result.included).toHaveLength(0);
    expect(result.unmatchedCount).toBe(2);
  });

  it("applies layer exclude rules", () => {
    const config = makeConfig({
      layers: [{
        name: "scripts",
        source: "scripts/",
        include: ["**/*"],
        exclude: ["TestLoader/**", "**/*Test.as"]
      }]
    });

    const files = [
      "scripts/类定义/Main.as",
      "scripts/TestLoader/runner.as",
      "scripts/类定义/SortTest.as"
    ];
    const result = filterFiles(files, config);
    expect(result.included).toHaveLength(1);
    expect(result.included[0]!.path).toBe("scripts/类定义/Main.as");
    expect(result.excluded).toHaveLength(2);
  });

  // --- globalExclude ---

  it("applies globalExclude to all files", () => {
    const config = makeConfig({
      globalExclude: ["**/*.bak", "**/.DS_Store"]
    });
    const files = [
      "data/items/weapon.xml",
      "data/items/weapon.xml.bak",
      "data/.DS_Store"
    ];
    const result = filterFiles(files, config);
    expect(result.included).toHaveLength(1);
    expect(result.excluded).toHaveLength(2);
    expect(result.excluded.every((f) => f.layer === "__global__")).toBe(true);
  });

  // --- flashswf 97% 排除场景 ---

  it("flashswf layer: includes only .swf/.txt/.png/.jpg, excludes .fla/.xml source projects", () => {
    const config = makeConfig({
      layers: [{
        name: "flashswf",
        source: "flashswf/",
        include: ["**/*.swf", "**/*.txt", "**/*.png", "**/*.jpg"],
        exclude: ["unused/**", "miniGames/**", "ComicTool/**"]
      }]
    });

    const files = [
      "flashswf/UI/hud.swf",
      "flashswf/arts/new/char1.swf",
      "flashswf/arts/things0/sword.fla",           // .fla 不在 include
      "flashswf/UI/任务栏界面/DOMDocument.xml",     // .xml 不在 include (注意：如果配置里有 **/*.xml 则会包含)
      "flashswf/UI/任务栏界面/LIBRARY/btn.xml",     // .xml 不在 include
      "flashswf/backgrounds/sky.png",
      "flashswf/Langrage/Chinese.txt",
      "flashswf/unused/old.swf",                    // excluded dir
      "flashswf/miniGames/game.swf",                // excluded dir
      "flashswf/ComicTool/tool.swf"                 // excluded dir
    ];

    const result = filterFiles(files, config);

    const includedPaths = result.included.map((f) => f.path);
    expect(includedPaths).toContain("flashswf/UI/hud.swf");
    expect(includedPaths).toContain("flashswf/arts/new/char1.swf");
    expect(includedPaths).toContain("flashswf/backgrounds/sky.png");
    expect(includedPaths).toContain("flashswf/Langrage/Chinese.txt");

    expect(includedPaths).not.toContain("flashswf/arts/things0/sword.fla");
    expect(includedPaths).not.toContain("flashswf/unused/old.swf");
    expect(includedPaths).not.toContain("flashswf/miniGames/game.swf");
    expect(includedPaths).not.toContain("flashswf/ComicTool/tool.swf");
  });

  // --- 多层级优先级 ---

  it("first matching layer wins", () => {
    const config = makeConfig({
      layers: [
        { name: "data", source: "data/", include: ["**/*"], exclude: [] },
        { name: "catchall", source: ".", include: ["**/*"], exclude: [] }
      ]
    });

    const result = filterFiles(["data/items/weapon.xml", "music/bgm.mp3"], config);
    const dataEntry = result.included.find((f) => f.path === "data/items/weapon.xml");
    const musicEntry = result.included.find((f) => f.path === "music/bgm.mp3");

    expect(dataEntry?.layer).toBe("data");
    expect(musicEntry?.layer).toBe("catchall");
  });

  // --- root-files layer (source: ".") ---

  it("root layer with explicit file includes", () => {
    const config = makeConfig({
      layers: [{
        name: "root-files",
        source: ".",
        include: [
          "CRAZYFLASHER7MercenaryEmpire.exe",
          "CRAZYFLASHER7MercenaryEmpire.swf",
          "config.xml"
        ],
        exclude: []
      }]
    });

    const files = [
      "CRAZYFLASHER7MercenaryEmpire.exe",
      "CRAZYFLASHER7MercenaryEmpire.swf",
      "config.xml",
      "config.toml",  // not included
      "AGENTS.md"     // not included
    ];

    const result = filterFiles(files, config);
    expect(result.included).toHaveLength(3);
    expect(result.unmatchedCount).toBe(2);
  });

  // --- root-dirs layer (source: "." with glob dirs) ---

  it("root layer with directory glob patterns", () => {
    const config = makeConfig({
      layers: [{
        name: "root-dirs",
        source: ".",
        include: ["闪7重置版字体/**", "0.说明文件与教程/**"],
        exclude: []
      }]
    });

    const files = [
      "闪7重置版字体/font1.ttf",
      "闪7重置版字体/font2.otf",
      "0.说明文件与教程/readme.txt",
      "tools/pack.ps1",   // not matched
      "AGENTS.md"         // not matched
    ];

    const result = filterFiles(files, config);
    expect(result.included).toHaveLength(3);
    expect(result.unmatchedCount).toBe(2);
  });

  // --- sounds 排除版权音乐 ---

  it("sounds layer excludes copyright music", () => {
    const config = makeConfig({
      layers: [{
        name: "sounds",
        source: "sounds/",
        include: ["**/*"],
        exclude: ["阿卡music/**"]
      }]
    });

    const files = [
      "sounds/bgm_list.xml",
      "sounds/BONUS/track.mp3",
      "sounds/阿卡music/Call your name.wav",
      "sounds/阿卡music/【Ayasa】God knows.wav"
    ];

    const result = filterFiles(files, config);
    expect(result.included).toHaveLength(2);
    expect(result.excluded).toHaveLength(2);
    expect(result.excluded.every((f) => f.layer === "sounds")).toBe(true);
  });

  // --- LayerSummary 统计 ---

  it("produces correct layer summaries", () => {
    const config = makeConfig({
      layers: [
        { name: "data", source: "data/", include: ["**/*"], exclude: [] },
        { name: "scripts", source: "scripts/", include: ["**/*"], exclude: ["TestLoader/**"] }
      ]
    });

    const files = [
      "data/a.xml",
      "data/b.xml",
      "scripts/main.as",
      "scripts/TestLoader/run.as"
    ];

    const result = filterFiles(files, config);
    const dataSummary = result.layers.find((l) => l.name === "data");
    const scriptsSummary = result.layers.find((l) => l.name === "scripts");

    expect(dataSummary?.includedCount).toBe(2);
    expect(dataSummary?.excludedCount).toBe(0);
    expect(scriptsSummary?.includedCount).toBe(1);
    expect(scriptsSummary?.excludedCount).toBe(1);
  });

  // --- 反斜杠路径处理 ---

  it("normalizes backslash paths", () => {
    const config = makeConfig();
    const result = filterFiles(["data\\items\\weapon.xml"], config);
    expect(result.included).toHaveLength(1);
    expect(result.included[0]!.layer).toBe("data");
  });

  // --- 空文件列表 ---

  it("handles empty file list", () => {
    const config = makeConfig();
    const result = filterFiles([], config);
    expect(result.included).toHaveLength(0);
    expect(result.excluded).toHaveLength(0);
    expect(result.unmatchedCount).toBe(0);
  });

  // --- scripts compile_* 排除 ---

  it("scripts layer excludes compile_* files", () => {
    const config = makeConfig({
      layers: [{
        name: "scripts",
        source: "scripts/",
        include: ["**/*"],
        exclude: ["compile_*"]
      }]
    });

    const files = [
      "scripts/compile_output.txt",
      "scripts/compile_env.sh",
      "scripts/config.as"
    ];

    const result = filterFiles(files, config);
    expect(result.included).toHaveLength(1);
    expect(result.included[0]!.path).toBe("scripts/config.as");
  });

  // --- 全场景综合测试 ---

  it("full scenario: multi-layer config processes correctly", () => {
    const config = makeConfig({
      layers: [
        { name: "data", source: "data/", include: ["**/*"], exclude: [] },
        { name: "scripts", source: "scripts/", include: ["**/*"], exclude: ["TestLoader/**"] },
        { name: "flashswf", source: "flashswf/", include: ["**/*.swf"], exclude: ["unused/**"] },
        { name: "sounds", source: "sounds/", include: ["**/*"], exclude: ["阿卡music/**"] },
        { name: "root", source: ".", include: ["config.xml", "README.md"], exclude: [] }
      ],
      globalExclude: ["**/*.bak"]
    });

    const files = [
      "data/items/weapon.xml",
      "data/items/weapon.xml.bak",     // globalExclude
      "scripts/main.as",
      "scripts/TestLoader/run.as",      // layer exclude
      "flashswf/UI/hud.swf",
      "flashswf/arts/char.fla",         // not in include (.fla)
      "flashswf/unused/old.swf",        // layer exclude
      "sounds/bgm.mp3",
      "sounds/阿卡music/song.wav",     // layer exclude
      "config.xml",
      "README.md",
      "AGENTS.md",                      // unmatched
      "tools/pack.ps1"                  // unmatched
    ];

    const result = filterFiles(files, config);

    expect(result.included.map((f) => f.path).sort()).toEqual([
      "README.md",
      "config.xml",
      "data/items/weapon.xml",
      "flashswf/UI/hud.swf",
      "scripts/main.as",
      "sounds/bgm.mp3"
    ]);

    expect(result.unmatchedCount).toBe(3); // AGENTS.md, tools/pack.ps1, flashswf/arts/char.fla
    expect(result.excluded.length).toBe(4); // .bak, TestLoader, unused, 阿卡music
  });
});
