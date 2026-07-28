/* Transactional slot switching while the embedded tuning subview owns the right pane. */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.CharacterBuildSlotTransition = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function resumeAfterDetach(controller, selection, generation, instance) {
        Promise.resolve().then(function() {
            if (generation !== controller._mountGeneration
                    || instance !== controller._panelInstanceId
                    || !controller._view
                    || controller._tuning && controller._tuning.isActive()) {
                return;
            }
            controller._view.restoreSlot(selection.key);
        });
    }

    function handle(controller, selection, target, tuningModule) {
        if (!controller._tuning || !controller._tuning.isActive()) return null;
        var item = target && target.kind === 'equipment' && controller._snapshotPayload
            ? tuningModule.findLoadoutItem(
                controller._snapshotPayload,
                target.slotKey)
            : null;
        var capability = tuningModule.tuningCapability(item);
        if (!capability.available) {
            var generation = controller._mountGeneration;
            var instance = controller._panelInstanceId;
            var returned = false, settled = false, detachSucceeded = false;
            var exitStarted = controller._tuning.exit(function(detached) {
                settled = true;
                detachSucceeded = !!detached;
                if (detached) {
                    resumeAfterDetach(
                        controller,
                        selection,
                        generation,
                        instance);
                } else if (returned
                        && generation === controller._mountGeneration
                        && instance === controller._panelInstanceId
                        && controller._view
                        && controller._view.setSlotTransitionFailure) {
                    controller._view.setSlotTransitionFailure();
                }
            }, {restore:false});
            returned = true;
            return exitStarted === false || settled && !detachSucceeded
                ? false : {deferSelection:true};
        }
        if (!controller._tuning.selectSlot(
                target.slotKey,
                item,
                selection && selection.key)) {
            if (controller._ports.toast) {
                controller._ports.toast(
                    '当前调制仍在读取或同步；完成后才能切换装备。');
            }
            return false;
        }
        // Candidate data is not needed behind the hidden tuning face. Defer that independent
        // read until exit: attempting it after the tuning source has already moved would create
        // a two-step half-commit if transport admission changed between the two operations.
        return {deferCandidates:true};
    }

    return {handle:handle};
});
