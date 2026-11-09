---
name: stack-cascade
description: "Carry a change up a stack of dependent branches (stacked PRs) safely: record every head, back up as tags, rebase bottom-up with `git rebase --onto <parent's new head> <parent's old head>` in a scratch worktree, send judgement conflicts to the branch's owner, let each branch's range-diff decide what gets checked (unchanged: nothing; a manual change: a quick build plus the touched tests; one full check at the top), then push everything in one atomic push with leases on the user's go, and verify every PR's base and order. Use when a fix lands low in a stack, a parent branch was amended or rebased, the trunk moved under a stack, review fixes were made on several stacked branches, or the user says cascade, restack, rebase the stack, sync the stack, or propagate a change up. Triggers: 'cascade', 'restack', 'rebase the stack', 'sync the stack', 'stacked PRs', 'propagate up', 'gh stack'."
argument-hint: "[lowest changed branch]"
---

# Stack cascade

A stack is a chain of branches, each built on the one below, usually with a PR each. When a branch low in the stack
changes (a review fix, an amended commit, a rebase onto a newer trunk), every branch above it has to move onto its
parent's new head. That's a cascade.

Done carelessly, a cascade silently drops a branch's commits, or replays a parent's whole history into it. Nothing
looks wrong until a reviewer sees it. This skill is the safe way.

Starting point: **$ARGUMENTS** (the lowest changed branch, if given; otherwise find it with the user).

## Before you start

1. **Know the stack, bottom to top.** Take it from `gh stack view`, from the PRs' base chain
   (`gh pr list --json number,headRefName,baseRefName`), or from the user. Write it down in order, and settle which
   branch changed and what its old and new heads are.
2. **Work in a scratch worktree of your own:** `git worktree add --detach <path>`. Never cascade in the user's checkout
   or in a branch owner's worktree, and never leave a paused rebase in one.
3. **Fetch, and compare** each local branch with its remote. Someone else (a reviewer, another session) may have pushed
   or rebased. Settle every difference before you start.
4. **Record every head:** the branch and its old head, one per line. It's your way back, and later your push's lease.
5. **Back up as tags, not branches:** `git tag <run>/<branch>-before <head>`. A `rebase --update-refs` moves every local
   branch that points into the rebased range, backup branches included. It leaves tags alone.

`scripts/cascade.sh` in this skill's folder does steps 4 and 5 and the loop below, with the guards:
```sh
sh scripts/cascade.sh start <run> <parent-old> <parent-new> <branch>...   # branches bottom to top
sh scripts/cascade.sh resume <run>                                        # after a resolved conflict
```
It works on a detached HEAD, moves no branch, tags new heads `<run>/<branch>-after`, and prints the push command.

## The one rule

For each branch above the change, bottom-up:

```sh
git rebase --onto <parent's NEW head> <parent's OLD head> <branch>
```

The parent's old head is the head it had **before this cascade**, from your recorded list. Two wrong upstreams look
right and aren't:
- **`git merge-base <branch> <parent>`** is only valid while the parent hasn't been rewritten. Once it has, the merge
  base falls back to an old ancestor, and the rebase replays the parent's history into the branch.
- **The branch's own old head** makes the range empty: the branch lands on its parent with all its commits dropped. The
  sign is that every branch ends up with the same hash.

**Guard every step:**
- Before: `git merge-base --is-ancestor <parent's old head> <branch>`, or stop. It catches a wrong parent or order.
- After: the branch's own commit count (`git rev-list --count <parent new>..<new head>`) matches its count before. If
  it's lower, check why before going on. A commit that's already in the parent is fine. Anything else is a bug.

## Conflicts

- **Mechanical conflicts are yours:** imports, a line moved next to yours, two additions to the same list. Keep both
  sides' intent.
- **Judgement conflicts go to the branch's owner:** two behaviours collide, a signature changed under the branch, a
  test now asserts something else. Stop, give the owner the exact spot, and continue after they've resolved it.
- **A branch that no longer compiles after a clean merge** counts as a manual change. Fix it in the commit where it
  broke, so every commit still builds.
- **Add no new behaviour during a cascade.** If the cascade shows something needs fixing, make it a separate commit,
  say so, and make sure it can be dropped on its own.
- **Write down every resolution**, for the report.

## Check proportionally

After each branch, read its range-diff (`git range-diff -s <parent old>..<old head> <parent new>..<new head>`). Let it
decide what gets checked:

| Range-diff | Check |
|---|---|
| all `=` | nothing: no build, no tests |
| `!` only where your lines merged next to theirs | nothing more |
| `!` from a conflict you resolved or an adaptation | a quick build, plus only the tests covering the touched code |
| added or dropped commits | read them: a commit changed beyond recognition shows as one dropped plus one added |

Then **one full check at the top,** once, at the end: the full build and the full test suite on the top branch. Not
per branch, not per PR.

- **Once the touched tests pass, stop.** Don't rebuild to prove they fail without the fix.
- **Don't let a pipe hide a failed build:** `set -o pipefail` before `build | tail`.
- **Restore packages first** when a rebase brought new dependencies. Otherwise the build fails, or tests "pass" on stale
  binaries.

## Report

Write the cascade down, from `templates/CASCADE-REPORT.md`:
- each branch's old and new head;
- its range-diff counts, and where the `!` are;
- every conflict and how it was resolved;
- any new commit and why;
- what was checked, with the results, and the top's full check.

The user and the reviewers read this instead of re-checking every branch.

## Push

1. **Only on the user's go,** after the full check at the top passed, or with its failures reported.
2. **Fetch again right before.** If any remote head differs from your recorded old head, stop: someone pushed in
   between.
3. **Push everything in one atomic push with explicit leases:**
   ```sh
   git push --atomic origin \
     --force-with-lease=<branch>:<old head> <new head>:refs/heads/<branch> \
     ...
   ```
   Either every branch moves, or none does.
4. **Verify every PR afterwards:**
   - its base (`gh pr view <n> --json baseRefName,headRefOid,mergeable`);
   - that its head is the new head;
   - that its file count matches `git diff --name-only origin/<parent>...origin/<branch> | wc -l`;
   - that the stack's order is intact.
5. **Move the local branches** to the new heads. Sync an owner's worktree only if it's clean (`git reset --keep <new>`).
   Otherwise, tell the owner.

## GitHub stacked PRs

The PRs' bases survive a cascade untouched: no `gh stack` command is needed after one. For everything else (adding a
PR, removing a closed one, inserting mid-stack, a PR stuck as "dirty"), read `references/gh-stack.md` first. Several
`gh stack` commands push or retarget more than they seem to.

## Rules

- **Nothing is pushed without the user's go, and nothing is force-pushed without leases.**
- **Re-read the heads right before acting** when others are committing on the same branches.
- **Keep spike and throwaway branches out of the stack**, and out of its local tracking.
- **In a team** (see the `team-coordinator` skill), the coordinator runs the cascade or hands it to one worker, and the
  branch owners resolve their own judgement conflicts.
