"""Console entry point: run the packaged bash dispatcher.

The gate scripts are bash and stay bash. This module only finds a bash, points
HOUSEBROKEN_SCRIPTS at the copy of the scripts inside the installed package,
and hands every argument to bin/housebroken unchanged. Three subcommands are
answered in Python because they are about the package, not about a gate:
version, skill-path and install-skill.
"""

import contextlib
import os
import shutil
import subprocess
import sys
from importlib import metadata, resources
from pathlib import Path

DISTRIBUTION = "housebroken-cli"


def find_bash():
    bash = shutil.which("bash")
    if bash:
        return bash
    if os.name == "nt":
        git = shutil.which("git")
        if git:
            git_root = Path(git).resolve().parent.parent
            for candidate in (
                git_root / "bin" / "bash.exe",
                git_root / "usr" / "bin" / "bash.exe",
            ):
                if candidate.is_file():
                    return str(candidate)
    return None


def package_version():
    try:
        return metadata.version(DISTRIBUTION)
    except metadata.PackageNotFoundError:
        from housebroken import __version__

        return __version__


def install_skill(skill_md):
    target = Path(os.path.expanduser("~")) / ".claude" / "skills" / "housebroken" / "SKILL.md"
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(skill_md, target)
    print(f"installed {target}")


def main():
    args = sys.argv[1:]
    cmd = args[0] if args else "help"

    if cmd == "version" or cmd == "--version":
        print(f"housebroken {package_version()}")
        return 0

    with contextlib.ExitStack() as stack:
        root = stack.enter_context(resources.as_file(resources.files("housebroken")))

        if cmd == "skill-path":
            print(root / "skill" / "SKILL.md")
            return 0
        if cmd == "install-skill":
            install_skill(root / "skill" / "SKILL.md")
            return 0

        bash = find_bash()
        if bash is None:
            print(
                "housebroken: no bash found. Install Git Bash on Windows "
                "(https://git-scm.com/download/win) or bash on Unix, and make "
                "sure bash is on PATH.",
                file=sys.stderr,
            )
            return 2

        scripts = root / "scripts"
        env = dict(os.environ)
        env["HOUSEBROKEN_SCRIPTS"] = str(scripts)
        completed = subprocess.run(
            [bash, str(scripts / "housebroken"), *args], env=env
        )
        return completed.returncode


if __name__ == "__main__":
    sys.exit(main())
