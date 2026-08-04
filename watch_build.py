import urllib.request, json, zipfile, io, os, time

TOKEN = os.environ.get('TOKEN', '')
REPO = os.environ.get('REPO', 'hleivy/HippoPoker')
HEAD = os.environ.get('HEAD', '')
proxy = urllib.request.ProxyHandler({'http': 'http://127.0.0.1:10808', 'https': 'http://127.0.0.1:10808'})
op = urllib.request.build_opener(proxy)
urllib.request.install_opener(op)

def api(path):
    req = urllib.request.Request('https://api.github.com' + path,
                                 headers={'Authorization': 'Bearer ' + TOKEN,
                                          'Accept': 'application/vnd.github+json'})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)

# 1) find the run for this head sha
print('looking up run for head', HEAD)
run_id = None
for _ in range(30):
    runs = api('/repos/%s/actions/runs?per_page=10' % REPO).get('workflow_runs', [])
    for r in runs:
        if r.get('head_sha', '').startswith(HEAD):
            run_id = r['id']
            print('found run', run_id, 'status=', r.get('status'))
            break
    if run_id:
        break
    time.sleep(10)
if not run_id:
    print('RUN_NOT_FOUND')
    raise SystemExit(1)

# 2) poll until completed
print('polling run', run_id)
conclusion = None
for _ in range(120):  # up to 20 min
    r = api('/repos/%s/actions/runs/%s' % (REPO, run_id))
    st = r.get('status')
    print('  status=', st, 'conclusion=', r.get('conclusion'))
    if st == 'completed':
        conclusion = r.get('conclusion')
        break
    time.sleep(10)

print('RUN_URL=https://github.com/%s/actions/runs/%s' % (REPO, run_id))
print('CONCLUSION=', conclusion)

if conclusion != 'success':
    # fetch logs and print errors
    print('=== fetch logs ===')
    req = urllib.request.Request('https://api.github.com/repos/%s/actions/runs/%s/logs' % (REPO, run_id),
                                 headers={'Authorization': 'Bearer ' + TOKEN})
    data = urllib.request.urlopen(req, timeout=120).read()
    z = zipfile.ZipFile(io.BytesIO(data))
    for name in z.namelist():
        txt = z.read(name).decode('utf-8', 'replace').splitlines()
        for i, l in enumerate(txt):
            low = l.lower()
            if any(k in low for k in ['error', 'exception', 'fatal', 'what went wrong', 'could not', 'unable to', 'not found', 'unknown property']):
                s = max(0, i - 2); e = min(len(txt), i + 6)
                for x in txt[s:e]:
                    print(x)
                print('----')
    raise SystemExit(2)

# 3) success: list artifacts
print('=== artifacts ===')
arts = api('/repos/%s/actions/runs/%s/artifacts' % (REPO, run_id))
for a in arts.get('artifacts', []):
    print('ARTIFACT name=%s id=%s size=%s' % (a.get('name'), a.get('id'), a.get('size_in_bytes')))
print('DONE success')
