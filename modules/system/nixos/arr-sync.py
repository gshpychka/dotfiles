"""arr-sync — idempotently converge Servarr cross-service wiring over the REST API.

Reads one JSON spec per target service and ensures the target's root folders,
download clients and (Prowlarr) applications match what is declared. Resources are
matched by name (clients/applications) or path (root folders): existing ones are
updated in place, missing ones are created, and all other resources are preserved.

Create payloads are seeded from the target's own /schema endpoint, so the field and
contract shape always matches the running app version; we only overlay managed fields.
Secrets are passed as file paths and read at runtime, keeping them out of the Nix store.
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

# How long to wait for a target's API to answer before giving up.
READY_TIMEOUT = 180


def read_secret(path):
    with open(path) as handle:
        return handle.read().strip()


class Api:
    def __init__(self, url, version, api_key):
        self.base = f"{url.rstrip('/')}/api/{version}"
        self.api_key = api_key

    def request(self, method, path, body=None):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(self.base + path, data=data, method=method)
        req.add_header("X-Api-Key", self.api_key)
        if data is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req) as resp:
                raw = resp.read()
        except urllib.error.HTTPError as err:
            detail = err.read().decode("utf-8", "replace")
            raise SystemExit(f"{method} {path} -> HTTP {err.code}: {detail}") from err
        return json.loads(raw) if raw else None

    def get(self, path):
        return self.request("GET", path)

    def post(self, path, body):
        return self.request("POST", path, body)

    def put(self, path, body):
        return self.request("PUT", path, body)


def wait_ready(name, url, version, api_key):
    api = Api(url, version, api_key)
    deadline = time.monotonic() + READY_TIMEOUT
    while True:
        try:
            api.get("/system/status")
            return
        except urllib.error.URLError as err:
            if time.monotonic() > deadline:
                raise SystemExit(
                    f"timed out waiting for {name} at {url}: {err}"
                ) from err
            time.sleep(3)


def overlay_fields(resource, values):
    """Set values onto a resource's `fields` array, matched by field name."""
    by_name = {field["name"]: field for field in resource.get("fields", [])}
    for key, value in values.items():
        if key not in by_name:
            valid = ", ".join(sorted(by_name)) or "<none>"
            raise SystemExit(
                f"unknown field '{key}' for {resource.get('implementation')}; valid fields: {valid}"
            )
        by_name[key]["value"] = value


def sync_collection(api, kind, desired):
    schemas = {item["implementation"]: item for item in api.get(f"/{kind}/schema")}
    existing = {item["name"]: item for item in api.get("/" + kind)}
    for spec in desired:
        impl = spec["implementation"]
        updating = spec["name"] in existing
        if updating:
            resource = existing[spec["name"]]
            if resource.get("implementation") != impl:
                raise SystemExit(
                    f"{kind} '{spec['name']}' exists with implementation "
                    f"{resource.get('implementation')} (want {impl}); remove it first"
                )
        else:
            if impl not in schemas:
                raise SystemExit(f"no {kind} schema for implementation '{impl}'")
            resource = json.loads(json.dumps(schemas[impl]))
        resource["name"] = spec["name"]
        for prop in ("enable", "priority", "protocol", "syncLevel"):
            if prop in spec:
                resource[prop] = spec[prop]
        values = dict(spec.get("fields", {}))
        values.update(
            {
                key: read_secret(path)
                for key, path in spec.get("secretFields", {}).items()
            }
        )
        overlay_fields(resource, values)
        if updating:
            api.put(f"/{kind}/{resource['id']}", resource)
        else:
            api.post("/" + kind, resource)


def sync_root_folders(api, paths, needs_profiles):
    existing = {rf["path"].rstrip("/") for rf in api.get("/rootfolder")}
    extra = {}
    if needs_profiles:
        # Lidarr requires default quality/metadata profiles on every root folder.
        quality = api.get("/qualityprofile")
        metadata = api.get("/metadataprofile")
        if not quality or not metadata:
            raise SystemExit(
                "root folder needs an existing quality and metadata profile"
            )
        extra = {
            "defaultQualityProfileId": quality[0]["id"],
            "defaultMetadataProfileId": metadata[0]["id"],
            "defaultMonitorOption": "all",
            "defaultNewItemMonitorOption": "all",
            "defaultTags": [],
        }
    for path in paths:
        if path.rstrip("/") in existing:
            continue
        body = {"path": path}
        if needs_profiles:
            body["name"] = os.path.basename(path.rstrip("/"))
            body.update(extra)
        api.post("/rootfolder", body)


def main():
    with open(sys.argv[1]) as handle:
        spec = json.load(handle)
    api_key = read_secret(spec["apiKeyFile"])
    wait_ready(spec["name"], spec["url"], spec["apiVersion"], api_key)
    for dep in spec.get("waitFor", []):
        wait_ready(
            dep["name"], dep["url"], dep["apiVersion"], read_secret(dep["apiKeyFile"])
        )
    api = Api(spec["url"], spec["apiVersion"], api_key)
    if spec.get("rootFolders"):
        sync_root_folders(
            api, spec["rootFolders"], spec.get("rootFolderNeedsProfiles", False)
        )
    for kind, key in (
        ("downloadclient", "downloadClients"),
        ("applications", "applications"),
    ):
        if spec.get(key):
            sync_collection(api, kind, spec[key])
    print(f"{spec['name']}: wiring converged")


if __name__ == "__main__":
    main()
