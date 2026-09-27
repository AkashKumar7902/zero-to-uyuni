#!/usr/bin/env python3
"""lab/runner/doors-publish.py - RUNNER-HQ v7: keep the presenter's Mac pointed at HQ's CURRENT doors.

hq.yml starts it once, in the background, from a JavaScript step (actions/github-script), because only an action's
process receives the job's artifact credentials (ACTIONS_RUNTIME_TOKEN, ACTIONS_RESULTS_URL). Every 15 s it reads
`doors.sh env` (sudo) and, whenever the record changed (a Cloudflare quick tunnel restarted with a NEW name, a bore.pub
port fell back, HQ's state moved on, leap-a/leap-b got ready), uploads it as a NEW artifact "doors-<n>" of this run.
mac/door.sh takes the newest `doors*` artifact of the newest hq run (`gh api .../artifacts`), while the job still runs.

Why this channel (the brief asked for one the Mac can read without a secret of HQ's):
  - the job summary is written only when a step ends, and the keep-alive step lasts hours: a renamed door would stay
    invisible there until the end;
  - an artifact is readable while the run is in progress, by any logged-in GitHub user (`gh` on the Mac: no new
    secret), and this upload needs no write token on HQ: the runtime token is scoped to this run's artifacts;
  - committing to a branch would need `contents: write` on the runner that outside machines talk to; it stays read-only.
Uses the same results-service calls as actions/upload-artifact v4 (@actions/artifact 2.x): CreateArtifact -> one blob
PUT -> FinalizeArtifact. Standard library only. The record is public (no secret; the repo's logs are public anyway),
the token is never printed or written anywhere. Log: /tmp/osas26-doors-publish.log (names and sizes only).
"""
import base64, datetime, hashlib, io, json, os, subprocess, sys, time, urllib.request, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
LOG = "/tmp/osas26-doors-publish.log"
SVC = "twirp/github.actions.results.api.v1.ArtifactService/"
EVERY = int(os.environ.get("DOORS_EVERY", "15"))


def log(msg):
    with open(LOG, "a") as f:
        f.write(f"{datetime.datetime.now(datetime.timezone.utc):%H:%M:%S} {msg}\n")


def backend_ids(token):
    p = token.split(".")[1]
    p += "=" * (-len(p) % 4)
    for s in json.loads(base64.urlsafe_b64decode(p)).get("scp", "").split(" "):
        q = s.split(":")
        if q[0] == "Actions.Results" and len(q) == 3:
            return q[1], q[2]
    raise RuntimeError("the runtime token carries no Actions.Results scope")


def twirp(base, token, method, body):
    req = urllib.request.Request(base.rstrip("/") + "/" + SVC + method, data=json.dumps(body).encode(), method="POST",
                                 headers={"Content-Type": "application/json", "Authorization": "Bearer " + token,
                                          "User-Agent": "osas26-doors-publish"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read() or b"{}")


def upload(name, text, days=3):
    token, base = os.environ["ACTIONS_RUNTIME_TOKEN"], os.environ["ACTIONS_RESULTS_URL"]
    run, job = backend_ids(token)
    exp = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=days)).strftime("%Y-%m-%dT%H:%M:%SZ")
    ids = {"workflow_run_backend_id": run, "workflow_job_run_backend_id": job, "name": name}
    r = twirp(base, token, "CreateArtifact", dict(ids, version=4, expires_at=exp))
    url = r.get("signed_upload_url") or r.get("signedUploadUrl")
    if not (r.get("ok") and url):
        raise RuntimeError("CreateArtifact was not ok")
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("doors.env", text)
    data = buf.getvalue()
    put = urllib.request.Request(url, data=data, method="PUT",
                                 headers={"x-ms-blob-type": "BlockBlob", "Content-Type": "zip"})
    urllib.request.urlopen(put, timeout=60).read()
    f = twirp(base, token, "FinalizeArtifact", dict(ids, size=str(len(data)), hash="sha256:" + hashlib.sha256(data).hexdigest()))
    if not f.get("ok"):
        raise RuntimeError("FinalizeArtifact was not ok")
    return f.get("artifact_id") or f.get("artifactId")


def current():
    out = subprocess.run(["sudo", "-n", "bash", os.path.join(HERE, "doors.sh"), "env"], capture_output=True, text=True,
                         timeout=30)
    return out.stdout if out.returncode == 0 and "HQ_STATE=" in out.stdout else None


def main():
    n, last = 0, None
    if len(sys.argv) > 1 and sys.argv[1] == "--once":           # a self-test from a JavaScript step
        print("uploaded artifact id", upload("doors-selftest", "# self-test\n", days=1))
        return
    log("started")
    while True:
        try:
            text = current()
            if text and text != last:
                n += 1
                aid = upload(f"doors-{n}", text)
                last = text
                state = next((l.split("=", 1)[1] for l in text.splitlines() if l.startswith("HQ_STATE=")), "?")
                cf = next((l.split("=", 1)[1] for l in text.splitlines() if l.startswith("CF_SSH_HOST=")), "")
                log(f"doors-{n} uploaded (id {aid}; state {state}; cloudflare {'yes' if cf else 'no'})")
                if state == "stopping":
                    log("HQ is stopping: done"); return
        except Exception as e:                                      # never the token: only the exception's type
            log(f"upload failed ({type(e).__name__}); retry in {EVERY} s")
        time.sleep(EVERY)


if __name__ == "__main__":
    main()
