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

## Quickstart

```matlab
>> cd my_project
>> uvm init                                             % start a project (creates uvm.json)
>> uvm add https://github.com/altmany/export_fig.git    % install a package
>> export_fig(gcf, 'figure.pdf')                        % use it right away
```

- `uvm search [query]`: search your registries, GitHub and the File Exchange
- `uvm add [name or url]`: install a package and add it to the project
- `uvm remove [name]`: remove a package
- `uvm list`: show the installed packages
- `uvm sync`: install exactly what `uvm.lock` says and put it on the path
- `uvm doc`: open the full documentation

Commit `uvm.json` and `uvm.lock`. Anyone who clones the project runs `uvm sync` and gets
identical code.

## Usage

__Start a project:__

```matlab
>> uvm init              % uvm.json in the current folder
>> uvm init --project    % also a MATLAB Project (.prj) that activates it when opened
```

__Search for packages:__

```matlab
>> uvm search colormap
>> uvm search export fig --github --limit 5    % one source: --registry, --github or --fex
```

Each result shows the command that installs it. Searching never changes your project.

__Install a package:__

```matlab
>> uvm add https://github.com/altmany/export_fig.git    % newest version tag
>> uvm add git@git.company.local:lab/daq_tools.git      % SSH, e.g. a work server
>> uvm add ../my_local_lib                              % a folder on disk
>> uvm add gramm                                        % by name, from a registry
```

A repository without version tags is installed from its default branch. The package name is
the repository name; pass `--name` to choose another.

__Install a specific version:__

```matlab
>> uvm add https://github.com/matlab2tikz/matlab2tikz.git --tag v1.1.0
>> uvm add https://github.com/matlab2tikz/matlab2tikz.git --branch develop
>> uvm add https://github.com/matlab2tikz/matlab2tikz.git --rev 816f875
>> uvm add https://github.com/altmany/export_fig.git --version ^3.50
>> uvm add 'export_fig@>=3.50, <4'                     % by name, with a range
```

`^3.50` allows compatible updates (below 4.0), `~3.50` only bug fixes (below 3.51). Without a
version, uvm records `^` the newest version, so `uvm sync --upgrade` stays compatible.

__Remove a package:__

```matlab
>> uvm remove export_fig
```

__See what is installed:__

```matlab
>> uvm list
Package              Version          Commit     Source
export_fig           3.58.0           b9c20a51   https://github.com/altmany/export_fig.git
matlab2tikz          branch:develop   a9b65a97   https://github.com/matlab2tikz/matlab2tikz.git
>> packages = uvm("list");    % as a struct array
```

__Set up a cloned project:__

```matlab
>> uvm sync              % install what uvm.lock says, then activate
>> uvm sync --frozen     % the same, but fail if uvm.lock is out of date (for CI)
```

__Upgrade:__

```matlab
>> uvm sync --upgrade    % newest versions allowed by uvm.json
>> uvm lock --upgrade    % only update uvm.lock
```

Without `--upgrade`, packages keep their locked versions, even when newer ones exist.

__Switch between projects:__

```matlab
>> cd ../other_project
>> uvm activate          % its packages replace the previous project's on the path
>> uvm deactivate        % remove them
>> uvm project           % or let a MATLAB Project do this when it opens and closes
```

Only one project is active at a time. The `startup.m` hook activates the project MATLAB
starts in.

__Run scripts and tests:__

```matlab
>> uvm run analysis.m                  % sync, then run the script
>> uvm test                            % sync, then run the tests in tests/
>> uvm test --junit results.xml        % also write a JUnit report
```

__Share your code with people who don't use uvm:__

```matlab
>> uvm build                   % dist/my_analysis-0.1.0.zip: your code + every locked package
>> uvm build --toolbox         % dist/my_analysis-0.1.0.mltbx: install with a double click
>> uvm build --toolbox --no-deps
```

The zip contains `setup_my_analysis.m`, which puts everything on the path; no uvm, git or
network needed. Git-ignored files stay out. Every bundle lists its packages' licenses in
`THIRD_PARTY_LICENSES.md`, and uvm warns about GPL-licensed or unlicensed packages.

__Manage the cache:__

```matlab
>> uvm cache dir      % where packages are stored (~/.uvm, or UVM_HOME)
>> uvm cache clean    % delete downloads; the next uvm sync fetches them again
```

__Use uvm from code:__ every command also works with function syntax, so you can pass
variables and get results. Add `--quiet` to hide progress messages.

```matlab
>> uvm("add", url, "--tag", tag, "--quiet")
>> results = uvm("search", "optimization");
```

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

```matlab
>> uvm registry add mylab https://github.com/me/uvm-registry.git
>> uvm registry list
>> uvm add gramm
```

`paths`, `branch` and `dependencies` make libraries without a `uvm.json` work. A project can
also list registries in its `uvm.json`, so colleagues need no setup. See
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
