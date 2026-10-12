"""Expose configured built-in IDF components, matching ESPHome discovery.

The first configure supplies project_description.json without compiling. A second
configure receives these REQUIRES, so a clean build does not need prior caches.
"""

import json
from pathlib import Path

description = json.loads(Path("build/project_description.json").read_text())
components = sorted(
    name
    for name, info in description["build_component_info"].items()
    if name != "src"
    and "/managed_components/" not in info["dir"]
    and "/vendor/" not in info["dir"]
)
assert "esp_driver_uart" in components
cmake = Path("CMakeLists.txt")
text = cmake.read_text()
assert "ESPHOME_PROJECT_BUILTIN_COMPONENTS" not in text
marker = "project("
position = text.index(marker)
properties = "\n".join(
    f"idf_build_set_property(ESPHOME_PROJECT_BUILTIN_COMPONENTS {name} APPEND)"
    for name in components
)
cmake.write_text(text[:position] + properties + "\n" + text[position:])
print("Discovered", len(components), "built-in IDF components from fresh configure")
