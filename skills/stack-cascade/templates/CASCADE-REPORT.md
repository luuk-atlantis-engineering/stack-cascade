# Cascade <run>: <what changed>, through the <N> branches above it

YYYY-MM-DD, <who>. Run in `<scratch worktree>` on a detached HEAD, not in the owners' worktrees. Each branch was rebased
with `git rebase --onto <new parent head> <run>/<parent>-before`. Nothing is pushed.

- **Old heads** are tagged `<run>/<branch>-before`, **new heads** `<run>/<branch>-after`.
- **Top:** the new top differs from the old one by <+x/−y in n files>: <the change, and any adaptations>.

## New heads

| Branch | Old | New | Note |
|---|---|---|---|
| <branch> | <old head> | <new head> | <e.g. +1 commit: …> |

## Range-diff per branch

| Branch | = | ! | added | dropped | Where the `!` are |
|---|---|---|---|---|---|
| <branch> | <n> | <n> | <n> | <n> | <commit: resolved / context only> |

## Conflicts, and how they were resolved

- **<branch>:** clean.
- **<branch>:** `<file>` (in "<commit subject>"): <both sides kept / which side, and why>.

## New commits

- **<branch> `<head>`:** "<subject>". Why: <reason>. It can be dropped on its own.

## Checks

- Unchanged branches: none needed.
- <branch>: quick build, <tests run>: <result>.
- **Top, full check:** <build and suite>: <passed / what failed>.

## Push

Waiting for the user's go. Push list: `<run folder>/push.txt`.
