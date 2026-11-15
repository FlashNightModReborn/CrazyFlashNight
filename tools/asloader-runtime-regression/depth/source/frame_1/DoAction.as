stop();

var host = _root;
var phase = "waiting";
var frameCount = 0;
var nextLayer = 1024;
var observedLayers = 0;
var batchCount = 0;
var checkCount = 0;
var failedChecks = 0;
var fillStart;
var manager;
var keyDriver;
var clockDriver;
var moduleHolder;
var recoveredLayer;
var report = [];

function record(message) {
    report.push(message);
    var receipt = SharedObject.getLocal("cf7_depth_stress_v1");
    receipt.data.result = report.join("\n");
    receipt.flush();
}

function check(name, passed, details) {
    checkCount++;
    if (!passed) failedChecks++;
    record("check " + name + " " + passed + " " + details);
}

function systemClipsSurvive() {
    return host.getInstanceAtDepth(1024) === keyDriver &&
           host.getInstanceAtDepth(1025) === clockDriver &&
           host.getInstanceAtDepth(65531) === moduleHolder;
}

function testMixedChildren() {
    var layer = 2000;
    while (layer < 2016) {
        host.createEmptyMovieClip("named_" + layer, layer);
        layer++;
    }
    host.createEmptyMovieClip("dupe", 2016);
    host.createEmptyMovieClip("dupe", 2017);
    var hidden = host.createEmptyMovieClip("ghost", 2018);
    hidden._visible = false;
    // The same-name scalar masks this real display object during root enumeration.
    host.ghost = 123;
    host.addProperty("ghost", function() { return 123; }, function(value) {});
    _global.ASSetPropFlags(host, ["ghost"], 1, false);
    host.createTextField("textControl", 2019, 0, 0, 20, 20);
    var textControl = host.textControl;
    var ordinary = host.getInstanceAtDepth(2002);
    ordinary.getDepth = function() { return 2020; };
    host.nestedAlias = ordinary.createEmptyMovieClip("inner", 2020);
    host.fakeAlias = {_parent:host, getDepth:function() { return 2020; }};

    var visibleDepths = {};
    var nativeDepth = MovieClip.prototype.getDepth;
    for (var name in host) {
        var value = host[name];
        if (typeof value == "movieclip" && value._parent === host) {
            var actualDepth = nativeDepth.call(value);
            if (actualDepth >= 2000 && actualDepth <= 2020) visibleDepths[actualDepth] = true;
        }
    }

    var nativeLookup = host.getInstanceAtDepth;
    var queries = {};
    host.getInstanceAtDepth = function(depth) {
        queries[depth] = true;
        return nativeLookup.call(host, depth);
    };
    manager.highest = 1999;
    var available = host.getNextHighestDepth();
    delete host.getInstanceAtDepth;
    check("dense_mixed_chooses_only_genuine_hole", available == 2020 &&
          host.getInstanceAtDepth(2020) == undefined && host.getInstanceAtDepth === nativeLookup,
          "returned=" + available);
    var duplicateDetails = "enumerated=" + visibleDepths[2016] + "," + visibleDepths[2017] +
                           " queried=" + queries[2016] + "," + queries[2017];
    check("duplicate_clips_still_at_separate_depths", nativeDepth.call(host.getInstanceAtDepth(2016)) == 2016 &&
          nativeDepth.call(host.getInstanceAtDepth(2017)) == 2017 &&
          (visibleDepths[2016] != true || visibleDepths[2017] != true), duplicateDetails);
    check("cache_skips_only_known_duplicate", (visibleDepths[2016] == true && queries[2016] != true) ||
          (visibleDepths[2017] == true && queries[2017] != true), duplicateDetails);
    check("unseen_duplicate_checked_natively", (visibleDepths[2016] == true || queries[2016] == true) &&
          (visibleDepths[2017] == true || queries[2017] == true), duplicateDetails);
    check("hidden_and_text_preserved", nativeDepth.call(host.getInstanceAtDepth(2018)) == 2018 &&
          host.getInstanceAtDepth(2019) === textControl && queries[2019] == true,
          "textType=" + typeof textControl + " queried=" + queries[2019]);
    check("hidden_clip_checked_natively", visibleDepths[2018] != true && queries[2018] == true &&
          host.ghost === 123, "enumerated=" + visibleDepths[2018] + " queried=" + queries[2018]);
    check("overridden_and_nested_depth_do_not_hide_hole", ordinary.getDepth() == 2020 &&
          nativeDepth.call(ordinary) == 2002 && host.nestedAlias._parent === ordinary && available == 2020,
          "native=" + nativeDepth.call(ordinary) + " override=" + ordinary.getDepth());

    layer = 2000;
    while (layer < 2020) {
        var child = host.getInstanceAtDepth(layer);
        if (layer == 2019) child.removeTextField();
        else child.removeMovieClip();
        layer++;
    }
    delete host.nestedAlias;
    delete host.fakeAlias;
    manager.highest = 1027;
}

function beginChecks() {
    manager = host.层级管理器;
    keyDriver = host.keyPollMC;
    clockDriver = host._cdWheel;
    moduleHolder = host.__asLoaderCode;
    check("resident_installed_before_real_drivers", systemClipsSurvive() && manager.highest == 1025,
          "key=" + keyDriver.getDepth() + " clock=" + clockDriver.getDepth() + " holder=" + moduleHolder.getDepth());
    var first = host.getNextHighestDepth();
    var second = host.getNextHighestDepth();
    check("adjacent_lookups_without_placement", first == 1026 && second == 1027 &&
          host.getInstanceAtDepth(first) == undefined && host.getInstanceAtDepth(second) == undefined,
          "first=" + first + " second=" + second);

    host.__boot.f2_1();
    check("S1_preserves_manager_and_cursor", host.层级管理器 === manager && manager.highest == second &&
          manager.注释框 == 65533 && manager.mouse == 65535, "cursor=" + manager.highest);
    var next = host.getNextHighestDepth();
    check("first_S1_allocation_continues", next == 1028, "returned=" + next);

    manager.highest = 32766;
    var last = host.getNextHighestDepth();
    var wrapped = host.getNextHighestDepth();
    var adjacent = host.getNextHighestDepth();
    check("wrap_skips_live_drivers", last == 32767 && wrapped == 1026 && adjacent == 1027 && systemClipsSurvive(),
          "last=" + last + " firstFree=" + wrapped + " next=" + adjacent);
    testMixedChildren();
    fillStart = getTimer();
    phase = "fill";
}

function fillBatch() {
    var end = Math.min(nextLayer + 512, 32768);
    while (nextLayer < end) {
        var child;
        if (nextLayer == 1024) child = keyDriver;
        else if (nextLayer == 1025) child = clockDriver;
        else child = host.createEmptyMovieClip("occupied_" + nextLayer, nextLayer);
        if (child.getDepth() == nextLayer) observedLayers++;
        nextLayer++;
    }
    batchCount++;
    if (batchCount % 16 == 0) record("progress layers=" + observedLayers);
    if (nextLayer == 32768) phase = "full";
}

function testFullRange() {
    check("all_actual_slots_occupied", observedLayers == 31744,
          "count=" + observedLayers + " batches=" + batchCount + " fillMs=" + (getTimer() - fillStart));
    var errorMessage = "";
    var before = manager.highest;
    var started = getTimer();
    try {
        host.getNextHighestDepth();
    } catch (failure) {
        errorMessage = failure.message;
    }
    check("full_range_raises_without_moving_cursor", errorMessage == "No free dynamic root depth (1024..32767)" &&
          manager.highest == before, "elapsedMs=" + (getTimer() - started) + " error=" + errorMessage);
    phase = "release";
}

function finish() {
    record("DEPTH_STRESS complete passed=" + (checkCount - failedChecks) + " total=" + checkCount);
    phase = "done";
}

function runFrame() {
    frameCount++;
    if (phase == "waiting") {
        var boot = _global.org.flashNight.boot.BootSequencer;
        if (typeof boot == "function") {
            phase = "hooked";
            boot.run = function(definitions) { beginChecks(); };
        }
    } else if (phase == "fill") {
        fillBatch();
    } else if (phase == "full") {
        testFullRange();
    } else if (phase == "release") {
        var occupied = host.getInstanceAtDepth(1040);
        check("sole_hole_previously_exists", occupied.getDepth() == 1040, "depth=" + occupied.getDepth());
        occupied.removeMovieClip();
        phase = "reuse";
    } else if (phase == "reuse") {
        var empty = host.getInstanceAtDepth(1040) == undefined;
        check("sole_hole_is_empty_next_frame", empty, "depth=1040");
        if (!empty) { finish(); return; }
        var started = getTimer();
        recoveredLayer = host.getNextHighestDepth();
        check("released_slot_recovered", recoveredLayer == 1040 && host.getInstanceAtDepth(32767) != undefined,
              "returned=" + recoveredLayer + " elapsedMs=" + (getTimer() - started));
        check("system_clips_survive_exhaustion", systemClipsSurvive(), "holder=" + moduleHolder.getDepth());
        phase = "repeat";
    } else if (phase == "repeat") {
        var repeatedAt = getTimer();
        var same = host.getNextHighestDepth();
        check("sole_unfilled_slot_can_be_returned_twice", recoveredLayer == 1040 && same == 1040,
              "first=" + recoveredLayer + " second=" + same + " elapsedMs=" + (getTimer() - repeatedAt));
        finish();
    } else if (phase == "done") {
        fscommand("quit");
    }
    if ((phase == "waiting" || phase == "hooked") && frameCount > 200) {
        check("production_boot_registration", false, "phase=" + phase);
        finish();
    }
}

record("DEPTH_STRESS begin");
runFrame();
host.onEnterFrame = function() {
    try {
        runFrame();
    } catch (failure) {
        check("unexpected_fixture_error", false, String(failure));
        finish();
    }
};
