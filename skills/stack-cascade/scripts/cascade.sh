#!/bin/sh
# Cascades a change up a stack of branches, bottom to top, on a detached HEAD.
#   cascade.sh start  <run> <parent-old> <parent-new> <branch>...   branches bottom to top
#   cascade.sh resume <run>                                          after resolving a conflict and `git rebase --continue`
# Nothing is pushed and no branch is moved. Old heads are tagged <run>/<branch>-before, new heads <run>/<branch>-after,
# and push.txt in the run's folder lists "<branch> <old head> <new head>" for the push.
set -eu

die() { echo "STOP: $*" >&2; exit 1; }
usage() { sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

cmd=${1:-}
run=${2:-}
[ -n "$cmd" ] && [ -n "$run" ] || usage
remote=${REMOTE:-origin}
state="$(cd "$(git rev-parse --git-common-dir)" && pwd)/cascade/$run"

rebasing() { [ -d "$(git rev-parse --git-path rebase-merge)" ] || [ -d "$(git rev-parse --git-path rebase-apply)" ]; }

# Prints "<old> <new>" for the parent of branch $1: the run's parent for the lowest branch, else the branch below it.
parent_of() {
  prev=""
  prevold=""
  while read -r b h; do
    if [ "$b" = "$1" ]; then
      if [ -z "$prev" ]; then
        cat "$state/parent"
      else
        echo "$prevold $(awk -v b="$prev" '$1 == b { print $2 }' "$state/done")"
      fi
      return 0
    fi
    prev=$b
    prevold=$h
  done < "$state/heads"
}

old_of() { awk -v b="$1" '$1 == b { print $2 }' "$state/heads"; }

# Records the finished rebase of branch $1 at HEAD: tag, push line, commit count and range-diff summary.
record() {
  b=$1
  new=$(git rev-parse HEAD)
  old=$(old_of "$b")
  set -- $(parent_of "$b")
  pold=$1
  pnew=$2
  git tag "$run/$b-after" "$new"
  echo "$b $new" >> "$state/done"
  echo "$b $old $new" >> "$state/push.txt"
  rm -f "$state/current"
  before=$(git rev-list --count "$pold..$old")
  after=$(git rev-list --count "$pnew..$new")
  counts=$(git range-diff --no-color -s "$pold..$old" "$pnew..$new" \
    | awk '{ n[$3]++ } END { printf "= %d  ! %d  added %d  dropped %d", n["="], n["!"], n[">"], n["<"] }')
  line="$b: $(git rev-parse --short "$old") -> $(git rev-parse --short "$new")  commits $before -> $after  $counts"
  echo "$line" | tee -a "$state/summary.txt"
  if [ "$after" -lt "$before" ]; then
    echo "STOP: $b has fewer commits than before ($before -> $after). Check them with" >&2
    echo "  git range-diff $pold..$old $pnew..$new" >&2
    echo "If that's right (a commit was already in the parent), go on with: cascade.sh resume $run" >&2
    exit 3
  fi
}

case $cmd in
  start)
    [ $# -ge 5 ] || usage
    [ ! -e "$state" ] || die "run '$run' already exists ($state). Resume it, or pick a new name."
    rebasing && die "a rebase is in progress in this worktree"
    [ -z "$(git status --porcelain --untracked-files=no)" ] || die "this worktree has uncommitted changes"
    pold=$(git rev-parse --verify --quiet "$3^{commit}") || die "no commit $3"
    pnew=$(git rev-parse --verify --quiet "$4^{commit}") || die "no commit $4"
    shift 4
    for b in "$@"; do
      git rev-parse --verify --quiet "refs/heads/$b" > /dev/null || die "no branch $b"
      if git rev-parse --verify --quiet "refs/tags/$run/$b-before" > /dev/null; then die "tag $run/$b-before already exists"; fi
    done
    mkdir -p "$state"
    echo "$pold $pnew" > "$state/parent"
    : > "$state/done"
    : > "$state/push.txt"
    for b in "$@"; do
      h=$(git rev-parse "refs/heads/$b")
      echo "$b $h" >> "$state/heads"
      git tag "$run/$b-before" "$h"
      r=$(git rev-parse --verify --quiet "refs/remotes/$remote/$b" || true)
      if [ -n "$r" ] && [ "$r" != "$h" ]; then
        echo "WARNING: $b differs from $remote/$b; fetch and settle that before you push" >&2
      fi
    done
    echo "Run '$run': $(wc -l < "$state/heads" | tr -d ' ') branches, old heads tagged $run/<branch>-before, state in $state"
    ;;
  resume)
    [ -d "$state" ] || die "no run '$run'"
    rebasing && die "the rebase isn't finished: resolve, git add, then git rebase --continue"
    if [ -f "$state/current" ]; then
      record "$(cat "$state/current")"
    fi
    ;;
  *)
    usage
    ;;
esac

while read -r b old; do
  if awk -v b="$b" '$1 == b { found = 1 } END { exit !found }' "$state/done"; then continue; fi
  set -- $(parent_of "$b")
  pold=$1
  pnew=$2
  git merge-base --is-ancestor "$pold" "$old" \
    || die "$b doesn't contain its parent's old head $(git rev-parse --short "$pold"): wrong parent or order"
  echo "$b" > "$state/current"
  git checkout -q --detach "$old"
  if ! git rebase -q --onto "$pnew" "$pold"; then
    echo "STOP: conflict in $b. Resolve it (judgement calls go to the branch's owner), git add, git rebase --continue," >&2
    echo "then: cascade.sh resume $run" >&2
    exit 4
  fi
  record "$b"
done < "$state/heads"

echo
echo "Done. New heads are tagged $run/<branch>-after; HEAD is detached at the top. Nothing is pushed."
echo "Summary: $state/summary.txt"
echo "Push list: $state/push.txt"
echo "After the checks and the user's go, fetch, then push all branches at once with leases:"
printf '  git push --atomic %s' "$remote"
awk '{ printf " \\\n    --force-with-lease=%s:%s %s:refs/heads/%s", $1, $2, $3, $1 }' "$state/push.txt"
echo
