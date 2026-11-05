# uvm: Universal Matlab Package Manager

A package manager for MATLAB, inspired by [uv](https://github.com/astral-sh/uv). Install
packages from any git repository, pin them per project, and get the same versions on every
machine.

## Install

Download [`install_uvm.m`](install_uvm.m) and run it in MATLAB:

```matlab
>> install_uvm
```

This installs uvm into `~/.uvm/uvm` and adds it to `startup.m`. Run it again to update, or
`install_uvm(Uninstall=true)` to remove it. Requires MATLAB R2023a+ and `git`.

## Usage

```matlab
>> uvm init                                             % start a project (uvm.json)
>> uvm search colormap                                  % search registries, GitHub, File Exchange
>> uvm add https://github.com/altmany/export_fig.git    % add a package
>> uvm list                                             % show installed packages
>> uvm sync                                             % install exactly what uvm.lock says
```

Commit `uvm.json` and `uvm.lock`; anyone who clones the project runs `uvm sync` and gets
identical code. Run `uvm doc` for the full documentation.

| Command | Description |
|---|---|
| `uvm add NAME` / `uvm add URL` | Add a package from a registry or a git URL |
| `uvm add URL --tag T` / `--branch B` / `--rev C` / `--version ^1.2` | Pin a version |
| `uvm remove NAME` | Remove a package |
| `uvm sync --upgrade` | Move to the newest allowed versions |
| `uvm activate` / `deactivate` | Switch the MATLAB path to the current project |
| `uvm project` | Activate automatically when a MATLAB Project opens |
| `uvm run SCRIPT` / `uvm test` | Sync, then run a script or the tests |
| `uvm registry add NAME URL` | Add a registry |

## How it works

- **Packages are git repositories, versions are git tags.** Publishing is `git tag v1.0.0 && git push --tags`.
- **One shared cache.** Packages are downloaded once into `~/.uvm` and shared by all
  projects; nothing is copied into your project.
- **Dependencies are resolved transitively** and pinned to exact commits in `uvm.lock`.
- **Your own git does the downloading**, so SSH keys, credential helpers and private servers just work.

## Packages

Any repository works as-is: its root folder goes on the path. Add a `uvm.json` to declare
more:

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

## Registries

A registry lets you add packages by name. It is a git repository with an `index.json`:

```json
{
  "packages": {
    "export_fig": "https://github.com/altmany/export_fig.git",
    "gramm":   { "url": "https://github.com/piermorel/gramm.git", "paths": ["gramm"] },
    "cmocean": { "url": "https://github.com/chadagreene/cmocean.git", "branch": "main" }
  }
}
```

`paths`, `branch` and `dependencies` make libraries without a `uvm.json` work. See
[`examples/registry/index.json`](examples/registry/index.json) for 18 popular libraries.

## CI

```sh
matlab -batch "addpath('uvm/toolbox'); uvm test --frozen --junit results.xml"
```

`--frozen` fails if `uvm.lock` is out of date instead of updating it.

## Troubleshooting

If a download fails, check that `git ls-remote URL` works in a terminal without a password
prompt; uvm cannot answer prompts inside MATLAB. `uvm doc troubleshooting` lists every
warning and error.

Tested on Linux with R2024a (the core also with R2023a). Windows and macOS are not yet tested. Run the tests
with `runtests('tests')`.
