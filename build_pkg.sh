# Bash functions for building Mac installer packages.
#
# 1. Declare the following variables:
#
#   declare -r PKGTITLE="Example Package"
#   declare -r PKGNAME="Example"
#   declare -r PKGVERSION="1.0"
#   declare -r PKGID="com.example.$PKGNAME.pkg"
#
# 2. Source this file:
#
#   source build_pkg.sh
#
# 3. Copy your payload into "$buildroot", setting modes and ownership as
#    needed:
#
#   cp -rp example_payload/* "$buildroot"
#   with_sudo chown -hR root:wheel "$buildroot"
#
# 4. Build package, passing extra args to PackageMaker as needed (e.g.
#    --scripts --info --resources):
#
#   build_pkg --scripts my_install_script_folder


# Print message and exit.
error_exit() {
    echo "${1:-"Unknown Error"}" 1>&2
    exit ${2:-1}
}

declare -r PKGFILE=`date +"$PKGNAME-$PKGVERSION-%Y%m%d.pkg"`
declare -r PKGTARGET="10.5"
declare -a CLEANED_XATTRS=( \
    "com.apple.FinderInfo" \
    "com.apple.Preview.UIstate.v1" \
    "com.apple.TextEncoding" \
    "com.apple.metadata:kMDItemDownloadedDate" \
    "com.apple.metadata:kMDItemWhereFroms" \
    "com.apple.quarantine" \
    "com.dropbox.attributes" \
    "com.macromates.caret" \
)

echo
echo "Packaging $PKGTITLE ($PKGID $PKGVERSION) as"
echo "$PKGFILE"
echo 


# Remove old package.
rm -f "$PKGFILE"

# Give sudo a nice prompt.
with_sudo() {
    sudo -p 'Password for %p@%h: ' "$@"
}

# Find packagemaker binary.
PACKAGEMAKER=""
if [ -e "/Developer/usr/bin/packagemaker" ]; then
    PACKAGEMAKER="/Developer/usr/bin/packagemaker"
else
    while read path; do
        if [ -e "$path/Contents/MacOS/PackageMaker" ]; then
            PACKAGEMAKER="$path/Contents/MacOS/PackageMaker"
            break
        fi
    done < <(mdfind "(kMDItemCFBundleIdentifier == com.apple.PackageMaker)")
fi
test -z "$PACKAGEMAKER" && error_exit "PackageMaker not found"

# Create a temporary root for building.
buildroot=`mktemp -d -t $PKGNAME`
# Remove root on exit.
remove_buildroot() {
    with_sudo rm -rf "$buildroot"
    return 0
}
trap remove_buildroot EXIT


# Clean common cruft that we don't want in the package.
clean_buildroot() {
    echo "* Cleaning buildroot"
    with_sudo find "$buildroot" -name .DS_Store -print0 | with_sudo xargs -0 rm -f
    with_sudo find "$buildroot" -name .svn -print0 | with_sudo xargs -0 rm -rf
    with_sudo find "$buildroot" -name .git -print0 | with_sudo xargs -0 rm -rf
    for attr in "${CLEANED_XATTRS[@]}"; do
        with_sudo xattr -r -d "$attr" "$buildroot"
    done
    return 0
}


# Build the package.
build_pkg() {
    clean_buildroot
    
    echo "* Fixing permissions"
    with_sudo ./copymodes / "$buildroot"
    
    echo "* Creating package $PKGFILE"
    with_sudo "$PACKAGEMAKER" \
        --root "$buildroot" \
        --id "$PKGID" \
        --title "$PKGTITLE" \
        --version "$PKGVERSION" \
        --target $PKGTARGET \
        --no-recommend \
        --no-relocate \
        --out "$PKGFILE" \
        "$@" || error_exit "PackageMaker failed with exit code $?"
    
    gid=$(id -g "$USER")
    with_sudo chown $USER:"$gid" "$PKGFILE"
    
    echo "* Done"
    echo
    return 0
}
