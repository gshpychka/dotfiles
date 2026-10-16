"""Extract the settings and notifier schema of a packaged Tautulli release.

Runs at build time against the exact Tautulli source the service runs, so the
declared settings, notify actions, agent config keys and default templates are
checked against that release instead of being copied by hand. Only literals
are read through ast; no Tautulli code is imported.

usage: schema.py <tautulli>/libexec/tautulli/plexpy > schema.json
"""

import ast
import json
import sys
from pathlib import Path


def _assignment(tree, name):
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(
            isinstance(t, ast.Name) and t.id == name for t in node.targets
        ):
            return node.value
    raise SystemExit(f"schema: {name} not found")


def _function(tree, name):
    for node in tree.body:
        if isinstance(node, ast.FunctionDef) and node.name == name:
            return node
    raise SystemExit(f"schema: {name}() not found")


def settings(config_py):
    # _CONFIG_DEFINITIONS = {'KEY': (type, 'Section', default), ...}; some
    # entries carry an extra element before the default
    tree = ast.parse(config_py.read_text(encoding="utf-8-sig"))
    definitions = _assignment(tree, "_CONFIG_DEFINITIONS")
    result = {}
    for key, value in zip(definitions.keys, definitions.values, strict=True):
        kind, section = value.elts[0].id, ast.literal_eval(value.elts[1])
        result[ast.literal_eval(key).lower()] = {"section": section, "type": kind}
    return result


def notifiers(notifiers_py):
    tree = ast.parse(notifiers_py.read_text(encoding="utf-8-sig"))

    # the action list is a plain literal inside a function; run just that
    # function with the one helper it can call stubbed out
    namespace = {"get_notify_agents": lambda **_: {}}
    exec(  # noqa: S102 - literal-only function from the pinned package
        compile(
            ast.Module([_function(tree, "available_notification_actions")], []),
            str(notifiers_py),
            "exec",
        ),
        namespace,
    )
    actions = {
        a["name"]: {"subject": a["subject"], "body": a["body"]}
        for a in namespace["available_notification_actions"]()
    }

    agent_ids = ast.literal_eval(_assignment(tree, "AGENT_IDS"))
    class_defaults = {}
    for node in tree.body:
        if isinstance(node, ast.ClassDef):
            for item in node.body:
                if isinstance(item, ast.Assign) and any(
                    isinstance(t, ast.Name) and t.id == "_DEFAULT_CONFIG"
                    for t in item.targets
                ):
                    class_defaults[node.name] = ast.literal_eval(item.value)

    # available_notification_agents() maps each agent name to its class
    agents = {}
    for node in ast.walk(_function(tree, "available_notification_agents")):
        if isinstance(node, ast.Dict):
            entry = {
                ast.literal_eval(k): v
                for k, v in zip(node.keys, node.values, strict=True)
                if isinstance(k, ast.Constant)
            }
            if "name" in entry and "class" in entry:
                name = ast.literal_eval(entry["name"])
                agents[name] = {
                    "id": agent_ids[name],
                    "config": class_defaults.get(entry["class"].id, {}),
                }

    return {
        "actions": actions,
        "agents": agents,
        "default_custom_conditions": ast.literal_eval(
            _assignment(tree, "DEFAULT_CUSTOM_CONDITIONS")
        ),
    }


def main():
    plexpy = Path(sys.argv[1])
    schema = {
        "settings": settings(plexpy / "config.py"),
        **notifiers(plexpy / "notifiers.py"),
    }
    if "telegram" not in schema["agents"] or not schema["actions"]:
        raise SystemExit("schema: unexpected Tautulli source layout")
    json.dump(schema, sys.stdout, ensure_ascii=False, indent=1, sort_keys=True)


if __name__ == "__main__":
    main()
