"""Run common SeqCheckFlow commands in the pinned Docker environment."""

from pathlib import Path
import subprocess
import sys


PROJECT_ROOT = Path(__file__).resolve().parents[1]
COMMANDS = {
    "analyze": "seqcheckflow.pipeline",
    "download": "seqcheckflow.download",
    "prepare-hg002": "seqcheckflow.giab_data",
    "compare-hg002": "seqcheckflow.full_benchmark",
}


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        choices = " | ".join(COMMANDS)
        print(f"Usage: python scripts/seqcheckflow.py <{choices}> [options]", file=sys.stderr)
        return 2

    command, *arguments = sys.argv[1:]
    docker_command = [
        "docker",
        "compose",
        "run",
        "--build",
        "--rm",
        "seqcheckflow",
        "python",
        "-m",
        COMMANDS[command],
        *arguments,
    ]
    try:
        return subprocess.run(docker_command, cwd=PROJECT_ROOT, check=False).returncode
    except FileNotFoundError:
        print(
            "Docker Compose was not found. Install Docker Desktop (or Docker Engine "
            "with the Compose plugin), start the Docker daemon, and retry.",
            file=sys.stderr,
        )
        return 127


if __name__ == "__main__":
    raise SystemExit(main())
