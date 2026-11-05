# uvm: Universal Matlab Package Manager

A project and package manager for MATLAB, inspired by [uv](https://github.com/astral-sh/uv).
Installs packages from any git repository (GitHub, GitLab, your company server, or a local
folder), pins them in a lockfile, and puts exactly the right versions on the path for each
project.

## Quickstart

Download [`install_uvm.m`](install_uvm.m) (or clone this repo) and run it in MATLAB:

```
>> install_uvm
```

It installs uvm into `~/.uvm/uvm` and hooks it into `startup.m`. Run it again to update,
`install_uvm(Ref="v0.1.0")` for a specific version, or `install_uvm(Uninstall=true)` to
remove it. Then, in a project folder:

- `uvm init`: start a project (creates `uvm.json`)
- `uvm search [query]`: search your registries, GitHub and the File Exchange
- `uvm add [name or git-url]`: add a package and install it
- `uvm remove [name]`: remove a package
- `uvm sync`: install exactly what `uvm.lock` says and put it on the path
- `uvm list`: show installed packages with their versions and commits
- `uvm run script.m` / `uvm test`: sync, then run a script or the tests
- `uvm doc`: open the full documentation

### What it does

Each project lists its dependencies in `uvm.json`. uvm resolves them, including the
packages they depend on, to exact commits in `uvm.lock`. Commit both files, and anyone who
clones the project gets identical code with `uvm sync`.

Packages are downloaded once into a shared cache (`~/.uvm`, or `UVM_HOME`). Projects only
point the MATLAB path at it, so nothing is copied into your project. Versions are git tags,
so publishing a package is `git tag v1.0.0 && git push --tags`.

## More details

__Search for a package:__

```
>> uvm search colormap
```

Prints matches from your registries, GitHub (MATLAB repositories, by stars) and the File
Exchange, each with the command that adds it. Use `--github`, `--registry` or `--fex` to
search one source.

__Add from git, at the newest version tag:__

```
>> uvm add https://github.com/altmany/export_fig.git
```

__Add a specific tag, branch or commit:__

```
>> uvm add https://github.com/matlab2tikz/matlab2tikz.git --tag v1.1.0
>> uvm add https://github.com/matlab2tikz/matlab2tikz.git --branch develop
>> uvm add https://github.com/matlab2tikz/matlab2tikz.git --rev 816f875
```

__Add a version range__ (`^1.2` = compatible updates, `~1.2` = bug fixes only):

```
>> uvm add https://github.com/altmany/export_fig.git --version ^3.50
```

__Add a local folder:__

```
>> uvm add ../my_package
```

__Upgrade to the newest allowed versions:__

```
>> uvm sync --upgrade
```

__Switch between projects:__

```
>> cd ../other_project
>> uvm activate
```

Or run `uvm project` once, so a MATLAB Project (`.prj`) activates its packages whenever it
opens.

## Registries

A registry lets you add packages by name instead of URL. It is just a git repository
containing an `index.json`:

```json
{
  "packages": {
    "export_fig": "https://github.com/altmany/export_fig.git",
    "gramm":      { "url": "https://github.com/piermorel/gramm.git", "paths": ["gramm"] },
    "cmocean":    { "url": "https://github.com/chadagreene/cmocean.git", "branch": "main" }
  }
}
```

```
>> uvm registry add mylab https://github.com/me/uvm-registry.git
>> uvm add gramm
```

Optional fields make libraries without a `uvm.json` work as-is: `paths` (folders to add;
`"src/**"` includes subfolders), `branch` (for repositories without version tags), and
`dependencies`. [`examples/registry/index.json`](examples/registry/index.json) lists 18
popular libraries, including export_fig, chebfun, gramm, manopt, YALMIP and
FastVisualization.

## Packages

Any git repository works as a package: by default its root folder goes on the path. Add a
`uvm.json` to say more:

```json
{
  "name": "signal_utils",
  "version": "1.2.0",
  "matlab": ">=R2023a",
  "toolboxes": ["Signal Processing Toolbox"],
  "paths": ["src"],
  "dependencies": { "export_fig": "^3.50" }
}
```

uvm warns about missing toolboxes, unsupported MATLAB releases, and functions defined by
more than one package.

## CI

```
matlab -batch "addpath('uvm/toolbox'); uvm test --frozen --junit results.xml"
```

`--frozen` fails if `uvm.lock` is missing or out of date, instead of re-resolving.

## Troubleshooting

uvm uses your system `git`, so whatever works for `git clone` in a terminal works in uvm,
including SSH keys, credential helpers and proxies. It cannot answer password prompts inside
MATLAB, so if a download fails, check that `git ls-remote [url]` works in a terminal without
asking for anything. `uvm doc troubleshooting` lists every warning and error.

## Requirements

MATLAB R2023a or later, and `git` on the system path. Tested on Linux with R2023a and
R2024a; Windows and macOS support is written but not yet tested. Run the test suite with
`runtests('tests')`.
