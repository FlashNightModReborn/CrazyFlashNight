'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..', '..');
const nativeRoot = path.join(repoRoot, 'launcher', 'native');
const decoderLockPath = path.join(nativeRoot, 'decoder-dependencies.lock.v1.json');
const outputPath = path.join(nativeRoot, 'audio-v2-build-inputs.v1.json');

const vorbisSources = [
  'analysis.c',
  'bitrate.c',
  'block.c',
  'codebook.c',
  'envelope.c',
  'floor0.c',
  'floor1.c',
  'info.c',
  'lookup.c',
  'lpc.c',
  'lsp.c',
  'mapping0.c',
  'mdct.c',
  'psy.c',
  'registry.c',
  'res0.c',
  'sharedbook.c',
  'smallft.c',
  'synthesis.c',
  'window.c',
  'vorbisfile.c'
];

function toNativePath(relativePath) {
  return relativePath.split(path.sep).join('/');
}

function sha256(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex').toUpperCase();
}

function parseMakeVariable(filePath, variableName) {
  const lines = fs.readFileSync(filePath, 'utf8').replace(/\r\n/g, '\n').split('\n');
  const result = [];
  let collecting = false;
  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!collecting) {
      const match = line.match(new RegExp(`^${variableName}\\s*=\\s*(.*)$`));
      if (!match) {
        continue;
      }
      collecting = true;
      const value = match[1].replace(/\\$/, '').trim();
      if (value) {
        result.push(...value.split(/\s+/));
      }
      if (!match[1].endsWith('\\')) {
        break;
      }
      continue;
    }
    const value = line.replace(/\\$/, '').trim();
    if (value) {
      result.push(...value.split(/\s+/));
    }
    if (!line.endsWith('\\')) {
      break;
    }
  }
  if (result.length === 0) {
    throw new Error(`make variable ${variableName} is missing or empty in ${filePath}`);
  }
  return result;
}

function compileEntry(sourcePath) {
  return {
    language: sourcePath.endsWith('.cpp') ? 'cpp17' : 'c17',
    path: toNativePath(sourcePath)
  };
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

function buildInputs() {
  const opusRoot = path.join(nativeRoot, 'third_party', 'opus-1.6.1');
  const opusSources = [
    ...parseMakeVariable(path.join(opusRoot, 'opus_sources.mk'), 'OPUS_SOURCES'),
    ...parseMakeVariable(path.join(opusRoot, 'opus_sources.mk'), 'OPUS_SOURCES_FLOAT'),
    ...parseMakeVariable(path.join(opusRoot, 'silk_sources.mk'), 'SILK_SOURCES'),
    ...parseMakeVariable(path.join(opusRoot, 'silk_sources.mk'), 'SILK_SOURCES_FLOAT'),
    ...parseMakeVariable(path.join(opusRoot, 'celt_sources.mk'), 'CELT_SOURCES')
  ].map((source) => `third_party/opus-1.6.1/${source}`);

  const sources = [
    'miniaudio.c',
    'extras/decoders/libvorbis/miniaudio_libvorbis.c',
    'extras/decoders/libopus/miniaudio_libopus.c',
    'third_party/libogg-1.3.6/src/bitwise.c',
    'third_party/libogg-1.3.6/src/framing.c',
    ...vorbisSources.map((source) => `third_party/libvorbis-1.3.7/lib/${source}`),
    ...opusSources,
    'third_party/opusfile-0.12/src/info.c',
    'third_party/opusfile-0.12/src/internal.c',
    'third_party/opusfile-0.12/src/opusfile.c',
    'third_party/opusfile-0.12/src/stream.c',
    'audio_mf_decoder.cpp',
    'audio_decoder_registry.c',
    'audio_backend_policy.c',
    'audio_bridge_support.c',
    'miniaudio_bridge.c'
  ];

  const uniqueSources = [...new Set(sources)];
  if (uniqueSources.length !== sources.length) {
    throw new Error('duplicate compile source in generated Audio v2 build inputs');
  }
  for (const source of uniqueSources) {
    if (!fs.statSync(path.join(nativeRoot, ...source.split('/'))).isFile()) {
      throw new Error(`compile source is missing: launcher/native/${source}`);
    }
  }

  const lock = JSON.parse(fs.readFileSync(decoderLockPath, 'utf8'));
  const thirdPartyInputs = lock.packages
    .flatMap((entry) => entry.sourceFiles.map((source) => source.path))
    .map((sourcePath) => sourcePath.replace(/^launcher\/native\//, ''));
  const firstPartyInputs = [
    'audio-v2-build-inputs.v1.json',
    'audio_bridge_v2.h',
    'audio_bridge_support.c',
    'audio_bridge_support.h',
    'audio_backend_policy.c',
    'audio_backend_policy.h',
    'audio_decoder_registry.c',
    'audio_decoder_registry.h',
    'audio_mf_decoder.cpp',
    'audio_mf_decoder.h',
    'audio_miniaudio_config.h',
    'build-audio-v2.ps1',
    'decoder-dependencies.lock.v1.json',
    'miniaudio.c',
    'miniaudio_bridge.c'
  ];

  return {
    compileDefinitions: [
      'HAVE_LRINT',
      'HAVE_LRINTF',
      'NDEBUG',
      'OGG_STATIC',
      'OPUS_BUILD',
      'USE_ALLOCA',
      '_CRT_SECURE_NO_WARNINGS'
    ],
    compileSources: uniqueSources.map(compileEntry),
    decoderLock: {
      path: 'decoder-dependencies.lock.v1.json',
      sha256: sha256(fs.readFileSync(decoderLockPath))
    },
    forceInclude: 'audio_miniaudio_config.h',
    includeDirectories: [
      '.',
      'third_party/opus-1.6.1/include',
      'third_party/opus-1.6.1/src',
      'third_party/opus-1.6.1/celt',
      'third_party/opus-1.6.1/silk',
      'third_party/opus-1.6.1/silk/float',
      'third_party/opusfile-0.12/include',
      'third_party/opusfile-0.12/src',
      'third_party/libogg-1.3.6/include',
      'third_party/libvorbis-1.3.7/include',
      'third_party/libvorbis-1.3.7/lib'
    ],
    linkLibraries: [
      'bcrypt.lib',
      'mfplat.lib',
      'mfreadwrite.lib',
      'mfuuid.lib',
      'ole32.lib',
      'propsys.lib',
      'shlwapi.lib'
    ],
    materializedInputs: [...new Set([...firstPartyInputs, ...thirdPartyInputs])]
      .sort((left, right) => left.localeCompare(right, 'en')),
    output: 'miniaudio.dll',
    schema: 'cf7.audio-v2.native-build-inputs.v1'
  };
}

function canonicalBytes(value) {
  return `${JSON.stringify(sortObject(value), null, 2)}\n`;
}

function main() {
  const mode = process.argv[2] || '--check';
  if (!['--check', '--print', '--write'].includes(mode) || process.argv.length > 3) {
    throw new Error('usage: node tools/audio-v2/generate-native-build-inputs.js [--check|--print|--write]');
  }
  const generated = canonicalBytes(buildInputs());
  if (mode === '--print') {
    process.stdout.write(generated);
    return;
  }
  if (mode === '--write') {
    fs.writeFileSync(outputPath, generated, 'utf8');
    process.stdout.write(`wrote launcher/native/audio-v2-build-inputs.v1.json sha256=${sha256(Buffer.from(generated, 'utf8'))}\n`);
    return;
  }
  if (!fs.existsSync(outputPath) || fs.readFileSync(outputPath, 'utf8') !== generated) {
    throw new Error('Audio v2 build input manifest drift; run this generator with --write');
  }
  process.stdout.write(`Audio v2 build inputs PASS sha256=${sha256(Buffer.from(generated, 'utf8'))}\n`);
}

try {
  main();
} catch (error) {
  process.stderr.write(`[FAIL] ${error.message}\n`);
  process.exitCode = 1;
}
