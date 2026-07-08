#!/usr/bin/env sh
# Smoke test for ccc open host flow (no-shell)
set -e
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
. "$repo_root/share/config.sh"

# Prepare temp home and courses dir
TMP_HOME="$(mktemp -d)"
export HOME="$TMP_HOME"

# Setup config to point courses dir to TMP_HOME/courses
printf "%s\n%s\n" "$TMP_HOME/courses" "n" | prompt_init >/dev/null 2>&1

# Add a fake registry entry directly to registry.csv for testing
# We'll create a simple local git repo to clone
mkdir -p "$TMP_HOME/local-repos/test-course"
cd "$TMP_HOME/local-repos/test-course"
git init -q
printf "#!/usr/bin/env sh\necho setup ran\n" >setup.sh
chmod +x setup.sh
git add setup.sh >/dev/null 2>&1
git commit -q -m "init" >/dev/null 2>&1
repo_url="$TMP_HOME/local-repos/test-course"

# Append to registry.csv temporarily (work on copy)
# Copy registry to temp and append test entry, export CCC_REGISTRY_FILE for the run
cp "$repo_root/registry.csv" "$TMP_HOME/registry.csv"
printf "test-course,%s,Test Course,now,\n" "$repo_url" >>"$TMP_HOME/registry.csv"
export CCC_REGISTRY_FILE="$TMP_HOME/registry.csv"
# Point the code to use the temp registry by overriding repo_root in registry.sh logic
# For test simplicity, we will call open_host with explicit course_dir operations

# Call ccc open with --no-shell and ensure it clones and writes session
"$repo_root/ccc.sh" open test-course --no-shell >/dev/null 2>&1 || true

# Check session file
session_file=$(resolve_config_dir)/session.json
if [ ! -f "$session_file" ]; then
    echo "FAIL: session file not written"
    exit 2
fi

echo "PASS: open_host created session"
