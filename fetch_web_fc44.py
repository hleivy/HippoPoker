import os, sys, time, json, subprocess, zipfile

TOKEN = os.environ.get("TOKEN", "")
HEAD = os.environ.get("HEAD", "")
REPO = "hleivy/HippoPoker"
OUT = "web_host"

def curl(extra, timeout=240):
    return subprocess.run(
        ["curl", "-s", "--max-time", str(timeout)] + extra,
        capture_output=True, text=True, timeout=timeout + 15)

def api_get(url):
    r = curl(["-u", f"{TOKEN}:",
              "-H", "Accept: application/vnd.github+json", url])
    return r.stdout

def find_web_run():
    url = f"https://api.github.com/repos/{REPO}/actions/runs?per_page=30"
    try:
        data = json.loads(api_get(url) or "{}")
    except Exception:
        return None
    for run in data.get("workflow_runs", []):
        if run.get("name") == "Build Web" and (run.get("head_sha") or "").startswith(HEAD):
            return run
    return None

def wait_web_run():
    for i in range(60):
        run = find_web_run()
        if run:
            st, con = run.get("status"), run.get("conclusion")
            print(f"[poll {i}] Build Web {run['id']} status={st} conclusion={con}")
            if st == "completed":
                return run, con
        else:
            print(f"[poll {i}] Build Web for {HEAD} not found yet")
        time.sleep(30)
    return None, None

def artifact_id(run_id):
    url = f"https://api.github.com/repos/{REPO}/actions/runs/{run_id}/artifacts"
    try:
        data = json.loads(api_get(url) or "{}")
    except Exception:
        return None
    for a in data.get("artifacts", []):
        if a.get("name") == "poker-web":
            return a["id"]
    return None

def download(aid):
    api = f"https://api.github.com/repos/{REPO}/actions/artifacts/{aid}/zip"
    loc = curl(["-o", "/dev/null", "-w", "%{redirect_url}",
                "-u", f"{TOKEN}:", api]).stdout.strip()
    if not loc:
        print("no redirect location")
        return False
    curl(["-L", loc, "-o", "/tmp/web_art.zip"], timeout=300)
    return os.path.exists("/tmp/web_art.zip") and os.path.getsize("/tmp/web_art.zip") > 0

def extract():
    os.makedirs(OUT, exist_ok=True)
    with zipfile.ZipFile("/tmp/web_art.zip") as z:
        z.extractall(OUT)
    names = z.namelist()
    return ("index.html" in names) and any(n.endswith("main.dart.js") for n in names)

def main():
    print(f"[start] HEAD={HEAD}")
    run_obj, con = wait_web_run()
    if not run_obj:
        print("NO_RUN"); sys.exit(1)
    if con != "success":
        print(f"BUILD_FAILED conclusion={con}"); sys.exit(1)
    aid = artifact_id(run_obj["id"])
    if not aid:
        print("NO_ARTIFACT"); sys.exit(1)
    print(f"[artifact] id={aid}")
    for attempt in range(3):
        if download(aid) and extract():
            print("DEPLOY_READY")
            return
        print(f"[retry] attempt {attempt+1}")
        time.sleep(5)
    print("FAILED"); sys.exit(1)

if __name__ == "__main__":
    main()
