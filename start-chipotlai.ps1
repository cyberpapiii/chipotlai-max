# Chipotlai Max - single-action launcher for Windows.
# Run this from PowerShell. One command. Everything happens.
#
# What it does, in order (all automatic, no user action required):
#   1. Kills any stale bun proxy from a prior run (keeps the user's Edge alone)
#   2. Starts a fresh-profile Edge with --remote-debugging-port=9222
#   3. Waits for CDP at 127.0.0.1:9222
#   4. Checks if Amazon is signed in; if not, waits for the user to sign
#      in manually in the browser window (no credentials are ever stored
#      or typed by this script — sign in is always the user's action)
#   5. Drives the browser to send a Rufus message ("hello")
#   6. Starts the amazon-rufus-proxy in the background (it captures the session
#      from the Rufus network request the browser just made)
#   7. Waits up to 90s for the proxy to save a session
#   8. Launches OpenCode TUI in a NEW window (so the user can see the proxy
#      state and the TUI at the same time)
#
# Required files (all already in the repo):
#   - C:\Users\Nokel\Documents\AI_crap\agent-remote\cdp.py
#   - C:\Users\Nokel\Documents\AI_crap\agent-remote\control.py
#   - C:\Users\Nokel\Documents\AI_crap\chipotlai-max-master\script\amazon-rufus-proxy.ts
#
# Required env (set automatically below):
#   AMAZON_RUFUS_BASE_URL = http://localhost:3001/v1
#   AMAZON_RUFUS_CDP_URL  = http://127.0.0.1:9222
#   AMAZON_RUFUS_SESSION_FILE = C:\Users\Nokel\Documents\AI_crap\agent-remote\.amazon-rufus-session.json

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentRemote = Join-Path (Split-Path -Parent $projectRoot) "agent-remote"
$edgeExe   = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
$proxyProfileDir = Join-Path $env:LOCALAPPDATA "chipotlai-edge-cdp-profile"
$sessionFile = Join-Path $agentRemote ".amazon-rufus-session.json"
$proxyLogFile = Join-Path $agentRemote ".amazon-rufus-proxy.log"
$script:logStep = 0
$script:logTotal = 8

function Step {
  param([string]$msg)
  $script:logStep++
  Write-Host ""
  Write-Host "[$script:logStep/$script:logTotal] $msg" -ForegroundColor Cyan
}

function Note {
  param([string]$msg)
  Write-Host "        $msg" -ForegroundColor DarkGray
}

function Ok {
  param([string]$msg)
  Write-Host "        OK: $msg" -ForegroundColor Green
}

function Warn {
  param([string]$msg)
  Write-Host "        WARN: $msg" -ForegroundColor Yellow
}

function Fail {
  param([string]$msg)
  Write-Host "        FAIL: $msg" -ForegroundColor Red
  exit 1
}

# Resolve python executable (the venv python may not be on PATH, but
# `python` works for our scripts because they all run via subprocess from
# within PowerShell using the same python that the launcher was invoked from).
$python = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $python) { Fail "python not on PATH" }

Write-Host ""
Write-Host "==================================================" -ForegroundColor Magenta
Write-Host " Chipotlai Max - one-action Amazon Rufus launcher" -ForegroundColor Magenta
Write-Host "==================================================" -ForegroundColor Magenta
Write-Host "  project: $projectRoot"
Write-Host "  agent-remote: $agentRemote"
Write-Host ""

# ------------------------------------------------------------------
# 1. Kill any stale bun proxy (chipotlai's). Leave the user's Edge alone.
# ------------------------------------------------------------------
Step "killing stale chipotlai proxy (if any)..."
Get-Process -Name bun -ErrorAction SilentlyContinue | ForEach-Object {
  $port = Get-NetTCPConnection -OwningProcess $_.Id -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -eq 3001 }
  if ($port) {
    try {
      Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
      Note "killed bun pid $($_.Id) (was holding port 3001)"
    } catch {}
  }
}
Start-Sleep -Milliseconds 500

# ------------------------------------------------------------------
# 2. Start a fresh-profile Edge with CDP enabled.
# ------------------------------------------------------------------
Step "starting Edge with --remote-debugging-port=9222..."
function Test-Cdp {
  try {
    $resp = Invoke-WebRequest -Uri "http://127.0.0.1:9222/json/version" -UseBasicParsing -TimeoutSec 2
    return ($resp.StatusCode -eq 200)
  } catch { return $false }
}

if (Test-Cdp) {
  Ok "Edge with CDP already on 127.0.0.1:9222 - reusing it"
} else {
  if (-not (Test-Path $proxyProfileDir)) {
    New-Item -ItemType Directory -Path $proxyProfileDir -Force | Out-Null
  }
  if (-not (Test-Path $edgeExe)) { Fail "Edge not found at $edgeExe" }
  $arg = @(
    "--remote-debugging-port=9222"
    "--remote-debugging-address=127.0.0.1"
    "--user-data-dir=`"$proxyProfileDir`""
    "--no-first-run"
    "--no-default-browser-check"
    "--disable-features=msEdgeWelcome,SignInProfileMenu,SigninIntercept,SigninPromo,EdgeShoppingCartsOnboarding"
    "--disable-sync"
    "--disable-background-networking"
    "about:blank"
  ) -join ' '
  Start-Process -FilePath $edgeExe -ArgumentList $arg
  Note "launched: $edgeExe"
  Note "profile: $proxyProfileDir"

  # Wait for CDP
  $cdpOk = $false
  for ($i = 0; $i -lt 30; $i++) {
    if (Test-Cdp) { $cdpOk = $true; break }
    Start-Sleep -Seconds 1
  }
  if (-not $cdpOk) { Fail "CDP didn't come up in 30s" }
  Ok "CDP reachable at 127.0.0.1:9222"
}

# ------------------------------------------------------------------
# 3. Check Amazon sign-in status via cdp.py.
#    Credentials are NEVER hardcoded. If Amazon isn't already signed in
#    in the browser window, the launcher waits for the user to sign in
#    manually, then continues. The proxy itself is account-agnostic —
#    it just captures whatever session the browser has.
# ------------------------------------------------------------------
Step "checking Amazon sign-in status..."
$signinScript = Join-Path $agentRemote "_launcher_signin.py"
@'
#!/usr/bin/env python
"""Check Amazon sign-in, sign in if needed, then trigger a Rufus message."""
import json, subprocess, sys, os, threading, time

CDP = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cdp.py")
PY = sys.executable

def run_cdp(cmds, label=""):
    p = subprocess.Popen(
        [PY, "-u", CDP],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, bufsize=0,
    )
    out, err = [], []
    threading.Thread(target=lambda: [err.append(l.rstrip()) for l in iter(p.stderr.readline, "")], daemon=True).start()
    for cmd in cmds:
        try:
            p.stdin.write(json.dumps(cmd) + "\n"); p.stdin.flush()
        except BrokenPipeError:
            print(f"[{label}] broken pipe", file=sys.stderr); break
        line = p.stdout.readline().strip()
        if not line: continue
        try: out.append(json.loads(line))
        except: out.append({"_raw": line})
    try: p.stdin.close()
    except: pass
    try: p.wait(timeout=5)
    except: p.kill(); p.wait()
    return out, err

def banner(s): print(f"--- {s} ---", flush=True)

# 1. Navigate to the Amazon home page first; if we're already signed in,
#    `#nav-item-signout` will exist and we can skip the sign-in dance.
banner("navigate to home")
run_cdp([{"id":"1","cmd":"navigate","url":"https://www.amazon.com/"}], "home")
run_cdp([{"id":"1","cmd":"wait","ms":4000}], "wait")

# 2. Check sign-in status
banner("check sign-in")
res, _ = run_cdp([
    {"id":"1","cmd":"evaluate","expression":"JSON.stringify({url:location.href,hasSignOut:!!document.querySelector('#nav-item-signout'),title:document.title})"},
], "check")
status = res[-1].get("result", "{}") if res else "{}"
print("status:", status)
import json as _j
signin_data = _j.loads(status)
if signin_data.get("hasSignOut"):
    print("already signed in - skipping sign-in step")
else:
    # Amazon is not signed in. We do NOT have credentials. Tell the user
    # to sign in manually in the browser window, then poll for the
    # sign-in state to flip.
    print("NOT signed in. Please sign in to Amazon in the browser window.")
    print("Waiting up to 120s for you to sign in...")
    banner("waiting for manual Amazon sign-in")
    for attempt in range(120):
        time.sleep(1)
        res, _ = run_cdp([{"id":"1","cmd":"evaluate","expression":"JSON.stringify({hasSignOut:!!document.querySelector('#nav-item-signout')})"}], "poll")
        if res:
            try:
                d = _j.loads(res[-1].get("result", "{}"))
                if d.get("hasSignOut"):
                    print(f"signed in after {attempt+1}s")
                    break
            except: pass
    else:
        print("ERROR: timed out waiting for Amazon sign-in (120s)")
        print("Please sign in to Amazon in the browser window, then re-run the launcher.")
        sys.exit(1)

# 6. Trigger Rufus on the home page
banner("navigate to a search page (Rufus appears there)")
run_cdp([{"id":"1","cmd":"navigate","url":"https://www.amazon.com/s?k=laptop&i=stripbooks&ref=nb_sb_noss"}], "search")
run_cdp([{"id":"1","cmd":"wait","ms":4000}], "wait")

# 7. Find Rufus widget, send a message
banner("trigger Rufus")
res, _ = run_cdp([
    {"id":"1","cmd":"evaluate","expression":"JSON.stringify({hasRufus:!!document.querySelector('textarea[placeholder*=\"shopping question\" i]'),hasSubmit:!!document.querySelector('#rufus-submit-button')})"},
    {"id":"2","cmd":"evaluate","expression":"(()=>{const t=document.querySelector('textarea[placeholder*=\"shopping question\" i]');if(!t)return 'no textarea';const s=Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype,'value').set;s.call(t,'hello');t.dispatchEvent(new Event('input',{bubbles:true}));return 'set text'})()"},
    {"id":"3","cmd":"click","selector":"#rufus-submit-button"},
    {"id":"4","cmd":"wait","ms":5000},
], "rufus")
for r in res: print(json.dumps(r)[:200])
print("signin + rufus trigger complete")
'@ | Set-Content -Path $signinScript -Encoding UTF8

& $python $signinScript
if ($LASTEXITCODE -ne 0) { Warn "signin script exit code $LASTEXITCODE (continuing anyway)" }
Ok "browser sign-in check + Rufus trigger issued"

# ------------------------------------------------------------------
# 4. Start the amazon-rufus-proxy in the background.
# ------------------------------------------------------------------
Step "starting amazon-rufus-proxy on :3001..."
$env:AMAZON_RUFUS_BASE_URL  = "http://localhost:3001/v1"
$env:AMAZON_RUFUS_CDP_URL   = "http://127.0.0.1:9222"
$env:AMAZON_RUFUS_SESSION_FILE = $sessionFile
$env:AMAZON_RUFUS_LOG_FILE   = $proxyLogFile
Set-Location (Join-Path $projectRoot "packages\opencode")
$proxyProc = Start-Process -FilePath "bun" -ArgumentList @("run", "../../script/amazon-rufus-proxy.ts") -PassThru -NoNewWindow -RedirectStandardOutput (Join-Path $agentRemote "_proxy.out") -RedirectStandardError (Join-Path $agentRemote "_proxy.err")
Note "proxy pid: $($proxyProc.Id)"
Note "log file: $proxyLogFile"

# ------------------------------------------------------------------
# 5. Wait for proxy to capture a session.
# ------------------------------------------------------------------
Step "waiting for proxy to capture a session..."
$sessionOk = $false
for ($i = 0; $i -lt 60; $i++) {
  if (Test-Path $sessionFile) {
    try {
      $j = Get-Content $sessionFile -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue
      if ($j -and $j.cookie -and $j.csrf) { $sessionOk = $true; break }
    } catch {}
  }
  Start-Sleep -Seconds 1
}
if (-not $sessionOk) { Fail "proxy did not save a session in 60s" }
Ok "session saved to $sessionFile"

# ------------------------------------------------------------------
# 6. Touch the session file so the proxy's 1h TTL doesn't bite later.
# ------------------------------------------------------------------
Step "bumping session file mtime (bypass 1h TTL)..."
(Get-Item $sessionFile).LastWriteTime = Get-Date
Ok "session file mtime updated"

# ------------------------------------------------------------------
# 7. Launch OpenCode TUI in a NEW PowerShell window.
# ------------------------------------------------------------------
Step "launching OpenCode TUI in a new window..."
$opencodeCmd = "Set-Location '$projectRoot\packages\opencode'; `$env:AMAZON_RUFUS_BASE_URL='$env:AMAZON_RUFUS_BASE_URL'; `$env:AMAZON_RUFUS_CDP_URL='$env:AMAZON_RUFUS_CDP_URL'; `$env:AMAZON_RUFUS_SESSION_FILE='$sessionFile'; bun run --conditions=browser src/index.ts"
Start-Process -FilePath "powershell" -ArgumentList @("-NoExit", "-Command", $opencodeCmd) -WindowStyle Normal
Ok "OpenCode TUI launched in new window"

# ------------------------------------------------------------------
# 8. Final status.
# ------------------------------------------------------------------
Step "done!"
Write-Host ""
Write-Host "  proxy:     http://localhost:3001/v1   (bun pid $($proxyProc.Id))" -ForegroundColor Green
Write-Host "  Edge:      http://127.0.0.1:9222    (CDP)" -ForegroundColor Green
Write-Host "  session:   $sessionFile" -ForegroundColor Green
Write-Host "  OpenCode:  TUI in new window" -ForegroundColor Green
Write-Host ""
Write-Host "  You can now type a code request in the OpenCode TUI." -ForegroundColor Yellow
Write-Host "  amazon-rufus / rufus-1 / rufus-1-sk / rufus-1-c should all be available." -ForegroundColor Yellow
Write-Host ""
Write-Host "(this PowerShell window will stay open for 30s, then close)" -ForegroundColor DarkGray
Start-Sleep -Seconds 30
Write-Host ""
Write-Host "  proxy:     http://localhost:3001/v1   (pid $proxyProc.Id)" -ForegroundColor Green
Write-Host "  Edge:      http://127.0.0.1:9222    (CDP)" -ForegroundColor Green
Write-Host "  session:   $sessionFile" -ForegroundColor Green
Write-Host "  OpenCode:  TUI in new window" -ForegroundColor Green
Write-Host ""
Write-Host "  You can now type a code request in the OpenCode TUI." -ForegroundColor Yellow
Write-Host "  amazon-rufus / rufus-1 / rufus-1-sk / rufus-1-c should all be available." -ForegroundColor Yellow
Write-Host ""
