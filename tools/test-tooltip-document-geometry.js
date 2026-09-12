#!/usr/bin/env node
'use strict';
/*
 * test-tooltip-document-geometry — 薄入口：调用
 * launcher/perf/tooltip-document-geometry/runner.js（Playwright + 真实 DOM）。
 *
 * 用法：
 *   node tools/test-tooltip-document-geometry.js [--corpus <json>] [--limit N]
 *       [--out <dir>] [--shots N]
 * 退出码透传 runner：0 全过 / 1 有断言失败 / 2 环境缺失（SKIP）。
 */
require('../launcher/perf/tooltip-document-geometry/runner.js');
