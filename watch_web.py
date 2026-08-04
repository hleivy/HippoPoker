import urllib.request, json, os, time

TOKEN = os.environ.get("TOKEN")
REPO = "hleivy/HippoPoker"
HEAD = os.environ.get("HEAD") or "e0d18eb"

proxy = urllib.request.ProxyHandler({'http': 'http://127.0.0.1:10808', 'https': 'http://127.0.0.1:10808'})
op = urllib.request.build_opener(proxy)


def api(path):
    req = urllib.request.Request(
        "https://api.github.com" + path,
        headers={'Authorization': 'Bearer ' + TOKEN, 'Accept': 'application/vnd.github+json', 'User-Agent': 'curl/8'})
    return json.load(op.open(req, timeout=30))


target = None
for i in range(180):  # up to ~60 min
    try:
        data = api(f"/repos/{REPO}/actions/runs?head_sha={HEAD}&per_page=30")
    except Exception as e:
        print("api err", e)
        time.sleep(15)
        continue
    for r in data.get("workflow_runs", []):
        if "Build Web" in r["name"]:
            target = r
            break
    if target is None:
        print(f"[{i}] no Build Web run yet, waiting...")
        time.sleep(15)
        continue
    st = target["status"]
    print(f"[{i}] run {target['id']} status={st} conclusion={target.get('conclusion')}")
    if st == "completed":
        print("DONE conclusion=", target.get("conclusion"))
        print("URL", target["html_url"])
        break
    time.sleep(20)
else:
    print("TIMEOUT waiting for Build Web")
