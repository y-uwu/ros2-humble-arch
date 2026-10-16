#!/usr/bin/env bash
# build.sh: build ros2-humble-arch on Arch Linux.
#
#   ./build.sh                         both stages: deps, then package
#   ./build.sh deps                    only the AUR dependency chain
#   ./build.sh package                 only ros2-humble-arch
#   ./build.sh --clean package         rebuild it from scratch (e.g. after a Python upgrade)
#   ./build.sh check                   check the installed package (also run after package)
#   ./build.sh -y ...                  don't stop to let you read the AUR recipes
#
# What each stage does, and nothing more:
#   deps    Clones each recipe in deps/aur.lock into deps/aur/<name>, checks out
#           the pinned commit, and applies deps/patches/<name>.patch if there is
#           one. Then it stops so you can read them, and builds and installs each
#           one that is missing or older than the recipe.
#   package makepkg -sif in this folder (about 3 hours with 16 GB of RAM;
#           needs ~60 GB free while it builds), then the check below
#   check   Lists every library or folder that the CMake files in /opt/ros/humble
#           point to but that isn't installed. Each one would make find_package
#           fail in your workspaces (PATCHES.md #16). Then checks that sourcing
#           ROS turns on the settings for course code (PATCHES.md #17).
#
# It never edits your shell config or sudoers. sudo asks for your password
# whenever makepkg installs something.
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
aur_dir=$repo/deps/aur
min_free_gb=60
assume_yes=0
clean=0

say() { printf '\e[1;34m==>\e[0m %s\n' "$*"; }
die() { printf '\e[1;31merror:\e[0m %s\n' "$*" >&2; exit 1; }

usage() { sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

preflight() {
    [[ -f /etc/arch-release ]] || die "this is for Arch Linux"
    (( EUID != 0 ))            || die "run as your normal user; makepkg refuses to run as root"
    [[ ${LANG:-} == *[Uu][Tt][Ff]*8* ]] \
        || die "set LANG to a UTF-8 locale first (e.g. LANG=en_US.UTF-8); the build checks for it"
    pacman -T base-devel git >/dev/null \
        || die "install the build tools first: sudo pacman -S --needed base-devel git"
}

pause() {
    (( assume_yes )) && return 0
    read -rp "Press Enter to build, or Ctrl-C to stop here. " \
        || die "no terminal to answer from; run again with -y to skip this pause"
}

# Clone (or reuse) one AUR recipe, put it at the pinned commit, apply our patch.
# deps/aur/ is scratch space: anything changed there by hand is reset.
fetch_recipe() {
    local name=$1 commit=$2 dir=$aur_dir/$1
    local patch=$repo/deps/patches/$1.patch
    if [[ ! -d $dir/.git ]]; then
        git clone -q "https://aur.archlinux.org/$name.git" "$dir"
    fi
    if ! git -C "$dir" cat-file -e "$commit^{commit}" 2>/dev/null; then
        git -C "$dir" fetch -q origin
    fi
    git -C "$dir" reset -q --hard "$commit" || die "$name: pinned commit $commit not found on the AUR"
    if [[ -f $patch ]]; then
        git -C "$dir" apply "$patch" || die "$name: $patch does not apply"
        say "$name: pinned to ${commit:0:12}, patched"
    else
        say "$name: pinned to ${commit:0:12}"
    fi
}

# The version pacman will report once the recipe is built: [epoch:]pkgver-pkgrel
recipe_version() {
    (cd "$aur_dir/$1" && makepkg --printsrcinfo) | awk -F' = ' '
        $1 == "\tepoch"  { e = $2 ":" }
        $1 == "\tpkgver" { v = $2 }
        $1 == "\tpkgrel" { r = $2 }
        END { print e v "-" r }'
}

stage_deps() {
    local name commit want have todo=()
    if pacman -Qq python-pytest-runner &>/dev/null; then
        die "python-pytest-runner is installed and breaks Python package builds (PATCHES.md #4).
       Remove it first:  sudo pacman -Rdd python-pytest-runner
       (-dd because the unpatched python-colcon-core and ros2-arch-deps still list it;
       this stage rebuilds both without it.)"
    fi
    mkdir -p "$aur_dir"
    while read -r name commit _; do
        [[ -z $name || $name == \#* ]] && continue
        fetch_recipe "$name" "$commit"
        want=$(recipe_version "$name")
        have=$(pacman -Q "$name" 2>/dev/null | cut -d' ' -f2) || true
        if [[ -n $have ]] && (( $(vercmp "$have" "$want") >= 0 )); then
            echo "    $have installed, nothing to do"
            continue
        fi
        echo "    will build $want${have:+ (installed: $have)}"
        todo+=("$name")
    done < "$repo/deps/aur.lock"

    if (( ${#todo[@]} == 0 )); then
        say "all AUR dependencies are up to date"
        return 0
    fi
    say "${#todo[@]} recipes to build, in $aur_dir"
    echo "    Read them before building. Patched ones show their change with: git -C $aur_dir/<name> diff"
    pause

    for name in "${todo[@]}"; do
        say "building $name"
        # BUILD_DEBIAN_PACKAGE: PATCHES.md #2.  --nocheck: PATCHES.md #1.
        (cd "$aur_dir/$name" && BUILD_DEBIAN_PACKAGE=1 makepkg -si --noconfirm --nocheck) \
            || die "$name failed to build. Fix it, then run ./build.sh deps again; finished ones are skipped."
    done
}

# BUILDDIR and PKGDEST keep the build tree (src/) and the finished package in this
# folder even if makepkg.conf points elsewhere: a tmpfs BUILDDIR can't hold the
# build. No --noconfirm: pacman asks before replacing an installed ros2-humble.
stage_package() {
    local free
    if (( clean )); then
        say "removing the previous build (src/ and pkg/)"
        rm -rf "$repo/src" "$repo/pkg"
    fi
    if [[ ! -d $repo/src ]]; then
        free=$(df -BG --output=avail "$repo" | tail -n 1 | tr -dc '0-9')
        (( free >= min_free_gb )) \
            || die "the build needs about ${min_free_gb} GB free in $repo (${free} GB free)"
    fi
    say "building ros2-humble-arch (about 3 hours with 16 GB of RAM; longer with less)"
    (cd "$repo" && BUILDDIR="$repo" PKGDEST="$repo" makepkg -sif) \
        || die "ros2-humble-arch did not build or install; see the output above and PATCHES.md.
       If it built and only the install was declined:  sudo pacman -U $(cd "$repo" && PKGDEST="$repo" makepkg --packagelist | head -n 1)"
    stage_check
}

# CMake refuses to load a package if a library its CMake files list is missing,
# so one missing library breaks every workspace that depends on it. Each CMake
# file says which install folder its paths start from (rviz's bundled OGRE, for
# one, lives in opt/rviz_ogre_vendor); the check works that out the same way
# CMake does. A missing include folder is only reported as a note: CMake only
# complains about it when something links that library, and one upstream package
# (rosbag2_storage_mcap) lists a folder it never installs, on Ubuntu too.
stage_check() {
    local root=/opt/ros/humble
    [[ -d $root ]] || die "$root does not exist; install the package first"
    say "checking the files the CMake files in $root point to"
    python3 -I - "$root" <<'PY' \
        || die "the files above are missing from $root; find_package fails for the packages that list them (PATCHES.md #16)"
import os, re, sys

root = sys.argv[1]
DEF_FIRST = 'get_filename_component(_IMPORT_PREFIX "${CMAKE_CURRENT_LIST_FILE}" PATH)'
DEF_UP = 'get_filename_component(_IMPORT_PREFIX "${_IMPORT_PREFIX}" PATH)'
DEF_ABS = re.compile(r'set\(_IMPORT_PREFIX "(/[^"]*)"\)')
REF = re.compile(r'\$\{_IMPORT_PREFIX\}(/[^";\s)]*)')
DIR_PROPS = ('INTERFACE_INCLUDE_DIRECTORIES', 'INTERFACE_SYSTEM_INCLUDE_DIRECTORIES')

prefixes = {}   # (dir, stem) -> prefix computed by that file
refs = []       # (file, kind, relative path)
for d, dirs, files in os.walk(root):
    for name in files:
        if not name.endswith('.cmake'):
            continue
        path = os.path.join(d, name)
        try:
            text = open(path, encoding='utf-8', errors='replace').read()
        except OSError:
            continue
        if '_IMPORT_PREFIX' not in text:
            continue
        stem = name[:-len('.cmake')]
        if DEF_FIRST in text:
            pre = d
            for _ in range(text.count(DEF_UP)):
                pre = os.path.dirname(pre)
            prefixes[(d, stem)] = pre
        else:
            m = DEF_ABS.search(text)
            if m:
                prefixes[(d, stem)] = m.group(1)
        for line in text.splitlines():
            for m in REF.finditer(line):
                kind = 'dir' if any(p in line for p in DIR_PROPS) else 'file'
                refs.append((path, kind, m.group(1)))

def prefix_for(path):
    d, name = os.path.split(path)
    stem = name[:-len('.cmake')]
    best = None
    for (pd, pstem), pre in prefixes.items():
        if pd == d and stem.startswith(pstem) and (best is None or len(pstem) > len(best[0])):
            best = (pstem, pre)
    if best is None:
        same_dir = {pre for (pd, _), pre in prefixes.items() if pd == d}
        if len(same_dir) == 1:
            return same_dir.pop()
        return None
    return best[1]

missing_files, missing_dirs, unknown = set(), set(), set()
for path, kind, rel in refs:
    pre = prefix_for(path)
    if pre is None:
        unknown.add(path)
        continue
    target = pre + rel
    if not os.path.exists(target):
        (missing_dirs if kind == 'dir' else missing_files).add((target, os.path.relpath(path, root)))

for target, src in sorted(missing_dirs):
    print(f"    note: include folder {target} does not exist (listed in {src})")
for path in sorted(unknown):
    print(f"    note: could not work out the install folder used by {path}")
for target, src in sorted(missing_files):
    print(f"    missing: {target} (listed in {src})")
print(f"checked {len(refs)} references in {len({r[0] for r in refs})} CMake files")
sys.exit(1 if missing_files else 0)
PY
    # Settings for course code come from the setup scripts (PATCHES.md #17).
    local want=$root/share/ros2_humble_arch/cmake/toolchain.cmake got
    got=$(env -i HOME="$HOME" bash -c ". $root/setup.bash >/dev/null 2>&1; printf %s \"\${CMAKE_TOOLCHAIN_FILE:-}\"")
    if [[ $got != "$want" ]]; then
        die "sourcing $root/setup.bash does not set CMAKE_TOOLCHAIN_FILE to $want (PATCHES.md #17)"
    fi
    if [[ -n ${CMAKE_TOOLCHAIN_FILE:-} && $CMAKE_TOOLCHAIN_FILE != "$want" ]]; then
        say "note: this shell sets CMAKE_TOOLCHAIN_FILE=$CMAKE_TOOLCHAIN_FILE, so the course-code settings are off here"
    fi
    local link=${COLCON_HOME:-$HOME/.colcon}/metadata/ros2-humble-arch.meta
    if [[ -L $link || -e $link ]]; then
        say "note: $link is from an earlier version and no longer used; colcon reports it missing. Remove it:"
        echo "    rm -f $link"
    fi
    say "check done: nothing missing"
}

stages=()
for arg in "$@"; do
    case $arg in
        -y|--yes)          assume_yes=1 ;;
        --clean)           clean=1 ;;
        deps|package|check) stages+=("$arg") ;;
        -h|--help)         usage; exit 0 ;;
        *)                 usage; die "unknown argument: $arg" ;;
    esac
done
(( ${#stages[@]} )) || stages=(deps package)

preflight
for stage in "${stages[@]}"; do
    "stage_$stage"
done
if [[ " ${stages[*]} " == *" package "* ]]; then
    say "done. Open a new shell and see \"After installing\" in README.md"
else
    say "done"
fi
