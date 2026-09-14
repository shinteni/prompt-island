# Compare isolated native app CPU time, RSS and Hook acknowledgement latency.
# Synthetic fixture: 5,000 history files, 15 seconds idle, then 4 Hooks/second for 15 seconds.
# Temporary fixtures are retained for inspection; no real project data is used.
import json, os, pathlib, socket, statistics, subprocess, sys, tempfile, time

def cpu_time(pid):
    value = subprocess.check_output(['/bin/ps','-o','time=','-p',str(pid)], text=True).strip()
    fields = value.split(':')
    return sum(float(x) * 60 ** n for n,x in enumerate(reversed(fields)))

def run(binary,label):
    root=pathlib.Path(tempfile.mkdtemp(prefix='island-runtime-',dir='/tmp'))
    config=root/'Library/Application Support/VibelslandFree/config.json'
    config.parent.mkdir(parents=True)
    config.write_text(json.dumps(dict(enableClaude=True,enableCodexCLI=False,enableCodexDesktop=False,enableSounds=False,doNotDisturb=True,launchAtLogin=False,enableApprovalNotifications=False,enableGlobalHotKeys=False,autoCheckUpdates=False,language='chinese',maxVisibleSessions=5)))
    history=root/'.claude/projects/project'; history.mkdir(parents=True)
    for i in range(5000): (history/f'history-{i}.jsonl').touch()
    transcript=root/'active.jsonl'; transcript.write_text('{"type":"user","message":{"content":"Performance verification"}}\n')
    env={**os.environ,'VIBELSLAND_HOME':str(root),'VIBELSLAND_SKIP_LAUNCH_INTRO':'1','VIBELSLAND_CODEX_IPC_SOCKET':str(root/'missing.sock')}
    proc=subprocess.Popen([binary],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    try:
        sock=root/'.vibelsland-free/run/vibelsland.sock'
        for _ in range(100):
            if sock.exists(): break
            if proc.poll() is not None: raise RuntimeError('App exited early')
            time.sleep(.1)
        time.sleep(3)
        start_cpu=cpu_time(proc.pid); start=time.monotonic()
        time.sleep(15)
        idle=100*(cpu_time(proc.pid)-start_cpu)/(time.monotonic()-start)
        token=(root/'.vibelsland-free/run/bridge-token').read_text().strip()
        latencies=[]; rss=[]; start_cpu=cpu_time(proc.pid); start=time.monotonic()
        for i in range(60):
            at=time.monotonic()
            payload=dict(source='claude',event='PreToolUse',session_id='active',cwd=str(root),token=token,payload=dict(tool_name='Read',tool_input={'file_path':f'fixture-{i}.swift'},transcript_path=str(transcript)))
            with socket.socket(socket.AF_UNIX) as client:
                client.settimeout(5); client.connect(str(sock)); client.sendall(json.dumps(payload).encode()); client.shutdown(socket.SHUT_WR)
                while client.recv(1024): pass
            latencies.append((time.monotonic()-at)*1000)
            if i%4==0: rss.append(int(subprocess.check_output(['/bin/ps','-o','rss=','-p',str(proc.pid)],text=True)))
            time.sleep(max(0,.25-(time.monotonic()-at)))
        active=100*(cpu_time(proc.pid)-start_cpu)/(time.monotonic()-start)
        result=dict(label=label,idle_cpu_percent=round(idle,2),active_cpu_percent=round(active,2),active_rss_peak_mb=round(max(rss)/1024,1),hook_ack_median_ms=round(statistics.median(latencies),2),hook_ack_p95_ms=round(sorted(latencies)[56],2),fixture_home=str(root))
        print(json.dumps(result),flush=True)
        return result
    finally:
        proc.terminate(); proc.wait(timeout=10)

if len(sys.argv) != 3:
    raise SystemExit('Usage: python3 scripts/benchmark-runtime.py <baseline-binary> <candidate-binary>')
run(str(pathlib.Path(sys.argv[1]).resolve()), 'baseline')
run(str(pathlib.Path(sys.argv[2]).resolve()), 'candidate')

