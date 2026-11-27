"""Deliberate SAST finding for the negative test; never merged."""

import subprocess


def run(cmd: str) -> None:
    subprocess.run(cmd, shell=True, check=True)  # noqa: S602
