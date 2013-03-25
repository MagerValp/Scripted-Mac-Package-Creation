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

# Remove temp dirs on exit.
declare -a tempdirs
remove_tempdirs() {
    for tempdir in "${tempdirs[@]}"; do
        with_sudo rm -rf "$tempdir"
    done
    return 0
}
trap remove_tempdirs EXIT


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
declare -r BUILD_TOOL="${BUILD_TOOL:-pkgbuild}" 2>/dev/null
declare -r OWNERSHIP="${OWNERSHIP:-preserve}" 2>/dev/null

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

if [[ "$BUILD_TOOL" == "packagemaker" ]]; then
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
fi

# Create a temporary root for building.
buildroot=`mktemp -d -t $PKGNAME`
tempdirs+=("$buildroot")


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
#
# Optional args:
#   --scripts path          Dir with preinstall and postinstall scripts.
build_pkg() {
    
    clean_buildroot
    
    echo "* Fixing permissions"
    with_sudo ./copymodes / "$buildroot"
    
    case "$BUILD_TOOL" in
        "packagemaker")
            echo "* Creating package $PKGFILE with PackageMaker"
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
        ;;
        
        "pkgbuild")
            echo "* Creating package $PKGFILE with productbuild"
            
            # Create a temporary for packaging.
            pkgroot=`mktemp -d -t $PKGNAME`
            tempdirs+=("$pkgroot")
            
            echo "Analyzing build root"
            compplist="$pkgroot/component.plist"
            pkgbuild --analyze --root "$buildroot" "$compplist" || error_exit "analyze failed with exit code $?"
            declare -i count=0
            while /usr/libexec/PlistBuddy -c "Set :$count:BundleIsRelocatable false" "$compplist" 2>/dev/null; do
                /usr/libexec/PlistBuddy -c "Print :$count:RootRelativeBundlePath" "$compplist"
                let count++
            done
            
            echo "Creating component package with pkgbuild"
            compfile="$pkgroot/$PKGNAME-$PKGVERSION.pkg"
            pkgbuild \
                --root "$buildroot" \
                --component-plist "$compplist" \
                --identifier "$PKGID" \
                --version "$PKGVERSION" \
                --install-location "/" \
                --ownership "$OWNERSHIP" \
                "$@" \
                "$compfile" || error_exit "pkgbuild failed with exit code $?"
            
            echo "Synthesizing distribution"
            distfile="$pkgroot/Distribution"
            productbuild --synthesize --package "$compfile" "$distfile" || error_exit "synthesize failed with exit code $?"
            # productbuild doesn't let you specify the package title, so the
            # Distribution file needs to be modified and have a title node
            # added. xsltproc can do it for us, but I really hope there is a
            # simple way...
            add_title="$pkgroot/AddTitle.xslt"
            cat > "$add_title" <<EOF
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:xalan="http://xml.apache.org/xalan" version="1.0">
    <xsl:template match="@* | node()">
        <xsl:copy>
            <xsl:apply-templates select="@* | node()" />
        </xsl:copy>
    </xsl:template>

    <xsl:template match="installer-gui-script">
        <xsl:copy>
            <xsl:apply-templates select="@* | node()" />
            <title>$PKGTITLE</title>
        </xsl:copy>
    </xsl:template>
</xsl:stylesheet>
EOF
            tmpdist="$pkgroot/Distribution.tmp"
            xsltproc --output "$tmpdist" "$add_title" "$distfile"
            # Clean it up with xmllint and put it back.
            xmllint --output "$distfile" --format "$tmpdist"
            
            echo "Creating distribution with productbuild"
            productbuild \
                --distribution "$distfile" \
                --package-path "$pkgroot" \
                "$PKGFILE" || error_exit "productbuild failed with exit code $?"
        ;;
        
        *)
            error_exit "Unknown build tool $BUILD_TOOL"
        ;;
    esac
    
    echo "* Done"
    echo
    return 0
}
