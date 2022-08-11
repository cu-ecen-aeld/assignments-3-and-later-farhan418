#!/bin/bash
# Script outline to install and build kernel.
# Author: Siddhant Jajoo.

set -e
set -u

OUTDIR=/tmp/aeld
KERNEL_REPO=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
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

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/linux" ]; then
    #Clone only if the repository does not exist.
	echo "CLONING GIT LINUX STABLE VERSION ${KERNEL_VERSION} IN ${OUTDIR}"
	git clone ${KERNEL_REPO} --depth 1 --single-branch --branch ${KERNEL_VERSION}
fi
if [ ! -e ${OUTDIR}/linux/arch/${ARCH}/boot/Image ]; then
    cd linux
    echo "Checking out version ${KERNEL_VERSION}"
    git checkout ${KERNEL_VERSION}

    # TODO: Add your kernel build steps here

	# "deep clean" the kernel build tree - removing the .config file with any existing configurations
	make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE}mrproper

	# configure for "virt" arm dev board we will simulate in QEMU
	make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE}defconfig

	# build a kernel image for booting with QEMU
	make -j4 ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE}all

	# build any kernel modules
	make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE}modules

	# build the devicetree
	make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE}dtbs

fi

cd "$OUTDIR"
# adding the modules we built during the kernel build step into our rootfs image
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE}modules_install INSTALL_MOD_PATH=${OUTDIR}/rootfs

echo "Adding the Image in outdir"
mv linux Image # renaming the 'linux' kernel directory to 'Image'

echo "Creating the staging directory for the root filesystem"
cd "$OUTDIR"
if [ -d "${OUTDIR}/rootfs" ]
then
	echo "Deleting rootfs directory at ${OUTDIR}/rootfs and starting over"
    sudo rm  -rf ${OUTDIR}/rootfs
fi

# TODO: Create necessary base directories
mkdir $OUTDIR/rootfs
cd $OUTDIR/rootfs
mkdir bin dev etc home lib proc sbin sys tmp usr var
mkdir usr/bin usr/lib usr/sbin var/log

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/busybox" ]
then
	git clone git://busybox.net/busybox.git
    cd busybox
    git checkout ${BUSYBOX_VERSION}
    # TODO:  Configure busybox
	make distclean
	make defconfig
else
    cd busybox
fi

# TODO: Make and install busybox
sudo make ARCH=arm CROSS_COMPILE=arm-unknown-linux-gnueabi-install

echo "Library dependencies"
${CROSS_COMPILE}readelf -a bin/busybox | grep "program interpreter"
${CROSS_COMPILE}readelf -a bin/busybox | grep "Shared library"

# TODO: Add library dependencies to rootfs
arm-unknown-linux-gnueabi-gcc -print-sysroot
cd $SYSROOT
ls -l lib/ld-linux-armhf.so.3

cd $OUTDIR/rootfs
cp -a $SYSROOT/lib/ld-linux-armhf.so.3 lib
cp -a $SYSROOT/lib/ld-2.22.so lib
cp -a $SYSROOT/lib/libc.so.6 lib
cp -a $SYSROOT/lib/libc-2.22.so lib
cp -a $SYSROOT/lib/libm.so.6 lib
cp -a $SYSROOT/lib/libm-2.22.so lib


# TODO: Make device nodes
cd "$OUTDIR"
sudo mknod -m 666 dev/null c 1 3 # Null device
sudo mknod -m 666 dev/tty c 5 1	 # console device


# TODO: Clean and build the writer utility
cd ${FINDER_APP_DIR}
make clean
make CROSS_COMPILE=aarch64-none-linux-gcc	# makes the writer utility

# TODO: Copy the finder related scripts and executables to the /home directory
# on the target rootfs
DEST=${OUTDIR}/rootfs/home
cp ${FINDER_APP_DIR}/finder.sh ${DEST}
cp ${FINDER_APP_DIR}/finder-test.sh ${DEST}
cp ${FINDER_APP_DIR}/writer ${DEST}
cp ${FINDER_APP_DIR}/autorun-qemu.sh ${DEST}
cp ${FINDER_APP_DIR}/dependencies.sh ${DEST}
cp ${FINDER_APP_DIR}/start-qemu-app.sh ${DEST}
cp ${FINDER_APP_DIR}/start-qemu-terminal.sh ${DEST}
cp ${FINDER_APP_DIR}/conf/username.txt ${DEST}

# TODO: Chown the root directory
cd $OUTDIR/rootfs
sudo chown -R root:root *

# TODO: Create initramfs.cpio.gz
cd "$OUTDIR"
find ${OUTDIR}/rootfs -depth -print0 | cpio -ocv0 | gzip -9 > initramfs.cpio.gz
