import {expect, it} from "vitest";
import {createHash} from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {execFileSync} from "node:child_process";
import {createRequire} from "node:module";
import {loadConfig} from "../src/config-loader.js";
import {filterFiles} from "../src/filter.js";
import {pack} from "../src/packer.js";

const packerRoot = path.resolve(import.meta.dirname, "../../..");
const repo = path.resolve(packerRoot, "../..");
const catalog = "data/tooltip/tooltip-catalog.json";
const receipt = "data/tooltip/tooltip-catalog.manifest.json";
const archive = "launcher/web/generated/archive-equipment.json";
const compiler = "launcher/scripts/dist/tooltip-catalog-compiler.js";
const bundle = "launcher/scripts/dist/tooltip-bundle.js";

it("prepares snapshots from selected working files or tag blobs, even with stale derived files", async () => {
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(),"cf7-tooltip-pack-"));
  const source = path.join(scratch,"source");
  const out = path.join(scratch,"package");
  const read = (root: string, file: string) => JSON.parse(fs.readFileSync(path.join(root,file),"utf8"));
  const config = loadConfig(path.join(packerRoot,"pack.config.yaml"));
  const current = createRequire(import.meta.url)("../../../../tooltip-catalog.cjs").compile(repo);
  const inputs = current.inputs as string[];
  const required = [...inputs, catalog, receipt, archive, compiler, bundle];
  try {
    for (const file of required) {
      const dest = path.join(source,file);
      fs.mkdirSync(path.dirname(dest),{recursive:true});
      fs.copyFileSync(path.join(repo,file),dest);
    }
    // A synthetic recipe list makes this regression independent of live balancing.
    const list = "data/crafting/list.xml";
    const recipe = "data/crafting/test-package.json";
    fs.writeFileSync(path.join(source,list),"<root><list>test-package</list></root>");
    const itemIds = Object.keys(JSON.parse(current.catalog).items);
    const product = itemIds[0], material = itemIds[1];
    const write = (name: string, count: number) => fs.writeFileSync(path.join(source,recipe),
      JSON.stringify([{recipeId:"test.pack",name:product,materials:[name+"##"+count]}]));
    write(material,2);
    fs.appendFileSync(path.join(source, compiler), "\n// tagged-compiler-revision\n");
    const git = (...args: string[]) => execFileSync("git",args,{cwd:source,stdio:"pipe"});
    git("init","-q"); git("add",".");
    git("-c","user.name=fixture","-c","user.email=fixture@localhost","commit","-qm","snapshot");
    git("tag","snapshot");
    fs.copyFileSync(path.join(repo, compiler), path.join(source, compiler));
    write(material,3);
    config.source.repoRoot = source;
    const selected = filterFiles([...required,recipe],config);
    expect(selected.included.map(entry=>entry.path).sort()).toEqual([...required,recipe].sort());
    for (const mode of ["worktree","git-tag"] as const) {
      config.source.mode = mode;
      config.source.tag = "snapshot";
      const result = await pack(selected,config,{dryRun:false,outputDir:out,clean:true});
      expect(result.errors).toEqual([]);
      const actual = read(out,catalog);
      expect(actual.recipes[product].materials[0].value).toBe(mode==="git-tag" ? 2 : 3);
      expect(read(out,receipt).outputSha256).toBe(createHash("sha256").update(fs.readFileSync(path.join(out,catalog))).digest("hex"));
      expect(read(out,receipt).sourceFiles[recipe]).toBe(createHash("sha256").update(fs.readFileSync(path.join(out,recipe))).digest("hex"));
      expect(read(out,archive).items).toEqual(JSON.parse(current.archive).items);
    }
    config.source.mode = "worktree";
    write("unknown-test-material",4);
    const failed = await pack(selected,config,{dryRun:false,outputDir:out,clean:true});
    expect(failed.errors.some(entry=>entry.error.includes("test.pack / materials[0]"))).toBe(true);
    expect(fs.existsSync(path.join(out,receipt))).toBe(false);
  } finally { fs.rmSync(scratch,{recursive:true,force:true}); }
}, 120000);
