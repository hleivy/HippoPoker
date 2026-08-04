import urllib.request, zipfile, io, os, time, json, sys

TOKEN = os.environ.get("TOKEN")
REPO = "hleivy/HippoPoker"

proxy = urllib.request.ProxyHandler({'http': 'http://127.0.0.1:10808', 'https': 'http://127.0.0.1:10808'})


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


op = urllib.request.build_opener(proxy, NoRedirect())


def api(path, method="GET", data=None):
    req = urllib.request.Request(
        "https://api.github.com" + path, data=data,
        headers={'Authorization': 'Bearer ' + TOKEN, 'Accept': 'application/vnd.github+json', 'User-Agent': 'curl/8'},
        method=method)
    resp = op.open(req, timeout=30)
    if resp.status == 204:
        return None
    return json.load(resp)


# 1) dispatch a new Build Web run (uses current master HEAD, which includes web/index.html)
try:
    api("/repos/%s/actions/workflows/build-web.yml/dispatches" % REPO, method="POST",
        data=json.dumps({"ref": "master"}).encode())
    print("DISPATCH OK")
except urllib.error.HTTPError as e:
    print("DISPATCH HTTP", e.code, e.read().decode())
    # continue anyway; a run may already exist from the push

# 2) poll for the newest Build Web run
run = None
for i in range(90):
    data = api("/repos/%s/actions/runs?per_page=20" % REPO)
    cands = [r for r in data.get("workflow_runs", []) if "Build Web" in r["name"]]
    pending = [r for r in cands if r["status"] != "completed"]
    if pending:
        run = pending[0]
        print(f"[{i}] found pending run {run['id']} status={run['status']}")
        break
    if cands:
        run = cands[0]
        print(f"[{i}] only completed runs; using newest {run['id']}")
        break
    print(f"[{i}] waiting for a Build Web run...")
    time.sleep(12)

if run is None:
    print("NO RUN FOUND")
    sys.exit(1)

# wait until completed
for i in range(60):
    data = api("/repos/%s/actions/runs/%s" % (REPO, run["id"]))
    run = data
    if run["status"] == "completed":
        break
    print(f"  waiting completion... status={run['status']}")
    time.sleep(12)

print("FINAL run", run["id"], "conclusion=", run["conclusion"])
if run["conclusion"] != "success":
    print("WEB BUILD FAILED")
    sys.exit(1)

# 3) download artifact
arts = api("/repos/%s/actions/runs/%s/artifacts" % (REPO, run["id"]))
print("artifacts:", [(a["name"], a["id"]) for a in arts.get("artifacts", [])])
aid = arts["artifacts"][0]["id"]
url = f"https://api.github.com/repos/{REPO}/actions/artifacts/{aid}/zip"
req = urllib.request.Request(url, headers={'Authorization': 'Bearer ' + TOKEN, 'Accept': 'application/vnd.github+json', 'User-Agent': 'curl/8'})
try:
    resp = op.open(req, timeout=120)
    data = resp.read()
except urllib.error.HTTPError as e:
    loc = e.headers.get("Location")
    req2 = urllib.request.Request(loc, headers={'User-Agent': 'curl/8'})
    data = op.open(req2, timeout=180).read()

print("zip bytes", len(data))
outdir = "C:/Users/hleiv/WorkBuddy/2026-08-02-19-05-12/wechat-poker/web_host"
os.makedirs(outdir, exist_ok=True)
z = zipfile.ZipFile(io.BytesIO(data))
names = z.namelist()
for n in names:
    rel = n
    if rel.startswith("build/web/"):
        rel = rel[len("build/web/"):]
    if not rel:
        continue
    dest = os.path.join(outdir, rel)
    if n.endswith("/"):
        os.makedirs(dest, exist_ok=True)
    else:
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "wb") as f:
            f.write(z.read(n))
print("extracted to", outdir)
print("index.html exists:", os.path.exists(os.path.join(outdir, "index.html")))
