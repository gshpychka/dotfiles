"""Reconcile Tautulli notification agents to declared state over the API v2.

Uses only get_notifiers, get_notifier_config, add_notifier_config and
set_notifier_config; never a notify/test command, never the database file.
Declared notifiers are matched by their stable database id. Undeclared
notifiers are reported and left alone. Each run computes the full plan first,
and refuses to write anything if any part of it cannot be applied.

Tautulli 2.18 API quirks this works around (plexpy/notifiers.py):
- set_notifier_config only applies friendly_name, custom_conditions and
  custom_conditions_logic when the passed value is truthy, so they cannot be
  blanked. "No conditions" is sent as Tautulli's own placeholder condition
  list (a truthy JSON string); a blank name or logic replacing a non-blank one
  is reported as an error instead of silently not converging.
- get_notifier_config masks non-empty config keys containing "password" as
  four spaces, and set_notifier_config ignores exactly that value for them.
  A masked value can't be compared, so a non-empty desired value is left as
  is, a blank one is sent as "" to clear it, and the mask is never sent back.
- Config values arrive as strings and are stored as sent; the read side casts
  ints back, so comparisons go through the agent's default types.
- Templates stored as NULL read back as Tautulli's defaults; a desired default
  therefore compares equal and the NULL is left untouched.

Secret config values (bot token, chat ids) come from systemd credentials. They
are only sent when they differ from the live value, and no value of any kind is
logged: output names notifier ids and field names only.

usage:
  reconcile.py check <desired.json> <schema.json>
  reconcile.py apply <desired.json> <schema.json> <base url> <state file>
"""

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

MASK = "    "
READ_COMMANDS = {"get_notifiers", "get_notifier_config"}
WRITE_COMMANDS = {"add_notifier_config", "set_notifier_config"}


def log(message):
    print(f"tautulli-notifiers: {message}", flush=True)


class ReconcileError(Exception):
    pass


class Api:
    def __init__(self, base_url, api_key, timeout=30):
        self.url = base_url.rstrip("/") + "/api/v2"
        self.api_key = api_key
        self.timeout = timeout

    def call(self, cmd, **params):
        if cmd not in READ_COMMANDS | WRITE_COMMANDS:
            raise ReconcileError(f"refusing API command {cmd}")
        # the key travels in a header so it never reaches Tautulli's API log;
        # writes go in a POST body so values stay out of any URL
        write = cmd in WRITE_COMMANDS
        query = urllib.parse.urlencode(
            {"cmd": cmd} if write else {"cmd": cmd, **params}
        )
        request = urllib.request.Request(
            f"{self.url}?{query}",
            data=urllib.parse.urlencode(params).encode() if write else None,
            headers={"X-Api-Key": self.api_key},
            method="POST" if write else "GET",
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                reply = json.load(response)["response"]
        except urllib.error.HTTPError as error:
            raise ReconcileError(f"{cmd} failed: HTTP {error.code}") from None
        data = reply.get("data")
        if reply.get("result") != "success" or (
            isinstance(data, dict) and data.get("result") == "error"
        ):
            message = (isinstance(data, dict) and data.get("message")) or reply.get(
                "message"
            )
            raise ReconcileError(f"{cmd} failed: {message}")
        return data

    def wait(self, deadline):
        while True:
            try:
                return self.call("get_notifiers")
            # HTTPError surfaces as ReconcileError above: Tautulli is up but refusing
            except (urllib.error.URLError, ConnectionError, TimeoutError) as error:
                if time.monotonic() > deadline:
                    raise ReconcileError(
                        f"Tautulli API not reachable: {error}"
                    ) from None
                time.sleep(2)


def check(desired, schema):
    errors = []
    ids = [n["id"] for n in desired["notifiers"]]
    if len(ids) != len(set(ids)):
        errors.append("duplicate notifier ids")
    for notifier in desired["notifiers"]:
        where = f"notifier {notifier['id']}"
        agent = schema["agents"].get(notifier["agent"])
        if agent is None:
            errors.append(f"{where}: unknown agent {notifier['agent']}")
            continue
        keys = set(notifier["config"]) | set(notifier["secret_config"])
        if set(notifier["config"]) & set(notifier["secret_config"]):
            errors.append(f"{where}: keys both plain and secret")
        # every agent key is declared, so the whole config is desired state
        if keys != set(agent["config"]):
            errors.append(
                f"{where}: config keys must be exactly {sorted(agent['config'])}"
            )
        for name in set(notifier["actions"]) | set(notifier["text"]):
            if name not in schema["actions"]:
                errors.append(f"{where}: unknown action {name}")
        for name, text in notifier["text"].items():
            if not set(text) <= {"subject", "body"}:
                errors.append(f"{where}: {name} text takes subject/body only")
    if errors:
        raise ReconcileError("; ".join(errors))


def normalize_conditions(conditions, schema):
    """Compare conditions by what Tautulli evaluates; [] is its placeholder.

    "type" is derived by Tautulli from the parameter, so it is not compared
    or sent.
    """

    def simplify(c):
        value = c.get("value", [])
        return {
            "parameter": c.get("parameter", ""),
            "operator": c.get("operator", ""),
            "value": value if isinstance(value, list) else [value],
        }

    return [simplify(c) for c in conditions or schema["default_custom_conditions"]]


def desired_config_value(notifier, key, credentials):
    if key in notifier["config"]:
        return notifier["config"][key]
    secret = notifier["secret_config"][key]
    return (credentials / secret["credential"]).read_text().rstrip("\n") + secret.get(
        "suffix", ""
    )


def plan(notifier, live, schema, credentials):
    """Return (params for set_notifier_config, impossible-change errors)."""
    agent = schema["agents"][notifier["agent"]]
    where = f"notifier {notifier['id']}"
    params, errors = {}, []

    if live["agent_name"] != notifier["agent"]:
        return {}, [
            f"{where}: live agent is {live['agent_name']}, declared {notifier['agent']}"
        ]

    if live["friendly_name"] != notifier["friendly_name"]:
        if notifier["friendly_name"]:
            params["friendly_name"] = notifier["friendly_name"]
        else:
            errors.append(
                f"{where}: the API cannot blank friendly_name; clear it in the UI"
            )

    for key, default in agent["config"].items():
        want = desired_config_value(notifier, key, credentials)
        have = live["config"].get(key)
        field = f"{notifier['agent']}_{key}"
        if "password" in key and have == MASK:
            if want == "":
                params[field] = ""
            continue
        if isinstance(default, int):
            if int(have or 0) != int(want):
                params[field] = str(int(want))
        elif have != want:
            params[field] = want

    enabled = set(notifier["actions"])
    for action, defaults in schema["actions"].items():
        want = 1 if action in enabled else 0
        if int(live["actions"].get(action, -1)) != want:
            params[action] = str(want)
        text = {**defaults, **notifier["text"].get(action, {})}
        have = live["notify_text"].get(action, {})
        for part in ("subject", "body"):
            if have.get(part) != text[part]:
                params[f"{action}_{part}"] = text[part]

    want_conditions = normalize_conditions(notifier["custom_conditions"], schema)
    if normalize_conditions(live["custom_conditions"], schema) != want_conditions:
        params["custom_conditions"] = json.dumps(want_conditions, ensure_ascii=False)

    if (live["custom_conditions_logic"] or "") != notifier["custom_conditions_logic"]:
        if notifier["custom_conditions_logic"]:
            params["custom_conditions_logic"] = notifier["custom_conditions_logic"]
        else:
            errors.append(
                f"{where}: the API cannot blank custom_conditions_logic; clear it in the UI"
            )

    return params, errors


def read_state(state_path, api_key_credential):
    """Mismatches recorded by configure.py (credential names only)."""
    if not state_path.exists():
        return []
    mismatched = json.loads(state_path.read_text()).get("mismatched", [])
    if api_key_credential in mismatched:
        raise ReconcileError(
            f"{api_key_credential} differs from config.ini; not calling the API with it"
        )
    return mismatched


def reconcile(api, desired, schema, credentials, deadline):
    live_ids = {n["id"]: n for n in api.wait(deadline)}
    for notifier_id in sorted(set(live_ids) - {n["id"] for n in desired["notifiers"]}):
        log(f"notifier {notifier_id} is not declared; left untouched")

    declared = sorted(desired["notifiers"], key=lambda n: n["id"])
    missing = [n for n in declared if n["id"] not in live_ids]
    if missing and live_ids and min(n["id"] for n in missing) <= max(live_ids):
        raise ReconcileError(
            "declared notifier ids "
            + ", ".join(str(n["id"]) for n in missing)
            + " are absent but below existing ids; they cannot be recreated with the same id"
        )

    # plan everything that exists before writing anything
    plans, errors = {}, []
    for notifier in declared:
        if notifier["id"] in live_ids:
            live = api.call("get_notifier_config", notifier_id=notifier["id"])
            plans[notifier["id"]], notifier_errors = plan(
                notifier, live, schema, credentials
            )
            errors += notifier_errors
    if errors:
        raise ReconcileError("; ".join(errors))

    changes = 0
    for notifier in declared:
        notifier_id = notifier["id"]
        if notifier_id not in live_ids:
            created = api.call(
                "add_notifier_config",
                agent_id=schema["agents"][notifier["agent"]]["id"],
            )["notifier_id"]
            if int(created) != notifier_id:
                raise ReconcileError(
                    f"created notifier {created} while declaring {notifier_id}; "
                    "fix the declared id before the next run"
                )
            log(f"notifier {notifier_id}: created")
            changes += 1
            live = api.call("get_notifier_config", notifier_id=notifier_id)
            plans[notifier_id], errors = plan(notifier, live, schema, credentials)
            if errors:
                raise ReconcileError("; ".join(errors))

        params = plans[notifier_id]
        if not params:
            log(f"notifier {notifier_id}: unchanged")
            continue
        api.call("set_notifier_config", notifier_id=notifier_id, **params)
        changes += len(params)
        log(f"notifier {notifier_id}: updated {', '.join(sorted(params))}")

        live = api.call("get_notifier_config", notifier_id=notifier_id)
        remaining, _ = plan(notifier, live, schema, credentials)
        if remaining:
            raise ReconcileError(
                f"notifier {notifier_id}: still differs after update: {', '.join(sorted(remaining))}"
            )
    log(f"changes={changes}")
    return changes


def main():
    command, desired_path, schema_path, *rest = sys.argv[1:]
    desired = json.loads(Path(desired_path).read_text())
    schema = json.loads(Path(schema_path).read_text())
    try:
        check(desired, schema)
        if command == "check":
            return
        base_url, state_path = rest
        credentials = Path(os.environ["CREDENTIALS_DIRECTORY"])
        mismatched = read_state(Path(state_path), desired["api_key_credential"])
        api_key = (credentials / desired["api_key_credential"]).read_text().strip()
        reconcile(
            Api(base_url, api_key),
            desired,
            schema,
            credentials,
            time.monotonic() + desired.get("startup_timeout", 300),
        )
        if mismatched:
            raise ReconcileError(
                "config.ini kept live values that differ from credentials "
                + ", ".join(mismatched)
                + "; verify those SOPS values (see configure.py)"
            )
    except ReconcileError as error:
        log(f"error: {error}")
        sys.exit(1)


if __name__ == "__main__":
    main()
