#!/bin/bash
# Lay out the paths the ghc610 bootstrap script checks, run that script, then
# rewrite the installed tree so package.conf uses $topdir. The C compiler
# is the bare name host-gcc. mockbuild cannot create %{_libdir}/ghc-6.10.4.
set -euo pipefail
ROOT=${1:?usage: ghc610-build.sh ROOT LIBDIR}
LIBDIR=${2:?}
export STAGE="$ROOT"
export GMP_PREFIX="$LIBDIR/gmp612"
export TMPDIR="$ROOT/tmp"
mkdir -p "$TMPDIR" "$ROOT/build/sources" "$ROOT/build/ref-ghc-bootstrap/common/test" \
	"$ROOT/build/ghc66-work/ghc66-prefix/bin"
unset CFLAGS CXXFLAGS LDFLAGS CPPFLAGS RPM_OPT_FLAGS RPM_LD_FLAGS || true
ulimit -s unlimited 2>/dev/null || true

cp -a "$ROOT/incoming/ghc-6.10.4-src.tar.bz2" "$ROOT/build/sources/ghc-6.10.4-src.tar.bz2"
cp -a "$ROOT/incoming/regen-parsers.sh" "$ROOT/build/ref-ghc-bootstrap/common/regen-parsers.sh"
cp -a "$ROOT/incoming/cmp-regenerated.sh" "$ROOT/build/ref-ghc-bootstrap/common/cmp-regenerated.sh"
cp -a "$ROOT/incoming/T3.hs" "$ROOT/build/ref-ghc-bootstrap/common/test/T3.hs"
cp -a "$ROOT/incoming/T3.out" "$ROOT/build/ref-ghc-bootstrap/common/test/T3.out"
cp -a "$ROOT/incoming/GmpZero.hs" "$ROOT/build/ref-ghc-bootstrap/common/test/GmpZero.hs"
chmod 755 "$ROOT/build/ref-ghc-bootstrap/common/regen-parsers.sh" \
	"$ROOT/build/ref-ghc-bootstrap/common/cmp-regenerated.sh"

cat > "$ROOT/build/ghc66-work/ghc66-prefix/bin/ghc" << EOF
#!/bin/sh
exec /usr/bin/ghc66 "\$@"
EOF
cat > "$ROOT/build/ghc66-work/ghc66-prefix/bin/ghc-pkg" << EOF
#!/bin/sh
exec /usr/bin/ghc-pkg66 "\$@"
EOF
# libraries/hpc has a .hsc file, and the 6.10 build runs that Cabal
# configure before it has built utils/hsc2hs. ghc66 ships hsc2hs-bin in
# the libdir, not on PATH. Cabal also rewrites package.conf's $topdir
# from this wrapper's directory, so the -I/-L it passes miss HsFFI.h
# and libHSbase_cbits. This wrapper adds the real libdir.
cat > "$ROOT/build/ghc66-work/ghc66-prefix/bin/hsc2hs" << 'EOF'
#!/bin/sh
ghcbin=$(command -v ghc66) || {
	echo "hsc2hs: ghc66 is not on PATH" >&2
	exit 1
}
here=$(CDPATH= cd -- "$(dirname "$ghcbin")" && pwd)
root=$(dirname "$here")
if [ -x "$root/lib64/ghc-6.6/hsc2hs-bin" ]; then
	top="$root/lib64/ghc-6.6"
elif [ -x "$root/lib/ghc-6.6/hsc2hs-bin" ]; then
	top="$root/lib/ghc-6.6"
else
	echo "hsc2hs: no hsc2hs-bin next to $ghcbin" >&2
	exit 1
fi
extra="--cc=$top/bin/host-gcc"
tflag="--template=$top/template-hsc.h"
for arg do
	case "$arg" in
	-c*|--cc=*) extra= ;;
	-t*|--template=*) tflag= ;;
	--) break ;;
	esac
done
exec "$top/hsc2hs-bin" $tflag $extra --cflag="-I$top/include" --lflag="-L$top" "$@"
EOF
chmod 755 "$ROOT/build/ghc66-work/ghc66-prefix/bin/ghc" \
	"$ROOT/build/ghc66-work/ghc66-prefix/bin/ghc-pkg" \
	"$ROOT/build/ghc66-work/ghc66-prefix/bin/hsc2hs"
# Cabal 1.6 rewrites $topdir from the directory that contains bin/ghc.
# The stage1 compiler's own hsc2hs does not use the wrapper above, so
# its gcc line needs $topdir/include/HsFFI.h and $topdir/libHSbase_cbits.a.
# Mirror the installed libdir and keep the shims in bin/.
ghcbin=$(command -v ghc66) || {
	echo "ghc610: ghc66 is not on PATH" >&2
	exit 1
}
here=$(CDPATH= cd -- "$(dirname "$ghcbin")" && pwd)
root=$(dirname "$here")
if [ -d "$root/lib64/ghc-6.6" ]; then
	reallib="$root/lib64/ghc-6.6"
elif [ -d "$root/lib/ghc-6.6" ]; then
	reallib="$root/lib/ghc-6.6"
else
	echo "ghc610: no ghc-6.6 libdir next to $ghcbin" >&2
	exit 1
fi
boot="$ROOT/build/ghc66-work/ghc66-prefix"
for item in "$reallib"/*; do
	name=$(basename "$item")
	if [ "$name" = bin ]; then
		for b in "$item"/*; do
			bn=$(basename "$b")
			if [ ! -e "$boot/bin/$bn" ]; then
				ln -sfn "$b" "$boot/bin/$bn"
			fi
		done
	elif [ ! -e "$boot/$name" ]; then
		ln -sfn "$item" "$boot/$name"
	fi
done
test -f "$boot/include/HsFFI.h"
test -f "$boot/libHSbase_cbits.a"
mkdir -p "$ROOT/build/happy-1.16-prefix/bin"
ln -sfn /usr/bin/happy116 "$ROOT/build/happy-1.16-prefix/bin/happy"
mkdir -p "$ROOT/build/alex-2.1.0-prefix/bin"
ln -sfn /usr/bin/alex210 "$ROOT/build/alex-2.1.0-prefix/bin/alex"

bash "$ROOT/incoming/bootstrap.sh"

python - "$ROOT" "6.10.4" "$ROOT/dest" "$ROOT/build/ghc610-work/bin/host-gcc" "$ROOT/build/ghc610-work/ghc610-prefix" "ghc610" << 'PY'
import os, shutil, sys
root, ver, dest, host_gcc, prefix, pkg = sys.argv[1:]
lib = None
rel = None
for cand in ("lib/ghc-%s" % ver, "lib64/ghc-%s" % ver):
    if os.path.isdir(os.path.join(prefix, cand)):
        lib = os.path.join(prefix, cand)
        rel = cand
        break
if lib is None:
    sys.exit("no lib/ghc-%s under %s" % (ver, prefix))
os.makedirs(os.path.join(lib, "bin"), exist_ok=True)
shutil.copy(host_gcc, os.path.join(lib, "bin", "host-gcc"))
os.chmod(os.path.join(lib, "bin", "host-gcc"), 0o755)
work_gcc = os.path.join(root, "build", pkg + "-work", "bin", "gcc")
work_host = os.path.join(root, "build", pkg + "-work", "bin", "host-gcc")
build_work = os.path.join(root, "build", pkg + "-work")
for dirpath, dirnames, filenames in os.walk(lib):
    for name in filenames:
        path = os.path.join(dirpath, name)
        if name == "package.cache":
            os.remove(path)
            continue
        if not (name.endswith(".conf") or name in ("package.conf", "settings") or name.endswith(".hs") or name.endswith(".sh")):
            continue
        try:
            text = open(path, encoding="utf-8", errors="surrogateescape").read()
        except IsADirectoryError:
            continue
        if lib not in text and prefix not in text and work_gcc not in text and work_host not in text:
            continue
        # Library dirs become $topdir. The driver records host-gcc there.
        # Haddock and data-dir entries live under prefix/share; point those
        # at /usr/share. Compiling does not open them.
        text = text.replace(work_host, "$topdir/bin/host-gcc")
        text = text.replace(work_gcc, "$topdir/bin/host-gcc")
        text = text.replace(lib, "$topdir")
        text = text.replace(prefix, "/usr")
        open(path, "w", encoding="utf-8", errors="surrogateescape").write(text)
for dirpath, dirnames, filenames in os.walk(lib):
    if "package.cache" in filenames:
        os.remove(os.path.join(dirpath, "package.cache"))
bad = []
for dirpath, dirnames, filenames in os.walk(lib):
    for name in filenames:
        if not (name.endswith(".conf") or name == "package.conf" or name == "settings"):
            continue
        path = os.path.join(dirpath, name)
        text = open(path, encoding="utf-8", errors="surrogateescape").read()
        if prefix in text or build_work in text or "/media/space" in text:
            bad.append(path)
if bad:
    sys.exit("build prefix still in: %s" % " ".join(bad))
if os.path.isdir(dest):
    shutil.rmtree(dest)
os.makedirs(os.path.join(dest, os.path.dirname(rel)))
shutil.copytree(lib, os.path.join(dest, rel), symlinks=True)
print("RELOCATED", os.path.join(dest, rel))
PY
