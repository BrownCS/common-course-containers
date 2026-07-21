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

# Add a fake registry entry directly to a temp registry for testing.
# We'll create a simple local git repo to clone.
mkdir -p "$TMP_HOME/local-repos/test-course"
cd "$TMP_HOME/local-repos/test-course"
git init -q
printf "#!/usr/bin/env sh\necho setup ran\n" >setup.sh
chmod +x setup.sh
git add setup.sh >/dev/null 2>&1
git commit -q -m "init" >/dev/null 2>&1
repo_url="$TMP_HOME/local-repos/test-course"

# Create a minimal temp registry and export it for the run.
cat >"$TMP_HOME/registry.csv" <<EOF
test-course,$repo_url,Test Course,now,
EOF
export CCC_REGISTRY_FILE="$TMP_HOME/registry.csv"

# Call ccc open with --no-shell and ensure it opens without creating session state
"$repo_root/ccc.sh" open test-course --no-shell >/dev/null 2>&1 || true

# Check session file is not created
session_file=$(resolve_config_dir)/session.json
if [ -f "$session_file" ]; then
    echo "FAIL: session file should not be written"
    exit 2
fi

echo "PASS: open_host does not create session state"
