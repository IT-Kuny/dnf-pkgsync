# dnf-pkgsync

A small helper script to replicate the installed package set of a DNF-based system
(e.g. Fedora, RHEL, Alma, Rocky) on another machine.

It works purely on package **names** (no versions, no architecture).  
You can:

- export the list of currently installed packages to a plain text file
- import a list of package names and align the system to that set:
  - remove installed packages **not** in the list
  - install packages that are in the list but currently missing

> ⚠️ This can remove a large number of packages. Use with care and preferably only
> between systems with the same distribution, release, and enabled repositories.

---

## Requirements

- DNF-based distribution (Fedora / RHEL / compatible)
- `bash`
- `dnf`
- standard coreutils (`sort`, `grep`, `mktemp`, etc.)
- **root privileges** (run as `root` or via `sudo`)

---

## What the script does (and does not do)

**Does:**

- Export:  
  Uses `dnf repoquery --qf '%{name}' --installed` to build a sorted, deduplicated
  list of package names and writes it to a given file.
- Import:
  1. Exports the currently installed package names into a temporary file.
  2. Computes:
     - packages to remove → installed but **not** in the provided list
     - packages to install → in the provided list but **not** installed
  3. Runs `dnf remove -y …` for the removal set.
  4. Runs `dnf --setopt=install_weak_deps=False install -y …` for the install set.

**Does not:**

- Backup or restore configuration files under `/etc` or elsewhere.
- Handle non-RPM artifacts (manual binaries, containers, flatpaks, etc.).
- Guarantee success if:
  - the target system has different Fedora/RHEL major versions,
  - required repositories are missing or disabled.

---

## File format

The script works with plain-text files containing **one package name per line**, for example:

```text
bash
coreutils
vim-enhanced
git

For import, the list file can be:

    produced by this script on another host, or

    a manually constructed list, as long as package names are valid for dnf.
```

## Usage

The script must be run as root:

```bash
sudo ./dnf-export-import-pkgs.sh -o <export|import> -p <file>
```

#### Options

    -o <export|import>
    Operation to perform:

        export
        Export the names of all currently installed packages (without version/arch)
        into a text file.

        import
        Read package names from a text file and align the installed package set:

            remove packages that are installed but not in the file

            install packages that are in the file but not installed

    -p <file>
    Path to the package list file (relative or absolute):

        for export:

            the file must not exist (the script refuses to overwrite it)

        for import:

            the file must exist

            must be readable

            must be non-empty

## Examples
Export the package list on the source system
```bash
sudo ./dnf-export-import-pkgs.sh -o export -p pkgs-source.txt
```
This creates pkgs-source.txt with the list of installed package names.

Copy this file to the target system (e.g. via scp, rsync, USB, …).
Import the package list on the target system
```bash
sudo ./dnf-export-import-pkgs.sh -o import -p pkgs-source.txt
```
This will:

    Generate a temporary snapshot of currently installed packages.

    Compute the difference between the snapshot and pkgs-source.txt.

    Remove packages that are not in pkgs-source.txt.

    Install packages that are in pkgs-source.txt but currently missing.

## Safety notes

    Use only between systems with the same (or very closely matching) distro version
    and architecture.

    Make sure the same third-party repositories (RPM Fusion, custom repos, etc.)
    are configured on the target system before importing.

    Consider testing on a VM or non-critical system first to verify the resulting package set.
