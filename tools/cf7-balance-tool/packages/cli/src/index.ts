#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

import {
  discoverXmlFiles,
  loadXmlDocument,
  scanProjectFields
} from "@cf7-balance-tool/xml-io";

interface CliOptions {
  attribute?: string;
  file?: string;
  inPlace: boolean;
  output?: string;
  path?: string;
  project?: string;
  value?: string;
}

function main(): void {
  const args = process.argv.slice(2);
  const [group, action] = args;

  if (group === "project" && action === "scan") {
    runProjectScan(args.slice(2));
    return;
  }

  if (group === "project" && action === "fields") {
    runFieldScan(args.slice(2));
    return;
  }

  if (group === "xml" && action === "get") {
    runXmlGet(args.slice(2));
    return;
  }

  if (group === "xml" && action === "set") {
    runXmlSet(args.slice(2));
    return;
  }

  printHelp();
  process.exitCode = 1;
}

function runProjectScan(args: string[]): void {
  const options = parseOptions(args);
  const projectConfigPath = resolveProjectConfigPath(options.project);
  const files = discoverXmlFiles(projectConfigPath);

  emitJson(
    {
      projectConfigPath,
      totals: {
        files: files.length
      },
      files
    },
    options.output
  );
}

function runFieldScan(args: string[]): void {
  const options = parseOptions(args);
  const projectConfigPath = resolveProjectConfigPath(options.project);
  const report = scanProjectFields(projectConfigPath);

  emitJson(report, options.output);
}

function runXmlGet(args: string[]): void {
  const options = parseOptions(args);
  const filePath = resolveRequiredFilePath(options.file);
  const xmlPath = requireOption(options.path, "--path");
  const document = loadXmlDocument(filePath);
  const value = options.attribute
    ? document.getAttribute(xmlPath, options.attribute)
    : document.getNodeText(xmlPath);

  if (value === undefined) {
    throw new Error(`XML value not found: ${xmlPath}`);
  }

  emitJson(
    {
      file: filePath,
      xmlPath,
      attribute: options.attribute ?? null,
      value
    },
    options.output
  );
}

function runXmlSet(args: string[]): void {
  const options = parseOptions(args);
  const filePath = resolveRequiredFilePath(options.file);
  const xmlPath = requireOption(options.path, "--path");
  const nextValue = requireOption(options.value, "--value");
  const document = loadXmlDocument(filePath);

  if (options.attribute) {
    document.setAttribute(xmlPath, options.attribute, nextValue);
  } else {
    document.setNodeText(xmlPath, nextValue);
  }

  const serialized = document.serialize();

  if (options.inPlace) {
    document.save(filePath);
    process.stdout.write(`${filePath}\n`);
    return;
  }

  if (options.output) {
    const outputPath = path.resolve(process.cwd(), options.output);
    fs.mkdirSync(path.dirname(outputPath), { recursive: true });
    fs.writeFileSync(outputPath, serialized, "utf8");
    process.stdout.write(`${outputPath}\n`);
    return;
  }

  process.stdout.write(serialized);
}

function emitJson(payload: unknown, output?: string): void {
  const serialized = JSON.stringify(payload, null, 2);

  if (output) {
    const absoluteOutputPath = path.resolve(process.cwd(), output);
    fs.mkdirSync(path.dirname(absoluteOutputPath), { recursive: true });
    fs.writeFileSync(absoluteOutputPath, serialized, "utf8");
    process.stdout.write(`${absoluteOutputPath}\n`);
    return;
  }

  process.stdout.write(`${serialized}\n`);
}

function parseOptions(args: string[]): CliOptions {
  const options: CliOptions = {
    inPlace: false
  };

  for (let index = 0; index < args.length; index += 1) {
    const current = args[index];
    const next = args[index + 1];

    if ((current === "--attribute" || current === "--attr") && next) {
      options.attribute = next;
      index += 1;
      continue;
    }

    if (current === "--file" && next) {
      options.file = next;
      index += 1;
      continue;
    }

    if (current === "--output" && next) {
      options.output = next;
      index += 1;
      continue;
    }

    if (current === "--path" && next) {
      options.path = next;
      index += 1;
      continue;
    }

    if (current === "--project" && next) {
      options.project = next;
      index += 1;
      continue;
    }

    if (current === "--value" && next) {
      options.value = next;
      index += 1;
      continue;
    }

    if (current === "--in-place") {
      options.inPlace = true;
    }
  }

  return options;
}

function resolveProjectConfigPath(value?: string): string {
  if (value) {
    const directPath = path.resolve(process.cwd(), value);

    if (fs.existsSync(directPath)) {
      return directPath;
    }

    const fallbackFromValue = findProjectConfig(
      path.dirname(directPath),
      path.basename(value)
    );
    if (fallbackFromValue) {
      return fallbackFromValue;
    }

    return directPath;
  }

  const fallback = findProjectConfig(process.cwd(), "project.json");
  return fallback ?? path.resolve(process.cwd(), "project.json");
}

function resolveRequiredFilePath(value?: string): string {
  return path.resolve(process.cwd(), requireOption(value, "--file"));
}

function requireOption(value: string | undefined, flagName: string): string {
  if (!value) {
    throw new Error(`Missing required option: ${flagName}`);
  }

  return value;
}

function findProjectConfig(startDir: string, fileName: string): string | undefined {
  let currentDir = path.resolve(startDir);

  while (true) {
    const candidate = path.join(currentDir, fileName);
    if (fs.existsSync(candidate)) {
      return candidate;
    }

    const parentDir = path.dirname(currentDir);
    if (parentDir === currentDir) {
      return undefined;
    }

    currentDir = parentDir;
  }
}

function printHelp(): void {
  process.stdout.write(
    [
      "CF7 Balance Tool CLI",
      "",
      "Commands:",
      "  project scan [--project <file>] [--output <file>]",
      "  project fields [--project <file>] [--output <file>]",
      "  xml get --file <file> --path <xmlPath> [--attr <name>] [--output <file>]",
      "  xml set --file <file> --path <xmlPath> --value <value> [--attr <name>] [--output <file>] [--in-place]",
      "",
      "Examples:",
      "  npm run project-scan -- --project ./project.json",
      "  npm run field-scan -- --project ./project.json --output ./reports/field-usage-report.json",
      "  tsx packages/cli/src/index.ts xml get --file ../../data/items/武器_手枪_压制机枪.xml --path root.item[1].data.power",
      "  tsx packages/cli/src/index.ts xml set --file ../../data/items/武器_手枪_压制机枪.xml --path root.item[1].data.power --value 55 --output ./reports/sample.xml"
    ].join("\n")
  );
}

main();