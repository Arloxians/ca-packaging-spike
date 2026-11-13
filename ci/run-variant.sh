#!/usr/bin/env bash
# usage: run-variant.sh <variant>   (runs from repo root, node already hidden)
v=$1; root=$PWD
echo "::group::variant $v"
case "$OSTYPE" in msys*|cygwin*) WIN=1;; *) WIN=0;; esac
if [ "$v" = vb-exe ] && [ $WIN = 0 ]; then echo "RESULT $v: SKIP (windows only)"; exit 0; fi
# prepare per-variant plugin contents
if [ $WIN = 1 ] && [ "$v" != va ]; then (cd launcher && go build -o "$root/plugins/$v/bin/ca-launch.exe" .) || { echo "RESULT $v: FAIL (go build)"; exit 1; }; fi
if [ "$v" = vc ]; then
  mkdir -p plugins/vc/runtime; cp dist/hello.cjs plugins/vc/runtime/
  V=v22.23.5
  case "$(uname -s)-$(uname -m)" in
    Darwin-arm64) F=node-$V-darwin-arm64.tar.gz;; Darwin-x86_64) F=node-$V-darwin-x64.tar.gz;;
    Linux-aarch64) F=node-$V-linux-arm64.tar.gz;; Linux-x86_64) F=node-$V-linux-x64.tar.gz;; *) F=node-$V-win-x64.zip;; esac
  mkdir -p /tmp/nodedl && curl -fsSL https://nodejs.org/dist/$V/$F -o /tmp/nodedl/$F
  echo "node archive size: $(wc -c < /tmp/nodedl/$F)"
  cd /tmp/nodedl && if [ "${F##*.}" = zip ]; then unzip -q $F; cp */node.exe "$root/plugins/vc/runtime/node.exe"; else tar xzf $F; cp */bin/node "$root/plugins/vc/runtime/node"; fi; cd "$root"
  echo "SIZE vc runtime dir bytes: $(du -sk plugins/vc | cut -f1) KB (this OS only)"
fi
claude plugin install "$v@spike" 2>&1 | tail -3
T0=$(date +%s)
out=$(timeout 300 claude mcp list 2>&1); echo "$out"
echo "claude mcp list took $(( $(date +%s) - T0 ))s"
if echo "$out" | grep -i "plugin:$v:hello" | grep -qi "connected\|✓"; then echo "RESULT $v: PASS (claude mcp list Connected)"; res=pass; else res=fail; fi
# fallback: launch as Claude Code would
inst=$(find "$HOME/.claude/plugins" -path "*cache*" -type d -name "$v" -prune 2>/dev/null | head -1)
[ -z "$inst" ] && inst=$(find "$HOME/.claude/plugins" -type d -path "*$v/*" -name .claude-plugin 2>/dev/null | head -1 | xargs -r dirname)
echo "installed at: $inst"; ls -la "$inst" 2>&1 | head -20
export CLAUDE_PLUGIN_DATA="$HOME/.claude/plugins/data/$v-spike-ci"; mkdir -p "$CLAUDE_PLUGIN_DATA"
rm -rf "$CLAUDE_PLUGIN_DATA"/*
if [ "$v" = va ]; then
  echo "mcpb fallback: manifest command is 'node' (no node on PATH):"; which node || echo "node not found"
  python3 ci/mcp_init.py node "$inst/server/hello.cjs" && echo "RESULT $v fallback: PASS" || echo "RESULT $v fallback: FAIL"
else
  cmd="$inst/bin/ca-launch"; [ $WIN = 1 ] && cmd="$inst/bin/ca-launch.exe"
  [ $WIN = 1 ] && cmd=$(cygpath -w "$cmd")
  echo "--- first run"; python3 ci/mcp_init.py "$cmd" && echo "RESULT $v fallback first-run: PASS" || echo "RESULT $v fallback first-run: FAIL"
  echo "--- second run"; python3 ci/mcp_init.py "$cmd" && echo "RESULT $v fallback second-run: PASS" || echo "RESULT $v fallback second-run: FAIL"
  cat "$CLAUDE_PLUGIN_DATA/launch.log" 2>/dev/null
  echo "SIZE data dir: $(du -sk "$CLAUDE_PLUGIN_DATA" | cut -f1) KB"
  if [ "$(uname -s)" = Darwin ]; then echo "quarantine xattrs:"; xattr -rl "$CLAUDE_PLUGIN_DATA" | grep -c quarantine; fi
  if [ $WIN = 1 ]; then powershell -NoProfile -Command "Get-ChildItem -Recurse '$(cygpath -w "$CLAUDE_PLUGIN_DATA")' -Filter node.exe | ForEach-Object { Get-Item \$_.FullName -Stream * | Select Stream,Length }"; fi
fi
echo "SIZE installed plugin: $(du -sk "$inst" | cut -f1) KB"
echo "::endgroup::"
