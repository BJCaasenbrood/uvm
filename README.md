# uvm

A project and package manager for MATLAB, inspired by [uv](https://github.com/astral-sh/uv).

Each MATLAB project declares its dependencies in `uvm.json`. uvm resolves them to exact
commits in `uvm.lock` and puts exactly those packages on the path. Anyone who checks out
the project gets the same code with a single `uvm sync`.

Packages are plain git repositories and versions are git tags. A git server you already
have (GitLab, Bitbucket, Gitea or GitHub) is all the infrastructure you need, and there
is no package index to host.

```matlab
>> uvm init
>> uvm add git@git.company.local:lab/daq_tools.git
>> uvm run analysis.m
```

## Features

- **Written in MATLAB** and used from the Command Window: `uvm add`, `uvm sync`, `uvm test`, ...
- **Reproducible**: `uvm.lock` pins every package, including indirect ones, to an exact commit.
- **Version constraints** in the style of Cargo and npm: `^1.2`, `~1.2`, `>=1.0, <2`.
  Dependencies are resolved transitively.
- **Any git source**: SSH, HTTPS or a local folder, at a version tag, branch or commit.
- **Optional registries**: one git repo with an `index.json` lets people write
  `uvm add signal_utils` instead of a URL.
- **Path management**: activate one project at a time, from `startup.m` or automatically
  when a MATLAB Project (`.prj`) opens.
- **MATLAB checks**: warns about missing toolboxes, unsupported releases, and functions
  that shadow each other across packages.
- **Ready for CI**: `uvm test --frozen --junit results.xml` fails if the lock is out of date
  and writes a JUnit report.
- **Works offline** once packages are cached. Several MATLAB sessions can share one cache.
- **Uses your own git**, so SSH keys, credential helpers, proxies and company certificates
  just work.

## Requirements

- MATLAB R2023a or newer
- `git` on the system path

## Installation

```matlab
>> addpath('/path/to/uvm/toolbox')
>> uvm setup      % adds uvm to startup.m, so it is available in every session
>> uvm version    % shows the uvm version and the git it found
```

`uvm setup --remove` takes the hook out again.

## Quick start

```matlab
>> cd ~/work/my_analysis
>> uvm init                                                  % creates uvm.json

>> uvm add git@git.company.local:lab/daq_tools.git           % newest version tag
>> uvm add https://github.com/someone/fancy-lib.git --tag v1.2.0
>> uvm add ../my_local_lib                                   % a folder on disk

>> uvm list
Package              Version      Commit     Source
daq_tools            0.4.0        3f9c2a1b   git@git.company.local:lab/daq_tools.git
fancy_lib            1.2.0        a81d07e2   https://github.com/someone/fancy-lib.git
my_local_lib         branch:main  c0ffee12   /home/me/work/my_local_lib

>> uvm run analysis.m     % sync, then run a script
>> uvm test               % sync, then run tests/
```

Commit `uvm.json` and `uvm.lock`. A colleague clones the project and runs `uvm sync`.

## Commands

| Command | Description |
|---|---|
| `uvm init [--project]` | Create `uvm.json` in the current folder |
| `uvm add NAME[@SPEC]` / `uvm add URL [--tag T \| --branch B \| --rev R]` | Add a dependency |
| `uvm remove NAME` | Remove a dependency |
| `uvm lock [--upgrade]` | Resolve dependencies and write `uvm.lock` |
| `uvm sync [--upgrade \| --frozen]` | Lock if needed, install, and activate |
| `uvm list` | Show the locked packages |
| `uvm run SCRIPT [--frozen]` | Sync, then run a script |
| `uvm test [FOLDER] [--frozen] [--junit FILE]` | Sync, then run the tests |
| `uvm activate` / `uvm deactivate` | Put the project's packages on the path, or take them off |
| `uvm project [--remove]` | Activate the project whenever its MATLAB Project opens |
| `uvm registry add\|remove\|list` | Manage registries |
| `uvm cache dir\|clean` | Show or empty the package cache |
| `uvm setup [--remove]` | Install the `startup.m` hook |
| `uvm doc [PAGE]` | Open the documentation |

Every command accepts `--quiet`. See `help uvm` for the complete syntax.

## uvm.json

```json
{
  "name": "my_analysis",
  "version": "0.1.0",
  "matlab": ">=R2023a",
  "toolboxes": ["Signal Processing Toolbox"],
  "paths": ["."],
  "dependencies": {
    "signal_utils": "^1.2",
    "daq_tools": { "git": "git@git.company.local:lab/daq_tools.git", "tag": "v0.4.0" }
  }
}
```

A plain string is a version constraint resolved through a registry. An object names a
git URL, with an optional `tag`, `branch`, `rev` or `version`. A repository without a
`uvm.json` still works as a package: its root folder goes on the path.

## Registries

A registry is a git repository containing one file:

```json
{
  "packages": {
    "signal_utils": { "url": "git@git.company.local:matlab/signal_utils.git" },
    "daq_tools":    { "url": "git@git.company.local:lab/daq_tools.git" }
  }
}
```

```matlab
>> uvm registry add work git@git.company.local:matlab/registry.git
>> uvm add signal_utils
```

You can also list registries under `"registries"` in a project's `uvm.json`, so
colleagues need no setup.

## Continuous integration

```sh
matlab -batch "addpath('uvm/toolbox'); uvm test --frozen --junit test-results.xml"
```

`--frozen` never changes `uvm.lock` and fails if the lock does not match `uvm.json`.
`matlab -batch` exits non-zero when tests fail. Set `UVM_HOME` to a cached folder to
avoid downloading packages on every run.

## Documentation

Run `uvm doc` in MATLAB to open the full documentation in the Help browser. It covers
getting started, the `uvm.json` reference, version constraints, registries, publishing
packages, CI, and troubleshooting. The pages also live in [`toolbox/doc`](toolbox/doc).

## How it works

- Each git repository is mirrored once in `~/.uvm/git` (or `UVM_HOME`). Each locked commit
  is unpacked once into `~/.uvm/pkgs/<name>/<commit>`, which all projects share.
- `uvm sync` writes the folders to activate into `.uvm/paths.txt` in the project.
  `uvm activate` only reads that file, so it is fast enough for `startup.m` and needs no
  network.
- Resolution picks the newest version tag that satisfies every requirement. A package
  keeps its locked commit while it still fits, unless you pass `--upgrade`.

## Development

Run the test suite, which uses local git repositories as fixtures and never touches your
real cache:

```matlab
>> runtests('tests')
```

Tested on MATLAB R2023a and R2024a on Linux. Windows and macOS support is written but not
yet tested.
