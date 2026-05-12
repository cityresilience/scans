# Scan Sharing
> **Internal — WIP**. This is cityresilience/scans, used for internal sharing of per-scan branches via git worktrees. Currently public while testing as a fork; will be made private after leaving the fork network. The canonical public repo is cityresilience/city-scan

Ideas on how per-scan customizations can be shared using git, instead of manual file copying.


Two repos:
- `cityresilience/city-scan` — public code. Canonical branch `unified` (for now). 
- `cityresilience/scans` — private internal repo. Default branch `working`. Holds one branch per `mnt/<scan-id>/`. The `working` branch is the stripped scan-shape template (only `core/`, `source/`, `tasks/`, `scan-calculations/`).

**Idea:** Each scan in `mnt/` is a git worktree of `scans`, on a branch named after the scan-id (e.g. `2026-04-lobito_corridor`), forked from `working`. Because `working` only contains the scan-shape dirs, every scan worktree is naturally clean and do not carry bloat (`docs/`, `inputs/`, `notebook/`, `orchestrator.sh`, etc.).

<!-- ![Scan sharing architecture](workflow-scan-sharing.png) -->

---

## 1. One-time setup

```bash
cd ~/Documents/Work/city-scan-automation (or any local repo)
git remote add scans https://github.com/cityresilience/scans.git
git fetch scans
git checkout working
```

`working` is the local branch in the main folder. Bloat files (`docs/`, `inputs/`, `notebook/`, etc.) stay on disk locally as untracked — they're not tracked on `working`.

--- 
## 2. Get a scan into `mnt/`

Three ways depending on starting state.

### a. New scan from scratch

```bash
scan --all --worktree
```

Creates branch `<scan-id>` on scans (off `working`), runs `git worktree add mnt/<scan-id>`, then collection/analysis.

### b. Pull a scan from GitHub

```bash
git fetch scans
git worktree add -b <scan-id> mnt/<scan-id> scans/<scan-id>
```

Data dirs (`01-/02-/03-`) are gitignored — regenerate via `scan --all` or pull from GCS.

### c. Migrate an existing cp-r scan

```bash
scan --worktree <scan-id>
```

> **Steps under the hood:**
> 1. Rename `mnt/<scan-id>/` → `mnt/<scan-id>.temp/` (frees the path)
> 2. `git worktree add mnt/<scan-id>` on a new branch forked from `scans/working` — folder is naturally scan-shape (only `core/`, `source/`, `tasks/`, `scan-calculations/`, `README.md`, `.gitignore`)
> 3. Move non-code items from `.temp` back (data dirs `01-/02-/03-/.here`, local artifacts like `cache/`, `logs/`, `Rplots.pdf`, root-level files like `README.md`) — overwrites the fresh-from-`working` defaults
> 4. Copy customized code (`core/`, `source/`, `tasks/`, `scan-calculations/`) from `.temp` on top of the worktree
> 5. Delete `.temp`

End result: a worktree on a new scan branch with all your customizations layered on top — ready for `git add -A && git commit && git push scans <scan-id>` when you want to share.


---
## 3. Pulling Scans from Google Cloud

**TODO:** implement a way to start a scan from GCS, use --GCS flag.

---
## 4. Edit + push

Inside a scan worktree, commits go to that scan's branch when ready to share:

```bash
cd mnt/2026-04-lobito_corridor
git add .
git commit -m "tune flood breaks"
git push scans 2026-04-lobito_corridor
```

The main folder (on `working`) is unaffected by edits inside the worktree.

---

## 5. Sync ** STILL EXPERIMENTAL **

### a. Pull `working` updates into a scan

When the main folder (on `working`) has updates you want in your scan:

```bash
scan --scan-id <scan-id> --sync                  # all targets
scan --scan-id <scan-id> --sync tasks            # specific targets
```

Per-scan, on-demand. Dormant scans don't need it.

### b. Backport a scan fix to `working` (`--syncback`) ** to be implemented **

```bash
scan --scan-id <scan-id> --syncback core/R/some-fix.R
```

Would copy a file from the scan worktree into the main folder's working tree (on `working`). Not in the CLI yet.

### c. Bring upstream city-scan updates into `working`

 When `cityresilience/city-scan/unified` has new commits,  pull only the scan-shape dirs (because `working` is a stripped subset):

```bash
git fetch city-scan
git checkout working
git checkout city-scan/unified -- core source tasks scan-calculations
```

**TODO:** Maybe this could be another flag like --pull? 

> Note: `--sync`, `--syncback`, and the `git checkout` above are all local file operations. Commit + push to `scans working` (or the scan branch) only when you have changes to share — see section 4.

---

## 6. Remove a worktree

```bash
git worktree remove mnt/<scan-id>
git branch -D <scan-id>
git push scans --delete <scan-id>   # only if you want to drop the remote branch too
```

---
## Notes

- `01-user-input/`, `02-process-output/`, `03-render-output/` are gitignored — never committed.
- Same branch can only be checked out in one worktree at a time per clone. We can each have `mnt/<scan-id>/` locally — those are independent worktrees pointing at the same scans branch.
- `--worktree` and `--syncback` (to be implemented) are pipeline conveniences. Under the hood they're plain `git worktree add` / `cp` operations.
