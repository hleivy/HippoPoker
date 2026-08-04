import urllib.request, json, time, os, sys
TOKEN=os.environ.get('TOKEN','')
REPO=os.environ.get('REPO','hleivy/HippoPoker')
SHA=os.environ.get('SHA','')
proxy=urllib.request.ProxyHandler({'http':'http://127.0.0.1:10808','https':'http://127.0.0.1:10808'})
opener=urllib.request.build_opener(proxy)
urllib.request.install_opener(opener)
def api(path):
    req=urllib.request.Request('https://api.github.com'+path, headers={'Authorization':'Bearer '+TOKEN,'Accept':'application/vnd.github+json'})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)
run_id=None
for attempt in range(20):
    try:
        runs=api('/repos/%s/actions/runs?per_page=10' % REPO)
    except Exception as e:
        print('list_err', e); time.sleep(10); continue
    for r in runs.get('workflow_runs',[]):
        if SHA=='' or r.get('head_sha','').startswith(SHA):
            run_id=r.get('id'); break
    if run_id: break
    print('waiting_new_run_attempt_%d' % (attempt+1)); time.sleep(10)
if not run_id:
    print('NO_NEW_RUN'); sys.exit(1)
print('NEW_RUN_ID=%d' % run_id)
for i in range(40):
    try:
        d=api('/repos/%s/actions/runs/%d' % (REPO, run_id))
    except Exception as e:
        print('[poll %d] ERR %s' % (i+1, e), flush=True); time.sleep(30); continue
    status=d.get('status'); concl=d.get('conclusion')
    print('[poll %d] status=%s conclusion=%s' % (i+1, status, concl), flush=True)
    if status=='completed':
        print('FINAL_STATUS='+str(status)); print('FINAL_CONCL='+str(concl))
        print('HTML_URL='+str(d.get('html_url','')))
        if concl=='success':
            try:
                ad=api('/repos/%s/actions/runs/%d/artifacts' % (REPO, run_id))
                for a in ad.get('artifacts',[]):
                    print('ARTIFACT name=%s id=%s size=%s expired=%s' % (a.get('name'),a.get('id'),a.get('size_in_bytes'),a.get('expired')))
            except Exception as e:
                print('ART_ERR '+str(e))
            print('BUILD_SUCCESS')
        else:
            print('BUILD_FAILED')
        break
    time.sleep(30)
print('MONITOR_DONE')
