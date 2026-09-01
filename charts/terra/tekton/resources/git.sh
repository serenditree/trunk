#!/usr/bin/env ash
date +%s | tr -d '\n' > "$(results.start.path)"

mkdir -pv "$(params.subdirectory)"
cd "$(params.subdirectory)" || exit 1

if [[ -d .git ]] && [[ -n "$(params.clone)" ]]; then
  echo "Cleaning repository..."
  rm -rf .
fi

if [[ ! -d .git ]]; then
  git clone "$(params.url)" .
else
  git fetch --all
fi

if git show-ref --verify --quiet "refs/remotes/origin/$(params.revision)"; then
  git checkout -B "$(params.revision)" "origin/$(params.revision)"
else
  git checkout "$(params.revision)"
fi

git log -1 --pretty="%h" | tr -d '\n' | tee "$(results.sha.path)"
