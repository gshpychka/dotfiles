"""Resolve cached IDF manifests into explicit CMake REQUIRES, offline.

With IDF_COMPONENT_MANAGER=0 the registry manager no longer supplies YAML
requirements. Only components actually present in the pinned closure are linked;
optional manifest dependencies absent from this SDK configuration are ignored.
"""

import re
from pathlib import Path

import yaml

root = Path.cwd()
components = (
    [root / "src"]
    + sorted((root / "managed_components").iterdir())
    + sorted((root / "vendor").iterdir())
)
by_name = {p.name: p for p in components if p.is_dir()}


def patch_calls(text, dependencies):
    prefix = "idf_component_register("
    offset = 0
    while (start := text.find(prefix, offset)) >= 0:
        position = start + len(prefix)
        end = position
        depth = 1
        quote = False
        while depth:
            char = text[end]
            if char == '"' and (end == 0 or text[end - 1] != "\\"):
                quote = not quote
            if not quote:
                if char == "(":
                    depth += 1
                elif char == ")":
                    depth -= 1
            end += 1
        body = text[position : end - 1]
        match = re.search(r"\bREQUIRES\b", body)
        if match:
            index = match.end()
            body = body[:index] + " " + " ".join(dependencies) + " " + body[index:]
        else:
            body = "\n REQUIRES " + " ".join(dependencies) + "\n" + body
        text = text[:position] + body + text[end - 1 :]
        offset = position + len(body) + 1
    return text


for name, component in by_name.items():
    manifest = component / "idf_component.yml"
    if not manifest.exists():
        continue
    dependencies = []
    for dependency in (yaml.safe_load(manifest.read_text()) or {}).get(
        "dependencies", {}
    ):
        qualified = dependency.replace("/", "__")
        if qualified in by_name and qualified != name:
            dependencies.append(qualified)
        elif dependency in by_name and dependency != name:
            dependencies.append(dependency)
    if not dependencies:
        continue
    changed = False
    for file in list(component.rglob("*.cmake")) + list(
        component.rglob("CMakeLists.txt")
    ):
        text = file.read_text()
        if "idf_component_register(" in text:
            file.write_text(patch_calls(text, dependencies))
            changed = True
    if not changed:
        raise RuntimeError(
            f"Manifest dependencies found but no registration for {name}"
        )
    print(name + " requires " + ", ".join(dependencies))
