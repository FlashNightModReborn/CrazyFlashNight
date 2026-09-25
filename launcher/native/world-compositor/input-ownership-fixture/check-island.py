"""Real projector/service protocol test. No physical-click or C1 acceptance claim."""
import argparse
import hashlib
import json
from pathlib import Path
import socket
import subprocess
import time
import uuid
import ctypes
from ctypes import wintypes

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]

def main():
    parser = argparse.ArgumentParser(); parser.add_argument('evidence', type=Path); parser.add_argument('--inspect', action='store_true'); args = parser.parse_args()
    evidence = args.evidence.resolve(); evidence.mkdir(parents=True, exist_ok=False)
    frozen = evidence / 'flash'; frozen.mkdir()
    for name in ('C1Bootstrap.swf','C1Island.swf'): (frozen / name).write_bytes((HERE / name).read_bytes())
    movie = frozen / 'C1Bootstrap.swf'; module = frozen / 'C1Island.swf'; projector = ROOT / 'Adobe Flash Player 20.exe'
    session = uuid.uuid4().hex
    closure = hashlib.sha256((HERE / 'island/asset-closure.json').read_bytes() + (HERE / 'island/C1Island.as').read_bytes() + movie.read_bytes() + module.read_bytes()).hexdigest()
    checks, records = [], []
    def check(name, passed, detail=None):
        checks.append(dict(name=name, passed=bool(passed), detail=detail))
        if not passed: raise AssertionError(name)
    with socket.socket() as listener:
        # No SO_REUSEADDR: an existing listener is a collision, never a target.
        listener.bind(('127.0.0.1', 32188)); listener.listen(1); listener.settimeout(20)
        process = subprocess.Popen([str(projector), str(movie)], cwd=ROOT)
        identity = dict(pid=process.pid, session=session, closure=closure, utc=time.time(), protocolStimuli=True,
                        businessInputGrantedByPhysicalSource=False, C1Acceptance=False,
                        artifacts={str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in (movie, module, projector, HERE / 'island/C1Island.as', HERE / 'bootstrap/C1Bootstrap.as')})
        (evidence / 'identity.json').write_text(json.dumps(identity, ensure_ascii=False, indent=2), encoding='utf-8')
        try:
            connection, _ = listener.accept()
            with connection:
                connection.settimeout(10); pending = bytearray()
                def receive(kind=None):
                    while True:
                        while 0 not in pending:
                            data = connection.recv(4096)
                            if not data: raise EOFError('projector disconnected')
                            pending.extend(data)
                            if len(pending) > 131072: raise ValueError('oversized AS2 packet')
                        end = pending.index(0); raw = bytes(pending[:end]); del pending[:end+1]
                        message = json.loads(raw.decode('utf-8')); records.append(message)
                        (evidence / 'as2.jsonl').write_text(''.join(json.dumps(row, ensure_ascii=False) + '\n' for row in records), encoding='utf-8')
                        if kind is None or message.get('kind') == kind or message.get('task') == kind: return message
                epoch, ticket = 1, 1
                def send(op, **fields):
                    message = dict(op=op, session=session, coverage=closure, epoch=epoch, ticket=ticket, geometry=1)
                    message.update(fields); connection.sendall(json.dumps(message, ensure_ascii=False).encode('utf-8') + b'\0')
                receive('BOOT'); send('HELLO'); registered = receive('REGISTER')
                check('cold_closed_real_appearance_registered', registered.get('gateClosed') and registered.get('actorReady')
                      and registered.get('bodyAttached') and registered.get('faceAttached') and not registered.get('persistenceInstalled'), registered)
                check('bootstrap_precedes_legacy_class_drivers', registered.get('policy', {}).get('valid') is True
                      and registered.get('keyPollPresent') is False and registered.get('frameTimerPresent') is False
                      and registered.get('cooldownDriverPresent') is False, registered)
                send('LOAD_MOVIE', path='unregistered-child.swf'); check('unknown_dynamic_load_rejected_at_dispatch', receive('unsupported_operation').get('requested') == 'LOAD_MOVIE')
                send('CANCEL'); check('exact_cancel_receipt', receive('CANCELLED').get('pending') == 0)
                send('LEGACY_TASK_PROBE'); denied_tasks = receive('LEGACY_TASKS_DENIED')
                check('legacy_scheduler_admission_denied_before_queueing', denied_tasks.get('executed') == 0
                      and denied_tasks.get('taskId') == -1 and denied_tasks.get('delayedId') == -1
                      and denied_tasks.get('policy', {}).get('deniedTasks', 0) >= 10
                      and denied_tasks.get('bootstrapMode') == 'closed-legacy-drivers'
                      and not any(denied_tasks.get(key) for key in ('keyPollPresent','frameTimerPresent','cooldownDriverPresent')), denied_tasks)
                send('SNAPSHOT', callId=1); snapshot = receive('plastic_surgery_response')
                check('production_surgery_snapshot_without_mock_save', snapshot.get('success') and snapshot.get('phase') == 'editing'
                      and snapshot.get('current', {}).get('characterName') == '输入验收角色', snapshot)
                send('DENY_PROBE'); denied = receive('WRITE_DENIED')
                check('direct_paid_commit_denied_in_actual_vm', denied.get('error') == 'read_only_capability'
                      and denied.get('name') == '输入验收角色' and denied.get('balance') == 20 and not denied.get('persistenceInstalled'), denied)
                send('RAW_OPENER_PROBE'); check('direct_opener_without_intent_denied', receive('RAW_OPENER_RESULT').get('accepted') is False)
                ticket = 2; send('PREPARE', prefix={'generation':1, 'sequence':10}); prepared = receive('PREPARED')
                check('prepared_still_closed', prepared.get('gateClosed') is True)
                send('GRANT', sequence=9, sourceGeneration=1)
                send('BEGIN', sequence=11, gesture=1, button=1, x=370, y=160)
                check('grant_cannot_change_prepared_prefix', receive('closed_rejected').get('ticket') == ticket)
                send('GRANT', sequence=10, sourceGeneration=1); receive('GRANTED')
                send('BEGIN', sequence=11, gesture=1, button=1, x=10, y=10)
                send('END', sequence=12, gesture=1, begin=11, button=1, x=10, y=10)
                check('actual_shape_miss_cannot_open', receive('end_miss').get('ticket') == ticket)
                send('BEGIN', sequence=13, gesture=2, button=1, x=370, y=160); receive('BEGIN')
                send('END', sequence=14, gesture=2, begin=13, button=1, x=370, y=160)
                opened = receive('panel_request')
                check('production_opener_carries_completed_intent', opened.get('panel') == 'surgery'
                      and opened.get('source') == 'world_plastic_surgery' and opened.get('inputIntent', {}).get('end') == 14, opened)
                epoch = 2; ticket = 3; send('CANCEL'); receive('CANCELLED')
                send('END', sequence=13, gesture=1, begin=11, button=1, x=370, y=160)
                check('cancelled_old_end_rejected', receive('closed_rejected').get('epoch') == 2)
                send('RAW_OPENER_PROBE'); check('opener_intent_consumed_once', receive('RAW_OPENER_RESULT').get('accepted') is False)
                if args.inspect:
                    send('VISUAL'); receive('VISUAL')
                    windows = []
                    callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
                    def collect(hwnd, _):
                        pid = wintypes.DWORD(); ctypes.windll.user32.GetWindowThreadProcessId(ctypes.c_void_p(hwnd), ctypes.byref(pid))
                        if pid.value == process.pid:
                            cloaked = wintypes.DWORD(); name = ctypes.create_unicode_buffer(256)
                            ctypes.windll.user32.GetClassNameW(ctypes.c_void_p(hwnd), name, 256)
                            hr = ctypes.windll.dwmapi.DwmGetWindowAttribute(ctypes.c_void_p(hwnd), 14, ctypes.byref(cloaked), 4)
                            windows.append({'hwnd':hwnd,'class':name.value,'visible':bool(ctypes.windll.user32.IsWindowVisible(ctypes.c_void_p(hwnd))), 'cloaked':cloaked.value,'cloakHr':hr})
                        return True
                    ctypes.windll.user32.EnumWindows(callback_type(collect), 0)
                    (evidence / 'inspect-ready.json').write_text(json.dumps({'pid': process.pid, 'windowUnmodified': True,'windows':windows}), encoding='utf-8')
                    deadline = time.monotonic() + 180
                    while not (evidence / 'inspect.flag').is_file() and time.monotonic() < deadline: time.sleep(.1)
                    if not (evidence / 'inspect.flag').is_file(): raise TimeoutError('Unmodified projector inspection')
        finally:
            # Exact process launched above, disposable no-save VM, never player runtime.
            if process.poll() is None: process.terminate()
            process.wait(timeout=10)
            (evidence / 'result.json').write_text(json.dumps(dict(checks=checks, C1Acceptance=False), ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'Actual isolated Flash protocol/service checks: {len(checks)} passed; no C1 acceptance')

if __name__ == '__main__': main()
