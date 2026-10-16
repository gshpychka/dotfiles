"""Assert declared settings and SOPS secrets into Tautulli's config.ini.

Runs as Tautulli's ExecStartPre (service user, Tautulli stopped). config.ini
stays Tautulli's own runtime-writable file: only the declared keys are
re-asserted on every start, everything else (server identifiers, upgrade
flags, UI-only state) is left exactly as Tautulli wrote it. The file is only
rewritten when a value actually differs, through the same configobj library
Tautulli bundles, so a converged start is a no-op.

Secrets come from systemd credentials ($CREDENTIALS_DIRECTORY) and are never
printed; log lines carry section/key and credential names only.

No rotation on adoption: the first time a credential is seen, a differing
non-empty live value is kept and reported as a mismatch instead of being
overwritten (tautulli-notifiers turns that into a failed unit). Once a
credential matched or filled an empty value it is recorded as adopted, and
from then on SOPS is authoritative and a changed SOPS value is applied.

The first run also snapshots config.ini and the database (via sqlite's backup
API) under backups/pre-declarative-<UTC>/ before anything is changed, and the
whole data directory is restricted to the service user (it holds the API key,
Plex token, password hash, JWT secret and notifier tokens).

usage:
  configure.py check <settings.json> <schema.json>
  configure.py apply <settings.json> <schema.json> <configobj dir> <data dir> <config.ini>
  configure.py preview <same as apply>

preview runs the same logic read-only against the live files before a deploy
and exits non-zero if any credential would be kept as a mismatch or rotated
(see preview()); credentials come from $CREDENTIALS_DIRECTORY as in apply.
"""

import json
import os
import shutil
import sqlite3
import stat
import sys
import tempfile
from datetime import UTC, datetime
from pathlib import Path

STATE_FILE = "declarative-secrets.json"
DATABASE_FILE = "tautulli.db"
# declared JSON value types accepted for each Tautulli setting type (bools
# are flags written as 1/0); other setting types aren't declarable
JSON_TYPES = {"int": int, "bool_int": int, "str": str, "list": list}


def log(message):
    print(f"tautulli-configure: {message}", flush=True)


def ini_value(value):
    """Render a declared JSON value the way configobj holds it."""
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, list):
        return [ini_value(v) for v in value]
    return value


def check(desired, schema):
    """Fail on any declared key Tautulli does not define in that section."""
    known = schema["settings"]
    errors = []
    seen = set()
    for section, values in desired["settings"].items():
        for key, value in values.items():
            definition = known.get(key)
            if definition is None or definition["section"] != section:
                errors.append(f"unknown setting {section}.{key}")
            elif not isinstance(value, JSON_TYPES.get(definition["type"], ())):
                errors.append(f"{section}.{key} must be a {definition['type']}")
            seen.add(key)
    for secret in desired["secrets"]:
        definition = known.get(secret["key"])
        if definition is None or definition["section"] != secret["section"]:
            errors.append(f"unknown secret setting {secret['section']}.{secret['key']}")
        if secret["key"] in seen:
            errors.append(f"{secret['key']} is declared as both a setting and a secret")
        seen.add(secret["key"])
    if errors:
        raise SystemExit("tautulli-configure: " + "; ".join(errors))


def restrict(data_dir):
    """Drop group/other access below the data dir; returns the count changed."""
    changed = _restrict_one(data_dir)
    for root, dirs, files in os.walk(data_dir):
        for name in dirs + files:
            changed += _restrict_one(os.path.join(root, name))
    return changed


def _restrict_one(path):
    mode = os.lstat(path).st_mode
    # symlink modes are meaningless and chmod would follow the link
    if stat.S_ISLNK(mode) or not mode & 0o077:
        return 0
    os.chmod(path, stat.S_IMODE(mode) & ~0o077)
    return 1


def snapshot(data_dir, config_path):
    """One-off pre-migration copy of config.ini and the database."""
    target = (
        data_dir / "backups" / f"pre-declarative-{datetime.now(UTC):%Y%m%dT%H%M%SZ}"
    )
    target.mkdir(parents=True, mode=0o700)
    if config_path.exists():
        shutil.copy2(config_path, target / config_path.name)
    database = data_dir / DATABASE_FILE
    if database.exists():
        source = sqlite3.connect(f"file:{database}?mode=ro", uri=True)
        copy = sqlite3.connect(target / DATABASE_FILE)
        with copy:
            source.backup(copy)
        copy.close()
        source.close()
    for path in target.iterdir():
        path.chmod(0o600)
    log(f"saved pre-migration snapshot to {target}")


def write_atomic(path, write):
    fd, temp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(fd, "wb") as handle:
            write(handle)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temp, 0o600)
        os.replace(temp, path)
    except BaseException:
        os.unlink(temp)
        raise


def converge(config, desired, credentials, adopted):
    """Assert desired values into a loaded ConfigObj, in memory only.

    Returns (changed keys, adopted credential names, secret outcomes); an
    outcome is one of match, fill (live empty), rotate (adopted, SOPS
    changed) or mismatch (differing live value kept, nothing assigned).
    """
    adopted = set(adopted)
    changes, outcomes = [], {}

    def assign(section, key, value):
        if section not in config:
            config[section] = {}
        if config[section].get(key) != value:
            config[section][key] = value
            changes.append(f"{section}.{key}")

    for section, values in desired["settings"].items():
        for key, value in values.items():
            assign(section, key, ini_value(value))

    for secret in desired["secrets"]:
        name, section, key = secret["credential"], secret["section"], secret["key"]
        value = (credentials / name).read_text().rstrip("\n")
        live = config.get(section, {}).get(key, "")
        if live == value:
            outcomes[name] = "match"
        elif live == "":
            outcomes[name] = "fill"
        elif name in adopted:
            outcomes[name] = "rotate"
        else:
            outcomes[name] = "mismatch"
            continue
        assign(section, key, value)
        adopted.add(name)
    return changes, adopted, outcomes


def load_config(configobj_dir, config_path):
    sys.path.insert(0, str(configobj_dir))
    from configobj import ConfigObj  # Tautulli's bundled copy

    return ConfigObj(str(config_path), encoding="utf-8")


def apply(desired, configobj_dir, data_dir, config_path, credentials):
    state_path = data_dir / STATE_FILE
    if state_path.exists():
        state = json.loads(state_path.read_text())
    else:
        snapshot(data_dir, config_path)
        state = {"adopted": [], "mismatched": []}

    # after the snapshot, which may have created backups/
    changed_modes = restrict(data_dir)
    if changed_modes:
        log(f"restricted permissions on {changed_modes} path(s)")

    config = load_config(configobj_dir, config_path)
    changes, adopted, outcomes = converge(
        config, desired, credentials, state["adopted"]
    )
    mismatched = {name for name, outcome in outcomes.items() if outcome == "mismatch"}
    for secret in desired["secrets"]:
        if secret["credential"] in mismatched:
            log(
                f"{secret['section']}.{secret['key']} differs from credential "
                f"{secret['credential']}; kept the live value (no rotation on adoption)"
            )

    if changes:
        write_atomic(config_path, config.write)
        log(f"updated {', '.join(changes)}")
    else:
        log("config.ini already converged")

    new_state = {"adopted": sorted(adopted), "mismatched": sorted(mismatched)}
    if new_state != state or not state_path.exists():
        write_atomic(
            state_path, lambda h: h.write(json.dumps(new_state, indent=1).encode())
        )


def preview(desired, configobj_dir, data_dir, config_path, credentials):
    """Read-only dry run of apply against the live files; True if safe.

    Writes nothing. Strict: any credential whose value differs from a
    non-empty live one fails, whether apply would keep it (mismatch) or
    overwrite it (rotate), so a deploy can't change a working secret.
    """
    state_path = data_dir / STATE_FILE
    adopted = (
        json.loads(state_path.read_text())["adopted"] if state_path.exists() else []
    )
    config = load_config(configobj_dir, config_path)
    changes, _, outcomes = converge(config, desired, credentials, adopted)
    for name, outcome in sorted(outcomes.items()):
        log(f"preview: credential {name}: {outcome}")
    log(f"preview: would update {', '.join(changes) or 'nothing'}")
    return all(outcome in ("match", "fill") for outcome in outcomes.values())


def main():
    command, desired_path, schema_path, *rest = sys.argv[1:]
    desired = json.loads(Path(desired_path).read_text())
    check(desired, json.loads(Path(schema_path).read_text()))
    if command == "check":
        return
    configobj_dir, data_dir, config_path = map(Path, rest)
    credentials = Path(os.environ["CREDENTIALS_DIRECTORY"])
    if command == "preview":
        if not preview(desired, configobj_dir, data_dir, config_path, credentials):
            raise SystemExit(
                "tautulli-configure: preview: a credential differs from live"
            )
        return
    apply(desired, configobj_dir, data_dir, config_path, credentials)


if __name__ == "__main__":
    main()
