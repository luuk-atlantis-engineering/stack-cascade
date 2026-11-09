# stack-cascade

A [Claude Code](https://claude.com/claude-code) skill for carrying a change up a stack of dependent branches (stacked
PRs) without losing commits, without over-checking, and without surprises on the remote.

## Why

When a fix lands low in a stack, every branch above it has to move onto its parent's new head. It looks like a few
rebases, but it's easy to get wrong in ways that don't show:
- `git merge-base` as the upstream, after the parent was rewritten, replays the parent's whole history into the child;
- the child's own old head as the upstream drops all its commits;
- `rebase --update-refs` silently moves your backup branches;
- a full build and test run per branch turns a ten-minute job into hours;
- one force-push per branch leaves the stack half-moved when one of them fails.

## What the skill does

- **Records every head** and backs it up as a tag before anything moves.
- **Rebases bottom-up** with `git rebase --onto <parent's new head> <parent's old head>`, in a scratch worktree. Before
  each step it checks the parent's old head is really in the branch, and after each step it checks no commit was lost.
- **Sorts conflicts:** mechanical ones it resolves, judgement ones go to the branch's owner.
- **Checks proportionally,** from each branch's range-diff: unchanged branches get nothing, manual changes get a quick
  build and the touched tests, and the top gets one full check.
- **Writes a report** per cascade: heads, range-diffs, resolutions, checks.
- **Pushes once:** atomic, with explicit leases, only on the user's go. It then verifies every PR's base, head and diff.
- **Knows the traps of GitHub stacked PRs** (`gh stack`): what `submit`, `link` and `unstack` really do.

`scripts/cascade.sh` runs the loop with those guards:

```sh
sh scripts/cascade.sh start <run> <parent-old> <parent-new> <branch>...   # branches bottom to top
sh scripts/cascade.sh resume <run>                                        # after a resolved conflict
```

It moves no branch and pushes nothing. New heads are tagged `<run>/<branch>-after`, and it prints the atomic push
command.

## Install

```sh
git clone https://github.com/luuk-atlantis-engineering/stack-cascade.git
cp -r stack-cascade/skills/stack-cascade ~/.claude/skills/
```

Then ask Claude Code to "cascade the fix on `<branch>` up the stack", or run `/stack-cascade <branch>`.

It works well with [team-skills](https://github.com/luuk-atlantis-engineering/team-skills), where the coordinator runs
the cascade and the branch owners resolve their own conflicts.
