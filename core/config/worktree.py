"""Git worktree helpers for per-scan branches.

Migration: convert an existing cp-r mnt/<scan-id> folder to a git worktree.
The worktree's branch is named after the scan-id and lives in the `scans` remote.
"""
import subprocess
from pathlib import Path
from core.py.log_module import setup_logger

logger = setup_logger(__name__)

SCANS_REMOTE = "scans"


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
    2. scans/<scan_id> exists on remote → create local branch tracking remote, check out
    3. Otherwise → create new branch <scan_id> from HEAD, check out

    target_path must NOT exist yet.
    """
    repo_root = Path(repo_root)
    target_path = Path(target_path)

    if target_path.exists():
        raise FileExistsError(
            f"Path already exists: {target_path}. "
            f"Use migrate_to_worktree to convert an existing folder."
        )

    # Try to fetch latest from scans (silent if remote not configured)
    _git(["fetch", SCANS_REMOTE], cwd=repo_root, check=False)

    if _branch_exists_local(scan_id, repo_root):
        logger.info(f"Local branch '{scan_id}' exists — adding worktree at {target_path}")
        _git(["worktree", "add", str(target_path), scan_id], cwd=repo_root)
    elif _branch_exists_remote(scan_id, repo_root):
        logger.info(f"Remote branch '{SCANS_REMOTE}/{scan_id}' exists — adding worktree")
        _git(["worktree", "add", "-b", scan_id, str(target_path),
              f"{SCANS_REMOTE}/{scan_id}"], cwd=repo_root)
    else:
        logger.info(f"Creating new branch '{scan_id}' from HEAD — adding worktree")
        _git(["worktree", "add", "-b", scan_id, str(target_path)], cwd=repo_root)


def migrate_to_worktree(repo_root, scan_id):
    """
    Convert mnt/<scan_id>/ from a plain dir to a git worktree.

    Steps:
    1. Rename existing dir to mnt/<scan_id>.old
    2. Create worktree at mnt/<scan_id>
    3. Move data dirs (01-, 02-, 03-, .here) from .old back into the worktree
    4. Leave .old for the user to inspect (port any code customizations, then rm)
    """
    repo_root = Path(repo_root)
    scan_path = repo_root / "mnt" / scan_id
    backup_path = repo_root / "mnt" / f"{scan_id}.old"

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

    logger.info(f"Step 1/3: rename {scan_path.name} → {backup_path.name}")
    scan_path.rename(backup_path)

    logger.info(f"Step 2/3: git worktree add at {scan_path}")
    add_worktree(repo_root, scan_id, scan_path)

    logger.info(f"Step 3/3: move data dirs back into the worktree")
    for name in ["01-user-input", "02-process-output", "03-render-output", ".here"]:
        src = backup_path / name
        dst = scan_path / name
        if src.exists():
            logger.info(f"  → {name}")
            src.rename(dst)

    print(f"\n  Migration complete: {scan_path}")
    print(f"  Backup: {backup_path}")
    print(f"  Inspect {backup_path.name} for any code customizations to port,")
    print(f"  then `rm -rf {backup_path}` when done.\n")
