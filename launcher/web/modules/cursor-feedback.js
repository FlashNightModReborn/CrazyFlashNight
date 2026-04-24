var CursorFeedback = (function() {
    var lastState = "";
    var lastActive = null;
    var hoverTarget = null;
    var pressed = false;
    var stateCache = (typeof WeakMap === "function") ? new WeakMap() : null;

    function closestInteractive(node) {
        while (node && node !== document && node.nodeType === 1) {
            if (node.getAttribute("data-cursor-state")) return node;
            if (node.hasAttribute("data-key")) return node;
            var tag = node.tagName ? node.tagName.toLowerCase() : "";
            if (tag === "button" || tag === "a" || tag === "input" || tag === "select" || tag === "textarea") return node;
            if (node.getAttribute("role") === "button") return node;
            node = node.parentElement;
        }
        return null;
    }

    function stateFromTarget(target) {
        if (!target) return "normal";
        var explicit = target.getAttribute("data-cursor-state");
        if (explicit) return explicit;

        if (stateCache && stateCache.has(target)) return stateCache.get(target);

        var cursor = "";
        try { cursor = window.getComputedStyle(target).cursor || ""; } catch(e) {}
        var result;
        switch (cursor) {
            case "grab":
            case "grabbing":
            case "move":
                result = "grab"; break;
            case "crosshair":
                result = "attack"; break;
            case "pointer":
            case "help":
            default:
                result = "hoverGrab"; break;
        }
        if (stateCache) stateCache.set(target, result);
        return result;
    }

    function send(state, active, reason) {
        state = state || "normal";
        active = !!active;
        if (state === lastState && active === lastActive) return;
        lastState = state;
        lastActive = active;
        if (typeof Bridge !== "undefined" && Bridge && typeof Bridge.send === "function") {
            Bridge.send({
                type: "cursorFeedback",
                state: state,
                active: active,
                reason: reason || "event"
            });
        }
    }

    function updateFromEvent(event, reason) {
        hoverTarget = closestInteractive(event ? event.target : null);
        if (!hoverTarget) {
            pressed = false;
            send("normal", false, reason);
            return;
        }

        var state = stateFromTarget(hoverTarget);
        if (pressed && state === "hoverGrab") state = "click";
        send(state, true, reason);
    }

    function reset(reason) {
        hoverTarget = null;
        pressed = false;
        send("normal", false, reason || "reset");
    }

    document.addEventListener("mouseover", function(event) {
        updateFromEvent(event, "mouseover");
    }, true);

    document.addEventListener("mousemove", function(event) {
        var next = closestInteractive(event.target);
        if (next !== hoverTarget) updateFromEvent(event, "mousemove_target");
    }, true);

    document.addEventListener("mouseout", function(event) {
        if (!event.relatedTarget || event.relatedTarget === document || event.relatedTarget === document.documentElement) {
            reset("mouseout_document");
        }
    }, true);

    document.addEventListener("mousedown", function(event) {
        if (event.button !== 0) return;
        pressed = true;
        updateFromEvent(event, "mousedown");
    }, true);

    document.addEventListener("mouseup", function(event) {
        if (event.button !== 0) return;
        pressed = false;
        updateFromEvent(event, "mouseup");
    }, true);

    window.addEventListener("blur", function() { reset("blur"); });
    document.addEventListener("visibilitychange", function() {
        if (document.hidden) reset("hidden");
    });

    return {
        reset: reset
    };
})();
