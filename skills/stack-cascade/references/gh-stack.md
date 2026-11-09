# GitHub stacked PRs: what each command really does

GitHub stacked pull requests are driven by the `gh stack` extension (`github/gh-stack`, GitHub CLI 2.90.0 or later).
Several of its commands do more than their names suggest. Read this before you run one on a stack that matters.

## Opening and growing a stack

- **Open a child PR straight away**, while its parent's PR is still open. That's what stacks are for. Don't wait for the
  parent to merge.
- `gh stack init --base <trunk> <lower> <upper>` adopts existing branches. It only writes local tracking.
- `gh stack submit` pushes and opens or links the PRs. **It pushes every branch in local tracking, merged ones
  included.** If tracking still lists merged branches that were deleted on the remote, `submit` recreates them. Check
  first, for each tracked branch: `git ls-remote --heads origin <branch>`.
- **To add one PR on top of an existing stack:** `gh pr create --base <parent>`, then `gh stack link <stack> <pr>`.
  That pushes nothing else.
- **Chained bases are not a stack.** PRs opened with `gh pr create` one on the other must still be linked into the
  stack.
- **A stack can target a branch other than the default**, for example an epic's staging branch:
  `gh stack init --base <branch>`.

## Syncing

- `gh stack sync` aborts on the first conflict. A real sync of a long stack is a cascade by hand (see `SKILL.md`).
- After a lower PR merges, `gh stack sync --prune` fetches, rebases the rest and pushes, when nothing conflicts.
- **If a parent merged before the child was submitted:**
  1. Preview the conflicts with `git merge-tree --write-tree <trunk> HEAD`.
  2. Rebase the child onto the trunk, and check it.
  3. Open a plain `gh pr create` against the trunk. A stack of one adds nothing.

## Removing a PR from a stack

- **`gh stack link` never removes members.** If the stack holds a closed PR, `link` keeps it as the top and retargets
  the first new PR's base onto the dead branch. There's no dry run.
- What works:
  1. `gh stack unstack <stack>`. It only dissolves the grouping: the PRs and their bases stay as they are.
  2. `gh stack link --base <trunk> <every open PR, bottom to top>`. It re-chains the bases and makes a new stack number.
  3. `gh stack init --base <trunk> <branches...>`, to restore the local tracking that `unstack` wiped.
  4. Verify every PR's `baseRefName` and diff size.
- `gh stack view --json` shows local tracking with cached PR states, not what GitHub holds.

## Inserting or reordering

There's no insert and no reorder. Stacks can only be listed, created, extended on top, and dissolved (REST:
`POST repos/{o}/{r}/stacks` with the PRs bottom to top as an unbroken base-to-head chain; `POST /stacks/{n}/add`;
`POST /stacks/{n}/unstack`). To insert:
1. Create the new PRs with `gh pr create --base <parent>`.
2. `gh stack unstack <n>`. Merged PRs stay in the old, now closed, stack, so the history survives. Only the open PRs are
   released.
3. Change the bases now. A stacked PR's base can't be changed while it's in a stack.
4. Verify the chain, then `POST /stacks` with the open PR numbers. The new stack gets a new number.

## Spikes and throwaway branches

- Base a spike on the stack top with a plain `git checkout -b`, never with `gh stack add`. Otherwise the next `submit`
  pushes it and opens a PR inside the real stack.
- If one got tracked anyway: local tracking is the JSON file `.git/gh-stack` (a `stacks[]` array, each with
  `branches[]`). Back it up, then delete only that branch's entry, and check with `gh stack view` from both branches.
- Example PRs for a spike are plain chained `gh pr create --draft`, never linked into the real stack.

## A PR stuck as "dirty"

GitHub sometimes stops recomputing one stacked PR's mergeability: its `refs/pull/<n>/merge` stays at an old head, and
every PR above it sits at UNKNOWN.
- First prove it isn't real: `gh api repos/{o}/{r}/compare/<base>...<head>` shows `behind_by: 0`, and
  `git merge-tree --write-tree` merges cleanly.
- A push to the PR's own head doesn't clear it. A push that moves its base branch does.

## Before syncing a stack onto its trunk

Build the trunk itself first. If the trunk is broken (for example after a merge into it), fix it with commits on the
trunk, then rebase the stack onto them.
