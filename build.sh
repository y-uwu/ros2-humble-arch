#!/usr/bin/env bash
# build.sh: build ros2-humble-arch on Arch Linux.
#
#   ./build.sh                         both stages: deps, then package
#   ./build.sh deps                    only the AUR dependency chain
#   ./build.sh package                 only ros2-humble-arch
#   ./build.sh --clean package         rebuild it from scratch (e.g. after a Python upgrade)
#   ./build.sh -y ...                  don't stop to let you read the AUR recipes
#
# What each stage does, and nothing more:
#   deps    Clones each recipe in deps/aur.lock into deps/aur/<name>, checks out
#           the pinned commit, and applies deps/patches/<name>.patch if there is
#           one. Then it stops so you can read them, and builds and installs each
#           one that is missing or older than the recipe.
#   package makepkg -sif in this folder (about 3 hours with 16 GB of RAM;
#           needs ~60 GB free while it builds)
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

usage() { sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

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
}

stages=()
for arg in "$@"; do
    case $arg in
        -y|--yes)          assume_yes=1 ;;
        --clean)           clean=1 ;;
        deps|package)      stages+=("$arg") ;;
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
