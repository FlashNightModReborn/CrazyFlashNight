'use strict';
// Read-only attachment to the runner's already authenticated, exact runtime.
// This module owns no input channel, lifecycle action, credentials, or polling loop.
const Preflight=require('./preflight');
const Affiliated=require('./affiliated-slot');

async function snapshot({runtime,admission=null}) {
    if(!runtime?.session||typeof runtime.session.verifyRuntimeIdentity!=='function'
            ||typeof runtime.session.agentControl!=='function'||!runtime.expectedIdentity
            ||runtime.identity?.runtimeMode!=='candidate'||!Number.isInteger(runtime.identity.pid)
            ||!runtime.ready?.expectedAttemptId)throw Error('manual observation requires an existing exact candidate session');
    if(admission)Affiliated.assertCollateral(runtime.collateralBefore,runtime.collateralBefore,admission);
    const verify=()=>{
        const identity=runtime.session.verifyRuntimeIdentity(runtime.expectedIdentity);
        if(identity.pid!==runtime.identity.pid||identity.httpPort!==runtime.identity.httpPort)
            throw Error('manual observation runtime identity changed');
        return identity;
    };
    verify();
    const status=await runtime.session.agentControl('status');
    const identity=verify();
    const attempt=runtime.ready.expectedAttemptId;
    if(status?.success!==true||status.save?.slot!==Preflight.TARGET_SLOT||status.save?.attemptId!==attempt
            ||status.saveRuntime?.attemptId!==attempt||status.gameEnteredAttemptId!==attempt)
        throw Error('manual observation launch slot or attempt changed');
    const slot=status.saveRuntime.savePath;
    if(slot!==Preflight.TARGET_SLOT&&slot!==admission?.slot)throw Error('manual observation runtime slot is not admitted');
    return {schema:'cf7-cf6-e2e.manual-observation.v1',observedAt:new Date().toISOString(),identity,
        originSlot:Preflight.TARGET_SLOT,observedRuntimeSlot:slot,attemptId:attempt,
        hostReportedRuntimeReady:status.readyForRuntimeAutomation===true,
        activePanel:typeof status.activePanel?.name==='string'?status.activePanel.name:null,
        gameplay:{foreground:'unknown',paused:'unknown',map:'unknown',health:'unknown',keysHeld:'unknown'},
        inputSent:false,physicalInputAttestation:false};
}
module.exports={snapshot};
