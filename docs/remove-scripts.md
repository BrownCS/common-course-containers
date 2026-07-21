Tuese are the commands that ccc cleanup should run, but if anything isn't working
and seems like it should run these and try again

podman stop default 2>/dev/null || true
podman rm -f default 2>/dev/null || true
podman image rm -f ccc 2>/dev/null || true
rm -f ".ccc-image-buildstamp-ccc" 2>/dev/null || true
rm -f ~/.config/ccc/default-container-courses.txt 2>/dev/null || true