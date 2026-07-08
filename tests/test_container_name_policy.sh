#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
export REGISTRY_FILE="$repo_root/registry.csv"

# shellcheck disable=SC1091
source "$repo_root/lib/utils.sh"
# shellcheck disable=SC1091
source "$repo_root/lib/courses.sh"
# shellcheck disable=SC1091
source "$repo_root/lib/runtime.sh"

shared_container="$(get_container_name csci-0300-demo)"
specific_container="$(get_container_name csci-1680-demo2)"

if [ "$shared_container" != "default" ]; then
  echo "FAIL: default courses should reuse the shared default container" >&2
  echo "got: $shared_container" >&2
  exit 1
fi

if [ "$specific_container" != "ccc-csci-1680-demo2" ]; then
  echo "FAIL: course-specific courses should get a dedicated container" >&2
  echo "got: $specific_container" >&2
  exit 1
fi

echo "PASS: container naming follows the image_mode policy"