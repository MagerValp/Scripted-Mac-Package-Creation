Scripted Mac Package Creation
=============================

This is a cleaned up up version of the script I'm using to create packages for internal deployment.

Files:

    build_pkg.sh                Include this in your packaging script.
    copymodes                   Utility to set correct permissions for system directories.

Sample project:

    create_example_package.sh   Run this to create the sample package.
    payload_root                Sample payload.
    scripts                     Dummy postinstall script.

Usage
-----

Declare the following variables:

    declare -r PKGTITLE="Example Package"
    declare -r PKGNAME="Example"
    declare -r PKGVERSION="1.0"
    declare -r PKGID="com.example.$PKGNAME.pkg"

Source this file:

    source build_pkg.sh

Copy your payload into "$buildroot", setting modes and ownership as needed:

    cp -rp my_payload/* "$buildroot"
    with_sudo chown -hR root:wheel "$buildroot"

Build package, passing extra args to PackageMaker as needed (e.g. --scripts --info --resources):

    build_pkg --scripts my_install_script_folder
