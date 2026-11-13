"""Launch an MCP stdio server command like Claude Code would; do initialize + tools/call ping."""
import json, subprocess, sys, threading, time
cmd = sys.argv[1:]
t0 = time.time()
p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=sys.stderr, text=True)
threading.Timer(240, p.kill).start()
def send(o): p.stdin.write(json.dumps(o) + "\n"); p.stdin.flush()
send({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"spike","version":"0"}}})
ok = False
for line in p.stdout:
    m = json.loads(line)
    if m.get("id") == 1:
        send({"jsonrpc":"2.0","method":"notifications/initialized"})
        send({"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"ping","arguments":{}}})
    elif m.get("id") == 2:
        print("PING RESULT:", m["result"]["content"][0]["text"]); ok = True; break
print("elapsed_s=%.1f" % (time.time() - t0))
p.kill()
sys.exit(0 if ok else 1)
