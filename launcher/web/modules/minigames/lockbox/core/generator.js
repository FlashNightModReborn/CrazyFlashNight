(function(root, factory) {
    if (typeof module === 'object' && module.exports) {
        module.exports = factory(
            require('./index.js'),
            require('./solver.js')
        );
    } else {
        root.LockboxGenerator = factory(root.LockboxCore, root.LockboxSolver);
    }
})(typeof self !== 'undefined' ? self : this, function(core, solver) {
    'use strict';

    function nextAxisHasBranch(path, size, mainLen) {
        if (mainLen >= path.length) return true;
        var cell = path[mainLen - 1];
        var used = {};
        for (var i = 0; i < mainLen; i++) used[core.cellKey(path[i])] = true;
        var axis = core.nextAxisAfterPickCount(mainLen);
        var legal = core.getLegalCells(size, cell, axis);
        var count = 0;
        for (i = 0; i < legal.length; i++) {
            if (!used[core.cellKey(legal[i])]) count++;
        }
        return count >= 2;
    }

    function sequenceConstraintsOk(config, fullString, seqs) {
        var freq = core.countFrequencies(fullString);
        var maxFreq = Math.ceil(config.bufferCap / 2);
        var key;
        for (key in freq) {
            if (freq[key] > maxFreq) return false;
        }

        for (var i = 2; i < fullString.length; i++) {
            if (fullString[i] === fullString[i - 1] && fullString[i] === fullString[i - 2]) return false;
        }

        if (core.arrayEquals(seqs.seqA, seqs.seqB)) return false;
        if (core.arrayEquals(seqs.seqA, seqs.seqC)) return false;
        if (core.arrayEquals(seqs.seqB, seqs.seqC)) return false;

        if (config.bufferCap > seqs.mainLen) {
            var prefix = fullString.slice(0, seqs.mainLen);
            if (core.bufferContainsSequence(prefix, seqs.seqC)) return false;
        }

        return true;
    }

    function generateFullString(config, rng) {
        var length = config.bufferCap;
        var limit = Math.ceil(length / 2);

        for (var attempt = 0; attempt < 120; attempt++) {
            var values = [];
            var counts = {};
            for (var i = 0; i < length; i++) {
                var pool = [];
                for (var token = 0; token < config.alphabetSize; token++) {
                    if ((counts[token] || 0) >= limit) continue;
                    if (i >= 2 && values[i - 1] === token && values[i - 2] === token) continue;
                    pool.push(token);
                }
                if (!pool.length) break;
                var picked = rng.pick(pool);
                values.push(picked);
                counts[picked] = (counts[picked] || 0) + 1;
            }
            if (values.length !== length) continue;
            if (core.uniq(values).length < Math.min(config.alphabetSize, 3)) continue;
            return values;
        }

        throw new Error('generateFullString failed');
    }

    function generateAxisPath(config, mainLen, rng) {
        for (var retry = 0; retry < 220; retry++) {
            var used = {};
            var path = [];
            var cell = { r: 0, c: rng.int(0, config.size - 1) };
            path.push(cell);
            used[core.cellKey(cell)] = true;

            while (path.length < config.bufferCap) {
                var axis = core.nextAxisAfterPickCount(path.length);
                var legal = core.getLegalCells(config.size, cell, axis);
                var candidates = [];
                for (var i = 0; i < legal.length; i++) {
                    if (!used[core.cellKey(legal[i])]) candidates.push(legal[i]);
                }
                if (!candidates.length) break;

                candidates = rng.shuffle(candidates).sort(function(a, b) {
                    return futureDegree(config.size, used, a, path.length + 1) - futureDegree(config.size, used, b, path.length + 1);
                });

                cell = candidates[candidates.length - 1];
                path.push(cell);
                used[core.cellKey(cell)] = true;
            }

            if (path.length !== config.bufferCap) continue;
            if (config.bufferCap > mainLen && !nextAxisHasBranch(path, config.size, mainLen)) continue;
            return path;
        }

        return null;
    }

    function futureDegree(size, used, cell, nextPickCount) {
        var axis = core.nextAxisAfterPickCount(nextPickCount);
        var legal = core.getLegalCells(size, cell, axis);
        var count = 0;
        for (var i = 0; i < legal.length; i++) {
            if (!used[core.cellKey(legal[i])]) count++;
        }
        return count;
    }

    function fillNearMissDecoys(matrix, path, fullString, config, rng) {
        var used = {};
        for (var i = 0; i < path.length; i++) used[core.cellKey(path[i])] = true;

        for (i = 0; i < path.length - 1; i++) {
            var cell = path[i];
            var axis = core.nextAxisAfterPickCount(i + 1);
            var legal = core.getLegalCells(config.size, cell, axis);
            var candidates = [];
            for (var j = 0; j < legal.length; j++) {
                if (!used[core.cellKey(legal[j])] && matrix[legal[j].r][legal[j].c] === null) candidates.push(legal[j]);
            }

            candidates = rng.shuffle(candidates);
            var take = Math.min(candidates.length, rng.int(1, Math.min(2, candidates.length || 1)));
            for (j = 0; j < take; j++) {
                var tokenPool = [
                    fullString[i],
                    fullString[Math.min(fullString.length - 1, i + 1)],
                    fullString[Math.max(0, i - 1)]
                ];
                matrix[candidates[j].r][candidates[j].c] = rng.pick(tokenPool);
            }
        }
    }

    function fillRemainingCells(matrix, config, rng) {
        for (var r = 0; r < config.size; r++) {
            for (var c = 0; c < config.size; c++) {
                if (matrix[r][c] === null) matrix[r][c] = rng.int(0, config.alphabetSize - 1);
            }
        }
    }

    function assemblePuzzle(config, familySeed, variantIndex, attempt, fullString, seqs, path, matrix, report) {
        return {
            config: core.clone(config),
            puzzle: {
                profile: config.id,
                matrix: matrix,
                seqA: seqs.seqA,
                seqB: seqs.seqB,
                seqC: seqs.seqC,
                fullString: fullString,
                canonicalPath: path,
                familySeed: familySeed >>> 0,
                variantIndex: variantIndex | 0,
                attemptCount: attempt,
                accepted: true
            },
            report: report
        };
    }

    function withinBand(value, range) {
        return value >= range[0] && value <= range[1];
    }

    function acceptPuzzle(config, seqs, report) {
        if (!report || !report.mainSolutionCount) return false;
        if (!report.fullSolutionCount) return false;
        if (report.minMainLen !== config.mainMinLen) return false;
        if (!withinBand(report.mainSolutionCountMinLen, config.targetMainMinSolutions)) return false;
        if (!withinBand(report.entryStartCount, config.targetEntryStarts)) return false;
        if (!withinBand(report.fullSolutionCount, config.targetFullSolutions)) return false;
        if (report.bonusShare < config.targetBonusShare[0] || report.bonusShare > config.targetBonusShare[1]) return false;
        if (config.bufferCap > seqs.mainLen && report.canonicalFullPath && report.minMainLen >= config.bufferCap) return false;
        return true;
    }

    function generatePuzzle(profileId, familySeed, variantIndex, options) {
        options = options || {};
        var config = typeof profileId === 'string' ? core.getProfile(profileId) : core.clone(profileId);
        var baseSeed = core.mixSeed(familySeed >>> 0, core.mixSeed((variantIndex | 0) + 1, config.bufferCap));
        var maxAttempts = options.maxAttempts || 240;
        var fallback = null;

        for (var attempt = 1; attempt <= maxAttempts; attempt++) {
            var rng = new core.RNG(core.mixSeed(baseSeed, attempt));
            var fullString = generateFullString(config, rng);
            var seqs = core.deriveSequencesFromF(config, fullString);
            if (!sequenceConstraintsOk(config, fullString, seqs)) continue;

            var path = generateAxisPath(config, seqs.mainLen, rng);
            if (!path) continue;

            var matrix = core.createMatrix(config.size, null);
            for (var i = 0; i < path.length; i++) {
                matrix[path[i].r][path[i].c] = fullString[i];
            }

            fillNearMissDecoys(matrix, path, fullString, config, rng);
            fillRemainingCells(matrix, config, rng);

            var report = solver.solvePuzzle(config, matrix, seqs.seqA, seqs.seqB, seqs.seqC);
            var assembled = assemblePuzzle(config, familySeed, variantIndex, attempt, fullString, seqs, path, matrix, report);

            if (!fallback || report.difficultyScore > fallback.report.difficultyScore) fallback = assembled;
            if (acceptPuzzle(config, seqs, report)) return assembled;
        }

        if (fallback) {
            fallback.puzzle.accepted = false;
            return fallback;
        }
        throw new Error('generatePuzzle failed for profile=' + config.id);
    }

    function bakeVariantPool(profileIds, familiesPerProfile, variantsPerFamily) {
        profileIds = profileIds && profileIds.length ? profileIds : ['standard', 'elite6', 'elite7'];
        familiesPerProfile = familiesPerProfile || 1;
        variantsPerFamily = variantsPerFamily || 3;

        var output = {
            generatedAt: new Date().toISOString(),
            variantPool: []
        };

        for (var p = 0; p < profileIds.length; p++) {
            for (var family = 0; family < familiesPerProfile; family++) {
                var familySeed = core.mixSeed(0x4c4f434b + p * 97, family + 1);
                for (var variant = 0; variant < variantsPerFamily; variant++) {
                    var baked = generatePuzzle(profileIds[p], familySeed, variant, { maxAttempts: 320 });
                    output.variantPool.push({
                        familySeed: familySeed >>> 0,
                        variantIndex: variant,
                        tier: profileIds[p],
                        puzzle: baked.puzzle,
                        config: baked.config,
                        report: baked.report
                    });
                }
            }
        }

        return output;
    }

    return {
        generatePuzzle: generatePuzzle,
        bakeVariantPool: bakeVariantPool
    };
});
