# Packaging spike: which plugin packaging runs an MCP server with no Node installed

Final run (all 5 jobs green): https://github.com/Arloxians/ca-packaging-spike/actions/runs/43415454393 (commit 794d7fb)
Claude Code 2.1.323 installed with the native installer on each runner. Node/npm/npx/corepack were moved out of PATH
(`ci/hide-node.sh` asserts `command -v node` is empty). Test server: `hello` with tool `ping` using `node:sqlite`, one esbuild-bundled
file (740 KB, no node_modules). Pinned runtime Node v22.23.5.

**Login was NOT needed.** `claude mcp list` runs MCP health checks with no API key; plugin servers appear as `plugin:<plugin>:hello` and show
`Connected`. So the table below is real Claude Code launching the server, not the stdio fallback. As an extra, every variant was also launched
by hand through `ci/mcp_init.py` (initialize then tools/call ping, result `pong node=v22.23.5 sqlite=3.54.1`).

Variants: **A** = plugin whose `mcpServers` is a node-type `hello.mcpb`. **B** = `.mcp.json` command `${CLAUDE_PLUGIN_ROOT}/bin/ca-launch`
(POSIX sh on mac/linux; Go-built `ca-launch.exe` beside it on Windows) which downloads Node (sha256 checked against SHASUMS256.txt) and the app
bundle (sha256 pinned in `bin/app.sha256`) into `${CLAUDE_PLUGIN_DATA}`, then execs node. **B-exe** = same, command ends in `.exe` (Windows only).
**C** = node binary and app inside the plugin, tiny launcher, no download.

| Variant | macOS arm64 (macos-latest) | macOS x64 (macos-15-intel) | Windows x64 | Linux x64 | Linux arm64 |
|---|---|---|---|---|---|
| A (mcpb, node-type) | FAIL | FAIL | FAIL | FAIL | FAIL |
| B (download launcher) | PASS | PASS | PASS | PASS | PASS |
| B-exe (explicit .exe) | n/a | n/a | PASS | n/a | n/a |
| C (bundled runtime) | PASS | PASS | PASS | PASS | PASS |

Job URLs: mac arm64 https://github.com/Arloxians/ca-packaging-spike/actions/runs/43415454393/job/131852075277, mac x64 https://github.com/Arloxians/ca-packaging-spike/actions/runs/43415454393/job/131852074902, windows https://github.com/Arloxians/ca-packaging-spike/actions/runs/43415454393/job/131852075260, linux x64 https://github.com/Arloxians/ca-packaging-spike/actions/runs/43415454393/job/131852075218, linux arm64 https://github.com/Arloxians/ca-packaging-spike/actions/runs/43415454393/job/131852075189.
(The macos-14 label is rejected on this account: "configuration macos-14-arm64-us-default is not supported"; macos-13 stays queued, so macos-latest (arm64) and macos-15-intel were used.)

## Evidence
- **A fails without Node by design.** The mcpb manifest says `command: node`; Claude Code does not supply a Node for it. Linux/mac: `Failed to connect: ENOENT: Executable not found in $PATH: "stdio"`; Windows: `CONNECTION_CLOSED`. Locally, with Node on PATH, the same plugin shows `Connected`, so the bundle itself is fine; it only works where the user already has Node. The Claude Desktop app may behave differently (see human item).
- **B and C pass on all 5 OSes** with `claude mcp list` reporting `plugin:vb:hello ... Connected` / `plugin:vc:hello ... Connected`.
- **Windows resolves the extensionless command.** With `bin/ca-launch` (sh) and `bin/ca-launch.exe` side by side, command `.../bin/ca-launch` connected (it can only have run the .exe, Windows has no sh in that spawn path). Explicit `.../bin/ca-launch.exe` also connected. Not tested: Windows with only the extensionless sh script and no .exe (expected to fail), so ship the .exe.
- **Quarantine / Zone.Identifier:** mac `xattr -rl` on the downloaded node tree found 0 `com.apple.quarantine` entries (curl does not set it); Windows `Get-Item -Stream *` on the downloaded node.exe showed only the default data stream, no Zone.Identifier. CI runners are not a Gatekeeper/SmartScreen test, though; an interactive first-run on a real Mac and a real Windows box is still unverified.
- Tools used by the sh launcher: curl, tar, shasum or sha256sum, uname. All present on stock mac and the Linux runners; a minimal Linux image without curl would break it.

## Sizes and first-run time (CI runners)
| | mac arm64 | mac x64 | Windows | Linux x64 | Linux arm64 |
|---|---|---|---|---|---|
| Node archive downloaded (B) | 50.0 MB | 51.2 MB | 35.6 MB | 56.9 MB | 56.7 MB |
| B plugin itself | 16 KB | 16 KB | 7.4 MB (Go exe) | 28 KB | 28 KB |
| B data dir after first run (full node tree, could be slimmed to the binary) | 192 MB | 195 MB | 121 MB | 208 MB | 206 MB |
| B first launch (download+verify+start+ping) | 1.4 s | 5.3 s | 2.2 s | 1.5 s | 1.4 s |
| B later launches | 0.1 s | 0.2 s | 0.1 s | 0.1 s | 0.1 s |
| C plugin dir, this OS only (node binary + app) | 111 MB | 114 MB | 93 MB | 123 MB | 120 MB |
| A plugin (mcpb 141 KB) | 876 KB | 876 KB | 890 KB | 892 KB | 892 KB |

C for all five platforms in one plugin would be about 540 MB unpacked (roughly 250 MB of compressed node archives). C installed here was a per-OS build made in CI, not a single multi-OS plugin; the all-OS figure is arithmetic, not measured.

## Recommendation
Use **B** (downloading launcher): first variant that passes on every OS, tiny plugin (KB on mac/linux, 7 MB Windows exe), ~1.5 to 5 s one-time first run, then 0.1 s. Needs network at first launch to nodejs.org and the app host. Fall back to **C** only if offline first-run is a hard requirement (cost: ~100+ MB per OS, ~540 MB for all). Do not rely on **A** unless the user is known to have Node.
Notes for the real build: host the app bundle as a release asset (this spike fetches raw.githubusercontent.com main), keep Node pin + sha in the launcher, ship `ca-launch.exe` built for win x64 (and arm64 if needed; spike only covered win-x64), keep sh launcher executable bit (git mode 100755 survived install on all OSes).

## Not covered
- Claude Desktop Code tab, real Gatekeeper/SmartScreen/antivirus, Windows arm64, machines behind a proxy.

## Human item (not done)
Aman opens the Claude Desktop app Code tab once after installing the winning variant (B) locally and confirms the `ping` tool is listed.
