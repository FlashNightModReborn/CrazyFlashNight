#!/usr/bin/env node
"use strict";

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const verifier = require("./verify-lockbox-chest-s0-cross-stack.js");

const cases = [];

function test(id, title, run) {
    cases.push({ id, title, run });
}

function event(name, fields) {
    return `00:00:00.000 ${verifier.PREFIX}event=${name} ${fields}`.trimEnd();
}

function armPrefix(cap, flow, request, panel, session, epoch) {
    const ep = String(epoch || 1);
    return [
        event("arm_issued", `gen=1 pid=4242 epoch=${ep} capDigest=${cap}`),
        event("web_armed", `gen=1 pid=4242 epoch=${ep} capDigest=${cap}`),
        event("as2_bootstrap_sent", `gen=1 capDigest=${cap} resumeActive=false`),
        event("as2_bootstrap_ack", `gen=1 pid=4242 epoch=${ep} capDigest=${cap} resumeActive=false`),
        event("begin_received", "origin=trusted_as2_socket gen=1 pid=4242 pauseAcquired=true"),
        event("capability_consumed", `capDigest=${cap}`),
        event("open_reserved", `flowDigest=${flow} requestDigest=${request} panelDigest=${panel} sessionDigest=${session} epoch=${ep}`),
        event("pause_acquire", `delivered=true gen=1 panelDigest=${panel}`),
        event("open_enqueued", `flowDigest=${flow} requestDigest=${request}`)
    ];
}

function boundPrefix(cap, flow, request, panel, session, epoch) {
    return armPrefix(cap, flow, request, panel, session, epoch).concat([
        event("open_execute_recheck", `allowed=true gen=1 pid=4242 epoch=${epoch || 1}`),
        event("panel_post", `delivered=true host=PanelHostController transport=WebView2 panelDigest=${panel}`),
        event("web_bind", `accepted=true panelDigest=${panel}`)
    ]);
}

function freshReady() {
    return event("socket_ready", "gen=1");
}

function validEvidenceLines() {
    const lines = [freshReady()];

    lines.push(...boundPrefix("aaaaaaaaaaaa", "111111111111", "222222222222", "333333333333", "444444444444"));
    lines.push(event("result_forward", "flowCallId=1 result=success delivered=true"));
    lines.push(event("authority_ack", "watermark=1 state=OPENING_ANIMATION terminal=false panelDigest=333333333333"));
    lines.push(event("reconcile_tick", "state=resultapplied panelDigest=333333333333"));
    lines.push(event("authority_projection_retry", "cmd=result_ack panelDigest=333333333333"));
    lines.push(event("causal_query", "unknownFlowCallId=1 reason=terminal_poll delivered=true"));
    lines.push(event("query_reply", "flowCallId=1 watermark=1 disposition=success state=COMPLETED_NO_REWARD terminal=true panelDigest=333333333333"));
    lines.push(event("gate_rejected", "code=web_post_not_delivered origin=web_business"));
    lines.push(event("reconcile_tick", "state=knownterminal panelDigest=333333333333"));
    lines.push(event("authority_projection_retry", "cmd=authority_terminal panelDigest=333333333333"));
    lines.push(event("close_query", "panelDigest=333333333333"));
    lines.push(event("web_close_ack", "accepted=true panelDigest=333333333333"));
    lines.push(event("panel_exact_close", "closed=false reason=web_close_ack panelDigest=333333333333"));
    lines.push(event("reconcile_tick", "state=knownterminal panelDigest=333333333333"));
    lines.push(event("authority_projection_retry", "cmd=authority_terminal panelDigest=333333333333"));
    lines.push(event("panel_exact_close", "closed=true reason=reconcile_terminal panelDigest=333333333333"));
    lines.push(event("native_close_proof", "recorded=true reason=reconcile_terminal panelDigest=333333333333"));
    lines.push(event("gate_rejected",
        "code=pause_release_failed origin=socket gen=1 reason=callback_false"));
    lines.push(event("reconcile_tick", "state=knownterminal panelDigest=333333333333"));
    lines.push(event("authority_projection_retry", "cmd=authority_terminal panelDigest=333333333333"));
    lines.push(event("pause_release", "terminal=true domClosed=true nativeClosed=true panelDigest=333333333333"));

    lines.push(freshReady());
    lines.push(...armPrefix("bbbbbbbbbbbb", "555555555555", "666666666666", "777777777777", "888888888888"));
    lines.push(event("open_execute_recheck", "allowed=true gen=1 pid=4242 epoch=1"));
    lines.push(event("panel_post", "delivered=true host=PanelHostController transport=WebView2 panelDigest=777777777777"));
    lines.push(event("bind_unknown", "panelDigest=777777777777"));
    lines.push(event("close_query", "panelDigest=777777777777"));
    lines.push(event("reconcile_tick", "state=openbindunknown panelDigest=777777777777"));
    lines.push(event("close_query", "panelDigest=777777777777"));
    lines.push(event("bind_query_reply", "accepted=true binding=bound panelDigest=777777777777"));
    lines.push(event("gate_rejected", "code=busy origin=socket"));
    lines.push(event("gate_rejected", "code=other_panel_blocked origin=panel_host"));
    lines.push(event("generic_unpause_blocked", "reason=s0_active"));
    lines.push(event("result_forward", "flowCallId=1 result=cancel delivered=true"));
    lines.push(event("authority_ack", "watermark=1 state=REVOKED terminal=true panelDigest=777777777777"));
    lines.push(event("web_close_ack", "accepted=true panelDigest=777777777777"));
    lines.push(event("panel_exact_close", "closed=true reason=web_close_ack panelDigest=777777777777"));
    lines.push(event("native_close_proof", "recorded=true reason=web_close_ack panelDigest=777777777777"));
    lines.push(event("pause_release", "terminal=true domClosed=true nativeClosed=true panelDigest=777777777777"));

    lines.push(freshReady());
    lines.push(event("arm_issued", "gen=1 pid=4242 epoch=1 capDigest=cccccccccccc"));
    lines.push(event("web_armed", "gen=1 pid=4242 epoch=1 capDigest=cccccccccccc"));
    lines.push(event("as2_bootstrap_sent", "gen=1 capDigest=cccccccccccc resumeActive=false"));
    lines.push(event("as2_bootstrap_ack", "gen=1 pid=4242 epoch=1 capDigest=cccccccccccc resumeActive=false"));
    lines.push(event("begin_received", "origin=trusted_as2_socket gen=1 pid=4242 pauseAcquired=true"));
    lines.push(event("capability_consumed", "capDigest=cccccccccccc"));
    lines.push(event("gate_rejected", "code=panel_orchestration_busy origin=socket"));
    lines.push(event("gate_rejected", "code=panel_orchestration_busy origin=socket"));
    lines.push(event("panel_host_idle", "panel=inventory instanceDigest=010101010101"));
    lines.push(...armPrefix("dddddddddddd", "999999999999", "abababababab", "cdcdcdcdcdcd", "efefefefefef"));
    lines.push(event("open_execute_recheck", "allowed=false gen=1 pid=4242 epoch=1"));
    lines.push(event("panel_post", "delivered=false host=PanelHostController transport=WebView2 panelDigest=cdcdcdcdcdcd"));
    lines.push(event("result_forward", "flowCallId=1 result=failure delivered=true reason=pre_execution_rejected"));
    lines.push(event("native_close_proof", "recorded=true reason=tracked_open_preexecutionrejected panelDigest=cdcdcdcdcdcd"));
    lines.push(event("authority_ack", "watermark=1 state=REVOKED terminal=true panelDigest=cdcdcdcdcdcd"));
    lines.push(event("pause_release", "terminal=true domClosed=true nativeClosed=true panelDigest=cdcdcdcdcdcd"));

    lines.push(freshReady());
    lines.push(...boundPrefix("eeeeeeeeeeee", "101010101010", "202020202020", "303030303030", "404040404040"));
    lines.push(event("result_forward", "flowCallId=1 result=cancel delivered=false"));
    lines.push(event("result_unknown", "flowCallId=1"));
    lines.push(event("causal_query", "unknownFlowCallId=1 reason=host_detected_unknown delivered=true"));
    lines.push(event("reconcile_tick", "state=reconcilerequired panelDigest=303030303030"));
    lines.push(event("causal_query", "unknownFlowCallId=1 reason=timer_reconcile delivered=true"));
    lines.push(event("query_reply", "flowCallId=1 watermark=1 disposition=cancel state=REVOKED terminal=true panelDigest=303030303030"));
    lines.push(event("web_close_ack", "accepted=true panelDigest=303030303030"));
    lines.push(event("panel_exact_close", "closed=true reason=web_close_ack panelDigest=303030303030"));
    lines.push(event("native_close_proof", "recorded=true reason=web_close_ack panelDigest=303030303030"));
    lines.push(event("pause_release", "terminal=true domClosed=true nativeClosed=true panelDigest=303030303030"));

    lines.push(freshReady());
    lines.push(...boundPrefix("ffffffffffff", "414141414141", "424242424242", "434343434343", "444545454545"));
    lines.push(event("authority_ack", "watermark=0 state=EXPIRED terminal=true panelDigest=434343434343"));
    lines.push(event("web_close_ack", "accepted=true panelDigest=434343434343"));
    lines.push(event("panel_exact_close", "closed=true reason=web_close_ack panelDigest=434343434343"));
    lines.push(event("native_close_proof", "recorded=true reason=web_close_ack panelDigest=434343434343"));
    lines.push(event("pause_release", "terminal=true domClosed=true nativeClosed=true panelDigest=434343434343"));

    lines.push(freshReady());
    lines.push(...armPrefix("909090909090", "464646464646", "474747474747", "484848484848", "494949494949"));
    lines.push(event("open_execute_recheck", "allowed=true gen=1 pid=4242 epoch=1"));
    lines.push(event("panel_post", "delivered=true host=PanelHostController transport=WebView2 panelDigest=484848484848"));
    lines.push(event("gate_rejected", "code=web_rejection_mismatch origin=web_control"));
    lines.push(event("runtime_open_rejected", "accepted=true code=dom_bind_not_committed panelDigest=484848484848"));
    lines.push(event("result_forward", "flowCallId=1 result=failure delivered=true reason=web_bind_rejected"));
    lines.push(event("reconcile_tick", "state=revokepending panelDigest=484848484848"));
    lines.push(event("result_forward", "flowCallId=1 result=failure delivered=true reason=web_bind_rejected"));
    lines.push(event("close_query", "panelDigest=484848484848"));
    lines.push(event("close_proof", "recorded=true origin=web_dom reason=runtime_rejected panelDigest=484848484848"));
    lines.push(event("panel_exact_close", "closed=true reason=runtime_rejected panelDigest=484848484848"));
    lines.push(event("native_close_proof", "recorded=true reason=runtime_rejected panelDigest=484848484848"));
    lines.push(event("authority_ack", "watermark=1 state=REVOKED terminal=true panelDigest=484848484848"));
    lines.push(event("pause_release", "terminal=true domClosed=true nativeClosed=true panelDigest=484848484848"));

    lines.push(freshReady());
    lines.push(...boundPrefix("a1a1a1a1a1a1", "515151515151", "616161616161", "717171717171", "818181818181"));
    lines.push(event("document_navigation_start", "navigationId=101 active=true"));
    lines.push(event("document_epoch_advance", "navigationId=101 old=1 new=2 active=true"));
    lines.push(event("old_document_teardown", "proved=true panelDigest=717171717171"));
    lines.push(event("document_recovery", "path=pre_result state=revoke_pending"));
    lines.push(event("result_forward", "flowCallId=1 result=failure delivered=true reason=web_bind_rejected"));
    lines.push(event("panel_exact_close", "closed=true reason=document_teardown panelDigest=717171717171"));
    lines.push(event("native_close_proof", "recorded=true reason=document_teardown panelDigest=717171717171"));
    lines.push(event("authority_ack", "watermark=1 state=REVOKED terminal=true panelDigest=717171717171"));
    lines.push(event("pause_release", "terminal=true domClosed=true nativeClosed=true panelDigest=717171717171"));

    lines.push(freshReady());
    lines.push(...boundPrefix("b1b1b1b1b1b1", "525252525252", "626262626262", "727272727272", "828282828282", 2));
    lines.push(event("result_forward", "flowCallId=1 result=cancel delivered=true"));
    lines.push(event("document_navigation_start", "navigationId=102 active=true"));
    lines.push(event("document_epoch_advance", "navigationId=102 old=2 new=3 active=true"));
    lines.push(event("old_document_teardown", "proved=true panelDigest=727272727272"));
    lines.push(event("causal_query", "unknownFlowCallId=1 reason=document_teardown delivered=true"));
    lines.push(event("document_recovery", "path=post_result state=reconcile_required unknownFlowCallId=1 delivered=true"));
    lines.push(event("panel_exact_close", "closed=true reason=document_teardown panelDigest=727272727272"));
    lines.push(event("native_close_proof", "recorded=true reason=document_teardown panelDigest=727272727272"));
    lines.push(event("query_reply", "flowCallId=1 watermark=1 disposition=cancel state=REVOKED terminal=true panelDigest=727272727272"));
    lines.push(event("pause_release", "terminal=true domClosed=true nativeClosed=true panelDigest=727272727272"));

    lines.push(freshReady());
    lines.push(...boundPrefix("c1c1c1c1c1c1", "121212121212", "232323232323", "343434343434", "454545454545", 3));
    lines.push(event("result_forward", "flowCallId=1 result=success delivered=true"));
    lines.push(event("socket_disconnected", "gen=1"));
    lines.push(event("result_unknown", "flowCallId=1"));
    lines.push(event("panel_exact_close", "closed=true reason=socket_disconnected panelDigest=343434343434"));
    lines.push(event("native_close_proof", "recorded=true reason=socket_disconnected panelDigest=343434343434"));
    lines.push(event("close_proof", "recorded=true origin=web_dom reason=force_close panelDigest=343434343434"));
    lines.push(event("socket_ready", "gen=2"));
    lines.push(event("as2_bootstrap_sent", "gen=2 capDigest=d1d1d1d1d1d1 resumeActive=true"));
    lines.push(event("reconnect_bootstrap_sent", "gen=2 pid=4242 epoch=3 capDigest=d1d1d1d1d1d1 resumeActive=true delivered=true"));
    lines.push(event("as2_bootstrap_ack", "gen=2 pid=4242 epoch=3 capDigest=d1d1d1d1d1d1 resumeActive=true"));
    lines.push(event("generic_unpause_blocked", "reason=s0_active"));
    lines.push(event("causal_query", "unknownFlowCallId=1 reason=reconnect delivered=true"));
    lines.push(event("query_forward", "unknownFlowCallId=1 delivered=true reason=reconnect"));
    lines.push(event("query_reply", "flowCallId=1 watermark=1 disposition=success state=OPENING_ANIMATION terminal=false panelDigest=343434343434"));
    lines.push(event("authority_ack", "watermark=1 state=COMPLETED_NO_REWARD terminal=true panelDigest=343434343434"));
    lines.push(event("pause_release", "terminal=true domClosed=true nativeClosed=true panelDigest=343434343434"));
    return lines;
}

function validEvidenceText() {
    return validEvidenceLines().join("\n") + "\n";
}

function verifyText(text) {
    return verifier.verifyActualCrossStack(verifier.parseStructuredEvents(text));
}

test("V01", "complete structured Host evidence proves exactly X01-X04", function() {
    const report = verifyText(validEvidenceText());
    assert.strictEqual(report.actualCrossStack, true);
    assert.strictEqual(report.browserShim, false);
    assert.deepStrictEqual(report.cases.map(item => item.id), ["X01", "X02", "X03", "X04"]);
});

test("V02", "browser/page self-attestation is never admissible Host evidence", function() {
    assert.throws(() => verifyText("executionMode=browser-host-shim\n" + validEvidenceText()),
        /self-attestation/);
});

test("V03", "raw capability/session/flow fields fail the exact log schema", function() {
    const text = validEvidenceText().replace("event=arm_issued gen=1",
        "event=arm_issued capability=raw-secret gen=1");
    assert.throws(() => verifyText(text), /unexpected or sensitive field 'capability'/);
});

test("V04", "a missing real PanelHost/WebView2 post cannot pass X01", function() {
    const text = validEvidenceText().replace(
        /00:00:00\.000 \[DevLockboxS0\] event=panel_post delivered=true host=PanelHostController transport=WebView2 panelDigest=333333333333\r?\n/,
        "");
    assert.throws(() => verifyText(text), /X01 missing/);
});

test("V05", "capability digest mismatch breaks the trusted arm/bootstrap chain", function() {
    const text = validEvidenceText().replace(
        "event=web_armed gen=1 pid=4242 epoch=1 capDigest=aaaaaaaaaaaa",
        "event=web_armed gen=1 pid=4242 epoch=1 capDigest=000000000000");
    assert.throws(() => verifyText(text), /X01 missing/);
});

test("V06", "unknown write delivery cannot depend only on a Web-originated query", function() {
    const text = validEvidenceText().replace(
        event("causal_query", "unknownFlowCallId=1 reason=host_detected_unknown delivered=true") + "\n",
        event("causal_query", "unknownFlowCallId=1 reason=web_request delivered=true") + "\n"
            + event("query_forward", "unknownFlowCallId=1 delivered=true") + "\n");
    assert.throws(() => verifyText(text), /X03 missing/);
});

test("V07", "unknown write cannot be replayed before the timer-driven causal retry", function() {
    const replay = event("result_forward", "flowCallId=1 result=cancel delivered=true") + "\n";
    const retry = event("causal_query", "unknownFlowCallId=1 reason=timer_reconcile delivered=true") + "\n";
    const text = validEvidenceText().replace(retry, replay + retry);
    assert.throws(() => verifyText(text), /X03 missing/);
});

test("V08", "reconnect cannot mint a new arm before old authority converges", function() {
    const injected = event("arm_issued", "gen=2 pid=4242 epoch=1 capDigest=010101010101") + "\n";
    const text = validEvidenceText().replace(
        "00:00:00.000 [DevLockboxS0] event=query_forward unknownFlowCallId=1 delivered=true reason=reconnect\n",
        injected + "00:00:00.000 [DevLockboxS0] event=query_forward unknownFlowCallId=1 delivered=true reason=reconnect\n");
    assert.throws(() => verifyText(text), /reserved attempt did not converge to exactly one matching pause release/);
});

test("V09", "reconnect cannot replay the submitted result before its causal query", function() {
    const replay = event("result_forward", "flowCallId=1 result=success delivered=true") + "\n";
    const text = validEvidenceText().replace(
        "00:00:00.000 [DevLockboxS0] event=query_forward unknownFlowCallId=1 delivered=true reason=reconnect\n",
        replay + "00:00:00.000 [DevLockboxS0] event=query_forward unknownFlowCallId=1 delivered=true reason=reconnect\n");
    assert.throws(() => verifyText(text), /X04 missing: disconnect\/reconnect/);
});

test("V10", "native PanelHost close cannot self-attest that Web DOM/current was cleared", function() {
    const text = validEvidenceText().replace(
        "00:00:00.000 [DevLockboxS0] event=close_proof recorded=true origin=web_dom reason=force_close panelDigest=343434343434\n", "");
    assert.throws(() => verifyText(text), /independently prove Web force-close and native PanelHost close/);
});

test("V11", "old document teardown cannot release pause without AS2 terminal reconciliation", function() {
    const text = validEvidenceText().replace(
        event("native_close_proof", "recorded=true reason=document_teardown panelDigest=717171717171") + "\n"
            + event("authority_ack", "watermark=1 state=REVOKED terminal=true panelDigest=717171717171") + "\n",
        event("native_close_proof", "recorded=true reason=document_teardown panelDigest=717171717171") + "\n");
    assert.throws(() => verifyText(text), /pre-result active document epoch teardown must reconcile AS2 authority/);
});

test("V12", "capture cursor accepts only fresh append-only launcher log bytes", function() {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-chest-s0-verifier-"));
    try {
        const log = path.join(dir, "launcher.log");
        const cursorPath = path.join(dir, "cursor.json");
        fs.writeFileSync(log, "before\n");
        verifier.beginCapture(log, cursorPath);
        fs.appendFileSync(log, validEvidenceText());
        const report = verifier.verifyCapture(cursorPath, 60 * 1000);
        assert.strictEqual(report.cases.length, 4);

        fs.writeFileSync(log, "befOre\n" + validEvidenceText());
        assert.throws(() => verifier.verifyCapture(cursorPath, 60 * 1000), /prefix changed/);
    } finally {
        fs.rmSync(dir, { recursive: true, force: true });
    }
});

test("V13", "normal bootstrap cannot claim active-authority resume semantics", function() {
    const text = validEvidenceText().replace(
        "event=as2_bootstrap_sent gen=1 capDigest=aaaaaaaaaaaa resumeActive=false",
        "event=as2_bootstrap_sent gen=1 capDigest=aaaaaaaaaaaa resumeActive=true");
    assert.throws(() => verifyText(text), /X01 missing/);
});

test("V14", "reconnect bootstrap and ack must preserve active-authority resume semantics", function() {
    const text = validEvidenceText().replace(
        "event=as2_bootstrap_ack gen=2 pid=4242 epoch=3 capDigest=d1d1d1d1d1d1 resumeActive=true",
        "event=as2_bootstrap_ack gen=2 pid=4242 epoch=3 capDigest=d1d1d1d1d1d1 resumeActive=false");
    assert.throws(() => verifyText(text), /X04 missing: disconnect\/reconnect/);
});

test("V15", "lost close ack cannot pass without a causal Host close_query", function() {
    const text = validEvidenceText().replace(
        event("close_query", "panelDigest=333333333333") + "\n", "");
    assert.throws(() => verifyText(text), /lost terminal projection\/close ack/);
});

test("V16", "Web close proof cannot replace the native PanelHost close proof", function() {
    const text = validEvidenceText().replace(
        event("native_close_proof", "recorded=true reason=reconcile_terminal panelDigest=333333333333") + "\n", "");
    assert.throws(() => verifyText(text), /retried exact native close lacks its Host proof/);
});

test("V17", "post-result navigation requires one document-teardown causal query", function() {
    const text = validEvidenceText().replace(
        event("causal_query", "unknownFlowCallId=1 reason=document_teardown delivered=true") + "\n", "");
    assert.throws(() => verifyText(text), /post-result active navigation/);
});

test("V18", "runtime rejection needs an independent Web DOM teardown proof", function() {
    const text = validEvidenceText().replace(
        event("close_proof", "recorded=true origin=web_dom reason=runtime_rejected panelDigest=484848484848") + "\n", "");
    assert.throws(() => verifyText(text), /independently prove Web\/native close/);
});

test("V19", "panel-busy flow cannot fresh-arm before PanelHost reports idle", function() {
    const freshArm = event("arm_issued", "gen=1 pid=4242 epoch=1 capDigest=dddddddddddd") + "\n";
    const idle = event("panel_host_idle", "panel=inventory instanceDigest=010101010101") + "\n";
    const text = validEvidenceText().replace(idle + freshArm, freshArm + idle);
    assert.throws(() => verifyText(text), /panel-busy consumed arm must wait/);
});

test("V20", "pause release must explicitly prove terminal, DOM close, and native close", function() {
    const text = validEvidenceText().replace(
        "event=pause_release terminal=true domClosed=true nativeClosed=true panelDigest=333333333333",
        "event=pause_release terminal=true domClosed=true panelDigest=333333333333");
    assert.throws(() => verifyText(text), /missing 'nativeClosed'/);
});

test("V21", "failed navigation cannot be promoted into old-document teardown evidence", function() {
    const start = event("document_navigation_start", "navigationId=101 active=true") + "\n";
    const failed = event("document_navigation_failed",
        "navigationId=101 success=false loadedNewDocument=true active=true") + "\n";
    const text = validEvidenceText().replace(start, start + failed);
    assert.throws(() => verifyText(text), /failed navigation cannot advance the document epoch/);
});

test("V22", "success must poll terminal state from ResultApplied without replaying the write", function() {
    const text = validEvidenceText().replace(
        event("reconcile_tick", "state=resultapplied panelDigest=333333333333") + "\n", "");
    assert.throws(() => verifyText(text), /read-only ResultApplied polling/);
});

test("V23", "a lost terminal projection requires an exact cached projection replay", function() {
    const text = validEvidenceText().replace(
        event("authority_projection_retry", "cmd=authority_terminal panelDigest=333333333333") + "\n", "");
    assert.throws(() => verifyText(text), /lost terminal projection\/close ack/);
});

test("V24", "a failed native exact close cannot pass without a successful retry", function() {
    const text = validEvidenceText().replace(
        event("panel_exact_close", "closed=true reason=reconcile_terminal panelDigest=333333333333") + "\n", "");
    assert.throws(() => verifyText(text), /exact native close failure was not retried/);
});

test("V25", "bind uncertainty requires an OpenBindUnknown timer retry", function() {
    const text = validEvidenceText().replace(
        event("reconcile_tick", "state=openbindunknown panelDigest=777777777777") + "\n", "");
    assert.throws(() => verifyText(text), /lost bind observation/);
});

test("V26", "authority projection retry command is a closed domain", function() {
    const text = validEvidenceText().replace(
        "event=authority_projection_retry cmd=result_ack",
        "event=authority_projection_retry cmd=close_request");
    assert.throws(() => verifyText(text), /invalid authority projection retry/);
});

test("V27", "successful completion without matching ContentLoading cannot prove document teardown", function() {
    const start = event("document_navigation_start", "navigationId=101 active=true") + "\n";
    const failed = event("document_navigation_failed",
        "navigationId=101 success=true loadedNewDocument=false active=true") + "\n";
    const text = validEvidenceText().replace(start, start + failed);
    assert.throws(() => verifyText(text), /failed navigation cannot advance the document epoch/);
});

test("V28", "terminal-poll flag must agree with the returned authority state", function() {
    const text = validEvidenceText().replace(
        "event=query_reply flowCallId=1 watermark=1 disposition=success state=COMPLETED_NO_REWARD terminal=true panelDigest=333333333333",
        "event=query_reply flowCallId=1 watermark=1 disposition=success state=COMPLETED_NO_REWARD terminal=false panelDigest=333333333333");
    assert.throws(() => verifyText(text), /terminal flag disagrees/);
});

test("V29", "pause cannot release between native close failure and its retry proof", function() {
    const failed = event("panel_exact_close",
        "closed=false reason=web_close_ack panelDigest=333333333333") + "\n";
    const injected = event("pause_release", "terminal=true domClosed=true nativeClosed=true panelDigest=333333333333") + "\n";
    const text = validEvidenceText().replace(failed, failed + injected);
    assert.throws(() => verifyText(text), /pause released before native close retry converged/);
});

test("V30", "runtime rejection cannot skip its RevokePending retry tick", function() {
    const text = validEvidenceText().replace(
        event("reconcile_tick", "state=revokepending panelDigest=484848484848") + "\n", "");
    assert.throws(() => verifyText(text), /retry revocation\/close from RevokePending/);
});

test("V31", "resumeActive reconnect capability cannot be consumed by a new begin", function() {
    const ack = event("as2_bootstrap_ack",
        "gen=2 pid=4242 epoch=3 capDigest=d1d1d1d1d1d1 resumeActive=true") + "\n";
    const illegalBegin = event("begin_received", "origin=trusted_as2_socket gen=2 pid=4242 pauseAcquired=true") + "\n"
        + event("capability_consumed", "capDigest=d1d1d1d1d1d1") + "\n";
    const text = validEvidenceText().replace(ack, ack + illegalBegin);
    assert.throws(() => verifyText(text), /reserve resumeActive capability/);
});

test("V32", "pause callback failure must retain KnownTerminal and retry before fresh arm", function() {
    const failure = event("gate_rejected",
        "code=pause_release_failed origin=socket gen=1 reason=callback_false") + "\n";
    const retry = event("reconcile_tick", "state=knownterminal panelDigest=333333333333") + "\n";
    const text = validEvidenceText().replace(failure + retry, failure);
    assert.throws(() => verifyText(text), /pause release failure did not retain KnownTerminal/);
});

test("V33", "pause callback failure forbids fresh Web arm before release succeeds", function() {
    const failure = event("gate_rejected",
        "code=pause_release_failed origin=socket gen=1 reason=callback_false") + "\n";
    const earlyArm = event("web_armed",
        "gen=1 pid=4242 epoch=1 capDigest=aaaaaaaaaaaa") + "\n";
    const text = validEvidenceText().replace(failure, failure + earlyArm);
    assert.throws(() => verifyText(text), /fresh arm was issued before pause release callback succeeded/);
});

test("V34", "unknown query replies still require a valid identity and authority tuple", function() {
    const text = validEvidenceText().replace(
        "event=query_reply flowCallId=1 watermark=1 disposition=success state=OPENING_ANIMATION terminal=false panelDigest=343434343434",
        "event=query_reply flowCallId=1 watermark=1 disposition=unknown state=not_a_state terminal=false panelDigest=343434343434");
    assert.throws(() => verifyText(text), /invalid query authority state/);
});

test("V35", "bind-query evidence must match the reserved panel identity", function() {
    const text = validEvidenceText().replace(
        "event=bind_query_reply accepted=true binding=bound panelDigest=777777777777",
        "event=bind_query_reply accepted=true binding=bound panelDigest=333333333333");
    assert.throws(() => verifyText(text), /attempt evidence crossed panel identity/);
});

test("V36", "document epoch evidence must match the starting NavigationId", function() {
    const text = validEvidenceText().replace(
        "event=document_epoch_advance navigationId=101 old=1 new=2 active=true",
        "event=document_epoch_advance navigationId=999 old=1 new=2 active=true");
    assert.throws(() => verifyText(text), /lacks its matching navigation start/);
});

test("V37", "a dangling reserved attempt cannot coexist with otherwise valid evidence", function() {
    const dangling = [freshReady()].concat(armPrefix(
        "deadbeef0001", "deadbeef0002", "deadbeef0003", "deadbeef0004", "deadbeef0005"))
        .map(line => line.replace(/gen=1/g, "gen=2"));
    assert.throws(() => verifyText(validEvidenceText() + dangling.join("\n") + "\n"),
        /reserved attempt did not converge to exactly one matching pause release/);
});

test("V38", "a rejected old-document teardown invalidates an otherwise clean capture", function() {
    const proved = event("old_document_teardown",
        "proved=true panelDigest=717171717171") + "\n";
    const rejected = event("old_document_teardown",
        "proved=false panelDigest=717171717171") + "\n";
    const text = validEvidenceText().replace(proved, proved + rejected);
    assert.throws(() => verifyText(text), /rejected old-document teardown/);
});

test("V39", "authority acknowledgement watermarks stay in the single-call domain", function() {
    const text = validEvidenceText().replace(
        "event=authority_ack watermark=1 state=OPENING_ANIMATION terminal=false panelDigest=333333333333",
        "event=authority_ack watermark=2 state=OPENING_ANIMATION terminal=false panelDigest=333333333333");
    assert.throws(() => verifyText(text), /authority watermark exceeds the S0 single-call domain/);
});

test("V40", "pause release evidence must match its reserved panel identity", function() {
    const text = validEvidenceText().replace(
        "event=pause_release terminal=true domClosed=true nativeClosed=true panelDigest=333333333333",
        "event=pause_release terminal=true domClosed=true nativeClosed=true panelDigest=777777777777");
    assert.throws(() => verifyText(text), /attempt evidence crossed panel identity/);
});

test("V41", "success query disposition cannot claim revoked authority", function() {
    const text = validEvidenceText().replace(
        "event=query_reply flowCallId=1 watermark=1 disposition=success state=COMPLETED_NO_REWARD terminal=true panelDigest=333333333333",
        "event=query_reply flowCallId=1 watermark=1 disposition=success state=REVOKED terminal=true panelDigest=333333333333");
    assert.throws(() => verifyText(text), /success disposition disagrees with authority state/);
});

test("V42", "cancel query disposition cannot claim expired authority", function() {
    const text = validEvidenceText().replace(
        "event=query_reply flowCallId=1 watermark=1 disposition=cancel state=REVOKED terminal=true panelDigest=303030303030",
        "event=query_reply flowCallId=1 watermark=1 disposition=cancel state=EXPIRED terminal=true panelDigest=303030303030");
    assert.throws(() => verifyText(text), /non-success disposition disagrees with authority state/);
});

test("V43", "LOCK_PENDING cannot appear as an authority acknowledgement", function() {
    const text = validEvidenceText().replace(
        "event=authority_ack watermark=1 state=OPENING_ANIMATION terminal=false panelDigest=333333333333",
        "event=authority_ack watermark=1 state=LOCK_PENDING terminal=false panelDigest=333333333333");
    assert.throws(() => verifyText(text), /LOCK_PENDING cannot be acknowledged/);
});

test("V44", "result-forward failure reasons are a closed producer domain", function() {
    const text = validEvidenceText().replace(
        "event=result_forward flowCallId=1 result=failure delivered=true reason=pre_execution_rejected",
        "event=result_forward flowCallId=1 result=success delivered=true reason=made_up");
    assert.throws(() => verifyText(text), /invalid result-forward failure reason/);
});

test("V45", "pause release cannot weaken any of its three proofs", function() {
    const text = validEvidenceText().replace(
        "event=pause_release terminal=true domClosed=true nativeClosed=true panelDigest=333333333333",
        "event=pause_release terminal=true domClosed=false nativeClosed=true panelDigest=333333333333");
    assert.throws(() => verifyText(text), /pause release requires all three independent proofs/);
});

test("V46", "reconnect bootstrap always reserves active-authority semantics", function() {
    const text = validEvidenceText().replace(
        "event=reconnect_bootstrap_sent gen=2 pid=4242 epoch=3 capDigest=d1d1d1d1d1d1 resumeActive=true delivered=true",
        "event=reconnect_bootstrap_sent gen=2 pid=4242 epoch=3 capDigest=d1d1d1d1d1d1 resumeActive=false delivered=true");
    assert.throws(() => verifyText(text), /reconnect bootstrap must reserve active-authority semantics/);
});

test("V47", "generic unpause blocks identify the active S0 lease", function() {
    const text = validEvidenceText().replace(
        "event=generic_unpause_blocked reason=s0_active",
        "event=generic_unpause_blocked reason=unknown");
    assert.throws(() => verifyText(text), /generic unpause block reason must identify the S0 lease/);
});

test("V48", "document epoch advances exactly once per matching navigation", function() {
    const text = validEvidenceText().replace(
        "event=document_epoch_advance navigationId=101 old=1 new=2 active=true",
        "event=document_epoch_advance navigationId=101 old=1 new=3 active=true");
    assert.throws(() => verifyText(text), /document epoch must advance by exactly one/);
});

test("V49", "every reserved attempt acquires the exact global pause before enqueue", function() {
    const acquire = event("pause_acquire",
        "delivered=true gen=1 panelDigest=333333333333") + "\n";
    const text = validEvidenceText().replace(acquire, "");
    assert.throws(() => verifyText(text), /reserved attempt lacks one exact successful pause acquisition/);
});

test("V50", "pause acquisition cannot occur after tracked-open enqueue", function() {
    const acquire = event("pause_acquire",
        "delivered=true gen=1 panelDigest=333333333333") + "\n";
    const enqueue = event("open_enqueued",
        "flowDigest=111111111111 requestDigest=222222222222") + "\n";
    const text = validEvidenceText().replace(acquire + enqueue, enqueue + acquire);
    assert.throws(() => verifyText(text), /pause acquisition must occur between reservation and enqueue/);
});

test("V51", "pause acquisition uses the begin binding generation", function() {
    const text = validEvidenceText().replace(
        "event=pause_acquire delivered=true gen=1 panelDigest=333333333333",
        "event=pause_acquire delivered=true gen=2 panelDigest=333333333333");
    assert.throws(() => verifyText(text), /reserved attempt lacks one exact successful pause acquisition/);
});

test("V52", "failed pause delivery cannot count as tracked-open acquisition", function() {
    const text = validEvidenceText().replace(
        "event=pause_acquire delivered=true gen=1 panelDigest=333333333333",
        "event=pause_acquire delivered=false gen=1 panelDigest=333333333333");
    assert.throws(() => verifyText(text), /reserved attempt lacks one exact successful pause acquisition/);
});

test("V53", "pause acquisition cannot exist without a reserved attempt", function() {
    const consumed = event("capability_consumed", "capDigest=cccccccccccc") + "\n";
    const stray = event("pause_acquire",
        "delivered=true gen=1 panelDigest=deadbeef0006") + "\n";
    const text = validEvidenceText().replace(consumed, consumed + stray);
    assert.throws(() => verifyText(text), /pause acquisition has no reserved attempt/);
});

test("V54", "pause release cannot precede reservation acquisition and enqueue", function() {
    const acquire = event("pause_acquire",
        "delivered=true gen=1 panelDigest=333333333333") + "\n";
    const release = event("pause_release",
        "terminal=true domClosed=true nativeClosed=true panelDigest=333333333333") + "\n";
    const text = validEvidenceText().replace(release, "").replace(acquire, release + acquire);
    assert.throws(() => verifyText(text), /pause release cannot precede reservation acquisition and enqueue/);
});

test("V55", "Host begin evidence requires the synchronous AS2 pause lease proof", function() {
    const text = validEvidenceText().replace(
        "event=begin_received origin=trusted_as2_socket gen=1 pid=4242 pauseAcquired=true",
        "event=begin_received origin=trusted_as2_socket gen=1 pid=4242 pauseAcquired=false");
    assert.throws(() => verifyText(text), /trusted AS2 origin and synchronous pause lease/);
});

test("V56", "binding-timeout and reentrant-generation recovery events use the frozen safe schema", function() {
    const prefix = [
        event("panel_queue_idle", "pauseHeld=false"),
        event("generic_unpause", "delivered=true gen=1"),
        event("reconnect_bootstrap_superseded", "gen=2"),
        event("pause_release_generation_retry", "oldGen=1 newGen=2"),
        event("gate_rejected", "code=web_arm_ack_timeout origin=web_control"),
        event("gate_rejected", "code=as2_bootstrap_ack_timeout origin=socket"),
        event("gate_rejected", "code=web_arm_rejected origin=web_control reason=panel_orchestration_busy"),
        event("telemetry_dropped", "code=non_allowlisted_minigame_session")
    ].join("\n") + "\n";
    const report = verifyText(prefix + validEvidenceText());
    assert.deepStrictEqual(report.cases.map(item => item.id), ["X01", "X02", "X03", "X04"]);
});

test("V57", "new recovery fields retain exact types and generation semantics", function() {
    assert.throws(() => verifier.parseStructuredEvents(
        event("panel_queue_idle", "pauseHeld=0") + "\n"), /must be true\/false/);
    assert.throws(() => verifier.parseStructuredEvents(
        event("pause_release_generation_retry", "oldGen=1 newGen=1") + "\n"),
    /requires a strictly increasing generation/);
    assert.throws(() => verifier.parseStructuredEvents(
        event("pause_release_generation_retry", "oldGen=2 newGen=1") + "\n"),
    /requires a strictly increasing generation/);
    assert.throws(() => verifier.parseStructuredEvents(
        event("reconnect_bootstrap_superseded", "gen=2 capability=raw-secret") + "\n"),
    /unexpected or sensitive field 'capability'/);
});

test("V58", "telemetry drops and optional rejection/result fields stay in closed producer domains", function() {
    const releaseFailure = verifier.parseStructuredEvents(
        event("gate_rejected",
            "code=pause_release_failed origin=socket gen=2 reason=callback_false") + "\n");
    assert.strictEqual(releaseFailure[0].fields.gen, "2");
    const externalUnknown = verifier.parseStructuredEvents(
        event("result_unknown", "flowCallId=1 origin=web_ack_timeout accepted=true") + "\n");
    assert.strictEqual(externalUnknown[0].fields.accepted, "true");
    assert.throws(() => verifier.parseStructuredEvents(
        event("telemetry_dropped", "code=raw_payload") + "\n"), /invalid telemetry-drop category/);
    assert.throws(() => verifier.parseStructuredEvents(
        event("gate_rejected", "code=busy origin=socket reason=made_up") + "\n"),
    /only a rejected Web arm or pause release may carry a reason/);
    assert.throws(() => verifier.parseStructuredEvents(
        event("gate_rejected", "code=busy origin=socket gen=2") + "\n"),
    /only an exact-generation pause-release failure or stale socket-ready may carry gen/);
    assert.throws(() => verifier.parseStructuredEvents(
        event("result_unknown", "flowCallId=1 accepted=true") + "\n"),
    /acceptance requires a Web timeout origin/);
    assert.throws(() => verifier.parseStructuredEvents(
        event("result_unknown", "flowCallId=1 origin=socket accepted=true") + "\n"),
    /invalid externally observed result-unknown evidence/);
});

test("V59", "stale socket-ready is safe only below an earlier monotonically adopted generation", function() {
    const stale = event("gate_rejected",
        "code=stale_socket_ready origin=socket gen=1") + "\n";
    const report = verifyText(validEvidenceText() + stale);
    assert.deepStrictEqual(report.cases.map(item => item.id), ["X01", "X02", "X03", "X04"]);
    assert.throws(() => verifier.parseStructuredEvents(stale),
        /requires an earlier strictly higher adopted generation/);
    assert.throws(() => verifier.parseStructuredEvents(
        event("socket_ready", "gen=2") + "\n"
            + event("gate_rejected", "code=stale_socket_ready origin=socket gen=2") + "\n"),
    /requires an earlier strictly higher adopted generation/);
    assert.throws(() => verifier.parseStructuredEvents(
        event("socket_ready", "gen=2") + "\n" + event("socket_ready", "gen=1") + "\n"),
    /accepted socket_ready generation regressed/);
    assert.throws(() => verifier.parseStructuredEvents(
        event("socket_ready", "gen=2") + "\n"
            + event("gate_rejected", "code=stale_socket_ready origin=socket gen=0") + "\n"),
    /gen must be positive/);
});

test("V60", "stale tracked-open settlement uses a frozen identity-only schema", function() {
    const stale = event("tracked_open_stale",
        "markedBindUnknown=true panelDigest=333333333333") + "\n";
    const report = verifyText(stale + validEvidenceText());
    assert.deepStrictEqual(report.cases.map(item => item.id), ["X01", "X02", "X03", "X04"]);
    assert.throws(() => verifier.parseStructuredEvents(event("tracked_open_stale",
        "markedBindUnknown=1 panelDigest=333333333333") + "\n"), /must be true\/false/);
    assert.throws(() => verifier.parseStructuredEvents(event("tracked_open_stale",
        "markedBindUnknown=true panelDigest=333333333333 sessionId=raw-secret") + "\n"),
    /unexpected or sensitive field 'sessionId'/);
});

test("V61", "process replacement recovery exposes only an allowlisted reason and panel digest", function() {
    const replacement = event("process_replacement_recovery",
        "reason=tracked_open_process_replaced panelDigest=333333333333") + "\n";
    const report = verifyText(replacement + validEvidenceText());
    assert.deepStrictEqual(report.cases.map(item => item.id), ["X01", "X02", "X03", "X04"]);
    assert.throws(() => verifier.parseStructuredEvents(event("process_replacement_recovery",
        "reason=unknown panelDigest=333333333333") + "\n"), /invalid process-replacement recovery reason/);
    assert.throws(() => verifier.parseStructuredEvents(event("process_replacement_recovery",
        "reason=reconnect_process_mismatch panelDigest=333333333333 pid=999") + "\n"),
    /unexpected or sensitive field 'pid'/);
});

let passed = 0;
for (const item of cases) {
    try {
        item.run();
        passed += 1;
        process.stdout.write(`[PASS] ${item.id} ${item.title}\n`);
    } catch (error) {
        process.stderr.write(`[FAIL] ${item.id} ${item.title}: ${error.stack || error}\n`);
        process.exitCode = 1;
    }
}
process.stdout.write(`Chest S0 cross-stack verifier: ${passed}/${cases.length} cases passed\n`);
if (passed !== cases.length) process.exitCode = 1;
