#!/bin/bash

# Script to update PPA files after adding a new .deb package

# Check if dpkg-scanpackages and apt-ftparchive are installed
if ! command -v dpkg-scanpackages &> /dev/null || ! command -v apt-ftparchive &> /dev/null; then
    echo "Please install dpkg-scanpackages and apt-ftparchive."
    exit 1
fi

# Array of PPAs to update
PPAS=("var" "var-ti" "var-nxp" "am62x-var-som")

# Array of releases
RELEASES=("bookworm" "trixie")

# Function to organize deb files into pool by first letter
organize_debs_into_pool() {
    local SOURCE_DIR="$1"
    local POOL_DIR="$2"

    # Copy deb files to pool directory organized by first letter of package name
    for DEB_FILE in "$SOURCE_DIR"/*.deb; do
        if [ -f "$DEB_FILE" ]; then
            PACKAGE_NAME=$(dpkg-deb --field "$DEB_FILE" Package)
            FIRST_LETTER="${PACKAGE_NAME:0:1}"
            POOL_SUBDIR="$POOL_DIR/$FIRST_LETTER/$PACKAGE_NAME"
            mkdir -p "$POOL_SUBDIR"
            cp "$DEB_FILE" "$POOL_SUBDIR/"
        fi
    done
}

# Function to clean up deb files after organizing
cleanup_debs() {
    local SOURCE_DIR="$1"
    rm -f "$SOURCE_DIR"/*.deb
}

# Loop through each PPA in the array
for PPA in "${PPAS[@]}"; do
    PPA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$PPA"

    # Check if PPA directory exists
    if [ ! -d "$PPA_DIR" ]; then
        echo "PPA directory $PPA_DIR does not exist, skipping..."
        continue
    fi

    # Create dists and pool directories if they don't exist
    mkdir -p "$PPA_DIR/dists"
    mkdir -p "$PPA_DIR/pool"

    # Loop through each release
    for RELEASE in "${RELEASES[@]}"; do
        DIST_DIR="$PPA_DIR/dists/$RELEASE"
        POOL_DIR="$PPA_DIR/pool/"
        POOL_RELEASE_DIR="$PPA_DIR/pool/$RELEASE"

        # Create directories for each release in dists and pool
        mkdir -p "$DIST_DIR/main/binary-arm64"
        mkdir -p "$POOL_RELEASE_DIR"

        # Organize deb files into pool for all releases
        organize_debs_into_pool "$POOL_DIR" "$POOL_RELEASE_DIR"

        # Organize deb files in the specific release directory into pool
        organize_debs_into_pool "$POOL_RELEASE_DIR" "$POOL_RELEASE_DIR"
        cleanup_debs "$POOL_RELEASE_DIR"

        # Change to the ppa directory for dpkg-scanpackages
        cd "$PPA_DIR" || exit 1

        # Generate Packages and Packages.gz files
        echo "Generating Packages and Packages.gz for $RELEASE in $POOL_RELEASE_DIR..."
        dpkg-scanpackages --multiversion "pool/$RELEASE" > "$DIST_DIR/main/binary-arm64/Packages"
        gzip -k -f "$DIST_DIR/main/binary-arm64/Packages"

        # Generate Release file with necessary metadata
        echo "Generating Release file for $RELEASE in $DIST_DIR..."
        apt-ftparchive release -o APT::FTPArchive::Release::Origin="Variscite" \
                               -o APT::FTPArchive::Release::Label="Variscite" \
                               -o APT::FTPArchive::Release::Suite="$RELEASE" \
                               -o APT::FTPArchive::Release::Codename="$RELEASE" \
                               -o APT::FTPArchive::Release::Architectures="arm64" \
                               -o APT::FTPArchive::Release::Components="main" \
                               -o APT::FTPArchive::Release::Description="Variscite $PPA packages for $RELEASE" \
                               "$DIST_DIR" > "$DIST_DIR/Release"

        echo "PPA files updated successfully for $RELEASE in $PPA_DIR."
        cd -
    done
    cleanup_debs "$POOL_DIR"
done
