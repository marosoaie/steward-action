#!/usr/bin/env bash
# Puts a Swift toolchain on PATH, and writes `key`, a hash of the build's
# environment for the build cache's key, to GITHUB_OUTPUT.
#
# On Linux, SWIFT_VERSION (such as 6.2 or 6.2.1) is installed with swiftly,
# swift.org's installer, unless the runner's Swift is that version already.
# Without it, the runner's Swift is used, and the latest release is
# installed only when there's none. On macOS, the selected Xcode's Swift
# is used.
set -euo pipefail

version=${SWIFT_VERSION:-}

fail() {
    echo "::error title=Steward::$1"
    exit 1
}

[[ $version =~ ^[A-Za-z0-9._-]*$ ]] || fail "swift-version is a version such as 6.2 or 6.2.1, not \"$version\"."

# Whether `swift` is on PATH, and is SWIFT_VERSION when that's set: 6.2
# matches "Swift version 6.2.1 (swift-6.2.1-RELEASE)", and 6.2.0 matches
# "Swift version 6.2", as 6.2.0 reports itself, but not 6.2.1.
has_swift() {
    command -v swift >/dev/null || return 1
    [ -n "$version" ] || return 0
    local installed pattern
    installed=$(swift --version 2>&1) || return 1
    if [[ $version =~ ^([0-9]+\.[0-9]+)\.0$ ]]; then
        pattern="${BASH_REMATCH[1]//./\\.}(\\.0)?( |$)"
    else
        pattern="${version//./\\.}([. ]|$)"
    fi
    grep -Eq "Swift version $pattern" <<<"$installed"
}

install_swift() {
    local toolchain=$1 work arch location
    work=$(mktemp -d "${RUNNER_TEMP:-/tmp}/swiftly.XXXXXX")
    arch=$(uname -m)
    echo "Installing Swift $toolchain with swiftly."
    curl -fsSL --retry 3 -o "$work/swiftly.tar.gz" "https://download.swift.org/swiftly/linux/swiftly-$arch.tar.gz"
    curl -fsSL --retry 3 -o "$work/swiftly.tar.gz.sig" "https://download.swift.org/swiftly/linux/swiftly-$arch.tar.gz.sig"
    # --compressed: swift.org's CDN can answer with a gzip-encoded copy even
    # when it wasn't asked for one.
    curl -fsSL --retry 3 --compressed -o "$work/keys.asc" https://www.swift.org/keys/all-keys.asc
    # swiftly verifies the toolchains it downloads; this verifies swiftly.
    export GNUPGHOME="$work/gnupg"
    mkdir -m 700 "$GNUPGHOME"
    gpg --batch --quiet --import "$work/keys.asc"
    gpg --batch --quiet --verify "$work/swiftly.tar.gz.sig" "$work/swiftly.tar.gz" ||
        fail "swiftly's download doesn't match its signature."
    tar -xzf "$work/swiftly.tar.gz" -C "$work"
    # Outside the checkout: `swiftly install --use` writes a .swift-version
    # file at the root of the git repository it runs in.
    cd "$work"
    ./swiftly init --assume-yes --skip-install --quiet-shell-followup --no-modify-profile
    # shellcheck source=/dev/null
    . "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh"
    swiftly install --use --assume-yes --post-install-file="$work/post-install.sh" "$toolchain"
    if [ -s "$work/post-install.sh" ]; then
        echo "The toolchain needs these system packages first:"
        cat "$work/post-install.sh"
        if [ "$(id -u)" = 0 ]; then
            as_root=()
        elif command -v sudo >/dev/null; then
            as_root=(sudo)
        else
            fail "Swift $toolchain needs system packages, and this job can't install them: see the log."
        fi
        # The script installs with apt-get without updating its index, which
        # a runner image's can be too old for.
        if grep -q apt-get "$work/post-install.sh"; then
            ${as_root[@]+"${as_root[@]}"} apt-get update -qq
        fi
        ${as_root[@]+"${as_root[@]}"} bash "$work/post-install.sh"
    fi
    # The toolchain's own directory, not swiftly's `swift`, which would
    # follow a .swift-version file in the checkout to another toolchain.
    location=$(swiftly use --print-location)
    cd - >/dev/null
    export PATH="$location/usr/bin:$PATH"
    echo "$location/usr/bin" >>"$GITHUB_PATH"
}

case "$(uname -s)" in
Linux)
    # Not `has_swift || install_swift`: a function called on the right of
    # `||` runs with errexit off.
    if ! has_swift; then
        install_swift "${version:-latest}"
        # What swiftly installed is the version asked for, whatever it
        # calls itself, such as a snapshot.
        version=
    fi
    ;;
Darwin)
    [ -z "$version" ] ||
        fail "swift-version is for Linux runners. On macOS, select the Xcode whose Swift to use, with xcode-select or DEVELOPER_DIR."
    ;;
*)
    fail "Steward runs on Linux and macOS runners, and this one runs $(uname -s)."
    ;;
esac

has_swift || fail "There's no Swift ${version:-toolchain} on PATH."

# What a build directory depends on besides the package: the toolchain, the
# OS release, such as a container's rather than the runner's, and the
# workspace's path, which SwiftPM records in it.
environment() {
    swift --version 2>&1
    if [ -f /etc/os-release ]; then cat /etc/os-release; else sw_vers; fi
    echo "$GITHUB_WORKSPACE"
}

swift --version
echo "key=$(environment | git hash-object --stdin | cut -c1-16)" >>"$GITHUB_OUTPUT"
