---
name: skill-update
description: Publish or update local Codex skills in a Git repository (for example a GitLab skills repo) with optional sanitization before commit/push. Use when Codex needs to sync current skill folders, redact personal markers, review git status, and safely commit/push skill updates to a remote repository.
---

# Skill Update

## Overview

Use this skill to package local skills for sharing and push them to a Git repo (for example GitLab).

Prefer a safe workflow: sanitize first, inspect the diff, then commit and push only after explicit confirmation.

## Workflow

### 1. Identify Source and Target

Collect:

- source skills directory (for example `./skills`)
- target Git repo directory (for example `./gitlab/skills`)
- which skills to publish (all or selected names)
- whether sanitization is required

If the repo path is unknown, inspect likely workspace paths first.

### 2. Sanitize (If Needed)

Before publishing, scan for:

- personal names/owner tags
- internal URLs/hostnames
- queue IDs / storage IDs / environment-specific values

For this workspace, common sanitization is replacing `<owner_id>` with `owner-tag` in shared skill docs.

### 3. Sync Files into the Git Repo

Use `scripts/publish_skills.sh` to:

- copy selected skill folders into the target repo
- optionally replace owner marker text in the copied files
- optionally copy a README

Do not modify the original `skills/` source folders when sanitizing.

### 4. Review Git Changes

Always inspect:

- `git status --short`
- `git diff --stat` (or a focused diff)
- remote URL (`git remote -v`)

### 5. Commit and Push (With Confirmation)

Before pushing:

- show the exact `git push` command
- confirm branch and remote
- ask user for confirmation

If push fails (auth/network), return the exact error and a concrete next step (SSH key, PAT, or manual push).

### 6. Create Backup Tarball (After Push)

After a successful push, create a backup archive of the sanitized published files.

Workspace convention:

- Output file: `/home/mi/codes/workspace/all.tar.gz`
- Archive source: sanitized stage/export copy (not the original `skills/` folders)

Do not include `.git/` metadata in the backup archive.

## Script

Use `scripts/publish_skills.sh --help` for options.

Typical usage:

```bash
scripts/publish_skills.sh \
  --src ./skills \
  --repo ./gitlab/skills \
  --export ./redacted/skills-public \
  --skills job-uploader,job-manager \
  --owner-from <owner_id> \
  --owner-to owner-tag \
  --readme ./redacted/skills-public/README.md \
  --commit --push \
  --backup-tar /home/mi/codes/workspace/all.tar.gz
```

## Safety Rules

- Default to sanitizing shared copies before publishing to remote repos.
- Do not push without explicit user confirmation.
- If the repo contains unrelated changes, call them out before committing.
- Commit only the intended skill files (and README if requested).
- For this workspace's GitLab publishing flow, do not include `skill-update` in the published skill list unless the user explicitly asks.
