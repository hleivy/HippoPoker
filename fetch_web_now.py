#!/usr/bin/env python3
"""Wait for the latest Build Web run at HEAD, download artifact to web_host.
Robust: proxy 127.0.0.1:10808 fails -> auto fallback to direct; verify index.html landed.
"""
import json
import os
import time
import urllib.request
import urllib.error
import zipfile
import io

TOKEN = os.environ.get('TOKEN', '')
REPO = os.environ.get('REPO', 'hleivy/HippoPoker')
HEAD = os.environ.get('HEAD', '')
WEB_HOST = r"C:\Users\hleiv\WorkBuddy\2026-08-02-19-05-12\wechat-poker\web_host"

proxy = urllib.request.ProxyHandler({'http': 'http://127.0.0.1:10808', 'https': 'http://127.0.0.1:10808'})
direct = urllib.request.ProxyHandler({})  # no proxy


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


opener_proxy = urllib.request.build_opener(proxy, NoRedirect())
opener_direct = urllib.request.build_opener(direct, NoRedirect())


def open_url(req, timeout=120):
    """Try proxied first; on any connection failure retry direct."""
    last = None
    for opener in (opener_proxy, opener_direct):
        try:
            return opener.open(req, timeout=timeout)
        except Exception as e:  # proxy down / 502 / DNS etc.
            last = e
            print(f"  opener failed ({opener is opener_proxy and 'proxy' or 'direct'}): {e}")
    raise last


def api(path):
    url = "https://api.github.com" + path
    headers = {'Authorization': 'Bearer ' + TOKEN, 'Accept': 'application/vnd.github+json', 'User-Agent': 'curl/8'}
    req = urllib.request.Request(url, headers=headers)
    return json.loads(open_url(req, 60).read())


def download_artifact(artifact_id, dest_dir, flatten_prefix=None):
    url = f"https://api.github.com/repos/{REPO}/actions/artifacts/{artifact_id}/zip"
    req = urllib.request.Request(url, headers={'Authorization': 'Bearer ' + TOKEN, 'Accept': 'application/vnd.github+json', 'User-Agent': 'curl/8'})
    try:
        resp = open_url(req, 180)
        data = resp.read()
    except urllib.error.HTTPError as e:
        loc = e.headers.get('Location')
        if not loc:
            raise
        data = open_url(urllib.request.Request(loc, headers={'User-Agent': 'curl/8'}), 180).read()
    print(f"Downloaded artifact {artifact_id}: {len(data)} bytes")
    z = zipfile.ZipFile(io.BytesIO(data))
    os.makedirs(dest_dir, exist_ok=True)
    for name in z.namelist():
        rel = name
        if flatten_prefix and rel.startswith(flatten_prefix):
            rel = rel[len(flatten_prefix):]
        if not rel:
            continue
        target = os.path.join(dest_dir, rel)
        if name.endswith('/'):
            os.makedirs(target, exist_ok=True)
        else:
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with open(target, 'wb') as f:
                f.write(z.read(name))
    print(f"Extracted to {dest_dir}")


def verify():
    idx = os.path.join(WEB_HOST, 'index.html')
    main = os.path.join(WEB_HOST, 'main.dart.js')
    ok = os.path.exists(idx) and os.path.getsize(idx) > 100 and os.path.exists(main) and os.path.getsize(main) > 1000
    print("VERIFY index.html+main.dart.js:", "OK" if ok else "MISSING")
    return ok


def main():
    web_run = None
    for i in range(140):
        runs = api(f"/repos/{REPO}/actions/runs?per_page=20")['workflow_runs']
        for r in runs:
            if r['head_sha'] == HEAD and r['name'] == 'Build Web':
                web_run = r
        status = web_run['status'] if web_run else 'missing'
        conclusion = web_run.get('conclusion') if web_run else None
        print(f"[{i}] web={status}/{conclusion}")
        if web_run and web_run['status'] == 'completed':
            if conclusion == 'success':
                break
            print("WEB BUILD FAILED:", conclusion)
            return
        time.sleep(15)
    if not web_run:
        print("TIMEOUT waiting for web run")
        return
    arts = api(f"/repos/{REPO}/actions/runs/{web_run['id']}/artifacts")['artifacts']
    web_art = next((a for a in arts if a['name'] == 'poker-web'), arts[0])
    for attempt in range(3):
        try:
            download_artifact(web_art['id'], WEB_HOST, flatten_prefix='build/web/')
            if verify():
                print("WEB_DONE")
                return
        except Exception as e:
            print(f"download attempt {attempt} error: {e}")
        time.sleep(5)
    print("WEB_DONE_BUT_VERIFY_FAILED")


if __name__ == '__main__':
    main()
