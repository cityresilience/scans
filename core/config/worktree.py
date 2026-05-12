"""Git worktree helpers for per-scan branches.

Each scan = a branch on the `scans` remote, forked from `scans/working`.
The `working` branch is already stripped to scan-shape (only core/, source/,
tasks/, scan-calculations/) — a plain `git worktree add` produces a clean
scan folder, no sparse-checkout needed.
"""
import shutil
import subprocess
from pathlib import Path
from core.py.log_module import setup_logger

logger = setup_logger(__name__)

SCANS_REMOTE = "scans"
BASE_BRANCH = "working"
CODE_DIRS = ["core", "source", "tasks", "scan-calculations"]
DATA_DIRS = ["01-user-input", "02-process-output", "03-render-output", ".here"]


def _git(args, cwd=None, check=True):
    """Run a git command, capture output, return CompletedProcess."""
    return subprocess.run(
        ["git"] + args, cwd=cwd, check=check,
        capture_output=True, text=True,
    )


def _branch_exists_local(branch_name, repo_root):
    result = _git(["branch", "--list", branch_name], cwd=repo_root, check=False)
    return bool(result.stdout.strip())


def _branch_exists_remote(branch_name, repo_root, remote=SCANS_REMOTE):
    result = _git(["ls-remote", "--heads", remote, branch_name],
                  cwd=repo_root, check=False)
    return bool(result.stdout.strip())


def is_worktree(path):
    """A worktree has a .git FILE (pointer); a normal repo has a .git DIR."""
    git_path = Path(path) / ".git"
    return git_path.is_file()


def add_worktree(repo_root, scan_id, target_path):
    """
    Create a git worktree at target_path on branch <scan_id>.

    Branch lookup order:
    1. Local branch <scan_id> exists → check out at target_path
    2. scans/<scan_id> exists on remote → create local branch tracking remote
    3. Otherwise → create new branch <scan_id> from scans/working

    target_path must NOT exist yet. Because `working` is naturally stripped,
    the resulting folder only contains the scan-shape dirs.
    """
    repo_root = Path(repo_root)
    target_path = Path(target_path)

    if target_path.exists():
        raise FileExistsError(
            f"Path already exists: {target_path}. "
            f"Use migrate_to_worktree to convert an existing folder."
        )

    _git(["fetch", SCANS_REMOTE], cwd=repo_root, check=False)

    if _branch_exists_local(scan_id, repo_root):
        logger.info(f"Local branch '{scan_id}' exists — adding worktree at {target_path}")
        _git(["worktree", "add", str(target_path), scan_id], cwd=repo_root)
    elif _branch_exists_remote(scan_id, repo_root):
        logger.info(f"Remote branch '{SCANS_REMOTE}/{scan_id}' exists — adding worktree")
        _git(["worktree", "add", "-b", scan_id, str(target_path),
              f"{SCANS_REMOTE}/{scan_id}"], cwd=repo_root)
    else:
        logger.info(f"Creating new branch '{scan_id}' from {SCANS_REMOTE}/{BASE_BRANCH}")
        _git(["worktree", "add", "-b", scan_id, str(target_path),
              f"{SCANS_REMOTE}/{BASE_BRANCH}"], cwd=repo_root)


def migrate_to_worktree(repo_root, scan_id):
    """
    Convert mnt/<scan_id>/ from a plain dir to a git worktree.

    Steps:
    1. Rename existing dir to mnt/<scan_id>.temp
    2. Create worktree at mnt/<scan_id> (naturally clean scan-shape from `working`)
    3. Move local artifacts (data dirs, caches, anything non-code) from .temp into worktree
    4. Copy customized code (4 scan-shape dirs) from .temp over the worktree
    5. Delete .temp
    """
    repo_root = Path(repo_root)
    scan_path = repo_root / "mnt" / scan_id
    backup_path = repo_root / "mnt" / f"{scan_id}.temp"

    if not scan_path.exists():
        raise FileNotFoundError(f"Scan folder not found: {scan_path}")
    if is_worktree(scan_path):
        logger.info(f"{scan_path} is already a worktree — nothing to do")
        return
    if backup_path.exists():
        raise FileExistsError(
            f"Backup path already exists: {backup_path}. "
            f"Resolve manually before re-running."
        )

    logger.info(f"Step 1/5: rename {scan_path.name} → {backup_path.name}")
    scan_path.rename(backup_path)

    logger.info(f"Step 2/5: git worktree add at {scan_path}")
    add_worktree(repo_root, scan_id, scan_path)

    logger.info(f"Step 3/5: move local artifacts from .temp into worktree")
    skip = set(CODE_DIRS) | {".git"}
    for item in backup_path.iterdir():
        if item.name in skip:
            continue
        dst = scan_path / item.name
        if dst.exists():
            # Overwrite: lobito's version wins over the fresh-from-`working` default
            if dst.is_dir():
                shutil.rmtree(dst)
            else:
                dst.unlink()
        logger.info(f"  → {item.name}")
        item.rename(dst)

    logger.info(f"Step 4/5: copy customized code (scan-shape dirs) from .temp")
    for name in CODE_DIRS:
        src = backup_path / name
        if src.exists():
            logger.info(f"  → {name}")
            shutil.copytree(src, scan_path / name, dirs_exist_ok=True)

    logger.info(f"Step 5/5: delete {backup_path.name}")
    shutil.rmtree(backup_path)

    print(f"\n  Migration complete: {scan_path}")
    print(f"  Review with `git status` inside the worktree, then commit + push to scans.\n")
