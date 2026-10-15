# Patches and fixes

ROS 2 Humble was written for Ubuntu 22.04: Python 3.10, CMake 3.22, GCC 11 and
Eigen 3.4, frozen in 2022. Arch is a rolling release and is years ahead of that.
At the time of this release, Arch has Python 3.14, CMake 4, GCC 16 and Eigen 5.
Almost every fix below has the same cause: code that assumes the 2022 versions
running on the current ones.

Each entry gives the error you would see without the fix, the cause, the fix,
and where the fix lives in this repository. Search this page for your error text.

The starting point is the AUR `ros2-humble` recipe at commit `203d02b6e3f2`
(release `2026.02.20`), the AUR dependency recipes pinned in
[`deps/aur.lock`](deps/aur.lock), and the repositories pinned in
[`extra.repos`](extra.repos) (MoveIt 2, ros2_control and the rest; #9 to #12).

| # | What breaks | Fix | Where |
|---|---|---|---|
| 1 | Test suites of the colcon recipes | Skip `check()` | `build.sh` (`--nocheck`) |
| 2 | colcon `setup.py` version check | `BUILD_DEBIAN_PACKAGE=1` | `build.sh` |
| 3 | `vcs` (vcstool) crashes at startup | `importlib.metadata` shim | `deps/patches/python-vcstool.patch` |
| 4 | `python-pytest-runner` dependency | Removed from two recipes | `deps/patches/python-colcon-core.patch`, `deps/patches/ros2-arch-deps.patch` |
| 5 | `console_bridge_vendor` fallback | Depend on AUR `console-bridge` | `deps/aur.lock`, `PKGBUILD` |
| 6 | Eigen 5 removed CMake variables | Build against and ship Eigen 3.4.0 | `PKGBUILD` |
| 7 | `rosidl_typesupport_introspection_tests` | Not built | `PKGBUILD` |
| 8 | Building with ROS already sourced | Clean environment in `build()` | `PKGBUILD` |
| 9 | colcon can't see the `octomap` package | Remove its top-level CMakeLists.txt | `PKGBUILD` (`prepare()`) |
| 10 | `octomap` fails under GCC 16 | Drop its `-Werror`, build as C++17 | `PKGBUILD` |
| 11 | System libraries Ubuntu ships (OMPL, FCL, libccd) | Built first, with Ubuntu's options | `extra.repos`, `PKGBUILD` |
| 12 | Parts of MoveIt that need OpenCV 4, old Boost or Python bindings | Not built | `PKGBUILD` (`_ignore`) |
| 13 | `-DBUILD_TESTING=OFF` never reached CMake | One flag per `--cmake-args` argument | `PKGBUILD` |
| 14 | Running out of memory on MoveIt's large files | Jobs sized to RAM, no LTO | `PKGBUILD` |
| 15 | `#include <eigen3/Eigen/...>` mixes Eigen 3.4 and 5 | Drop the `eigen3/` prefix | `PKGBUILD` (`prepare()`) |
| 16 | MoveIt users fail: `liboctomath.a` "does not exist" | Keep static libraries | `PKGBUILD` (`options`), `build.sh check` |

---

## 1. Test suites need `lib2to3`, removed in Python 3.13

**Error** (in `check()` of most `python-colcon-*` recipes):

```
ModuleNotFoundError: No module named 'lib2to3'
```

**Cause:** the colcon packages share a spell-check test whose checker imports
`lib2to3`, which Python removed from the standard library in 3.13.

**Fix:** `build.sh` builds the dependency chain with `makepkg --nocheck`. This
skips all of their test suites. These suites are mostly code-style checks
(flake8, copyright headers, spelling), not functional tests, and the same
code passes upstream CI. `ros2-humble-arch` has no `check()`, and it builds
with `-DBUILD_TESTING=OFF` (see #13 for why the AUR recipe's version of that
flag never took effect).

## 2. colcon `setup.py` files import `pkg_resources`

**Error** (building e.g. `python-colcon-notification` 0.3.0):

```
    from pkg_resources import parse_version
ModuleNotFoundError: No module named 'pkg_resources'
```

**Cause:** setuptools removed `pkg_resources`. The import only checks that
setuptools is at least 40.5.0. It is wrapped in
`if 'BUILD_DEBIAN_PACKAGE' not in os.environ:`, an escape hatch ROS uses for its
own Debian packaging. Newer upstream releases dropped the import, but some AUR
recipes are one version behind.

**Fix:** `build.sh` exports `BUILD_DEBIAN_PACKAGE=1` while building the
dependency chain. Nothing else reads it.

## 3. `vcs` crashes: `from pkg_resources import load_entry_point`

**Error** (in the package's `prepare()`, the first time `vcs import` runs):

```
  File "/usr/lib/python3.14/site-packages/vcstool/commands/help.py", line 4, in <module>
    from pkg_resources import load_entry_point
ModuleNotFoundError: No module named 'pkg_resources'
==> ERROR: A failure occurred in prepare().
```

**Cause:** same removal as #2. This one is in vcstool's runtime code, so it
can't be skipped.

**Fix:** [`deps/patches/python-vcstool.patch`](deps/patches/python-vcstool.patch)
adds a `prepare()` to the recipe. It replaces that import with an equivalent
`load_entry_point` built on `importlib.metadata`, and fails the build if
`pkg_resources` is still referenced anywhere. `pkgrel` is bumped to mark the
recipe as locally patched.

## 4. `python-pytest-runner` is gone

**Error** (`makepkg -s` on `python-colcon-core` or `ros2-arch-deps`):

```
error: target not found: python-pytest-runner
```

If you have an old copy installed, it breaks Python builds on the whole
machine instead: its setuptools entry point loads during every `setup.py` run
and fails.

**Cause:** pytest-runner is deprecated upstream. It relies on setuptools'
`test` command and on `pkg_resources`, both now removed, and Arch's repos no
longer carry it. Two AUR recipes still list it as a dependency.

**Fix:** [`deps/patches/python-colcon-core.patch`](deps/patches/python-colcon-core.patch)
and [`deps/patches/ros2-arch-deps.patch`](deps/patches/ros2-arch-deps.patch)
remove it from `depends` and bump `pkgrel`. If it is still installed from an
earlier attempt, `build.sh deps` stops and asks you to remove it first with
`sudo pacman -Rdd python-pytest-runner`. The `-dd` is needed because the
unpatched recipes still list it; the stage then rebuilds them without it.

## 5. `console_bridge_vendor` can't build its bundled copy

**Error** (in the build):

```
--- stderr: console_bridge_vendor
The no-dev option is deprecated.  Use -Wno-author instead.
CMake Error: The warning category "all" is not known.
...
Failed   <<< console_bridge_vendor
```

**Cause:** `ros2-arch-deps` doesn't pull in console_bridge. Without a system
copy, the vendor package builds its bundled one. It passes compiler flags to
that inner build unquoted, and CMake 4 reads the stray `-Wall` as its own
option.

**Fix:** `console-bridge` (AUR) is the last entry in `deps/aur.lock`, and
`ros2-humble-arch` depends on it, so the vendor package finds the system
library and builds nothing.

If you install `console-bridge` *after* a build already failed here, delete
`src/build/console_bridge_vendor` before resuming. CMake cached "not found" and
won't search again.

## 6. Eigen 5 dropped `EIGEN3_INCLUDE_DIRS`

**Error** (in the build, e.g. `rviz_rendering`, and in your own workspaces):

```
fatal error: Eigen/Dense: No such file or directory
```

**Cause:** Eigen releases after 3.4.0 no longer set the legacy CMake variables
`EIGEN3_INCLUDE_DIR` / `EIGEN3_INCLUDE_DIRS`. Humble's `eigen3_cmake_module`,
several Humble packages, and many course starter `CMakeLists.txt` files rely on
them, e.g. `include_directories(${EIGEN3_INCLUDE_DIRS})`. Ubuntu 22.04's
`libeigen3-dev` is 3.4.0 and still sets them, so the same code works there.

Check which Eigen a workspace package found:

```sh
grep Eigen3_DIR build/<package>/CMakeCache.txt
grep -c EIGEN3_INCLUDE_DIRS <that directory>/Eigen3Config.cmake   # 0 = the variables are gone
```

**Fix:** the PKGBUILD downloads Eigen 3.4.0 (headers and CMake config only;
Eigen is header-only). Before building ROS, it installs Eigen into a staging
folder and puts that folder first on `CMAKE_PREFIX_PATH`, so all of ROS builds
against 3.4.0. `package()` then ships Eigen 3.4.0 in `/opt/ros/humble`.

The staging folder's path ends up in what gets built, so it is mapped to the
final location:

- Some packages (`laser_geometry`, orocos KDL's pkg-config files, ...) write the
  absolute Eigen include path into their installed text files. `package()`
  rewrites the staging path to `/opt/ros/humble` and lists every file it changed.
- Eigen's assert messages compile the header path into libraries. The build
  adds `-ffile-prefix-map=<staging folder>=/opt/ros/humble` to `CFLAGS` and
  `CXXFLAGS`, so those messages name the installed headers. `package()` warns
  if the staging path still turns up in a binary.

How it reaches your code: any shell with ROS sourced has `/opt/ros/humble/bin`
early on `PATH`, so CMake's `find_package(Eigen3)` finds 3.4.0 there before the
system Eigen 5 in `/usr`. That covers your workspaces. Outside ROS, `/usr` keeps Eigen 5 and nothing else changes.
`pkg-config eigen3` still reports Eigen 5, because the bundled 3.4.0 is
installed without a pkg-config file. After installing, delete `build/` and
`install/` once in any workspace built before, because CMake caches
`Eigen3_DIR`. It should then read `/opt/ros/humble/share/eigen3/cmake`.

## 7. `rosidl_typesupport_introspection_tests` streams `char16_t`

**Error** (in the build):

```
error: use of deleted function ... operator<<(... char16_t)
--- stderr: rosidl_typesupport_introspection_tests
```

**Cause:** C++20 deleted `operator<<` for `char16_t` (it used to print a
number silently). GCC 16 uses C++20 by default. This test-only package prints
`char16_t` values through Humble's bundled gtest.

**Fix:** added to `--packages-ignore` in the PKGBUILD. Nothing depends on
it; it only holds tests. It only got built because tests were being built at
all (#13); with that fixed it would build nothing, and the ignore stays as a
safeguard.

## 8. Building while ROS is sourced

**Symptom:** the new package is missing libraries that the old one had,
e.g. `orocos_kdl`. Or a build picks up headers or Python modules from the
installed `/opt/ros/humble`, or from one of your workspaces, instead of the new
sources.

**Cause:** rebuilding happens in a shell where `~/.zshrc` already sourced
`/opt/ros/humble/setup.zsh`, and maybe a workspace. `makepkg` inherits that
environment, and CMake finds the *installed* ROS through `PATH`,
`CMAKE_PREFIX_PATH` and `AMENT_PREFIX_PATH`. Vendor packages
(`orocos_kdl_vendor`, `yaml_cpp_vendor`, ...) build a library only when CMake
can't find one. In a test with ROS sourced, `orocos_kdl_vendor` found
`/opt/ros/humble/share/orocos_kdl/cmake` and built nothing. In a rebuild, the
new package ships without the library, and pacman removes the old files on
upgrade. `RMW_IMPLEMENTATION` from your shell would also change the default
middleware compiled into `rmw_implementation`.

**Fix:** `build()` first removes the `bin/` folder of every sourced ROS install
or workspace (and anything under `/opt/ros`) from `PATH`. It then unsets the
ROS and colcon variables, including `RMW_IMPLEMENTATION`.

## 9. colcon can't see the `octomap` package

**Error** (MoveIt's dependencies can't find OctoMap; FCL builds without it):

```
Could not find a package configuration file provided by "octomap"
```

**Cause:** the octomap repository has a top-level `CMakeLists.txt`
(`project(octomap-distribution)`) that builds all of it as one project. colcon
treats a folder with a CMakeLists.txt as a package and doesn't look inside, so
it builds `octomap-distribution` and never sees the real `octomap` package.
Ubuntu builds from per-package release repositories, which don't have that file.

**Fix:** `prepare()` deletes that top-level file, so colcon finds
`octomap/package.xml`. Only octomap itself is needed: `octovis` needs QGLViewer,
which Arch doesn't have, and `dynamicEDT3D` is unused, so both get a
`COLCON_IGNORE`.

## 10. `octomap` fails under GCC 16

**Error:**

```
ciso646: error: #warning "<ciso646> is not a standard header since C++20" [-Werror=cpp]
ScanGraph.h:91:40: error: C++20 says that these are ambiguous, even though the second is reversed: [-Werror]
OcTreeIterator.hxx:42:39: error: 'struct std::iterator' is deprecated [-Werror=deprecated-declarations]
```

**Cause:** octomap 1.9.8 compiles with `-Werror`. GCC 16 defaults to C++20 and
warns about things GCC 11 (Ubuntu 22.04) never mentioned, and `-Werror` turns
each warning into an error.

**Fix:** `prepare()` removes `-Werror` from octomap's compiler settings, and
the build passes `-DCMAKE_CXX_STANDARD=17`, the standard GCC 11 used.

## 11. Libraries Ubuntu ships as system packages: OMPL, FCL, libccd

**Symptom:** none if you follow this recipe. The AUR versions would bring
problems of their own:

- the AUR's `ompl` is 2.0, while Humble's MoveIt is built for 1.7;
- all of them are compiled against Arch's Eigen 5, and FCL and OMPL pass Eigen
  types to and from MoveIt, which would mix two Eigen versions in one program.

**Fix:** they are in `extra.repos` at the versions Ubuntu 22.04 has (OMPL 1.7.0,
FCL 0.7.0, libccd 2.1) and built from source against Eigen 3.4.0 like
everything else. `build()` builds them first, in dependency order, with the
options Ubuntu's packages use:

- libccd with `-DENABLE_DOUBLE_PRECISION=ON` (FCL requires double precision);
- octomap (#9, #10), then FCL with `-DFCL_WITH_OCTOMAP=ON`, so MoveIt can
  collision-check against octrees;
- OMPL without its Python bindings, tests or demos.

The main build skips them, so its common CMake options never reconfigure them.
Ruckig, the other library involved, builds normally.

## 12. Parts of MoveIt that are not built

The MoveIt repository is imported whole, but these packages are in `_ignore`:

| Package | Why |
|---|---|
| `moveit_ros_perception` | Needs `cv_bridge`, which only accepts OpenCV 4 or 3; Arch has OpenCV 5 |
| `moveit_ros_benchmarks` | Includes `boost/progress.hpp`, which Boost removed |
| `moveit_py` | Python bindings, untested on Python 3.14 |
| `moveit_hybrid_planning`, `moveit_ros_control_interface`, `moveit_chomp_optimizer_adapter`, `pilz_industrial_motion_planner_testutils` | Not used by the course |
| `moveit`, `moveit_ros`, `moveit_runtime`, `moveit_plugins` | Metapackages that depend on the packages above |

None of them is a dependency of anything that is built: the planning interface,
move_group, the RViz MotionPlanning panel, the setup assistant, the planners and
MoveIt Servo are all there. Servo (`moveit_servo`) is built because the
Mitsubishi robot's bringup launch file starts its `servo_node_main`. Its
joystick demo launch files also want the `joy` driver, which is not included;
servo itself doesn't need it.

Also not built are the packages in these repositories that Humble never
released (examples, `moveit_planners_trajopt`, `moveit_setup_simulation`,
`joint_limits_interface`), so Ubuntu users never had them either.

## 13. `-DBUILD_TESTING=OFF` never reached CMake

**Symptom:** every package compiles its tests. With MoveIt included, the
configure step of e.g. `moveit_kinematics` fails, because its tests need
`moveit_resources_*` packages that aren't included:

```
Could not find a package configuration file provided by "moveit_resources_fanuc_moveit_config"
```

**Cause:** the AUR recipe passes `--cmake-args " -DBUILD_TESTING=OFF -Wno-dev"`.
colcon removes the leading space but does not split the string, so CMake gets
one argument and sets `BUILD_TESTING` to the text `OFF -Wno-dev`, which counts
as true. Any other flag in the same string is lost. With
`--cmake-args " -DBUILD_TESTING=OFF -DFOO=1 -Wno-dev"`, CMakeCache.txt reads
`BUILD_TESTING:BOOL=OFF -DFOO=1 -Wno-dev`, and `FOO` is never set.

**Fix:** every flag is its own argument:
`--cmake-args " -DBUILD_TESTING=OFF" " -Wno-dev"`. Tests are no longer compiled,
which is also what Ubuntu's binary packages do, and the build is smaller and
faster than the AUR recipe's.

## 14. Running out of memory on MoveIt's large files

**Symptom:** a compiler process is killed partway through the build
(`c++: fatal error: Killed signal terminated program cc1plus`), usually in
`moveit_core`, the Pilz planner or OMPL.

**Cause:** MoveIt's larger source files need 1-2 GB each to compile. The AUR
recipe builds several packages at once when RAM is 16 GB or more, and colcon
gives each package one compiler job per CPU thread. LTO, which makepkg turns on
by default, adds several GB more at each large link step.

**Fix:** the build runs one package at a time with `MAKEFLAGS=-jN`, where N is
about one job per 2 GB of RAM (at most one per CPU thread), and
`options=('!lto')`. ROS isn't tested with LTO upstream. On machines with lots
of RAM, this is somewhat slower than the AUR recipe's parallel build.

## 15. `#include <eigen3/Eigen/...>` mixes Eigen 3.4 and Eigen 5

**Error** (in the build, first in `kinematics_interface_kdl`; also in your own
workspaces):

```
eigen-3.4.0/stage/include/eigen3/Eigen/src/Geometry/Translation.h:134:38: error: expected unqualified-id before '<' token
  134 |   inline typename internal::enable_if<Derived::IsVectorAtCompileTime,VectorType>::type
      |                             ^~~~~~~~~
      |                             EnableIf
```

Other first errors are possible, e.g. `Eigen/Core:39:44: error: missing binary
operator before token '('`. They have the same cause if the path in the error is
an Eigen 3.4.0 header and the file being compiled has an `eigen3/` include.

**Cause:** Eigen can be included two ways. `<Eigen/Core>` is found through the
include folder CMake adds for Eigen, which is Eigen 3.4.0 (#6).
`<eigen3/Eigen/Core>` is found by the compiler's own search of `/usr/include`,
which on Arch holds Eigen 5. A file that uses both styles, directly or through
the headers it includes, gets half of each version, and Eigen 3.4's headers
don't compile against Eigen 5's internals (`internal::enable_if` is gone). On
Ubuntu both styles find the same Eigen, so this never shows there.

The packages that use the `eigen3/` style are `kinematics_interface_kdl` and, in
MoveIt, CHOMP, the Pilz planner and the cached IK plugin. All of them already
get Eigen through CMake (`Eigen3::Eigen`, `find_package(Eigen3)`, or
`moveit_core`), so the prefix isn't needed.

**Fix:** `prepare()` finds every `#include <eigen3/...>` or `#include "eigen3/..."`
under `src/ros2/src` and removes the `eigen3/` prefix. It prints each file it
changes. A file it already changed no longer matches, so a resumed build leaves
it alone and doesn't recompile it. The installed headers keep the fix, so your
code can include e.g. `chomp_motion_planner/chomp_cost.h` without hitting this.

**In your own code,** include Eigen as `#include <Eigen/Dense>` (or
`<Eigen/Core>`, ...), and get it in CMake with `find_package(Eigen3 REQUIRED)`.
That works the same here and on Ubuntu 22.04. If code you were given uses
`<eigen3/Eigen/...>` and fails with an error like the one above, change the
include the same way.


## 16. MoveIt users fail: `liboctomath.a` "does not exist"

**Error** (building your own package that uses MoveIt's C++ API, e.g. anything
with `find_package(moveit_ros_planning_interface)`; found with release
`2026.02.20-1`):

```
CMake Error at /opt/ros/humble/share/octomap/octomap-targets.cmake:104 (message):
  The imported target "octomath-static" references the file

     "/opt/ros/humble/lib/liboctomath.a"

  but this file does not exist.
```

**Cause:** octomap builds every library twice, shared (`liboctomap.so`) and
static (`liboctomap.a`), and its installed CMake file lists both. makepkg's
default `!staticlibs` option deletes any `.a` that has a `.so` next to it, after
`package()` has run. CMake checks that every file a package lists exists, so
the first `find_package(octomap)` fails. FCL looks for octomap, MoveIt looks for
FCL, so every workspace package that uses MoveIt from C++ fails to configure.
The ROS build itself never noticed, because it found octomap in its own build
folder, before makepkg deleted anything.

**Fix:** `options=(... 'staticlibs')` keeps the static libraries. They add a few
MB.

**Check for this whole class of problem:** `./build.sh check` (also run at the
end of `./build.sh package`) reads every CMake file in `/opt/ros/humble` and
lists any library they point to that isn't installed. Each CMake file says which
install folder its paths start from (rviz's bundled OGRE lives in
`/opt/ros/humble/opt/rviz_ogre_vendor`), and the check works that out the same
way CMake does.

A missing include folder is only reported as a `note`, because CMake only
checks those when something links that library. One note is expected:

```
note: include folder /opt/ros/humble/include/rosbag2_storage_mcap does not exist
```

`rosbag2_storage_mcap` (0.15.16) lists that folder in its CMake file but never
installs it, so Ubuntu's package has the same gap. It is a plugin that rosbag2
loads at run time; nothing links it, so the note is harmless.

---

## Other changes from the AUR recipe

These aren't build fixes, but they differ from AUR `ros2-humble`:

- **Name and contents:** the package is `ros2-humble-arch`, and it also
  contains the repositories in `extra.repos`. It `provides` `ros2-humble` and
  conflicts with `ros2-humble` and `ros2-humble-base`, so pacman offers to
  replace them, and an AUR helper won't swap it back for the AUR version. It
  also conflicts with `ros2-humble-core`, `ros2-humble-extras` and
  `ros2-humble-eigen3`, local packages from before this repository's first
  release, and with `ros2-humble-debug`, the debug-symbols package makepkg
  splits off the AUR build by default, so pacman offers to remove it too.
- **Dependencies for the extra repositories:** `boost`, `fmt`, `tl-expected`,
  `qhull`, `bullet`, `libcap`, `elfutils`, `python-jinja`, `python-typeguard`,
  `python-lxml`, `python-graphviz`, `python-rospkg` and `python-yaml`, the Arch
  equivalents of what rosdep installs for them on Ubuntu.
- **Runtime dependencies Ubuntu's `ros-humble-desktop` pulls in:**
  `python-psutil` (needed by `ros2 doctor`) is in `depends`.
  `python-matplotlib` and `python-pyqtgraph` are `optdepends`. Without one of
  them, `rqt_plot` fails with
  `RuntimeError: No usable plot type found. Install at least one of: PyQtGraph, MatPlotLib`.
- **`options=('!debug')`:** Arch's default `makepkg.conf` also builds a
  separate `-debug` package. In a test build it was 11 times the size of the
  real package, and for all of ROS it would be many gigabytes that are rarely
  installed. The build flags are otherwise unchanged.
- **Build paths in installed text files:** colcon writes its build-time
  install folder into the plain-`sh` setup scripts (`setup.sh`,
  `share/*/package.sh`, ...). On the AUR package, `. /opt/ros/humble/setup.sh`
  from `sh` therefore points at the deleted build folder. `package()` rewrites
  that path to `/opt/ros/humble` (bash and zsh setups were never affected).
  makepkg still warns `Package contains reference to $srcdir`, because compiled
  Python files record where they were built. That warning is harmless.
- **Checksums:** the `ros2` release tag has a real checksum instead of `SKIP`
  (pacman can checksum a pinned git tag).
- **Licenses:** SPDX identifiers instead of `Apache`, and every repository's
  license text is installed in `/usr/share/licenses/ros2-humble-arch`.
- The install message mentions zsh and Eigen.

## Known limitations

- **Licenses:** the `license` field names the three main licenses. Individual
  packages carry their own, e.g. LGPL (orocos KDL) and EPL (Cyclone DDS); all
  texts are in `/usr/share/licenses/ros2-humble-arch`.
- **Not included:** the MoveIt packages in #12, Gazebo, and anything else not in
  `ros2.repos` or `extra.repos`. To add a repository, see "Adding a package"
  in the README.
- **C++ rqt plugins are not built.** The AUR recipe skips `qt_gui_cpp` and
  `rqt_gui_cpp`, so `rqt_image_view` and other C++ rqt plugins are missing. The
  Python plugins (`rqt_plot`, `rqt_graph`, `rqt_console`, ...) work.
  Workaround: show images in `rviz2`.
- **rviz2 on Wayland** needs `export QT_QPA_PLATFORM=xcb`. Ogre 1.12 requires
  GLX. Launch files start `rviz2` directly, so put the export in your shell
  config rather than in an alias.
- **Arch updates can break the install or the build.** A new Python minor
  version (3.14 → 3.15) or a new soname for a library ROS links against means
  rebuilding from scratch: `./build.sh --clean package`. Signs:
  `ModuleNotFoundError: No module named 'rclpy'` or
  `error while loading shared libraries`.
