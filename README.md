# ros2-humble-arch

ROS 2 Humble on Arch Linux as one pacman package, `ros2-humble-arch`, built
from source with the fixes current Arch needs. It contains:

- **ROS 2 Humble**: everything in ROS 2's `ros2.repos` release manifest, the
  same set the AUR `ros2-humble` builds: rclcpp/rclpy, tf2, rviz2, rqt, launch,
  rosbag2, the DDS implementations.
- **MoveIt 2**: move_group, the C++ planning interface (`MoveGroupInterface`),
  the RViz MotionPlanning panel, the setup assistant, OMPL/CHOMP/Pilz planners
  and KDL kinematics.
- **ros2_control and ros2_controllers**, including the joint trajectory,
  position, gripper and joint state controllers.
- **xacro, joint_state_publisher and joint_state_publisher_gui.**

Everything is pinned to the versions Humble released for Ubuntu 22.04
(see [`extra.repos`](extra.repos)) and built against **Eigen 3.4.0**, the
version Ubuntu 22.04 ships, which installs alongside ROS in `/opt/ros/humble`.

It was made for a course that is taught and graded on Ubuntu 22.04. The goal is
that a package that builds on this setup builds unchanged on the grader's
machine. Eigen 3.4.0 is part of that: course starter code that uses
`${EIGEN3_INCLUDE_DIRS}` fails on Arch's Eigen 5 (see
[PATCHES.md #6](PATCHES.md#6-eigen-5-dropped-eigen3_include_dirs)).

## Before you start

- **Time and space:** the build takes roughly 3 hours on a machine with 16 GB of
  RAM and needs up to 60 GB of free disk while it runs. It builds one package at
  a time with about one compiler job per 2 GB of RAM, so machines with less RAM
  take longer. The installed package is a few GB.
- **It is a source build of 2022 software on a rolling distro.** It was last
  built on Arch in October 2026 (Python 3.14, GCC 16, CMake 4); a future Arch
  update can break it again. [PATCHES.md](PATCHES.md) lists every fix with the
  error it addresses, which is where to start when that happens.
- **Not included:** the parts of MoveIt the course doesn't use, which are also
  the ones that don't build on current Arch: perception (OpenCV 5), servo,
  `moveit_py`, benchmarks and hybrid planning. Also not included: Gazebo, and the
  C++ rqt plugins such as `rqt_image_view`. See
  [PATCHES.md](PATCHES.md#known-limitations).
- **Two Eigens.** The system Eigen 5 in `/usr` stays installed (other Arch
  packages need it). In shells with ROS sourced, CMake's `find_package(Eigen3)`
  finds 3.4.0 first; everything else, including `pkg-config eigen3`, keeps
  using Eigen 5. In your own code, write `#include <Eigen/Dense>`, not
  `#include <eigen3/Eigen/Dense>`: the second form finds Eigen 5 and fails to
  compile ([PATCHES.md #15](PATCHES.md#15-include-eigen3eigen-mixes-eigen-34-and-eigen-5)).
- **If you need exact Ubuntu behaviour or don't want to compile,** an Ubuntu
  22.04 container (e.g. [distrobox](https://distrobox.it/)) or
  [RoboStack](https://robostack.github.io/) gives you prebuilt Humble with no
  compiling.

## Install

```sh
sudo pacman -Syu                          # build against an up-to-date system
sudo pacman -S --needed base-devel git
git clone https://github.com/<your-github-user>/ros2-humble-arch.git
cd ros2-humble-arch
./build.sh
```

`build.sh` runs two stages; you can run them one at a time (`./build.sh deps`,
`./build.sh package`):

1. **deps**: the AUR recipes the package needs (colcon, vcstool, rosdep,
   `ros2-arch-deps`, `console-bridge`, ...). Each one is cloned into
   `deps/aur/`, checked out at the commit pinned in
   [`deps/aur.lock`](deps/aur.lock), and patched from
   [`deps/patches/`](deps/patches) where needed. The script then **stops so you
   can read them**, and builds and installs each one that is missing or older
   than the recipe.
2. **package**: `makepkg -sif` in this folder. The build stays in `src/` here
   even if your `makepkg.conf` sets `BUILDDIR`, because 60 GB doesn't fit on a
   tmpfs.

The script doesn't touch your shell config or sudoers. sudo asks for your
password whenever something is installed.

If a stage fails, fix the cause and run the same command again: up-to-date
dependencies are skipped, and colcon continues from where the build stopped.

Expect lots of compiler warnings and one makepkg warning,
`Package contains reference to $srcdir`. Compiled Python files and the
source-file names in C++ log messages record the folder they were built in.
These are harmless; the AUR recipe shows the same ones.

**After installing, delete the build tree** to get the space back:
`rm -rf src pkg` in this folder. Keep `src/` only if you plan to add packages
soon: with it, a rebuild compiles only what changed.

### Replacing AUR `ros2-humble`

Run `./build.sh` as above. The deps stage rebuilds only what is older than the
pinned recipes, which is typically the three patched ones (`python-vcstool`,
`python-colcon-core`, `ros2-arch-deps`, which get `pkgrel` 2) and
`console-bridge` if it's missing. If `python-pytest-runner` is still installed,
it stops first and tells you how to remove it. When the package installs,
pacman asks to remove `ros2-humble`; answer yes. You don't need to unsource ROS
first; the build cleans its own environment
([PATCHES.md #8](PATCHES.md#8-building-while-ros-is-sourced)).

## After installing

Load ROS in each shell by adding one line to `~/.zshrc` (or `~/.bashrc` with
`setup.bash`):

```sh
source /opt/ros/humble/setup.zsh
```

Check that it works, in two terminals:

```sh
ros2 run demo_nodes_cpp talker
ros2 run demo_nodes_py listener      # should print what the talker says
ros2 doctor
```

Then:

- **Existing colcon workspaces:** delete `build/` and `install/` once and
  rebuild. CMake caches where it found Eigen.
  `grep Eigen3_DIR build/<package>/CMakeCache.txt` should then show
  `/opt/ros/humble/share/eigen3/cmake`.
- **rviz2 on Wayland:** add `export QT_QPA_PLATFORM=xcb` to your shell config.
- **rqt_plot:** `sudo pacman -S --needed python-pyqtgraph python-matplotlib`.
- **rosdep:** course instructions often say
  `rosdep install --from-paths src --ignore-src -r -y`. Run
  `sudo rosdep init && rosdep update` once first. With ROS sourced, rosdep then
  counts everything this package contains as installed.

## After a system upgrade

If a Python minor version changed (e.g. 3.14 to 3.15), or ROS commands fail
with `No module named 'rclpy'` or `error while loading shared libraries`,
rebuild from scratch. CMake remembers the old Python, so a plain rebuild isn't
enough:

```sh
./build.sh --clean package
```

## Adding a package

1. Find the version Humble released: search for the repository in
   [humble/distribution.yaml](https://github.com/ros/rosdistro/blob/master/humble/distribution.yaml)
   (`release: version`, without the trailing `-1`).
2. Add an entry for it to [`extra.repos`](extra.repos) at that version, and any
   system libraries its `package.xml` needs to `depends` in the PKGBUILD.
3. Run `updpkgsums` (from `pacman-contrib`), bump `pkgrel`, then
   `./build.sh package`. If you kept `src/` from the last build, only the new
   packages compile; otherwise it's a full build.

## Repository layout

```
build.sh                 runs the two stages
PKGBUILD                 ros2-humble-arch
ros2-humble-arch.install message pacman prints after install
extra.repos              repositories built on top of ros2.repos, pinned
deps/aur.lock            AUR dependency recipes, build order, pinned commits
deps/patches/            our changes to three of them
PATCHES.md               every fix, with the error it addresses
```

`deps/aur/` and the build folders (`src/`, `pkg/`) are created while building
and are ignored by git.

## Uninstall

```sh
sudo pacman -Rns ros2-humble-arch
```

The AUR dependency chain stays installed. `pacman -Qm` lists it if you want to
remove it too, starting with `ros2-arch-deps`.

## Credits and license

The PKGBUILD is derived from the AUR
[`ros2-humble`](https://aur.archlinux.org/packages/ros2-humble) recipe. Its
maintainers and contributors are credited at the top of the file. The dependency
recipes are AUR packages by their own maintainers; this repository only pins
them and carries small patches.

The files written for this repository are released under the 0BSD license
([LICENSE](LICENSE)), the license Arch Linux uses for its own package sources.
The PKGBUILD keeps the credits of the AUR recipe it is derived from. ROS 2,
MoveIt, Eigen and everything else this builds keep their own licenses; every
license file the repositories ship is installed in
`/usr/share/licenses/ros2-humble-arch` (the rest declare their license only in
their `package.xml`).
