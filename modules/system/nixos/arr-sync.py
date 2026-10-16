"""arr-sync — idempotently converge Servarr configuration over the REST API.

Reads one JSON spec per target app and converges the declared resources:
- root folders (matched by path, only ever added);
- providers: download clients, notifications and (Prowlarr) applications,
  matched by their stable id when the declared id still holds the same
  implementation, otherwise by name; missing ones are created from the app's
  own /schema, so the payload always matches the running version;
- settings singletons such as config/naming or delayprofile/1;
- quality definitions, matched by quality name;
- fields of existing quality profiles, matched by name (never created here:
  Recyclarr owns the profiles and their custom formats).
Only declared keys are compared and written; every other key and every
undeclared resource is left exactly as it is, and nothing is ever deleted.

Every run first plans with reads only. A plan with a problem (unknown field,
implementation clash, a privacy field without a secret file, ...) writes
nothing. A write happens only for a resource whose declared keys differ, so a
converged app sees zero writes. Before the first write a before-image of
everything read is saved privately, and after the writes a second read-only
plan must come out empty.

Secrets are file paths read at runtime, never part of the spec or the logs;
output names resources and field names only. Servarr masks privacy fields as
"********" in its API and keeps the stored value when that mask is sent back.
A masked value is compared with the app's own database, opened read-only. The
adoption rule never rotates a credential: an empty live value is filled, an
equal one is left alone, and a differing one is kept and reported as a
mismatch, which fails the run so the SOPS value gets fixed.

A consequence of that rule: when a SOPS value is changed on purpose (say a
rotated API key), the app keeps the old one and the run fails until the field
is updated or blanked in the UI; arr-sync then fills or adopts it.

Servarr tests a provider (for a notification: sends a real message) on create
whenever it is enabled, forceSave or not, and on a changed update of an
enabled provider unless forceSave=true. A notification is "enabled" when any
of its event flags is on. So a notification is created with every event off
(no test) and then given its events by an update with forceSave=true.

usage:
  arr-sync apply <spec.json> [backup dir]
  arr-sync preview <spec.json> [--expect-no-changes]

preview plans against the live app with GET requests only and exits non-zero
on a problem, a secret mismatch or an unverifiable secret, and with
--expect-no-changes also when any write would happen.
"""

import copy
import datetime
import email.utils
import http.client
import json
import os
import socket
import sqlite3
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

# How long to wait for a target's API to answer before giving up.
READY_TIMEOUT = 180
# Per-request timeout, and how often a failed request is retried.
REQUEST_TIMEOUT = 60
RETRIES = 5
# Upper bound for one wait between retries, whatever Retry-After asks for.
MAX_BACKOFF = 60
MASK = "********"

# Provider kinds: API collection -> database table holding their settings.
PROVIDER_TABLES = {
    "downloadclient": "DownloadClients",
    "notification": "Notifications",
    "applications": "Applications",
}
# Kinds whose create/update must not run Servarr's connection test.
FORCE_SAVE_KINDS = {"notification"}


def log(message):
    print(f"arr-sync: {message}", flush=True)


def read_secret(path):
    with open(path) as handle:
        return handle.read().strip()


class ApiError(Exception):
    def __init__(self, method, path, status, detail):
        super().__init__(f"{method} {path} -> HTTP {status}: {detail}")
        self.status = status


class Uncertain(Exception):
    """A request whose outcome is unknown: it may or may not have been applied."""


def error_detail(raw):
    """A response body's error text, without any attempted values (they may be secrets)."""
    try:
        body = json.loads(raw)
    except ValueError:
        return raw.decode("utf-8", "replace")[:300]
    if isinstance(body, list):
        return "; ".join(
            f"{item.get('propertyName', '?')}: {item.get('errorMessage', '?')}"
            for item in body
            if isinstance(item, dict)
        )[:300]
    if isinstance(body, dict):
        return str(body.get("message") or body.get("error") or "")[:300]
    return ""


def retry_delay(attempt, retry_after=None):
    seconds = None
    if retry_after:
        try:
            seconds = float(retry_after)
        except ValueError:
            try:
                parsed = email.utils.parsedate_to_datetime(retry_after)
                seconds = (
                    parsed - datetime.datetime.now(parsed.tzinfo)
                ).total_seconds()
            except (TypeError, ValueError):
                # an unparsable Retry-After counts as absent
                seconds = None
    if seconds is None:
        seconds = 2**attempt
    return min(max(seconds, 0), MAX_BACKOFF)


class Api:
    def __init__(self, url, version, api_key):
        self.base = f"{url.rstrip('/')}/api/{version}"
        self.api_key = api_key

    def sleep(self, seconds):
        time.sleep(seconds)

    def _send(self, method, path, body, query):
        data = json.dumps(body).encode() if body is not None else None
        url = self.base + path
        if query:
            url += "?" + urllib.parse.urlencode(query)
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("X-Api-Key", self.api_key)
        if data is not None:
            req.add_header("Content-Type", "application/json")
        with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as resp:
            raw = resp.read()
        try:
            return json.loads(raw) if raw else None
        except ValueError as err:
            # a cut-off or garbled body: as unknown as a dropped connection
            raise http.client.HTTPException(f"unreadable response: {err}") from err

    def request(self, method, path, body=None, query=None):
        """One request, retried on 429, 5xx and connection failures.

        A POST is not idempotent: when its outcome is unknown (a dropped
        connection, a timeout, a 5xx) it raises Uncertain instead of retrying,
        so the caller can look the resource up before trying again."""
        attempt = 0
        while True:
            try:
                return self._send(method, path, body, query)
            except urllib.error.HTTPError as err:
                detail = error_detail(err.read())
                if err.code == 429 and attempt < RETRIES:
                    delay = retry_delay(attempt, err.headers.get("Retry-After"))
                    log(f"{method} {path} rate limited, retrying in {delay:.0f}s")
                elif err.code >= 500 and method == "POST":
                    raise Uncertain(f"{method} {path} -> HTTP {err.code}") from err
                elif err.code >= 500 and attempt < RETRIES:
                    delay = retry_delay(attempt)
                    log(f"{method} {path} -> HTTP {err.code}, retrying in {delay:.0f}s")
                else:
                    raise ApiError(method, path, err.code, detail) from err
            except (
                urllib.error.URLError,
                http.client.HTTPException,
                socket.timeout,
                ConnectionError,
            ) as err:
                if method == "POST":
                    raise Uncertain(f"{method} {path}: {err}") from err
                if attempt >= RETRIES:
                    raise
                delay = retry_delay(attempt)
                log(f"{method} {path} failed ({err}), retrying in {delay:.0f}s")
            attempt += 1
            self.sleep(delay)

    def get(self, path):
        return self.request("GET", path)


class ReadOnlyApi(Api):
    """The API for preview and planning: anything but GET is refused."""

    def request(self, method, path, body=None, query=None):
        if method != "GET":
            raise RuntimeError(f"refusing {method} {path} in a read-only run")
        return super().request(method, path, body, query)


def wait_ready(name, url, version, api_key):
    api = Api(url, version, api_key)
    deadline = time.monotonic() + READY_TIMEOUT
    while True:
        try:
            api._send("GET", "/system/status", None, None)
            return
        except urllib.error.HTTPError as err:
            # starting up answers 5xx; a 4xx (a wrong API key) won't change
            if err.code < 500:
                raise SystemExit(f"{name} at {url}: HTTP {err.code}") from err
            if time.monotonic() > deadline:
                raise SystemExit(
                    f"timed out waiting for {name} at {url}: {err}"
                ) from err
            time.sleep(3)
        except (
            urllib.error.URLError,
            http.client.HTTPException,
            socket.timeout,
            ConnectionError,
        ) as err:
            if time.monotonic() > deadline:
                raise SystemExit(
                    f"timed out waiting for {name} at {url}: {err}"
                ) from err
            time.sleep(3)


class StoredSecrets:
    """Provider settings as stored in the app's database, opened read-only.

    The API masks privacy fields, so this is the only way to tell whether a
    masked live value equals the declared one."""

    def __init__(self, path):
        self.path = path
        self.cache = {}

    def get(self, kind, resource_id, field):
        if not self.path or kind not in PROVIDER_TABLES:
            return None
        if kind not in self.cache:
            # mode=ro: never writes; the app's -wal/-shm let it read current data
            uri = f"file:{urllib.parse.quote(self.path)}?mode=ro"
            try:
                con = sqlite3.connect(uri, uri=True, timeout=30)
                try:
                    rows = con.execute(
                        f"SELECT Id, Settings FROM {PROVIDER_TABLES[kind]}"
                    ).fetchall()
                finally:
                    con.close()
            except sqlite3.Error as err:
                log(f"cannot read {kind} settings from the database: {err}")
                rows = None
            self.cache[kind] = (
                None
                if rows is None
                else {row_id: json.loads(settings) for row_id, settings in rows}
            )
        table = self.cache[kind]
        if table is None or resource_id not in table:
            return None
        return table[resource_id].get(field)


class Plan:
    def __init__(self):
        self.writes = []
        self.problems = []
        self.mismatches = []
        self.unverifiable = []
        self.notes = []
        # everything read while planning: the before-image of a write
        self.reads = {}

    def write(self, method, path, body, summary, query=None, match=None, then=None):
        self.writes.append(
            {
                "method": method,
                "path": path,
                "body": body,
                "summary": summary,
                "query": query,
                "match": match,
                # a body to PUT on the created resource once its id is known
                "then": then,
            }
        )


def read(api, plan, path):
    value = api.get(path)
    plan.reads[path] = value
    return value


def is_event(key):
    """A notification event flag: onGrab, onUpgrade, ... (not supportsOn*)."""
    return key.startswith("on") and key[2:3].isupper()


def provider_label(kind, spec):
    return f"{kind} '{spec['name']}'"


def find_provider(existing, spec):
    """The live resource a declared provider stands for, or None.

    The declared id wins while it still holds the same implementation and its
    name isn't taken by another resource, so a rename in the UI is undone
    instead of creating a duplicate; otherwise (a fresh install, where ids
    differ) the name decides."""
    by_name = {item["name"]: item for item in existing}
    wanted = spec.get("id")
    if wanted is not None:
        for item in existing:
            if (
                item["id"] == wanted
                and item.get("implementation") == spec["implementation"]
                and (
                    item["name"] == spec["name"]
                    or by_name.get(spec["name"], item) is item
                )
            ):
                return item
    return by_name.get(spec["name"])


def plan_secret(plan, secrets, kind, label, resource, field, desired):
    """Whether a declared secret has to be written, by the adoption rule."""
    live = field.get("value")
    if resource is None:
        return True
    if live == MASK:
        live = secrets.get(kind, resource["id"], field["name"])
        if live is None:
            plan.unverifiable.append(f"{label} field {field['name']}")
            return False
    if live in ("", None):
        return True
    if live != desired:
        plan.mismatches.append(f"{label} field {field['name']}")
    return False


def plan_provider(api, plan, secrets, kind, spec, schemas, existing):
    label = provider_label(kind, spec)
    impl = spec["implementation"]
    resource = find_provider(existing, spec)
    if resource is not None and resource.get("implementation") != impl:
        plan.problems.append(
            f"{label} exists with implementation {resource.get('implementation')} (want {impl})"
        )
        return
    if resource is None and impl not in schemas:
        plan.problems.append(f"{label}: no schema for implementation '{impl}'")
        return
    desired = copy.deepcopy(resource if resource is not None else schemas[impl])
    changed = []

    def assign(container, key, value, what):
        if container.get(key) != value:
            container[key] = value
            changed.append(what)

    assign(desired, "name", spec["name"], "name")
    for prop, value in spec.get("properties", {}).items():
        if prop not in desired:
            plan.problems.append(f"{label}: unknown property '{prop}'")
            continue
        supported = desired.get("supports" + prop[0].upper() + prop[1:])
        if value is True and supported is False:
            plan.problems.append(f"{label}: {impl} does not support '{prop}'")
            continue
        assign(desired, prop, value, prop)

    fields = {field["name"]: field for field in desired.get("fields", [])}
    for key, value in spec.get("fields", {}).items():
        field = fields.get(key)
        if field is None:
            valid = ", ".join(sorted(fields)) or "<none>"
            plan.problems.append(
                f"{label}: unknown field '{key}'; valid fields: {valid}"
            )
            continue
        if field.get("privacy", "normal") != "normal" and value not in ("", None):
            plan.problems.append(
                f"{label}: field '{key}' is private; declare it as a secret field"
            )
            continue
        # a blank declared over a masked (set) value clears it
        assign(field, "value", value, key)
    for key, path in spec.get("secretFields", {}).items():
        field = fields.get(key)
        if field is None:
            plan.problems.append(f"{label}: unknown secret field '{key}'")
            continue
        try:
            value = read_secret(path)
        except OSError as err:
            plan.problems.append(
                f"{label}: cannot read secret for '{key}': {err.strerror}"
            )
            continue
        if plan_secret(plan, secrets, kind, label, resource, field, value):
            field["value"] = value
            changed.append(key)

    query = {"forceSave": "true"} if kind in FORCE_SAVE_KINDS else None
    if resource is None:
        desired.pop("id", None)
        create = desired
        then = None
        if kind in FORCE_SAVE_KINDS:
            # created disabled (no test), enabled by the forceSave update after it
            create = copy.deepcopy(desired)
            for key in create:
                if is_event(key):
                    create[key] = False
            then = desired
        plan.write(
            "POST",
            "/" + kind,
            create,
            f"create {label}",
            query=query,
            match={"kind": kind, "name": spec["name"], "implementation": impl},
            then=then,
        )
    elif changed:
        plan.write(
            "PUT",
            f"/{kind}/{resource['id']}",
            desired,
            f"update {label} (id {resource['id']}): {', '.join(changed)}",
            query=query,
        )


def plan_providers(api, plan, secrets, kind, desired):
    names = [spec["name"] for spec in desired]
    if len(set(names)) != len(names):
        plan.problems.append(f"{kind}: declared names are not unique")
        return
    schemas = {
        item["implementation"]: item for item in read(api, plan, f"/{kind}/schema")
    }
    existing = read(api, plan, "/" + kind)
    claimed = {}
    for spec in desired:
        resource = find_provider(existing, spec)
        if resource is not None and resource["id"] in claimed:
            plan.problems.append(
                f"{kind} id {resource['id']} is matched by both "
                f"'{claimed[resource['id']]}' and '{spec['name']}'"
            )
            continue
        if resource is not None:
            claimed[resource["id"]] = spec["name"]
        plan_provider(api, plan, secrets, kind, spec, schemas, existing)


def plan_root_folders(api, plan, paths, needs_profiles):
    existing = {rf["path"].rstrip("/") for rf in read(api, plan, "/rootfolder")}
    extra = {}
    if needs_profiles:
        # Lidarr requires default quality/metadata profiles on every root folder.
        quality = read(api, plan, "/qualityprofile")
        metadata = read(api, plan, "/metadataprofile")
        if not quality or not metadata:
            plan.problems.append(
                "root folder needs an existing quality and metadata profile"
            )
            return
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
        plan.write(
            "POST",
            "/rootfolder",
            body,
            f"create root folder {path}",
            match={"kind": "rootfolder", "path": path},
        )


def plan_settings(api, plan, settings):
    for path, values in settings.items():
        try:
            current = read(api, plan, "/" + path)
        except ApiError as err:
            plan.problems.append(f"settings {path}: {err}")
            continue
        if not isinstance(current, dict) or "id" not in current:
            plan.problems.append(f"settings {path}: not a settings object")
            continue
        desired = copy.deepcopy(current)
        changed = []
        for key, value in values.items():
            if key not in current:
                plan.problems.append(f"settings {path}: unknown setting '{key}'")
            elif current[key] != value:
                desired[key] = value
                changed.append(key)
        if changed:
            # config/naming is written to config/naming/<id>; delayprofile/1 to itself
            last = path.rsplit("/", 1)[-1]
            target = path if last == str(current["id"]) else f"{path}/{current['id']}"
            plan.write(
                "PUT", "/" + target, desired, f"update {path}: {', '.join(changed)}"
            )


def plan_quality_definitions(api, plan, definitions):
    live = {d["quality"]["name"]: d for d in read(api, plan, "/qualitydefinition")}
    for name, values in definitions.items():
        current = live.get(name)
        if current is None:
            plan.problems.append(f"quality definition '{name}' does not exist")
            continue
        desired = copy.deepcopy(current)
        changed = []
        for key, value in values.items():
            if key not in current and value is not None:
                plan.problems.append(
                    f"quality definition '{name}': unknown key '{key}'"
                )
            # an absent key and null both mean "no limit"
            elif current.get(key) != value:
                desired[key] = value
                changed.append(key)
        if changed:
            plan.write(
                "PUT",
                f"/qualitydefinition/{current['id']}",
                desired,
                f"update quality definition '{name}': {', '.join(changed)}",
            )
    for name in sorted(set(live) - set(definitions)):
        plan.notes.append(f"quality definition '{name}' is not declared; left as is")


def plan_quality_profiles(api, plan, profiles):
    live = {p["name"]: p for p in read(api, plan, "/qualityprofile")}
    for name, values in profiles.items():
        current = live.get(name)
        if current is None:
            # Recyclarr creates the profile; the next run sets these fields
            plan.notes.append(f"quality profile '{name}' does not exist yet; skipped")
            continue
        desired = copy.deepcopy(current)
        changed = []
        for key, value in values.items():
            if key not in current:
                plan.problems.append(f"quality profile '{name}': unknown key '{key}'")
            elif current[key] != value:
                desired[key] = value
                changed.append(key)
        if changed:
            plan.write(
                "PUT",
                f"/qualityprofile/{current['id']}",
                desired,
                f"update quality profile '{name}' (id {current['id']}): {', '.join(changed)}",
            )


def make_plan(api, spec, secrets):
    plan = Plan()
    try:
        if spec.get("rootFolders"):
            plan_root_folders(
                api,
                plan,
                spec["rootFolders"],
                spec.get("rootFolderNeedsProfiles", False),
            )
        for kind, key in (
            ("downloadclient", "downloadClients"),
            ("notification", "notifications"),
            ("applications", "applications"),
        ):
            if spec.get(key):
                plan_providers(api, plan, secrets, kind, spec[key])
        if spec.get("settings"):
            plan_settings(api, plan, spec["settings"])
        if spec.get("qualityDefinitions"):
            plan_quality_definitions(api, plan, spec["qualityDefinitions"])
        if spec.get("qualityProfiles"):
            plan_quality_profiles(api, plan, spec["qualityProfiles"])
    except ApiError as err:
        plan.problems.append(str(err))
    return plan


def report(name, plan):
    for note in plan.notes:
        log(f"{name}: {note}")
    for write in plan.writes:
        log(f"{name}: would {write['summary']}")
    for item in plan.problems:
        log(f"{name}: PROBLEM {item}")
    for item in plan.mismatches:
        log(f"{name}: {item} differs from its secret file; live value kept")
    for item in plan.unverifiable:
        log(f"{name}: {item} is masked and the database can't confirm it; left as is")
    log(
        f"{name}: {len(plan.writes)} write(s), {len(plan.problems)} problem(s), "
        f"{len(plan.mismatches)} mismatch(es), {len(plan.unverifiable)} unverifiable"
    )


def find_created(api, match):
    """After an uncertain create: the resource it may have created, if any."""
    if match["kind"] == "rootfolder":
        wanted = match["path"].rstrip("/")
        return next(
            (rf for rf in api.get("/rootfolder") if rf["path"].rstrip("/") == wanted),
            None,
        )
    return next(
        (
            item
            for item in api.get("/" + match["kind"])
            if item["name"] == match["name"]
            and item.get("implementation") == match["implementation"]
        ),
        None,
    )


def create(api, write):
    """POST a resource; returns what was created."""
    for attempt in range(RETRIES + 1):
        try:
            return api.request("POST", write["path"], write["body"], write["query"])
        except Uncertain as err:
            # look before retrying, so a create that did land isn't duplicated
            found = find_created(api, write["match"])
            if found is not None:
                log(f"{err}; the resource exists, so the create landed")
                return found
            if attempt == RETRIES:
                raise Uncertain(
                    f"{err}; not created after {attempt + 1} attempts"
                ) from err
            # A create still running server-side when the timeout hit is missed
            # here; the retry then fails Servarr's unique-name check (a 400),
            # and the next run converges with the resource that did land.
            delay = retry_delay(attempt)
            log(f"{err}; not created, retrying in {delay:.0f}s")
            api.sleep(delay)


def execute(api, write):
    if write["method"] != "POST":
        api.request(write["method"], write["path"], write["body"], write["query"])
        return
    created = create(api, write)
    if write["then"] is not None:
        body = dict(write["then"], id=created["id"])
        api.request("PUT", f"{write['path']}/{created['id']}", body, write["query"])


def save_backup(backup_dir, name, plan):
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    for n in range(100):
        path = os.path.join(
            backup_dir, f"{name}-before-{stamp}{f'-{n}' if n else ''}.json"
        )
        try:
            # O_EXCL: never overwrites an earlier before-image
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            break
        except FileExistsError:
            continue
    else:
        raise SystemExit(f"{name}: no free before-image name in {backup_dir}")
    with os.fdopen(fd, "w") as handle:
        json.dump(plan.reads, handle, indent=1, sort_keys=True)
    log(f"{name}: before-image saved to {path}")


def load_spec(path):
    with open(path) as handle:
        return json.load(handle)


def wait_all(spec, api_key):
    wait_ready(spec["name"], spec["url"], spec["apiVersion"], api_key)
    for dep in spec.get("waitFor", []):
        wait_ready(
            dep["name"], dep["url"], dep["apiVersion"], read_secret(dep["apiKeyFile"])
        )


def apply(spec, backup_dir):
    name = spec["name"]
    api_key = read_secret(spec["apiKeyFile"])
    wait_all(spec, api_key)
    secrets = StoredSecrets(spec.get("database"))
    plan = make_plan(
        ReadOnlyApi(spec["url"], spec["apiVersion"], api_key), spec, secrets
    )
    report(name, plan)
    if plan.problems:
        raise SystemExit(f"{name}: nothing written, the plan has problems")
    if plan.writes:
        if backup_dir:
            save_backup(backup_dir, name, plan)
        api = Api(spec["url"], spec["apiVersion"], api_key)
        for done, write in enumerate(plan.writes):
            try:
                execute(api, write)
            except (ApiError, Uncertain, OSError, http.client.HTTPException) as err:
                pending = [w["summary"] for w in plan.writes[done:]]
                raise SystemExit(
                    f"{name}: {write['summary']} failed: {err}; "
                    f"{done} write(s) done, not done: {'; '.join(pending)}"
                ) from err
            log(f"{name}: {write['summary']}")
        check = make_plan(
            ReadOnlyApi(spec["url"], spec["apiVersion"], api_key),
            spec,
            StoredSecrets(spec.get("database")),
        )
        if check.writes or check.problems:
            report(name, check)
            raise SystemExit(f"{name}: not converged after writing")
    if plan.mismatches or plan.unverifiable:
        raise SystemExit(
            f"{name}: secrets differ from or can't be checked against SOPS"
        )
    print(f"{name}: converged, {len(plan.writes)} write(s)", flush=True)


def preview(spec, expect_no_changes):
    name = spec["name"]
    api_key = read_secret(spec["apiKeyFile"])
    secrets = StoredSecrets(spec.get("database"))
    plan = make_plan(
        ReadOnlyApi(spec["url"], spec["apiVersion"], api_key), spec, secrets
    )
    report(name, plan)
    failed = plan.problems or plan.mismatches or plan.unverifiable
    return 1 if failed or (expect_no_changes and plan.writes) else 0


def main(argv):
    if len(argv) >= 3 and argv[1] == "apply":
        apply(load_spec(argv[2]), argv[3] if len(argv) > 3 else None)
        return 0
    if len(argv) >= 3 and argv[1] == "preview":
        return preview(load_spec(argv[2]), "--expect-no-changes" in argv[3:])
    raise SystemExit(__doc__.split("usage:")[1])


if __name__ == "__main__":
    sys.exit(main(sys.argv))
