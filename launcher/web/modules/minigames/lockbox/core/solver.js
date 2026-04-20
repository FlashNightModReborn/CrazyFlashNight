(function(root, factory) {
    if (typeof module === 'object' && module.exports) {
        module.exports = factory(require('./index.js'));
    } else {
        root.LockboxSolver = factory(root.LockboxCore);
    }
})(typeof self !== 'undefined' ? self : this, function(core) {
    'use strict';

    function solvePuzzle(config, matrix, seqA, seqB, seqC) {
        var targetSet = {};
        var i;
        for (i = 0; i < seqA.length; i++) targetSet[seqA[i]] = true;
        for (i = 0; i < seqB.length; i++) targetSet[seqB[i]] = true;
        for (i = 0; i < seqC.length; i++) targetSet[seqC[i]] = true;

        var report = {
            profile: config.id,
            minMainLen: null,
            mainSolutionCountMinLen: 0,
            mainSolutionCount: 0,
            fullSolutionCount: 0,
            entryStartCount: 0,
            totalChoices: 0,
            deadChoices: 0,
            falseObviousChoices: 0,
            deadChoiceRate: 0,
            falseObviousRate: 0,
            bonusShare: 0,
            routeTightness: 0,
            canonicalMainPath: null,
            canonicalFullPath: null,
            mainMinPaths: [],
            exploredStates: 0,
            firstSolveAtPick: null
        };

        var used = {};
        var path = [];
        var buffer = [];

        function clonePath(p) {
            var out = [];
            for (var i = 0; i < p.length; i++) out.push({ r: p[i].r, c: p[i].c });
            return out;
        }

        function recordMainPath(len, p) {
            if (report.minMainLen === null || len < report.minMainLen) {
                report.minMainLen = len;
                report.mainSolutionCountMinLen = 1;
                report.canonicalMainPath = clonePath(p);
                report.mainMinPaths = [clonePath(p)];
                report.firstSolveAtPick = len;
            } else if (len === report.minMainLen) {
                report.mainSolutionCountMinLen++;
                if (report.mainMinPaths.length < 64) report.mainMinPaths.push(clonePath(p));
            }
        }

        function visit(cell, prevMainSolved, prevFullSolved) {
            report.exploredStates++;

            var completion = core.evaluateBuffer(buffer, seqA, seqB, seqC);
            var mainSolved = completion.a && completion.b;
            var fullSolved = mainSolved && completion.c;
            var hasMain = mainSolved;
            var hasFull = fullSolved;

            if (mainSolved && !prevMainSolved) {
                report.mainSolutionCount++;
                recordMainPath(buffer.length, path);
            }

            if (fullSolved && !prevFullSolved) {
                report.fullSolutionCount++;
                if (!report.canonicalFullPath) report.canonicalFullPath = clonePath(path);
            }

            if (buffer.length >= config.bufferCap) {
                return { hasMain: hasMain, hasFull: hasFull };
            }

            var nextAxis = core.nextAxisAfterPickCount(path.length);
            var candidates = core.getLegalCells(config.size, cell, nextAxis);
            var legal = [];
            for (var i = 0; i < candidates.length; i++) {
                if (!used[core.cellKey(candidates[i])]) legal.push(candidates[i]);
            }

            if (!legal.length) return { hasMain: hasMain, hasFull: hasFull };

            var childMainFlags = [];
            for (var j = 0; j < legal.length; j++) {
                var nextCell = legal[j];
                var nextKey = core.cellKey(nextCell);
                used[nextKey] = true;
                path.push({ r: nextCell.r, c: nextCell.c });
                buffer.push(matrix[nextCell.r][nextCell.c]);
                var child = visit(nextCell, prevMainSolved || mainSolved, prevFullSolved || fullSolved);
                buffer.pop();
                path.pop();
                delete used[nextKey];
                childMainFlags.push(child.hasMain);
                if (child.hasMain) hasMain = true;
                if (child.hasFull) hasFull = true;
            }

            report.totalChoices += legal.length;
            for (var c = 0; c < legal.length; c++) {
                if (!childMainFlags[c]) {
                    report.deadChoices++;
                    if (targetSet[matrix[legal[c].r][legal[c].c]]) report.falseObviousChoices++;
                }
            }

            return { hasMain: hasMain, hasFull: hasFull };
        }

        for (var col = 0; col < config.size; col++) {
            var startCell = { r: 0, c: col };
            var startKey = core.cellKey(startCell);
            used = {};
            used[startKey] = true;
            path = [{ r: 0, c: col }];
            buffer = [matrix[0][col]];
            var outcome = visit(startCell, false, false);
            if (outcome.hasMain) report.entryStartCount++;
        }

        report.deadChoiceRate = report.totalChoices ? report.deadChoices / report.totalChoices : 0;
        report.falseObviousRate = report.deadChoices ? report.falseObviousChoices / report.deadChoices : 0;
        report.bonusShare = report.mainSolutionCount ? report.fullSolutionCount / report.mainSolutionCount : 0;
        report.routeTightness = report.minMainLen ? report.minMainLen / config.bufferCap : 1;

        report.difficultyScore =
            28 * report.routeTightness +
            24 * report.deadChoiceRate +
            18 * (1 - Math.min(1, report.mainSolutionCountMinLen / 6)) +
            14 * (1 - Math.min(1, report.entryStartCount / Math.max(1, config.size))) +
            10 * (1 - report.bonusShare) +
            6 * report.falseObviousRate;

        return report;
    }

    return {
        solvePuzzle: solvePuzzle
    };
});
