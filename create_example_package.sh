#!/bin/bash


# Declare package variables.
declare -r PKGTITLE="Policy Banner Example"
declare -r PKGNAME="PolicyBannerExample"
declare -r PKGVERSION="1.0"
declare -r PKGID="com.example.$PKGNAME.pkg"
declare -r PKGSCRIPTS=scripts

# Include build functions.
source build_pkg.sh

# Create payload in "$buildroot".
echo "* Copying data"
cp -rp payload_root/* "$buildroot"
echo "* Setting owner"
with_sudo chown -hR root:wheel "$buildroot"

# Build package.
build_pkg --scripts "$PKGSCRIPTS"
