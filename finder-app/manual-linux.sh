#!/bin/bash
# Script outline to install and build kernel.
# Author: Siddhant Jajoo.

set -e
set -u


OUTDIR=/tmp/aeld
KERNEL_REPO=git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
KERNEL_VERSION=v5.1.10
BUSYBOX_VERSION=1_33_1
FINDER_APP_DIR=$(realpath $(dirname $0))
ARCH=arm64
CROSS_COMPILE=aarch64-none-linux-gnu-

if [ $# -lt 1 ]
then
	echo "Using default directory ${OUTDIR} for output"
else
	OUTDIR=$1
	echo "Using passed directory ${OUTDIR} for output"
fi

mkdir -p ${OUTDIR}

if [ ! -d "${OUTDIR}" ]; then  # if $OUTDIR could not be created, then fail
	exit -1
fi

echo "cd ${OUTDIR}"
cd "${OUTDIR}"
if [ ! -d "${OUTDIR}/linux-stable" ]; then
    #Clone only if the repository does not exist.
	echo "CLONING GIT LINUX STABLE VERSION ${KERNEL_VERSION} IN ${OUTDIR}"
	git clone ${KERNEL_REPO} --depth 1 --single-branch --branch ${KERNEL_VERSION}
fi
if [ ! -e ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ]; then
    cd linux-stable
    echo "Checking out version ${KERNEL_VERSION}"
    git checkout ${KERNEL_VERSION}

    # TODO: Add your kernel build steps here

	# "deep clean" the kernel build tree - removing the .config file with any existing configurations
	echo "KERNEL BUILD STEP #1 : \"deep clean\" the kernel build tree..."
	make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} mrproper

	# configure for "virt" arm dev board we will simulate in QEMU
	echo "KERNEL BUILD STEP #2 : configure for \"virt\" arm dev board we will simulate in QEMU..."
	make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig

	# vmlinux
    # fixes dtc parser error multiple declaration of yylloc
	echo "fix dtc parser error multiple declaration of yylloc..."
    if [ "$(grep "YYLTYPE yylloc;" ${OUTDIR}/linux-stable/scripts/dtc/dtc-lexer.l)" != "extern YYLTYPE yylloc;" ]
    then
    	sed -i 's/YYLTYPE yylloc/extern YYLTYPE yylloc/g' ${OUTDIR}/linux-stable/scripts/dtc/dtc-lexer.l
    fi

	# build a kernel image for booting with QEMU
	echo "KERNEL BUILD STEP #3 : build a kernel image for booting with QEMU..."
	make -j4 ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} all

	# build any kernel modules
	echo "KERNEL BUILD STEP #4 : build any kernel modules..."
	make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} modules

	# build the devicetree
	echo "KERNEL BUILD STEP #5 : build the devicetree..."
	make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} dtbs

fi


echo "Adding the Image in outdir"
cp -a "${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image" "${OUTDIR}"

echo "Creating the staging directory for the root filesystem"
cd "$OUTDIR"
if [ -d "${OUTDIR}/rootfs" ]
then
	echo "Deleting rootfs directory at ${OUTDIR}/rootfs and starting over"
    sudo rm  -rf ${OUTDIR}/rootfs
fi

# TODO: Create necessary base directories
echo -e "\nCreating necessary base directories..."
mkdir $OUTDIR/rootfs
cd $OUTDIR/rootfs
mkdir bin dev etc home lib proc sbin sys tmp usr var
mkdir usr/bin usr/lib usr/sbin 
mkdir -p var/log

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/busybox" ]
then
	git clone git://busybox.net/busybox.git
    cd busybox
    git checkout ${BUSYBOX_VERSION}
    # TODO:  Configure busybox
	echo -e "\nConfiguring busybox..."
	make distclean
	make defconfig
else
    cd busybox
fi

# TODO: Make and install busybox
echo -e "\nMake and install busybox..."
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE}
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} CONFIG_PREFIX="${OUTDIR}/rootfs" install

echo -e "\nLibrary dependencies ...\n"
${CROSS_COMPILE}readelf -a busybox | grep "program interpreter"
${CROSS_COMPILE}readelf -a busybox | grep "Shared library"

# TODO: Add library dependencies to rootfs
echo -e "\nAdding library dependencies to rootfs..."
cd "${OUTDIR}/rootfs"
SYSROOT=$(${CROSS_COMPILE}gcc -print-sysroot)
echo -e "\n\nSYSROOT is ${SYSROOT}\n\n"
# ls -l lib/ld-linux-aarch64.so.1

cp $SYSROOT/lib/ld-linux-aarch64.so.1 lib
cp $SYSROOT/lib64/ld-2.31.so lib64

cp $SYSROOT/lib64/libm.so.6 lib64
cp $SYSROOT/lib64/libm-2.31.so lib64

cp $SYSROOT/lib64/libresolv.so.2 lib64
cp $SYSROOT/lib64/libresolv-2.31.so lib64

cp $SYSROOT/lib64/libc.so.6 lib64
cp $SYSROOT/lib64/libc-2.31.so lib64


# TODO: Make device nodes
echo -e "\nMake device nodes..."
cd "$OUTDIR"
sudo mknod -m 666 ${OUTDIR}/rootfs/dev/null c 1 3		# Null device
sudo mknod -m 666 ${OUTDIR}/rootfs/dev/console c 5 1	# console device


# TODO: Clean and build the writer utility
echo -e "\nClean and build the writer utility..."
cd "${FINDER_APP_DIR}"
make clean
make CROSS_COMPILE=${CROSS_COMPILE}	# makes the writer utility


# TODO: Copy the finder related scripts and executables to the /home directory
# on the target rootfs
echo -e "\nCopy the finder related scripts and executables to the /home directory"
echo " on the target rootfs"
DEST=${OUTDIR}/rootfs/home
cp ${FINDER_APP_DIR}/finder.sh ${DEST}
cp ${FINDER_APP_DIR}/finder-test.sh ${DEST}
cp ${FINDER_APP_DIR}/writer ${DEST}
cp ${FINDER_APP_DIR}/writer ${DEST}
cp ${FINDER_APP_DIR}/autorun-qemu.sh ${DEST}
cp ${FINDER_APP_DIR}/dependencies.sh ${DEST}
cp ${FINDER_APP_DIR}/start-qemu-app.sh ${DEST}
cp ${FINDER_APP_DIR}/start-qemu-terminal.sh ${DEST}
cp -rL ${FINDER_APP_DIR}/conf ${DEST}

# TODO: Chown the root directory
echo -e "\nChown the root directory..."
cd "${OUTDIR}/rootfs"
sudo chown -R root:root *

# TODO: Create initramfs.cpio.gz
echo -e "\nCreate initramfs.cpio.gz ..."
cd "${OUTDIR}/rootfs"
find . | cpio -H newc -oV --owner root:root | gzip -9 > "${OUTDIR}/initramfs.cpio.gz"
