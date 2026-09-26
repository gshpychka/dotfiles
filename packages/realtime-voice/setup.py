"""Builds the AEC3 extension; everything else is declared in pyproject.toml."""

import shlex
import subprocess

from pybind11.setup_helpers import Pybind11Extension
from setuptools import setup


def pkg_config(*args: str) -> list[str]:
    return shlex.split(subprocess.check_output(["pkg-config", *args, "webrtc-audio-processing-2"], text=True))


setup(
    ext_modules=[
        Pybind11Extension(
            "realtime_voice._aec",
            ["src/realtime_voice/_aec.cpp"],
            cxx_std=17,
            extra_compile_args=pkg_config("--cflags"),
            extra_link_args=pkg_config("--libs"),
        )
    ]
)
