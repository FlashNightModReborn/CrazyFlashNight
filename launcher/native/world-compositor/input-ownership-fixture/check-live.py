"""Declared SendInput integration stimuli, not hardware/IME or human acceptance."""
import argparse
import ctypes
from ctypes import wintypes as W
import json
from pathlib import Path
import subprocess
import time
import uuid
import threading

u = ctypes.WinDLL('user32', use_last_error=True)
u.SetProcessDpiAwarenessContext(ctypes.c_void_p(-4))
u.GetForegroundWindow.restype = W.HWND
u.GetAncestor.argtypes = [W.HWND, W.UINT]; u.GetAncestor.restype = W.HWND
u.WindowFromPoint.restype = W.HWND
u.SetWindowPos.argtypes = [W.HWND, W.HWND, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, W.UINT]
class MI(ctypes.Structure):
    _fields_ = [('dx',W.LONG),('dy',W.LONG),('data',W.DWORD),('flags',W.DWORD),('time',W.DWORD),('extra',ctypes.c_size_t)]
class KI(ctypes.Structure):
    _fields_ = [('vk',W.WORD),('scan',W.WORD),('flags',W.DWORD),('time',W.DWORD),('extra',ctypes.c_size_t)]
class U(ctypes.Union):
    _fields_ = [('mi',MI),('ki',KI)]
class Input(ctypes.Structure):
    _fields_ = [('type',W.DWORD),('u',U)]

class Msg(ctypes.Structure):
    _fields_=[('hwnd',W.HWND),('message',W.UINT),('wp',W.WPARAM),('lp',W.LPARAM),('time',W.DWORD),('point',W.POINT),('private',W.DWORD)]
def pause(seconds):
    deadline=time.monotonic()+seconds
    while time.monotonic()<deadline:
        message=Msg()
        while u.PeekMessageW(ctypes.byref(message),None,0,0,1):
            u.TranslateMessage(ctypes.byref(message));u.DispatchMessageW(ctypes.byref(message))
        time.sleep(min(.01,max(0,deadline-time.monotonic())))

def send(down, key=None):
    value = Input()
    if key is None:
        value.u.mi.flags = 2 if down else 4; value.u.mi.extra = 0xC111
    else:
        value.type = 1; value.u.ki.scan = u.MapVirtualKeyW(key,0); value.u.ki.flags = 8 | (0 if down else 2); value.u.ki.extra = 0xC111
    assert u.SendInput(1,ctypes.byref(value),ctypes.sizeof(value)) == 1, 'SendInput rejected'

class SmokeComplete(Exception):pass

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('dotnet'); parser.add_argument('bin',type=Path); parser.add_argument('evidence',type=Path)
    parser.add_argument('--late-key-negative',action='store_true')
    parser.add_argument('--disconnect-probe',action='store_true')
    parser.add_argument('--smoke',action='store_true')
    parser.add_argument('--capture',action='store_true')
    parser.add_argument('--presentation-check',action='store_true')
    parser.add_argument('--aspect-stress',action='store_true')
    parser.add_argument('--delay-read-probe',action='store_true')
    parser.add_argument('--end-settlement-check',action='store_true')
    parser.add_argument('--core-entry',action='store_true',help='Use the verified producer runtime/Core.dll candidate startup')
    parser.add_argument('--duplicate-release-probe',action='store_true')
    parser.add_argument('--source-disabled-probe',action='store_true')
    args = parser.parse_args()
    if args.duplicate_release_probe and not args.end_settlement_check:
        parser.error('--duplicate-release-probe requires --end-settlement-check')
    root = Path(__file__).resolve().parents[4]
    evidence = args.evidence.resolve(); evidence.mkdir(parents=True, exist_ok=False)
    command = ([args.dotnet,str(args.bin.resolve()/'CRAZYFLASHER7MercenaryEmpire.Core.dll'),'--project-root',str(root),
                '--unified-input-candidate','c1','--evidence',str(evidence),'--diagnostic-input']
               if args.core_entry else
               [args.dotnet,str(args.bin.resolve()/'C1IslandHost.dll'),str(root),str(evidence),'--interactive'])
    process = subprocess.Popen(command,cwd=root)
    checks, stimuli = [], []; hwnd = None; external = None; held = set()
    samples=[]; sampling=threading.Event(); sampler=None
    def sample_presentation():
        from PIL import ImageGrab
        while sampling.is_set():
            rect=W.RECT()
            if not u.GetClientRect(W.HWND(hwnd),ctypes.byref(rect)) or u.IsIconic(W.HWND(hwnd)): pause(.02);continue
            scale=min(rect.right/640,rect.bottom/360)
            p=W.POINT(round((rect.right-640*scale)/2+36*scale),round((rect.bottom-360*scale)/2+116*scale))
            if not u.ClientToScreen(W.HWND(hwnd),ctypes.byref(p)) or u.GetAncestor(u.WindowFromPoint(p),2)!=hwnd: time.sleep(.01);continue
            # The real AS2 heartbeat is alternating fully saturated green or
            # magenta. Sample screen output, not a DOM/state acknowledgement.
            rgb=ImageGrab.grab(bbox=(p.x,p.y,p.x+1,p.y+1),all_screens=True).getpixel((0,0))[:3]
            exposed=(rgb[0]>220 and rgb[1]<35 and rgb[2]>220) or (rgb[0]<35 and rgb[1]>220 and rgb[2]<35)
            samples.append({'utc':time.time(),'rgb':rgb,'exposed':exposed})
            time.sleep(.015)
    def start_samples():
        nonlocal sampler
        if args.presentation_check:
            sampling.set();sampler=threading.Thread(target=sample_presentation,daemon=True);sampler.start()
    def stop_samples():
        sampling.clear()
        if sampler: sampler.join(5)
    def records():
        path = evidence/'events.jsonl'
        if not path.exists(): return []
        lines = path.read_text(encoding='utf-8').splitlines()
        result=[]
        for line in lines:
            try: result.append(json.loads(line))
            except json.JSONDecodeError: pass # concurrent trailing write; never accepted as result
        return result
    def wait(predicate, label, timeout=15):
        end=time.monotonic()+timeout
        while time.monotonic()<end:
            if process.poll() is not None: raise RuntimeError('Candidate exited: '+label)
            result=predicate(records())
            if result: return result
            pause(.03)
        raise TimeoutError(label)
    def check(name, condition):
        checks.append({'name':name,'passed':bool(condition)})
        assert condition,name
    def probe(op='state'):
        ident=uuid.uuid4().hex
        temp=evidence/'probe.next'; temp.write_text(json.dumps({'id':ident,'op':op}),encoding='utf-8'); 
        for retry in range(20):
            try: temp.replace(evidence/'probe.json'); break
            except PermissionError:
                if retry==19: raise
                pause(.01)
        return wait(lambda rows: next((r['detail'] for r in rows if r['kind']=='live_probe' and r['detail']['id']==ident),None),'probe '+op)
    def ready(owner):
        end=time.monotonic()+15
        while time.monotonic()<end:
            state=probe(); current=state['state']['Owner']
            page=json.loads(json.loads(state['page']))
            if current and current['Id']==owner and state['state']['Phase']==4:
                if owner!='Web' or (page.get('gate',{}).get('granted',False) and page['gate']['round']['ticket']==state['state']['Round']['Ticket']): return state
            pause(.04)
        raise TimeoutError(owner+' exact endpoint ready')
    def point(x,y):
        p=W.POINT(x,y); assert u.ClientToScreen(W.HWND(hwnd),ctypes.byref(p)); return p
    def move(x,y):
        p=point(x,y); assert u.SetCursorPos(p.x,p.y); pause(.08)
    def click(x,y):
        assert u.GetForegroundWindow()==hwnd,'Candidate lost foreground before stimulus'
        move(x,y); p=point(x,y); assert u.GetAncestor(u.WindowFromPoint(p),2)==hwnd,'Stimulus target is obscured'; send(True);held.add(None);pause(.12);send(False);held.remove(None)
        stimuli.append({'kind':'click','x':x,'y':y,'injected':True,'utc':time.time()})
    def target(id):
        page=json.loads(json.loads(probe()['page']))
        item=next(t for t in page['targets'] if t and t['id']==id)
        click(round(item['x']),round(item['y']))
        if id=='surgery-character-name':
            end=time.monotonic()+3
            while time.monotonic()<end:
                state=probe(); page=json.loads(json.loads(state['page'])); ev=page['gate'].get('events',{})
                if state['state']['Phase']==4 and page['active']==id and ev.get('mouseup',0)>=ev.get('mousedown',0):break
                pause(.02)
            else:raise TimeoutError('Actual text-field pointer completion')
    def world_click():
        r=W.RECT();assert u.GetClientRect(W.HWND(hwnd),ctypes.byref(r))
        scale=min(r.right/640,r.bottom/360)
        click(round((r.right-640*scale)/2+370*scale),round((r.bottom-360*scale)/2+160*scale))
    def capture(name, activate=True):
        if args.capture:
            command=['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',str(root/'scripts/capture_screenshot.ps1'),'-TargetProcessId',str(process.pid),'-OutputPath',str(evidence/(name+'.png'))]
            if not activate: command.append('-NoActivate')
            subprocess.run(command,check=True)
    def key(vk):
        assert u.GetForegroundWindow()==hwnd
        send(True,vk);held.add(vk);pause(.08);send(False,vk);held.remove(vk)
        stimuli.append({'kind':'key','vk':vk,'injected':True,'utc':time.time()})
    try:
        wait(lambda rows:any(r['kind']=='live_started' for r in rows),'cold setup',40)
        windows=[]
        cb=ctypes.WINFUNCTYPE(W.BOOL,W.HWND,W.LPARAM)
        def collect(window,_):
            pid=W.DWORD();u.GetWindowThreadProcessId(W.HWND(window),ctypes.byref(pid))
            if pid.value==process.pid and u.IsWindowVisible(W.HWND(window)):
                title=ctypes.create_unicode_buffer(256);u.GetWindowTextW(W.HWND(window),title,256)
                if title.value.startswith('CF7 C1 live'):windows.append(window)
            return True
        u.EnumWindows(cb(collect),0);assert len(windows)==1;hwnd=windows[0]
        # One bounded, identity-checked setup activation. No product focus loop.
        u.SetWindowPos(hwnd,W.HWND(-1),0,0,0,0,0x13)
        r=W.RECT();u.GetWindowRect(W.HWND(hwnd),ctypes.byref(r));p=W.POINT(r.left+150,r.top+16)
        u.SetCursorPos(p.x,p.y);pause(.08)
        hit=u.WindowFromPoint(p)
        (evidence/'setup.json').write_text(json.dumps({'target':hwnd,'hit':hit,'hitRoot':u.GetAncestor(hit,2),'point':[p.x,p.y],'temporaryTopmost':True}),encoding='utf-8')
        assert u.GetAncestor(hit,2)==hwnd,'Setup point obscured'
        send(True);held.add(None);pause(.08);send(False);held.remove(None)
        wait(lambda _:u.GetForegroundWindow()==hwnd,'exact foreground')
        u.SetWindowPos(hwnd,W.HWND(-2),0,0,0,0,0x13)
        ready('M');check('cold_actual_m_ready',True);capture('world')
        if args.source_disabled_probe:
            first=probe('visual_state')['visual'];pause(.2);second=probe('visual_state')['visual']
            check('disabled_source_still_advances_actual_as2_frames',second['frames']>first['frames'])
            check('source_parent_and_flash_input_are_disabled',any(r['kind']=='embedded_source_remains_input_disabled' and r['detail']['passed'] for r in records()))
        original_rect=W.RECT();u.GetWindowRect(W.HWND(hwnd),ctypes.byref(original_rect))
        if args.end_settlement_check: probe('delay_next_intent')
        if args.delay_read_probe: probe('delay_next_snapshot')
        if args.delay_read_probe:
            world_click()
            wait(lambda rows:any(r['kind']=='declared_snapshot_delay' for r in rows),'actual snapshot held in transport')
            u.SetWindowPos(hwnd,None,0,0,495,800,0x16);pause(.15)
            ready('Web')
            check('delayed_actual_snapshot_survives_geometry_revocation',any(r['kind']=='live_readonly_request' and r['detail']['accepted'] and r['detail']['round']['Geometry']<r['detail']['current']['Geometry'] for r in records()))
            capture('narrow-restored')
            u.SetWindowPos(hwnd,None,0,0,original_rect.right-original_rect.left,original_rect.bottom-original_rect.top,0x16)
            ready('Web')
        else:
            world_click()
            if args.duplicate_release_probe:
                pause(.06);send(False)
                stimuli.append({'kind':'declared_duplicate_pointer_up','injected':True,'utc':time.time()})
            if args.end_settlement_check: move(120,548)
            ready('Web')
        pause(.2)
        state=probe();check('actual_opener_once_and_web_granted',state['liveOpenCount']==1 and state['liveCloseCount']==0);capture('web')
        if args.duplicate_release_probe:
            check('observed_duplicate_release_does_not_discard_or_replay_opener',state['duplicatePointerReleases']>0 and state['liveOpenCount']==1)
        if args.aspect_stress:
            expected=json.loads(json.loads(probe()['page']))['panel']['draft']
            for cycle in range(3):
                send(True,16);held.add(16)
                for width,height in [(495,800),(1500,360),(600,880),(1550,620),(430,615),(1026,615)]*3:
                    u.SetWindowPos(hwnd,None,0,0,width,height,0x16);pause(.065)
                send(False,16);held.remove(16)
                ready('Web')
                page=json.loads(json.loads(probe()['page']))
                check('aspect_storm_restores_real_page_and_draft_'+str(cycle),page['panel']['draft']==expected and not probe().get('frozenPresentation',False))
            u.SetWindowPos(hwnd,None,0,0,original_rect.right-original_rect.left,original_rect.bottom-original_rect.top,0x16)
            ready('Web');capture('aspect-restored')
        target('surgery-character-name');key(65);pause(.1)
        state=probe();page=json.loads(json.loads(state['page']))
        check('real_keyboard_changes_production_draft','a' in page['panel']['draft']['characterName'].lower())
        if args.late_key_negative:
            class Gui(ctypes.Structure):
                _fields_=[('size',W.DWORD),('flags',W.DWORD),('active',W.HWND),('focus',W.HWND),('capture',W.HWND),('menu',W.HWND),('move',W.HWND),('caret',W.HWND),('rect',W.RECT)]
            gui=Gui();gui.size=ctypes.sizeof(gui);assert u.GetGUIThreadInfo(0,ctypes.byref(gui))
            old_focus=gui.focus;assert old_focus and u.GetAncestor(old_focus,2)==hwnd
            old_round=page['gate']['round']
            probe('source_fault');pause(.2);ready('Web');target('surgery-character-name')
            before=json.loads(json.loads(probe()['page']))
            assert before['gate']['round']['epoch']>old_round['epoch']
            u.PostMessageW.argtypes=[W.HWND,W.UINT,W.WPARAM,W.LPARAM]
            posted=0
            if u.IsWindow(W.HWND(old_focus)) and u.GetAncestor(old_focus,2)==hwnd:
                for msg,wp,lp in [(0x100,90,(44<<16)|1),(0x102,ord('z'),(44<<16)|1),(0x101,90,0xc0000001|(44<<16))]:
                    posted+=bool(u.PostMessageW(old_focus,msg,wp,lp))
            stimuli.append({'kind':'declared_old_hwnd_keyboard_tail','hwnd':old_focus,'fromRound':old_round,'noNewRawKey':True,'posted':posted,'oldTargetAlive':bool(u.IsWindow(W.HWND(old_focus)))})
            pause(.15);after=json.loads(json.loads(probe()['page']))
            check('old_hwnd_tail_cannot_mutate_new_epoch_draft',after['panel']['draft']==before['panel']['draft'])
            check('new_web_incarnation_after_actual_retirement',probe()['state']['Owner']['Incarnation']>1)
        target('surgery-cancel');ready('M');state=probe()
        check('real_cancel_returns_to_world_without_reopen',state['liveOpenCount']==1 and state['liveCloseCount']==1)
        if args.end_settlement_check:
            check('delayed_end_intent_survives_native_hover',any(r['kind']=='declared_intent_delay' for r in records()) and state['liveOpenCount']==1)
            click(450,100);move(120,548);ready('Native')
            check('empty_click_settles_and_releases_hover',any(r['kind']=='live_end_settlement' and r['detail']['kind']=='end_miss' and r['detail']['settled'] for r in records()))
            move(450,300);ready('M')
        if args.smoke:raise SmokeComplete()
        move(120,548);ready('Native');state=probe();check('real_native_resource_tooltip',state['nativeVisible'])
        move(450,300);ready('M');state=probe();check('native_leave_retires_tooltip',not state['nativeVisible'])
        world_click();ready('Web');pause(.2);target('surgery-character-name');key(27);ready('M');state=probe()
        check('escape_complete_gesture_uses_production_close',state['liveCloseCount']==2)
        state=probe('data_fault');pause(.2);state=probe()
        check('failed_data_lane_keeps_owner_closed',state['state']['Owner'] is None)
        probe('transport_recovered');ready('M');world_click();ready('Web');state=probe()
        check('recovered_transport_accepts_one_fresh_input',state['liveOpenCount']==3)
        target('surgery-cancel');ready('M');probe('source_fault');pause(.3);ready('M')
        world_click();ready('Web');state=probe()
        check('actual_source_recovery_has_fresh_business_input',state['liveOpenCount']==4)
        target('surgery-cancel');ready('M')
        # A held world gesture is cancelled when the actual screen geometry changes.
        move(592,256);send(True);held.add(None);pause(.1)
        rect=W.RECT();u.GetWindowRect(W.HWND(hwnd),ctypes.byref(rect))
        u.SetWindowPos(hwnd,None,rect.left+70,rect.top+40,0,0,0x15)
        pause(.15);send(False);held.remove(None);ready('M')
        check('held_move_does_not_retarget_old_end',probe()['liveOpenCount']==4)
        u.SetWindowPos(hwnd,None,0,0,1120,800,0x16)
        pause(.15);ready('M');world_click();ready('Web')
        check('resized_letterbox_uses_real_stage_hit',probe()['liveOpenCount']==5)
        if args.presentation_check:
            start_samples()
            rect=W.RECT();u.GetWindowRect(W.HWND(hwnd),ctypes.byref(rect))
            for i in range(8):
                u.SetWindowPos(hwnd,None,rect.left+i*4,rect.top+i*2,1120+i*5,800-i*3,0x14);pause(.09)
            ready('Web');pause(.2);stop_samples()
            check('web_after_repeated_move_resize_restored',probe().get('modalPresentation',True) and not probe().get('frozenPresentation',False))
        target('surgery-cancel');ready('M')
        # A disposable native window provides a real external foreground domain.
        u.CreateWindowExW.restype=W.HWND
        u.CreateWindowExW.argtypes=[W.DWORD,W.LPCWSTR,W.LPCWSTR,W.DWORD,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_int,W.HWND,W.HMENU,W.HINSTANCE,ctypes.c_void_p]
        external=u.CreateWindowExW(0,'STATIC','CF7 external-input probe',0x00cf0000,1400,80,260,120,None,None,None,None)
        assert external
        send(True,17);held.add(17)
        u.ShowWindow(W.HWND(external),4)
        u.SetForegroundWindow(W.HWND(external));pause(.15)
        assert u.GetForegroundWindow()==external
        send(False,17);held.remove(17);pause(.15)
        u.SetWindowPos(hwnd,None,0,0,0,0,0x13)
        r=W.RECT();u.GetClientRect(W.HWND(hwnd),ctypes.byref(r));scale=min(r.right/640,r.bottom/360)
        p=point(round((r.right-640*scale)/2+370*scale),round((r.bottom-360*scale)/2+160*scale))
        u.SetCursorPos(p.x,p.y);pause(.06)
        assert u.GetAncestor(u.WindowFromPoint(p),2)==hwnd
        send(True);held.add(None);pause(.12);send(False);held.remove(None)
        ready('M');check('external_release_and_activation_click_do_not_open',probe()['liveOpenCount']==5)
        world_click();ready('Web');check('first_fresh_click_after_activation_opens_once',probe()['liveOpenCount']==6)
        target('surgery-character-name');key(65)
        retained=json.loads(json.loads(probe()['page']))['panel']['draft']
        start_samples()
        u.SetForegroundWindow(W.HWND(external));assert u.GetForegroundWindow()==external,'External setup activation failed';pause(6 if args.end_settlement_check else .4)
        check('web_replacement_does_not_steal_external_foreground',u.GetForegroundWindow()==external)
        if args.presentation_check and args.capture:
            state=probe()
            check('background_retains_read_only_bitmap',state['frozenPresentation'] and state['state']['Owner'] is None)
            capture('frozen-background',False)
            if args.aspect_stress:
                before=W.RECT();u.GetWindowRect(W.HWND(hwnd),ctypes.byref(before))
                u.SetWindowPos(hwnd,None,0,0,495,800,0x16);pause(.2)
                capture('frozen-narrow',False)
                u.SetWindowPos(hwnd,None,0,0,before.right-before.left,before.bottom-before.top,0x16);pause(.1)
            check('visual_observation_does_not_activate_candidate',u.GetForegroundWindow()==external)
        u.SetWindowPos(hwnd,None,0,0,0,0,0x13)
        r=W.RECT();u.GetWindowRect(W.HWND(hwnd),ctypes.byref(r));u.SetCursorPos(r.left+150,r.top+16)
        send(True);held.add(None);pause(.1);send(False);held.remove(None)
        ready('Web')
        check('focus_return_restores_committed_draft',json.loads(json.loads(probe()['page']))['panel']['draft']==retained)
        pause(.2);stop_samples()
        if args.presentation_check:
            check('screen_samples_cover_real_transitions',len(samples)>=20)
            check('no_uncovered_as2_heartbeat_during_web_transitions',not any(s['exposed'] for s in samples))
            rows=records()
            for index,row in enumerate(rows):
                if row['kind']=='web_controller_retired' and row['detail']['draftRetained']:
                    presentation=next((r['detail'] for r in reversed(rows[:index]) if r['kind']=='presentation'),None)
                    check('retirement_has_independent_frozen_presentation',presentation and presentation['modal'] and presentation['frozen'])
        target('surgery-cancel');ready('M')
        u.ShowWindow(W.HWND(hwnd),6);pause(.15)
        check('minimized_owner_is_closed',probe()['state']['Owner'] is None)
        u.ShowWindow(W.HWND(hwnd),9)
        u.SetWindowPos(hwnd,None,0,0,0,0,0x13)
        r=W.RECT();u.GetWindowRect(W.HWND(hwnd),ctypes.byref(r));p=W.POINT(r.left+150,r.top+16)
        u.SetCursorPos(p.x,p.y);pause(.06);assert u.GetAncestor(u.WindowFromPoint(p),2)==hwnd
        send(True);held.add(None);pause(.1);send(False);held.remove(None)
        ready('M');world_click();ready('Web')
        check('restore_accepts_fresh_input',probe()['liveOpenCount']==7)
        target('surgery-character-name');key(65)
        before=json.loads(json.loads(probe()['page']))['panel']['draft']
        probe('composition_begin');during=json.loads(json.loads(probe()['page']))['panel']['draft']
        check('declared_composition_reaches_actual_handler',during!=before)
        probe('source_fault');pause(.15);ready('Web')
        after=json.loads(json.loads(probe()['page']))['panel']['draft']
        check('retirement_discards_composition_but_preserves_committed_draft',after==before)
        target('surgery-cancel');ready('M')
        def tab_cancel():
            target('surgery-character-name')
            for _ in range(10):
                key(9);page=json.loads(json.loads(probe()['page']))
                if page.get('active')=='surgery-cancel':return
            raise AssertionError('Tab did not reach real cancel button')
        world_click();ready('Web');tab_cancel();move(-10,-10);key(13);ready('M')
        check('tab_and_enter_work_with_pointer_outside',probe()['liveCloseCount']==8)
        world_click();ready('Web');tab_cancel()
        send(True,32);held.add(32);pause(.06);probe('source_fault');pause(6 if args.end_settlement_check else .1)
        send(False,32);held.remove(32);ready('Web')
        check('held_keyboard_tail_does_not_close_replacement',probe()['liveCloseCount']==8)
        tab_cancel();key(32);ready('M');check('fresh_space_activates_once',probe()['liveCloseCount']==9)
        # Real AS2 BEGIN exists when data delivery fails; control cancellation
        # must clear it without forwarding the release as a fresh operation.
        r=W.RECT();u.GetClientRect(W.HWND(hwnd),ctypes.byref(r));scale=min(r.right/640,r.bottom/360)
        move(round((r.right-640*scale)/2+370*scale),round((r.bottom-360*scale)/2+160*scale))
        send(True);held.add(None);pause(.08);probe('data_fault')
        send(False);held.remove(None);pause(.1)
        check('pending_as2_begin_cancelled_on_data_failure',probe()['liveOpenCount']==9)
        probe('transport_recovered');ready('M');world_click();ready('Web')
        check('fresh_input_after_pending_as2_cancel',probe()['liveOpenCount']==10)
        target('surgery-cancel');ready('M')
        if args.end_settlement_check:
            probe('drop_next_prepared');world_click()
            wait(lambda rows:any(r['kind']=='live_protocol_fault' and r['detail']['protocolFault']=='prepare_ack_timeout' for r in rows),'lost prepared bounded failure',12)
            state=probe()
            check('missing_prepared_faults_without_grant',state['state']['Owner'] is None and state['state']['Phase'] in (1,6))
        if args.disconnect_probe:
            temp=evidence/'probe.next';temp.write_text(json.dumps({'id':uuid.uuid4().hex,'op':'disconnect'}),encoding='utf-8');temp.replace(evidence/'probe.json')
            deadline=time.monotonic()+8
            while process.poll() is None and time.monotonic()<deadline:pause(.03)
            check('lost_peer_retires_candidate_without_new_grant',process.poll()==2 and any(r['kind']=='transport_terminal' for r in records()))
        outcome='passed' 
    except SmokeComplete:
        outcome='passed'
    except Exception as error:
        try: probe()
        except Exception: pass
        outcome='failed';checks.append({'name':'execution','passed':False,'error':repr(error)})
    finally:
        stop_samples()
        if args.presentation_check: (evidence/'presentation-samples.json').write_text(json.dumps(samples),encoding='utf-8')
        for keycode in held: send(False,keycode)
        if external: u.DestroyWindow(W.HWND(external))
        (evidence/'stop.request').touch()
        try: process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            if hwnd: u.PostMessageW(W.HWND(hwnd),0x10,0,0)
        try: process.wait(timeout=7)
        except subprocess.TimeoutExpired: process.kill()
        (evidence/'live-result.json').write_text(json.dumps({'outcome':outcome,'checks':checks,'stimuli':stimuli,
            'declaredInjectedStimuli':True,'C1Acceptance':False,'humanAcceptance':False},ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'outcome':outcome,'checks':checks},ensure_ascii=False))
    return 0 if outcome=='passed' else 1

if __name__=='__main__':raise SystemExit(main())
