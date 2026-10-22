'use strict';
const Affiliated = require('./affiliated-slot');

// This boundary is reached only after the production return receipt and the
// stable returned save have been captured. It never retries a business action.
async function observeVerifiedReturn({before, after, slot, originSlot, receipt, input, detach}) {
    if (receipt?.phase !== 'applied' || receipt.activeSlot !== originSlot
            || receipt.result?.runId !== slot || receipt.result.bookId !== 'cf6-sting'
            || receipt.result.sp !== 0) throw Error('exact applied return receipt is required before optional observation');
    const result = Affiliated.assertReturned(before, after, slot);
    const observation = {result, screenshot:null, warnings:[]};
    try { observation.screenshot = await input.screenshot('cf6-returned.png'); }
    catch (error) { observation.warnings.push({phase:'return_screenshot', message:String(error.message || error)}); }
    // A human may have closed the WebView after the confirmed return. Local
    // observer cleanup is optional here; authenticated shutdown/readback and
    // source/collateral/clone verification remain mandatory in the caller.
    try { await detach(); }
    catch (error) { observation.warnings.push({phase:'observer_detach', message:String(error.message || error)}); }
    return observation;
}
module.exports = {observeVerifiedReturn};
