import urllib.request, zipfile, io, os

TOKEN = os.environ.get("TOKEN")
REPO = "hleivy/HippoPoker"
AID = os.environ.get("AID") or "8846027856"

proxy = urllib.request.ProxyHandler({'http': 'http://127.0.0.1:10808', 'https': 'http://127.0.0.1:10808'})


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


op = urllib.request.build_opener(proxy, NoRedirect())

url = f"https://api.github.com/repos/{REPO}/actions/artifacts/{AID}/zip"
req = urllib.request.Request(url, headers={'Authorization': 'Bearer ' + TOKEN, 'Accept': 'application/vnd.github+json', 'User-Agent': 'curl/8'})
try:
    resp = op.open(req, timeout=120)
    data = resp.read()
except urllib.error.HTTPError as e:
    loc = e.headers.get("Location")
    req2 = urllib.request.Request(loc, headers={'User-Agent': 'curl/8'})
    data = op.open(req2, timeout=180).read()

print("zip bytes", len(data))
# 正确 Windows 绝对路径（正斜杠）
outdir = "C:/Users/hleiv/WorkBuddy/2026-08-02-19-05-12/wechat-poker/web_host"
if os.path.exists(outdir):
    for root, dirs, files in os.walk(outdir):
        for f in files:
            os.remove(os.path.join(root, f))
os.makedirs(outdir, exist_ok=True)
z = zipfile.ZipFile(io.BytesIO(data))
for n in z.namelist():
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
print("file count:", len([1 for _ in os.walk(outdir)]))
