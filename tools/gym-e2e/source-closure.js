'use strict';

const path = require('path');
const Evidence = require('../workbench-live-e2e/lib/evidence-artifact');

const SOURCE_FILES = Object.freeze([
    ['candidate_start','automation/start.ps1'],
    ['host_opener','launcher/src/Tasks/AgentControlTask.cs'],
    ['host_wiring','launcher/src/Program.cs'],
    ['host_route','launcher/src/Guardian/LauncherCommandRouter.cs'],
    ['host_open_contract','launcher/src/Tasks/GymPreviewOpenData.cs'],
    ['host_session','launcher/src/Tasks/GymTrainingTask.cs'],
    ['as2_open','scripts/类定义/org/flashNight/arki/ui/GymPreviewPanelService.as'],
    ['as2_session','scripts/类定义/org/flashNight/arki/ui/GymTrainingPanelService.as'],
    ['as2_projection','scripts/类定义/org/flashNight/arki/ui/GymPreviewProjection.as'],
    ['as2_publish','scripts/asLoader.swf'],
    ['flash_gym_scene','flashswf/levels/基地场景合集.swf'],
    ['web_registry','launcher/web/modules/panels-lazy-registry.js'],
    ['web_panel','launcher/web/modules/gym/gym-panel.js'],
    ['web_motion','launcher/web/modules/gym/gym-motion-renderer.js'],
    ['web_bridge','launcher/web/modules/bridge.js'],
    ['web_panels','launcher/web/modules/panels.js'],
    ['runner','tools/gym-e2e/run-candidate.js'],
    ['preflight','tools/gym-e2e/preflight.js'],
    ['ledger','tools/gym-e2e/ledger.js'],
    ['input','tools/gym-e2e/cdp-input-channel.js'],
    ['observer','tools/gym-e2e/passive-observer.js'],
    ['closure','tools/gym-e2e/source-closure.js'],
    ['shared_runtime_guard','tools/workbench-live-e2e/lib/runtime-guard.js'],
    ['shared_launcher_observation','tools/workbench-live-e2e/lib/launcher-observation.js'],
    ['shared_clone_guard','tools/workbench-live-e2e/lib/clone-save-guard.js'],
    ['shared_evidence','tools/workbench-live-e2e/lib/evidence-artifact.js'],
    ['shared_generic_opener','tools/workbench-live-e2e/kshop/generic-opener.js'],
    ['shared_cdp','tools/workbench-live-e2e/kshop/cdp-client.js'],
    ['shared_common','tools/workbench-live-e2e/kshop/common.js']
]);

const REQUIRED_SOURCE_MARKERS = Object.freeze({
    'automation/start.ps1':[
        'function Get-Cf7Sha256',
        '[Security.Cryptography.SHA256]::Create()',
        'Get-Cf7RuntimeManifestIdentity'
    ],
    'launcher/src/Tasks/AgentControlTask.cs':[
        'case "openGym"', 'OpenAgentPanel(msg, "gym")', 'IsAgentAutomationSlot(expectedSlot)'
    ],
    'launcher/src/Program.cs':[
        'SetGymOpenAction', 'openGymForAgent', 'SetGymTrainingTask'
    ],
    'launcher/src/Guardian/LauncherCommandRouter.cs':[
        'GymPreviewOpenData.Build', 'OpenPanel("gym"'
    ],
    'launcher/src/Tasks/GymTrainingTask.cs':[
        'gymFinish', 'needs_reconcile', 'saved'
    ],
    'scripts/类定义/org/flashNight/arki/ui/GymPreviewPanelService.as':[
        'openGymForAgent', 'openGymPreview', '"world_gym"'
    ],
    'scripts/类定义/org/flashNight/arki/ui/GymTrainingPanelService.as':[
        'flushDurableNow("ui.gym_training_paid")',
        '存档系统.markDirty()', '"gym_training_response"'
    ],
    'launcher/web/modules/gym/gym-panel.js':[
        "requestGym('start'", "requestGym('cancel'", "startButton.addEventListener('click'"
    ],
    'launcher/web/modules/panels-lazy-registry.js':[
        "Panels.registerLazy('gym'", 'modules/gym/gym-panel.js'
    ]
});

const FORBIDDEN_ACTIVE_INPUT = [
    /\bBridge\s*\.\s*send\s*\(/,
    /\bPanels\s*\.\s*open\s*\(/,
    /\b(?:window|document)\s*\.\s*dispatchEvent\s*\(/,
    /\b(?:element|button)\s*\.\s*click\s*\(/
];

function capture(root) {
    const repo = Evidence.assertExactDirectory(path.resolve(root), 'gym_source_closure');
    const files = SOURCE_FILES.map(([role, relativePath]) => {
        const fullPath = path.join(repo, ...relativePath.split('/'));
        const file = Evidence.readExactRegularFile(fullPath, {
            phase:'gym_source_closure', maximumBytes:64 * 1024 * 1024
        });
        if (REQUIRED_SOURCE_MARKERS[relativePath]) {
            const source = file.bytes.toString('utf8').replace(/^\uFEFF/, '');
            const absent = REQUIRED_SOURCE_MARKERS[relativePath]
                .filter(marker => !source.includes(marker));
            if (absent.length) throw new Error('gym source marker missing: '
                + relativePath + ' / ' + absent.join(', '));
        }
        return { role, relativePath, bytes:file.length, sha256:file.sha256 };
    });
    const inputPath = path.join(repo, 'tools', 'gym-e2e', 'cdp-input-channel.js');
    const runnerPath = path.join(repo, 'tools', 'gym-e2e', 'run-candidate.js');
    for (const filePath of [inputPath, runnerPath]) {
        const source = Evidence.readExactRegularFile(filePath, {
            phase:'gym_source_closure', maximumBytes:1024 * 1024
        }).bytes.toString('utf8');
        for (const pattern of FORBIDDEN_ACTIVE_INPUT) {
            if (pattern.test(source)) {
                throw new Error('gym runner/input contains a direct application action: '
                    + path.basename(filePath));
            }
        }
    }
    const value = { schema:'cf7-gym-e2e.source-closure.v1', files,
        directApplicationMutationAbsent:true };
    value.closureSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
    return value;
}

function assertUnchanged(before, after) {
    if (!before || !after || before.closureSha256 !== after.closureSha256
            || Evidence.canonicalJson(before.files) !== Evidence.canonicalJson(after.files)) {
        throw new Error('gym source closure changed during candidate journey');
    }
    return true;
}

module.exports = { SOURCE_FILES, REQUIRED_SOURCE_MARKERS, capture, assertUnchanged };
