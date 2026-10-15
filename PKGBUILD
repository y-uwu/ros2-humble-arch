# Maintainer: yuwu
#
# ros2-humble-arch: ROS 2 Humble for Arch Linux in one package. It contains
# everything in ROS 2's ros2.repos release manifest (what the AUR ros2-humble
# builds: rclcpp/rclpy, tf2, rviz2, rqt, launch, rosbag2, ...) plus the
# repositories in extra.repos: MoveIt 2, ros2_control, ros2_controllers, xacro,
# joint_state_publisher and their dependencies. Everything is built against
# Eigen 3.4.0, the version Ubuntu 22.04 ships, and installed with it into
# /opt/ros/humble.
#
# Derived from the AUR ros2-humble recipe at commit 203d02b6e3f2 (2026.02.20).
# Every change from that recipe is listed in PATCHES.md. Its credits:
# Contributor: Mohammad Mostafa Farzan <m2_farzan@yahoo.com>
# Contributor: mjbogusz <mjbogusz+github@gmail.com>
# Contributor: yuanyuyuan <az6980522@gmail.com>
# Contributor: Rémy B. (github.com/KirrimK)
# Contributor: Renato Caldas (github.com/rmsc)
# Contributor: goekce (github.com/goekce)
# Contributor: David Castellon (github.com/bobosito000)
# Contributor: Yannic Wehner <yannic.wehner@gmail.com> (github.com/ElCap1tan)
# Contributor: Kino <github.com/cybaol>
# Contributor: Zijian <github.com/zijian-x>
# Contributor: Jingbei Li <github.com/petronny>
# Contributor: Levi Tempfli <github.com/levtempfli>
# Acknowledgment: the AUR recipe is hugely based on the `ros2-arch-deps` AUR
# package, maintained by T. Borgert.

pkgname=ros2-humble-arch
pkgver=2026.02.20
pkgrel=2
_eigen_ver=3.4.0
pkgdesc="ROS 2 Humble with MoveIt 2, ros2_control and xacro, built against Eigen 3.4.0 to match Ubuntu 22.04"
url="https://docs.ros.org/en/humble/"
arch=('x86_64')
# Main licenses only; each repository's license text is in /usr/share/licenses/ros2-humble-arch.
license=('Apache-2.0' 'BSD-3-Clause' 'MPL-2.0')
depends=(
    'ros2-arch-deps'
    'console-bridge'   # AUR. Without it, console_bridge_vendor builds its bundled copy, which fails on CMake 4
    'python-psutil'    # ros2 doctor
    'qt6-base'
    'nvidia-cg-toolkit'
    'assimp'
    'gmock'
    # for the repositories in extra.repos (MoveIt, ros2_control, ...)
    'boost'            # headers too: packages built against MoveIt need them
    'bullet'
    'elfutils'         # libdw, for backward_ros
    'fmt'
    'libcap'           # realtime_tools
    'python-graphviz'  # ros2 control view_controller_chains
    'python-jinja'     # generate_parameter_library
    'python-lxml'
    'python-rospkg'    # AUR (built in build.sh's deps stage); rqt_joint_trajectory_controller
    'python-typeguard' # generate_parameter_library
    'python-yaml'
    'qhull'
    'tl-expected'
)
optdepends=(
    'python-matplotlib: rqt_plot'
    'python-pyqtgraph: rqt_plot'
)
makedepends=('cmake' 'git')
provides=("ros2-humble=${pkgver}" 'ros2-humble-base')
conflicts=('ros2-humble' 'ros2-humble-base' 'ros2-humble-debug'
           'ros2-humble-core' 'ros2-humble-extras' 'ros2-humble-eigen3')  # earlier versions of this repository
source=(
    "ros2::git+https://github.com/ros2/ros2#tag=release-humble-${pkgver//.}"
    "eigen-${_eigen_ver}.tar.gz::https://gitlab.com/libeigen/eigen/-/archive/${_eigen_ver}/eigen-${_eigen_ver}.tar.gz"
    'extra.repos'
)
sha256sums=('69c4e09effda8125d1a4ce3edaafc3a40b00fb7a2245bc0586d30c81aa701d5f'
            '8586084f71f9bde545ee7fa6d00288b264a2b7ac3607b974e54d13e7162c1c72'
            'cc10ef6d96324efa8fea6469d128f291b3df7b65a1f3966474f54ef03038e5e6')
install=ros2-humble-arch.install
# makepkg's default "debug" option would also produce a -debug package many times
# the size of this one; it is rarely used, so skip it. LTO (also a makepkg
# default) makes MoveIt's link steps use several GB each, and ROS isn't tested
# with it upstream, so it is off too (PATCHES.md #14). "staticlibs" keeps the
# static libraries makepkg would otherwise delete: octomap's CMake files list
# them, and CMake refuses to load a package whose listed files are missing
# (PATCHES.md #16).
options=('!debug' '!lto' 'staticlibs')

_ros_root=/opt/ros/humble
# Eigen 3.4.0 is installed here during the build. It sits inside the Eigen source
# folder, which carries a COLCON_IGNORE so colcon never treats Eigen as a ROS package.
_eigen_stage=eigen-${_eigen_ver}/stage

# Not built:
#  - qt_gui_cpp, rqt_gui_cpp: as in the AUR recipe (C++ rqt plugins)
#  - rosidl_typesupport_introspection_tests: PATCHES.md #7
#  - the parts of the MoveIt repository the course stack does not use, which are
#    also the ones that do not build on current Arch (PATCHES.md #12)
#  - packages in these repositories that Humble never released (examples and
#    unfinished work), so Ubuntu users never had them either
_ignore=(
    qt_gui_cpp rqt_gui_cpp rosidl_typesupport_introspection_tests
    moveit moveit_ros moveit_runtime moveit_plugins
    moveit_ros_perception moveit_ros_benchmarks moveit_ros_control_interface
    moveit_py moveit_hybrid_planning moveit_chomp_optimizer_adapter
    pilz_industrial_motion_planner_testutils
    moveit_planners_trajopt moveit_setup_simulation joint_limits_interface
    generate_parameter_library_example generate_parameter_library_example_external
    generate_parameter_module_example cmake_generate_parameter_module_example
)

prepare() {
    # Check locale according to
    # https://docs.ros.org/en/humble/Installation/Alternatives/Ubuntu-Development-Setup.html#set-locale
    if ! locale | grep LANG | grep 'UTF-8\|utf8' > /dev/null; then
        echo 'Your locale must support UTF-8. See ' \
             'https://wiki.archlinux.org/index.php/locale and ' \
             'https://docs.ros.org/en/humble/Installation/Alternatives/Ubuntu-Development-Setup.html#set-locale'
        exit 1
    fi

    touch "$srcdir/eigen-${_eigen_ver}/COLCON_IGNORE"

    # Clone the repos
    mkdir -p "$srcdir/ros2/src"
    vcs import "$srcdir/ros2/src" < "$srcdir/ros2/ros2.repos"
    vcs import --shallow "$srcdir/ros2/src" < "$srcdir/extra.repos"

    cd "$srcdir/ros2/src/eProsima/Fast-DDS"
    git submodule update --init thirdparty/asio

    # pybind11_vendor: Use jazzy branch to make compatible with Python 3.11 and later.
    git -C "$srcdir/ros2/src/ros2/pybind11_vendor" checkout 3.1.3

    # octomap (PATCHES.md #9): its top-level CMakeLists.txt builds the whole
    # repository as one project, which hides the octomap package from colcon.
    # Only octomap itself is needed; octovis needs QGLViewer, which Arch lacks.
    local octo=$srcdir/ros2/src/extra/octomap
    rm -f "$octo/CMakeLists.txt"
    touch "$octo/octovis/COLCON_IGNORE" "$octo/dynamicEDT3D/COLCON_IGNORE"
    # (PATCHES.md #10) -Werror turns GCC 16's new C++20 warnings into errors.
    # Only edit once, so a resumed build doesn't see a changed file and reconfigure.
    local cs=$octo/octomap/CMakeModules/CompilerSettings.cmake
    if grep -q ' -Werror' "$cs"; then
        sed -i 's/ -Werror//' "$cs"
    fi

    # (PATCHES.md #15) A few packages include Eigen as <eigen3/Eigen/...>. The
    # compiler finds that path in /usr/include, which is Arch's Eigen 5, while
    # their other Eigen includes find Eigen 3.4.0, and the mix doesn't compile.
    # Drop the eigen3/ prefix so every include finds Eigen 3.4.0. Files already
    # changed no longer match, so a resumed build doesn't recompile them.
    local f
    while IFS= read -r -d '' f; do
        sed -i -E 's@(#[[:space:]]*include[[:space:]]*[<"])eigen3/@\1@' "$f"
        printf 'Eigen include fixed: %s\n' "${f#"$srcdir"/ros2/src/}"
    done < <(grep -rlIZE --exclude-dir=.git \
                 '#[[:space:]]*include[[:space:]]*[<"]eigen3/' "$srcdir/ros2/src" || true)
}

build() {
    _clean_ros_env

    # Parallelism sized to RAM (PATCHES.md #14): one package at a time, and about
    # one compiler job per 2 GB, since MoveIt's larger files need 1-2 GB each.
    local mem_gb jobs
    mem_gb=$(( $(grep -Po 'MemTotal:\s+\K\d+' /proc/meminfo) / 1048576 ))
    jobs=$(( mem_gb / 2 ))
    (( jobs > $(nproc) )) && jobs=$(nproc)
    (( jobs < 1 )) && jobs=1
    export MAKEFLAGS="-j$jobs"
    export COLCON_EXTRA_ARGS="${COLCON_EXTRA_ARGS:-} --executor sequential"
    printf "\nBuilding one package at a time with %s compiler jobs (%s GB of RAM).\n\n" "$jobs" "$mem_gb"

    ## For people with the old version of makepkg.conf
    unset CPPFLAGS
    ## For people with the new version of makepkg.conf
    CFLAGS=$(sed "s/-Wp,-D_FORTIFY_SOURCE=[23]\s//g" <(echo $CFLAGS))
    CXXFLAGS=$(sed "s/-Wp,-D_FORTIFY_SOURCE=[23]\s//g" <(echo $CXXFLAGS))
    ## Fix missing cstdint headers in many packages
    CXXFLAGS+=" --include=cstdint"
    ## Eigen's assert messages compile its header paths into the libraries. Record
    ## them as their final location, not the staging folder used below.
    CFLAGS+=" -ffile-prefix-map=$srcdir/$_eigen_stage=$_ros_root"
    CXXFLAGS+=" -ffile-prefix-map=$srcdir/$_eigen_stage=$_ros_root"

    export CMAKE_POLICY_VERSION_MINIMUM=3.5

    # Eigen 3.4.0: headers and CMake config only (it is header-only, nothing compiles).
    # Putting it first on CMAKE_PREFIX_PATH makes every find_package(Eigen3) in the
    # ROS build pick it over the system Eigen 5 in /usr.
    cmake -B "eigen-${_eigen_ver}/build" -S "eigen-${_eigen_ver}" -Wno-dev \
        -DCMAKE_INSTALL_PREFIX="$srcdir/$_eigen_stage" \
        -DBUILD_TESTING=OFF \
        -DEIGEN_BUILD_DOC=OFF \
        -DEIGEN_BUILD_PKGCONFIG=OFF
    cmake --install "eigen-${_eigen_ver}/build"
    export CMAKE_PREFIX_PATH="$srcdir/$_eigen_stage"

    # Build
    ## To resolve the io_service removal in Asio 1.33.0, build FastRTPS against third-party Asio.
    colcon build --merge-install ${COLCON_EXTRA_ARGS} --packages-up-to fastrtps --cmake-args " -DTHIRDPARTY_Asio=FORCE" " -DBUILD_TESTING=OFF" " -Wno-dev"
    ## Libraries Ubuntu ships as system packages, built first and in this order with
    ## the options Ubuntu uses (PATCHES.md #11). The main build below skips them so
    ## its common options never reconfigure them.
    ## Every CMake flag is its own argument; colcon passes a quoted string with
    ## several flags to CMake as one argument (PATCHES.md #13).
    colcon build --merge-install --packages-select libccd \
        --cmake-args " -DBUILD_TESTING=OFF" " -DENABLE_DOUBLE_PRECISION=ON" " -Wno-dev"
    colcon build --merge-install --packages-select octomap \
        --cmake-args " -DBUILD_TESTING=OFF" " -DCMAKE_CXX_STANDARD=17" " -Wno-dev"
    colcon build --merge-install --packages-select fcl \
        --cmake-args " -DBUILD_TESTING=OFF" " -DFCL_WITH_OCTOMAP=ON" " -Wno-dev"
    colcon build --merge-install --packages-select ompl \
        --cmake-args " -DBUILD_TESTING=OFF" " -DOMPL_BUILD_TESTS=OFF" " -DOMPL_BUILD_DEMOS=OFF" \
                     " -DOMPL_BUILD_PYBINDINGS=OFF" " -DOMPL_BUILD_PYTESTS=OFF" " -DOMPL_REGISTRATION=OFF" " -Wno-dev"
    ## Build all packages.
    colcon build --merge-install ${COLCON_EXTRA_ARGS} --cmake-args " -DBUILD_TESTING=OFF" " -Wno-dev" \
        --packages-skip libccd octomap fcl ompl --packages-ignore "${_ignore[@]}"
}

package() {
    local root=$pkgdir$_ros_root stage=$srcdir/$_eigen_stage f
    mkdir -p "$root"
    cp -r "$srcdir"/install/* "$root"/
    cp -a "$stage"/. "$root"/

    # Installed text files can contain two build-time paths: the Eigen staging
    # folder (packages that record Eigen's include path in their CMake or
    # pkg-config files) and colcon's install folder (the plain-sh setup scripts).
    # Point both at /opt/ros/humble.
    while IFS= read -r -d '' f; do
        sed -i -e "s|${stage//./\\.}|${_ros_root}|g" \
               -e "s|${srcdir//./\\.}/install|${_ros_root}|g" "$f"
        echo "  build path updated: ${f#"$pkgdir"}"
    done < <(grep -rlIZF -e "$stage" -e "$srcdir/install" "$pkgdir")
    # Binaries can't be edited safely. The -ffile-prefix-map flag in build() should
    # leave none; anything listed here is at most a wrong path in an error message.
    if grep -rlF -- "$stage" "$pkgdir"; then
        printf 'WARNING: the binary files above still mention the Eigen staging folder.\n' >&2
    fi

    # Anything that found the system Eigen 5 instead would hand both Eigens to your workspaces.
    if grep -rlIF -- /usr/include/eigen3 "$pkgdir"; then
        printf 'WARNING: the files above mention the system Eigen in /usr/include/eigen3.\n' >&2
    fi

    # License texts (BSD and similar licenses must ship them): every license file a
    # repository ships at its top level or one folder down, named after its path,
    # e.g. ros2_rclcpp_LICENSE or extra_octomap_octomap_LICENSE.txt. Plus Eigen's.
    local lic rel licdir=$pkgdir/usr/share/licenses/$pkgname
    while IFS= read -r -d '' lic; do
        rel=${lic#"$srcdir/ros2/src/"}
        install -Dm644 "$lic" "$licdir/${rel//\//_}"
    done < <(find "$srcdir"/ros2/src/*/* -maxdepth 2 -type f \
                  \( -iname 'licen[cs]e*' -o -iname '*-licen[cs]e*' -o -iname 'copying*' \) -print0)
    for lic in "$srcdir/eigen-${_eigen_ver}"/COPYING.*; do
        install -Dm644 "$lic" "$licdir/eigen-${lic##*/}"
    done
}

# A shell with ROS sourced (as ~/.zshrc usually does) lets CMake find the installed
# /opt/ros/humble, or a sourced workspace, while the new one builds. Vendor packages
# then skip libraries they think already exist, and the new package can ship
# without them. Start from a shell with no ROS in it.
_clean_ros_env() {
    # Every sourced ROS install or workspace is listed in these two variables;
    # drop their bin/ folders from PATH, along with anything under /opt/ros.
    local sourced=":${AMENT_PREFIX_PATH:-}:${COLCON_PREFIX_PATH:-}:" dir dirs keep=()
    IFS=: read -ra dirs <<< "$PATH"
    for dir in "${dirs[@]}"; do
        [[ $dir == /opt/ros/* ]] && continue
        [[ $dir == ?*/bin && $sourced == *":${dir%/bin}:"* ]] && continue
        keep+=("$dir")
    done
    PATH=$(IFS=:; printf '%s' "${keep[*]}")
    unset AMENT_PREFIX_PATH AMENT_CURRENT_PREFIX COLCON_PREFIX_PATH CMAKE_PREFIX_PATH \
          PYTHONPATH LD_LIBRARY_PATH PKG_CONFIG_PATH RMW_IMPLEMENTATION \
          ROS_DISTRO ROS_VERSION ROS_PYTHON_VERSION ROS_LOCALHOST_ONLY ROS_DOMAIN_ID
}
