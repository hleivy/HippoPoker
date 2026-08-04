import urllib.request, json, zipfile, io, os
TOKEN=os.environ.get('TOKEN','')
REPO=os.environ.get('REPO','hleivy/HippoPoker')
RUN=os.environ.get('RUN','')
proxy=urllib.request.ProxyHandler({'http':'http://127.0.0.1:10808','https':'http://127.0.0.1:10808'})
opener=urllib.request.build_opener(proxy)
urllib.request.install_opener(opener)
def api(path):
    req=urllib.request.Request('https://api.github.com'+path, headers={'Authorization':'Bearer '+TOKEN,'Accept':'application/vnd.github+json'})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)
jobs=api('/repos/%s/actions/runs/%s/jobs' % (REPO,RUN))
for j in jobs.get('jobs',[]):
    print('JOB:', j.get('name'), 'conclusion=', j.get('conclusion'))
    for s in j.get('steps',[]):
        print('   STEP[%s] %s -> %s' % (s.get('number'), s.get('name'), s.get('conclusion')))
print('=== logs ===')
req=urllib.request.Request('https://api.github.com/repos/%s/actions/runs/%s/logs' % (REPO,RUN), headers={'Authorization':'Bearer '+TOKEN})
with urllib.request.urlopen(req, timeout=120) as r:
    data=r.read()
print('LOG_ZIP_BYTES=', len(data))
z=zipfile.ZipFile(io.BytesIO(data))
for name in z.namelist():
    content=z.read(name).decode('utf-8','replace')
    lines=content.splitlines()
    print('\n##### %s (%d lines) key lines #####' % (name, len(lines)))
    for idx,line in enumerate(lines):
        low=line.lower()
        if any(k in low for k in ['error','exception','fatal','fail','what went wrong','could not','unable to','not found','refused','unknown property','compilesdk','fluttersdk','flutter.sdk','license']):
            start=max(0,idx-2); end=min(len(lines),idx+6)
            for l in lines[start:end]:
                print(l)
            print('----')
