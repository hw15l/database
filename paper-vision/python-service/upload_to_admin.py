import json, base64, os, urllib.request, urllib.error

BASE = "http://localhost:8080/api"
TEST_DIR = os.path.join(os.path.dirname(__file__), "test_data")

def api(method, path, data=None, token=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    body = json.dumps(data).encode() if data else None
    req = urllib.request.Request(BASE + path, data=body, headers=headers, method=method)
    try:
        resp = urllib.request.urlopen(req, timeout=30)
        r = json.loads(resp.read().decode())
        return r.get("data") if r.get("code") == 200 else None
    except urllib.error.HTTPError as e:
        print("  HTTP " + str(e.code) + ": " + e.read().decode()[:80])
        return None

r = api("POST", "/auth/login", {"username": "admin", "password": "admin123"})
if not r or not r.get("token"):
    print("admin login failed")
    exit(1)
token = r["token"]
print("admin login OK")

count = 0
for f in sorted(os.listdir(TEST_DIR)):
    if not f.endswith(".xlsx"):
        continue
    fpath = os.path.join(TEST_DIR, f)
    with open(fpath, "rb") as fh:
        b64 = base64.b64encode(fh.read()).decode()
    result = api("POST", "/data/upload", {"fileName": f, "fileData": b64}, token)
    if result and result.get("id"):
        count += 1
        fid = result["id"]
        print("  [OK] " + f + " -> fileId=" + str(fid))
    else:
        print("  [FAIL] " + f)

print("\nDone: " + str(count) + "/27")
