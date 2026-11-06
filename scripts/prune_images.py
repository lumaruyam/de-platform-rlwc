"""Retention for our images in the class registry (ADR-0006).

Keep the 5 most recent versions of each image; delete older versions only when they are
also more than 30 days old. The class registry has no cleanup policy and we cannot add one,
so this script is the policy. Run: python scripts/prune_images.py [--apply]
Without --apply it only prints what it would delete.
"""
import json
import subprocess
import sys
import urllib.request
from datetime import datetime, timedelta, timezone

BASE = ("https://artifactregistry.googleapis.com/v1/projects/data-engineering-i2/"
        "locations/europe-west1/repositories/dataeng/packages")
IMAGES = ["group2-ingestion", "group2-dbt"]
KEEP, MAX_AGE = 5, timedelta(days=30)
APPLY = "--apply" in sys.argv

token = subprocess.run(["gcloud", "auth", "application-default", "print-access-token"],
                       capture_output=True, text=True, check=True).stdout.strip()


def call(url, method="GET"):
    req = urllib.request.Request(url, method=method, headers={
        "Authorization": f"Bearer {token}", "x-goog-user-project": "data-engineering-i2"})
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read() or b"{}")


now = datetime.now(timezone.utc)
for image in IMAGES:
    versions = call(f"{BASE}/{image}/versions?view=FULL&pageSize=100").get("versions", [])
    versions.sort(key=lambda v: v["createTime"], reverse=True)
    for i, v in enumerate(versions):
        created = datetime.fromisoformat(v["createTime"].replace("Z", "+00:00"))
        tags = [t["name"].rsplit("/", 1)[-1] for t in v.get("relatedTags", [])]
        old = i >= KEEP and now - created > MAX_AGE
        action = ("DELETE" if APPLY else "would delete") if old else "keep"
        print(f"{image:18} {','.join(tags) or '(untagged)':10} {created:%Y-%m-%d}  #{i + 1}  {action}")
        if old and APPLY:
            call(f"https://artifactregistry.googleapis.com/v1/{v['name']}?force=true", "DELETE")
