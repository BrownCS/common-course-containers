#!/usr/bin/env sh
set -eu

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
TMP_HOME="$(mktemp -d)"
TMP_BIN="$(mktemp -d)"
TMP_STATE="$(mktemp -d)"
TMP_LOG="$TMP_HOME/installer.log"
cleanup() {
  rm -rf "$TMP_HOME" "$TMP_BIN" "$TMP_STATE"
}
trap cleanup EXIT HUP INT TERM

cat >"$TMP_BIN/dpkg-query" <<'EOF'
#!/usr/bin/env sh
state_file="${TMP_STATE_DIR:?}/installed.txt"
for pkg in "$@"; do
  :
done
if [ -f "$state_file" ] && grep -qx "$pkg" "$state_file"; then
  printf 'install ok installed\n'
  exit 0
fi
case "$pkg" in
  installed-pkg)
    printf 'install ok installed\n'
    exit 0
    ;;
esac
exit 1
EOF

cat >"$TMP_BIN/apt-get" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$*" >>"${TMP_LOG_FILE:?}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    update)
      exit 0
      ;;
    install)
      shift
      while [ "$#" -gt 0 ]; do
        case "$1" in
          -y|--no-install-recommends|-o)
            if [ "$1" = "-o" ]; then
              shift 2
            else
              shift
            fi
            ;;
          *)
            printf '%s\n' "$1" >>"${TMP_STATE_DIR:?}/installed.txt"
            shift
            ;;
        esac
      done
      exit 0
      ;;
    -o)
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
exit 0
EOF

cat >"$TMP_BIN/dpkg" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$*" >>"${TMP_LOG_FILE:?}"
exit 0
EOF

cat >"$TMP_BIN/sudo" <<'EOF'
#!/usr/bin/env sh
exec "$@"
EOF

chmod +x "$TMP_BIN/dpkg-query" "$TMP_BIN/apt-get" "$TMP_BIN/dpkg"
chmod +x "$TMP_BIN/sudo"

export PATH="$TMP_BIN:$PATH"
export TMP_LOG_FILE="$TMP_LOG"
export TMP_STATE_DIR="$TMP_STATE"
export HOME="$TMP_HOME"

course_dir="$TMP_HOME/course"
mkdir -p "$course_dir/dev-specs/setup" "$course_dir/dev-specs/env"
cat >"$course_dir/dev-specs/setup/packages.txt" <<'EOF'
installed-pkg
missing-pkg
EOF
cat >"$course_dir/dev-specs/setup/links.txt" <<'EOF'
/bin/echo -> echo-copy
EOF
cat >"$course_dir/dev-specs/setup/env.txt" <<'EOF'
FOO=bar
EOF

sh "$repo_root/share/course_installer.sh" "$course_dir" >/dev/null 2>&1
sh "$repo_root/share/course_installer.sh" "$course_dir" >/dev/null 2>&1

if ! grep -q 'missing-pkg' "$TMP_LOG"; then
  echo "FAIL: installer did not install the missing package" >&2
  exit 2
fi

if grep -q 'installed-pkg' "$TMP_LOG"; then
  echo "FAIL: installer tried to reinstall an already installed package" >&2
  exit 2
fi

if [ ! -f "$course_dir/dev-specs/env/course.env" ] || ! grep -q 'export FOO="bar"' "$course_dir/dev-specs/env/course.env"; then
  echo "FAIL: installer did not regenerate the env file" >&2
  exit 2
fi

if [ ! -L "$course_dir/dev-specs/bin/echo-copy" ]; then
  echo "FAIL: installer did not refresh the requested symlink" >&2
  exit 2
fi

echo "PASS: installer checks packages individually and always refreshes links/env"