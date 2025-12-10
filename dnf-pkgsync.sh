#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME=${0##*/}

usage() {
    cat <<EOF
Usage:
  sudo $SCRIPT_NAME -o <export|import> -p <file>

Options:
  -o  Operation to perform:
        export  Export list of installed packages (names only, no version/arch).
        import  Import list and align installed packages to that set
                (removes packages not in list, installs missing ones).
  -p  Path to the package list file.
        export: file must NOT exist (will be created).
        import: file must exist, be readable and non-empty.

Notes:
  - This script can remove a LOT of packages. Use the same Fedora release,
    architecture and repo set on source and target host, otherwise you may
    break the system.
EOF
}

die() {
    echo "Error: $*" >&2
    exit 1
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found in PATH"
}

# Export current package names (no version/arch) to file
pkg_list_to_file() {
    local outfile=$1

    if [[ -e "$outfile" ]]; then
        die "Refusing to overwrite existing file '$outfile'"
    fi

    # dnf repoquery with name-only format
    dnf repoquery --qf '%{name}' --installed | sort -fu >"$outfile"
    echo "Package list exported to '$outfile'"
}

# Return lines present in 'current' but not in 'reference'
# get_delta reference current  =>  current - reference
get_delta() {
    local reference=$1
    local current=$2

    [[ -f "$reference" ]] || die "Reference file '$reference' does not exist"
    [[ -f "$current" ]]   || die "Current file '$current' does not exist"

    # grep returns 1 if no lines match; we don't want set -e to kill us in that case.
    grep -Fvx -f "$reference" "$current" || true
}

export_pkgs() {
    local list_file=$1

    [[ -n "$list_file" ]] || die "No path given for export (-p)"
    pkg_list_to_file "$list_file"
}

import_pkgs() {
    local list_file=$1

    [[ -n "$list_file" ]] || die "No path given for import (-p)"
    [[ -f "$list_file" && -r "$list_file" && -s "$list_file" ]] \
        || die "List file '$list_file' does not exist, is not readable, or is empty"

    # Temp files for snapshot before/after removals
    local snapshot_before snapshot_after
    snapshot_before=$(mktemp "${TMPDIR:-/tmp}/dnf-pkglist.before.XXXXXX")
    snapshot_after=$(mktemp  "${TMPDIR:-/tmp}/dnf-pkglist.after.XXXXXX")

    # Ensure cleanup
    trap 'rm -f "$snapshot_before" "$snapshot_after"' EXIT

    echo "Exporting current package set..."
    pkg_list_to_file "$snapshot_before"

    echo "Calculating packages to remove..."
    mapfile -t to_remove < <(get_delta "$list_file" "$snapshot_before")

    if (( ${#to_remove[@]} )); then
        echo "Packages to be removed (${#to_remove[@]}):"
        printf '  %s\n' "${to_remove[@]}"
        echo "Removing packages not present in target list..."
        dnf remove -y "${to_remove[@]}"
    else
        echo "No packages to remove."
    fi

    echo "Exporting package set after removals..."
    # Recreate snapshot_after (pkg_list_to_file refuses to overwrite)
    rm -f "$snapshot_after"
    pkg_list_to_file "$snapshot_after"

    echo "Calculating packages to install..."
    mapfile -t to_install < <(get_delta "$snapshot_after" "$list_file")

    if (( ${#to_install[@]} )); then
        echo "Packages to be installed (${#to_install[@]}):"
        printf '  %s\n' "${to_install[@]}"
        echo "Installing missing packages (weak deps disabled)..."
        dnf --setopt=install_weak_deps=False install -y "${to_install[@]}"
    else
        echo "No packages to install."
    fi

    echo "Import complete."
}

main() {
    require_cmd dnf

    local operation=""
    local path=""

    # Parse options
    while getopts ":o:p:h" opt; do
        case "$opt" in
            o) operation=$OPTARG ;;
            p) path=$OPTARG ;;
            h) usage; exit 0 ;;
            :) die "Option -$OPTARG requires an argument" ;;
            \?) die "Unknown option: -$OPTARG" ;;
        esac
    done
    shift $((OPTIND - 1))

    if (( EUID != 0 )); then
        die "Root privileges required. Run as root or via sudo."
    fi

    [[ -n "$operation" ]] || { usage; die "Missing -o <export|import>"; }
    [[ -n "$path" ]]      || { usage; die "Missing -p <file>"; }

    case "$operation" in
        export) export_pkgs "$path" ;;
        import) import_pkgs "$path" ;;
        *) usage; die "Invalid operation: '$operation' (must be 'export' or 'import')" ;;
    esac
}

main "$@"
