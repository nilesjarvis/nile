#!/bin/bash
set -Eeuo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
reference_root="$repository_root/.reference/android"
expected_commit="bd5451da891f2d886b9bc35f8ea67d6920df1d98"
expected_tree="3b954e5844f05276d34aaee34a7d3f69169ef9f5"
expected_hermes="7441e3395f9db0d8319f43bfe07dfb222777101e"

if [[ ! -d "$reference_root/.git" ]]; then
    printf 'Missing Android oracle at %s\n' "$reference_root" >&2
    printf 'Clone nilesjarvis/nile there and detach it at %s\n' "$expected_commit" >&2
    exit 2
fi

actual_commit="$(git -C "$reference_root" rev-parse HEAD)"
actual_tree="$(git -C "$reference_root" rev-parse HEAD^{tree})"
actual_hermes="$(tr -d '\r\n' < "$reference_root/scripts/test-lab/hermes.ref")"
worktree_status="$(git -C "$reference_root" status --porcelain)"

if [[ "$actual_commit" != "$expected_commit" ]]; then
    printf 'Android oracle commit mismatch: expected %s, found %s\n' \
        "$expected_commit" "$actual_commit" >&2
    exit 1
fi
if [[ "$actual_tree" != "$expected_tree" ]]; then
    printf 'Android oracle tree mismatch: expected %s, found %s\n' \
        "$expected_tree" "$actual_tree" >&2
    exit 1
fi
if [[ "$actual_hermes" != "$expected_hermes" ]]; then
    printf 'Hermes pin mismatch: expected %s, found %s\n' \
        "$expected_hermes" "$actual_hermes" >&2
    exit 1
fi
if [[ -n "$worktree_status" ]]; then
    printf 'Android oracle has local modifications; it must remain read-only:\n%s\n' \
        "$worktree_status" >&2
    exit 1
fi

printf 'Android oracle verified\n'
printf 'commit=%s\n' "$actual_commit"
printf 'tree=%s\n' "$actual_tree"
printf 'hermes=%s\n' "$actual_hermes"
