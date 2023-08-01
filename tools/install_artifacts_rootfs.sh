#
# Copyright 2018, Data61, CSIRO (ABN 41 687 119 230)
# Copyright 2023, UNSW
#
# SPDX-License-Identifier: BSD-2-Clause
#

#!/bin/bash

OUTPUT_NAME=rootfs_out.cpio
OUTPUT_DIR=out

set -e

# @ivanv: this bit needs to be re-done since it's not consistent with the arguments the script
# actually checks for
# instead of --root-install maybe have --install-dir
usage() {
    printf " Usage ./install_artifacts_rootfs.sh"
    printf "\n\t--image=<path to rootfs/initrd file>"
    printf "\n\t--root-install=<location of artifacts to install in rootfs>"
    printf "\n\t[--splitgz --output-image-name=<name of output image> --output-dir=<directory to output files to>]"
    printf "\n"
    exit 1
}

error_exit() {
    printf "$1\n">&2
    exit 1
}

gzip_rootfs_cpio() {
    printf "$(tput setaf 6)$(tput bold)Gzipping rootfs cpio image$(tput sgr0)\n"
    pushd ${OUTPUT_DIR}
    gzip -kf ${OUTPUT_NAME}
    popd
}

unpack_rootfs_cpio() {
    # printf "$(tput setaf 6)$(tput bold)Unpacking rootfs cpio image: $1$(tput sgr0)\n"

    UNPACK_FILE=`realpath $1`
    echo "Unpacking from '${UNPACK_FILE}' to '${OUTPUT_DIR}/${OUTPUT_NAME}'"

    if [[ "$UNPACK_FILE" = *.gz ]]; then

        gunzip -c ${UNPACK_FILE} > ${OUTPUT_DIR}/${OUTPUT_NAME}

        # printf "$(tput setaf 6)$(tput bold)Unzipped gz image to ${GUNZIP_FILE}$(tput sgr0)\n"
    fi
    mkdir -p ${OUTPUT_DIR}/unpack
    pushd ${OUTPUT_DIR}/unpack
    echo ${UNPACK_FILE} ${PWD}
    fakeroot cpio -id --no-preserve-owner --preserve-modification-time < ../${OUTPUT_NAME} || error_exit "$(tput setaf 1)$(tput bold)Unpacking CPIO failed$(tput sgr0)\n"
    popd
}

repack_rootfs_cpio() {
    UNPACK_DIR=`realpath ${OUTPUT_DIR}/unpack`
    printf "$(tput setaf 6)$(tput bold)Repacking rootfs cpio image$(tput sgr0)\n"
    pushd ${UNPACK_DIR}
    find . -print0 | fakeroot cpio --null -H newc -o > ../${OUTPUT_NAME}
    printf "$(tput setaf 6)$(tput bold)Cleaning unpack directory: ${OUTPUT_DIR}/unpack$(tput sgr0)\n"
    cd ..
    rm -r ${UNPACK_DIR}
    popd
}

buildroot_setup() {
    printf "$(tput setaf 6)$(tput bold)Configuring Buildroot rootfs$(tput sgr0)\n"

    printf "$(tput setaf 6)$(tput bold)Installing/Syncing build artifacts into rootfs$(tput sgr0)\n"
    if [[ -n "$INSTALL_DIR" && ! -d $INSTALL_DIR ]]; then
        printf "Given --install-dir option '$INSTALL_DIR' needs to be a directory\n"
        exit 1
    elif [[ -n "$INSTALL_FILE" && ! -f $INSTALL_FILE ]]; then
        printf "Given --install-file option '$INSTALL_FILE' needs to be a file\n"
        exit 1
    fi

    # rsync -a ${INSTALL_DIR}/ ${OUTPUT_DIR}/unpack
    rsync -a ${INSTALL_FILE} ${OUTPUT_DIR}/unpack
}

for arg in "$@"
do
    case $arg in
        -i=*|--image=*)
        IMAGE="${arg#*=}"
        shift
        ;;
        -d=*|--install-dir=*)
        INSTALL_DIR="${arg#*=}"
        shift
        ;;
        -f=*|--install-file=*)
        INSTALL_FILE="${arg#*=}"
        shift
        ;;
        -o=*|--output-image-name=*)
        OUTPUT_NAME="${arg#*=}"
        shift
        ;;
        -p=*|--output-dir=*)
        OUTPUT_DIR="${arg#*=}"
        shift
        ;;
        -z|--gzip)
        ZIP=YES
        shift
        ;;
        *)
            printf "Unknown argument: ${arg}\n"
            usage
        ;;
    esac
done

if [ -z "$IMAGE" ] || [ -z "$INSTALL_DIR" && -z "$INSTALL_FILE" ]; then
    usage
fi

printf "IMAGE=${IMAGE}\n"

mkdir -p ${OUTPUT_DIR}

CPIO=${IMAGE}

unpack_rootfs_cpio ${CPIO} ${OUTPUT_NAME}
buildroot_setup
repack_rootfs_cpio

if [ -n "$ZIP" ]; then
    gzip_rootfs_cpio
fi

OUTPUT=`pwd`/${OUTPUT_DIR}/rootfs_out.cpio

printf ${OUTPUT}
