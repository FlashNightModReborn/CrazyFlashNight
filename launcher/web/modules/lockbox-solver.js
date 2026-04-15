(function(root, factory) {
    if (typeof module === 'object' && module.exports) {
        module.exports = factory(require('./lockbox-core.js'));
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
            exploredStates: 0,
            firstSolveAtPick: null
        };

        function visit(cell, path, buffer, used, prevMainSolved, prevFullSolved) {
            report.exploredStates++;

            var completion = core.evaluateBuffer(buffer, seqA, seqB, seqC);
            var mainSolved = completion.a && completion.b;
            var fullSolved = mainSolved && completion.c;
            var hasMain = mainSolved;
            var hasFull = fullSolved;

            if (mainSolved && !prevMainSolved) {
                report.mainSolutionCount++;
                if (report.minMainLen === null || buffer.length < report.minMainLen) {
                    report.minMainLen = buffer.length;
                    report.mainSolutionCountMinLen = 1;
                    report.canonicalMainPath = path.slice();
                    report.firstSolveAtPick = buffer.length;
                } else if (buffer.length === report.minMainLen) {
                    report.mainSolutionCountMinLen++;
                }
            }

            if (fullSolved && !prevFullSolved) {
                report.fullSolutionCount++;
                if (!report.canonicalFullPath) report.canonicalFullPath = path.slice();
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
                var nextUsed = {};
                for (var key in used) nextUsed[key] = true;
                nextUsed[core.cellKey(nextCell)] = true;
                var nextBuffer = buffer.concat([matrix[nextCell.r][nextCell.c]]);
                var nextPath = path.concat([{ r: nextCell.r, c: nextCell.c }]);
                var child = visit(nextCell, nextPath, nextBuffer, nextUsed, prevMainSolved || mainSolved, prevFullSolved || fullSolved);
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
            var used = {};
            used[core.cellKey(startCell)] = true;
            var outcome = visit(startCell, [startCell], [matrix[0][col]], used, false, false);
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
