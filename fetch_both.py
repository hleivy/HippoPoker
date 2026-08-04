#!/usr/bin/env python3
"""Poll latest Build Android APK and Build Web runs for HEAD, download artifacts."""
import json
import os
import time
import urllib.request
import zipfile
import io

TOKEN = os.environ.get('TOKEN', '')
REPO = os.environ.get('REPO', 'hleivy/HippoPoker')
HEAD = os.environ.get('HEAD', '')

proxy = urllib.request.ProxyHandler({'http': 'http://127.0.0.1:10808', 'https': 'http://127.0.0.1:10808'})


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


opener = urllib.request.build_opener(proxy, NoRedirect())


def api(path, method="GET", data=None):
    url = "https://api.github.com" + path
    headers = {
        'Authorization': 'Bearer ' + TOKEN,
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'curl/8'
    }
    if data:
        data = json.dumps(data).encode()
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    resp = opener.open(req, timeout=60)
    body = resp.read()
    if body:
        return json.loads(body)
    return None


def download_artifact(artifact_id, dest_dir, flatten_prefix=None):
    url = f"https://api.github.com/repos/{REPO}/actions/artifacts/{artifact_id}/zip"
    req = urllib.request.Request(url, headers={
        'Authorization': 'Bearer ' + TOKEN,
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'curl/8'
    })
    try:
        resp = opener.open(req, timeout=120)
        data = resp.read()
    except urllib.error.HTTPError as e:
        loc = e.headers.get('Location')
        if not loc:
            raise
        req2 = urllib.request.Request(loc, headers={'User-Agent': 'curl/8'})
        data = opener.open(req2, timeout=180).read()

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


def main():
    apk_run = None
    web_run = None
    for i in range(120):  # ~30 min
        runs = api(f"/repos/{REPO}/actions/runs?per_page=20")['workflow_runs']
        for r in runs:
            if r['head_sha'] != HEAD:
                continue
            if r['name'] == 'Build Android APK':
                apk_run = r
            elif r['name'] == 'Build Web':
                web_run = r
        apk_status = apk_run['status'] if apk_run else 'missing'
        web_status = web_run['status'] if web_run else 'missing'
        apk_conclusion = apk_run.get('conclusion') if apk_run else None
        web_conclusion = web_run.get('conclusion') if web_run else None
        print(f"[{i}] apk={apk_status}/{apk_conclusion} web={web_status}/{web_conclusion}")
        if apk_run and web_run and apk_run['status'] == 'completed' and web_run['status'] == 'completed':
            if apk_conclusion == 'success' and web_conclusion == 'success':
                break
            print("FAILED:", apk_conclusion, web_conclusion)
            return
        time.sleep(15)

    if not apk_run or not web_run:
        print("TIMEOUT waiting for runs")
        return

    # download APK artifact (artifact name poker-app-release contains app-release.apk)
    apk_artifacts = api(f"/repos/{REPO}/actions/runs/{apk_run['id']}/artifacts")['artifacts']
    apk_art = next((a for a in apk_artifacts if a['name'] == 'poker-app-release'), apk_artifacts[0])
    download_artifact(apk_art['id'], r"C:\Users\hleiv\WorkBuddy\2026-08-02-19-05-12\wechat-poker\apk_host")

    # download Web artifact (contains build/web/*)
    web_artifacts = api(f"/repos/{REPO}/actions/runs/{web_run['id']}/artifacts")['artifacts']
    web_art = next((a for a in web_artifacts if a['name'] == 'poker-web'), web_artifacts[0])
    download_artifact(web_art['id'], r"C:\Users\hleiv\WorkBuddy\2026-08-02-19-05-12\wechat-poker\web_host", flatten_prefix='build/web/')

    # rename APK inside apk_host
    apk_src = r"C:\Users\hleiv\WorkBuddy\2026-08-02-19-05-12\wechat-poker\apk_host\app-release.apk"
    apk_dst = r"C:\Users\hleiv\WorkBuddy\2026-08-02-19-05-12\wechat-poker\apk_host\HippoPoker.apk"
    if os.path.exists(apk_src):
        os.replace(apk_src, apk_dst)
        print(f"Renamed {apk_src} -> {apk_dst}")


if __name__ == '__main__':
    main()
