#!/usr/bin/env bash
########################################################################################################################
# GIT
# Collection of git shortcuts.
########################################################################################################################

# Executes the given command in root and all submodules.
# $*: Git command.
function sc_git() {
    pushd "$_ST_HOME" &>/dev/null || exit 1
    sc_heading 1 root
    git $*
    git submodule foreach --recursive "sc_heading 1 \$name && git $*"
    popd &>/dev/null || exit 1
}
export -f sc_git

# Updates the submodules in root to point to HEAD and pushes root.
function sc_git_release() {
    pushd "$_ST_HOME" &>/dev/null || exit 1
    git submodule update --recursive --remote
    git submodule foreach --recursive \
        'git checkout $(git config -f $toplevel/.gitmodules submodule.$name.branch || echo dev)'
    git commit -am 'Release;'
    git push
    popd &>/dev/null || exit 1
}
export -f sc_git_release
