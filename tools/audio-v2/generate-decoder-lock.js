'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..', '..');
const outputPath = path.join(repoRoot, 'launcher', 'native', 'decoder-dependencies.lock.v1.json');

const packages = [
  {
    archiveBytes: 679285,
    archiveSha256: 'E347B59C29E8F938BB48B2FDA5DA02F2D5D97316C004ABAA76E171CF4A2FBDD7',
    buildFlags: ['OGG_STATIC', '_CRT_SECURE_NO_WARNINGS'],
    licensePath: 'launcher/native/third_party/libogg-1.3.6/COPYING',
    name: 'libogg',
    sourceKind: 'release_archive',
    sourceUrl: 'https://downloads.xiph.org/releases/ogg/libogg-1.3.6.zip',
    vendorRoots: ['launcher/native/third_party/libogg-1.3.6'],
    version: '1.3.6'
  },
  {
    archiveBytes: 1924556,
    archiveSha256: '57C8BC92D2741934B8DC939AF49C2639EDC44B8879CBA2EC14AD3189E2814582',
    buildFlags: ['_CRT_SECURE_NO_WARNINGS'],
    licensePath: 'launcher/native/third_party/libvorbis-1.3.7/COPYING',
    name: 'libvorbis_libvorbisfile',
    sourceKind: 'release_archive',
    sourceUrl: 'https://downloads.xiph.org/releases/vorbis/libvorbis-1.3.7.zip',
    vendorRoots: ['launcher/native/third_party/libvorbis-1.3.7'],
    version: '1.3.7'
  },
  {
    archiveBytes: null,
    archiveSha256: null,
    buildFlags: [
      'MA_ENABLE_ONLY_SPECIFIC_BACKENDS',
      'MA_ENABLE_WASAPI',
      'MA_ENABLE_DSOUND',
      'MA_ENABLE_WINMM',
      'MA_NO_NULL'
    ],
    licensePath: 'launcher/native/third_party/miniaudio-0.11.25/LICENSE',
    name: 'miniaudio_and_official_decoder_adapters',
    sourceCommit: '9634bedb5b5a2ca38c1ee7108a9358a4e233f14d',
    sourceKind: 'git_tag_and_commit',
    sourceUrl: 'https://github.com/mackron/miniaudio/tree/0.11.25',
    vendorFiles: [
      'launcher/native/miniaudio.h',
      'launcher/native/extras/decoders/libopus/miniaudio_libopus.c',
      'launcher/native/extras/decoders/libopus/miniaudio_libopus.h',
      'launcher/native/extras/decoders/libvorbis/miniaudio_libvorbis.c',
      'launcher/native/extras/decoders/libvorbis/miniaudio_libvorbis.h',
      'launcher/native/third_party/miniaudio-0.11.25/LICENSE'
    ],
    version: '0.11.25'
  },
  {
    archiveBytes: 10472813,
    archiveSha256: '6FFCB593207BE92584DF15B32466ED64BBEC99109F007C82205F0194572411A1',
    buildFlags: [
      'HAVE_LRINT',
      'HAVE_LRINTF',
      'NDEBUG',
      'OPUS_BUILD',
      'USE_ALLOCA',
      '_CRT_SECURE_NO_WARNINGS'
    ],
    licensePath: 'launcher/native/third_party/opus-1.6.1/COPYING',
    name: 'libopus',
    sourceKind: 'release_archive',
    sourceUrl: 'https://downloads.xiph.org/releases/opus/opus-1.6.1.tar.gz',
    vendorRoots: ['launcher/native/third_party/opus-1.6.1'],
    version: '1.6.1'
  },
  {
    archiveBytes: 497931,
    archiveSha256: '7F44575596B78D7787C1865B9653E2A71546FF1AE77D87C53AB16DCC7AF295BA',
    buildFlags: ['NDEBUG', '_CRT_SECURE_NO_WARNINGS'],
    licensePath: 'launcher/native/third_party/opusfile-0.12/COPYING',
    name: 'libopusfile',
    sourceKind: 'release_archive',
    sourceUrl: 'https://downloads.xiph.org/releases/opus/opusfile-0.12.zip',
    vendorRoots: ['launcher/native/third_party/opusfile-0.12'],
    version: '0.12'
  }
];

function toRepoPath(absolutePath) {
  return path.relative(repoRoot, absolutePath).split(path.sep).join('/');
}

function sha256(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex').toUpperCase();
}

function canonicalSourceBytes(bytes, sourcePath) {
  if (bytes.includes(0)) {
    throw new Error(`binary decoder input is forbidden: ${sourcePath}`);
  }
  const text = bytes.toString('utf8');
  if (Buffer.from(text, 'utf8').compare(bytes) !== 0) {
    throw new Error(`decoder input is not valid UTF-8: ${sourcePath}`);
  }
  return Buffer.from(text.replace(/\r\n/g, '\n').replace(/\r/g, '\n'), 'utf8');
}

function collectFiles(entry) {
  const results = [];
  const visit = (absolutePath) => {
    const stat = fs.lstatSync(absolutePath);
    if (stat.isSymbolicLink()) {
      throw new Error(`symbolic links are forbidden in decoder source closure: ${toRepoPath(absolutePath)}`);
    }
    if (stat.isDirectory()) {
      const names = fs.readdirSync(absolutePath).sort((left, right) => left.localeCompare(right, 'en'));
      for (const name of names) {
        visit(path.join(absolutePath, name));
      }
      return;
    }
    if (!stat.isFile()) {
      throw new Error(`unsupported decoder source entry: ${toRepoPath(absolutePath)}`);
    }
    const repoPath = toRepoPath(absolutePath);
    const bytes = canonicalSourceBytes(fs.readFileSync(absolutePath), repoPath);
    results.push({
      bytes: bytes.length,
      path: repoPath,
      sha256: sha256(bytes)
    });
  };

  for (const root of entry.vendorRoots || []) {
    visit(path.join(repoRoot, ...root.split('/')));
  }
  for (const file of entry.vendorFiles || []) {
    visit(path.join(repoRoot, ...file.split('/')));
  }

  const unique = new Map();
  for (const result of results) {
    unique.set(result.path, result);
  }
  return [...unique.values()].sort((left, right) => left.path.localeCompare(right.path, 'en'));
}

function sortObject(value) {
  if (Array.isArray(value)) {
    return value.map(sortObject);
  }
  if (value && typeof value === 'object') {
    const result = {};
    for (const key of Object.keys(value).sort((left, right) => left.localeCompare(right, 'en'))) {
      result[key] = sortObject(value[key]);
    }
    return result;
  }
  return value;
}

function buildLock() {
  return {
    materialization: 'utf8_without_bom_canonical_lf',
    mediaFoundation: {
      allowlistedCodecs: ['aac_lc', 'he_aac'],
      allowlistedContainers: ['adts', 'mpeg4_audio'],
      implementation: 'windows_sdk_source_reader_miniaudio_backend',
      linkLibraries: [
        'mfplat.lib',
        'mfreadwrite.lib',
        'mfuuid.lib',
        'ole32.lib',
        'propsys.lib',
        'shlwapi.lib'
      ],
      looseSidecars: false,
      sdkVersionSource: 'config/build/runtime-toolchain.lock.json'
    },
    packages: packages.map((entry) => ({
      ...entry,
      sourceFiles: collectFiles(entry),
      vendorFiles: undefined,
      vendorRoots: undefined
    })).map((entry) => Object.fromEntries(Object.entries(entry).filter(([, value]) => value !== undefined))),
    schema: 'cf7.audio-v2.decoder-dependencies.lock.v1'
  };
}

function canonicalBytes(value) {
  return `${JSON.stringify(sortObject(value), null, 2)}\n`;
}

function main() {
  const mode = process.argv[2] || '--check';
  if (!['--check', '--print', '--write'].includes(mode) || process.argv.length > 3) {
    throw new Error('usage: node tools/audio-v2/generate-decoder-lock.js [--check|--print|--write]');
  }

  const generated = canonicalBytes(buildLock());
  if (mode === '--print') {
    process.stdout.write(generated);
    return;
  }
  if (mode === '--write') {
    fs.writeFileSync(outputPath, generated, { encoding: 'utf8' });
    process.stdout.write(`wrote ${toRepoPath(outputPath)} sha256=${sha256(Buffer.from(generated, 'utf8'))}\n`);
    return;
  }
  if (!fs.existsSync(outputPath)) {
    throw new Error(`decoder lock is missing: ${toRepoPath(outputPath)}`);
  }
  const actual = fs.readFileSync(outputPath, 'utf8');
  if (actual !== generated) {
    throw new Error(`decoder lock drift: run node tools/audio-v2/generate-decoder-lock.js --write`);
  }
  process.stdout.write(`decoder lock PASS sha256=${sha256(Buffer.from(actual, 'utf8'))}\n`);
}

try {
  main();
} catch (error) {
  process.stderr.write(`[FAIL] ${error.message}\n`);
  process.exitCode = 1;
}
