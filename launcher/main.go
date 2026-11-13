// ca-launch.exe: Windows launcher. Bundled mode (variant C) if ../runtime/node.exe exists,
// otherwise downloads pinned Node + app into CLAUDE_PLUGIN_DATA (variant B), sha256 verified.
package main

import (
	"archive/zip"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

const nodeVer = "v22.23.5"
const appURL = "https://raw.githubusercontent.com/Arloxians/ca-packaging-spike/main/dist/hello.cjs"

var dataDir string

func logf(f string, a ...any) {
	m := fmt.Sprintf(f, a...)
	fmt.Fprintln(os.Stderr, "ca-launch: "+m)
	if lf, err := os.OpenFile(filepath.Join(dataDir, "launch.log"), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644); err == nil {
		fmt.Fprintf(lf, "%d %s\n", time.Now().Unix(), m)
		lf.Close()
	}
}
func die(f string, a ...any) { logf(f, a...); os.Exit(1) }

func get(url, dst string) string {
	r, err := http.Get(url)
	if err != nil || r.StatusCode != 200 {
		die("download failed %s: %v", url, err)
	}
	defer r.Body.Close()
	out, _ := os.Create(dst)
	defer out.Close()
	h := sha256.New()
	io.Copy(io.MultiWriter(out, h), r.Body)
	return hex.EncodeToString(h.Sum(nil))
}

func run(node, app string) {
	c := exec.Command(node, app)
	c.Stdin, c.Stdout, c.Stderr = os.Stdin, os.Stdout, os.Stderr
	if err := c.Run(); err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			os.Exit(ee.ExitCode())
		}
		die("run: %v", err)
	}
	os.Exit(0)
}

func main() {
	exe, _ := os.Executable()
	root := filepath.Dir(filepath.Dir(exe))
	if n := filepath.Join(root, "runtime", "node.exe"); fileExists(n) {
		run(n, filepath.Join(root, "runtime", "hello.cjs"))
	}
	dataDir = os.Getenv("CLAUDE_PLUGIN_DATA")
	if dataDir == "" {
		h, _ := os.UserHomeDir()
		dataDir = filepath.Join(h, ".ca-launch")
	}
	os.MkdirAll(dataDir, 0o755)
	shaB, _ := os.ReadFile(filepath.Join(filepath.Dir(exe), "app.sha256"))
	appSha := strings.TrimSpace(string(shaB))
	nodeDir := filepath.Join(dataDir, "node-"+nodeVer+"-win-x64")
	node := filepath.Join(nodeDir, "node.exe")
	if !fileExists(node) {
		logf("start node download")
		tmp, _ := os.MkdirTemp(dataDir, "tmp")
		defer os.RemoveAll(tmp)
		sums := filepath.Join(tmp, "SUMS")
		get("https://nodejs.org/dist/"+nodeVer+"/SHASUMS256.txt", sums)
		sb, _ := os.ReadFile(sums)
		f := "node-" + nodeVer + "-win-x64.zip"
		want := ""
		for _, l := range strings.Split(string(sb), "\n") {
			if strings.HasSuffix(strings.TrimSpace(l), "  "+f) {
				want = strings.Fields(l)[0]
			}
		}
		if want == "" {
			die("no checksum for %s", f)
		}
		zp := filepath.Join(tmp, f)
		if got := get("https://nodejs.org/dist/"+nodeVer+"/"+f, zp); got != want {
			die("node sha256 mismatch")
		}
		zr, err := zip.OpenReader(zp)
		if err != nil {
			die("zip: %v", err)
		}
		os.MkdirAll(nodeDir, 0o755)
		for _, zf := range zr.File {
			if strings.HasSuffix(zf.Name, "/node.exe") {
				rc, _ := zf.Open()
				o, _ := os.Create(node)
				io.Copy(o, rc)
				o.Close()
				rc.Close()
			}
		}
		zr.Close()
		if !fileExists(node) {
			die("node.exe not in zip")
		}
		logf("node ready")
	}
	app := filepath.Join(dataDir, "hello-"+appSha+".cjs")
	if !fileExists(app) {
		if got := get(appURL, app+".part"); got != appSha {
			os.Remove(app + ".part")
			die("app sha256 mismatch")
		}
		os.Rename(app+".part", app)
		logf("app ready")
	}
	run(node, app)
}

func fileExists(p string) bool { _, err := os.Stat(p); return err == nil }
