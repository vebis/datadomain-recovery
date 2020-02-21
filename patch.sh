#!/bin/bash

LOCALDIR="$(dirname $(readlink -f $0))"

SAVE_DD_DISK=/dev/sdd1

test -b ${SAVE_DD_DISK} || (echo "${SAVE_DD_DISK} is not a block device. Abort!"; exit 1)

echo "boot partition: ${SAVE_DD_DISK}"

MNT_TARGET="$(mktemp -d)"

mkdir -p ${MNT_TARGET}

mount ${SAVE_DD_DISK} ${MNT_TARGET} 2>/dev/null

echo "mounted boot partition at: ${MNT_TARGET}"

INITRD="${MNT_TARGET}$(grep initrd ${MNT_TARGET}/grub/grub.conf | awk '{ print $2; }' | sort | uniq | head -1)"

test -e ${INITRD} || (echo "initrd ${INITRD} not a file. Abort!"; exit 1)

echo "active initrd: ${INITRD}"

WDIR="$(mktemp -d)"

rm -rf ${WDIR}; mkdir -p ${WDIR}

echo "using working directory: ${WDIR}" 

INITRD_UNPACK="${WDIR}/initrd_unpack"

mkdir -p ${INITRD_UNPACK}

OLDPWD=$(pwd)
cd ${INITRD_UNPACK}

echo "unpacking initrd"
zcat ${INITRD} | cpio -idmv >/dev/null 2>&1

echo "apply available patches"
for p in $(ls ${LOCALDIR}/initrd-patch/*.patch); do
	echo "applying patch $p"
	patch -p1 < $p
done

echo "packing initrd"
NEWINITRD="${WDIR}/initrd"

find . | cpio --create --format='newc' | gzip -9 > ${NEWINITRD}
test -f ${NEWINITRD} || (echo "Could not find new initrd at ${NEWINITRD}. Abort!"; exit 1)

BACKPDIR="${LOCALDIR}/backup.$(date +%s)"
mkdir "${BACKPDIR}"
cp "${INITRD}" "${BACKUPDIR}/initrd.original"
cp "${NEWINITRD}" "${BACKUPDIR}/initrd.patched"
cd "${BACKPDIR}" && sync

umount "${MNT_TARGET}"

cd ${OLDPWD}
for dev in $(ls /dev/sd*1); do
	umount "${MNT_TARGET}" >/dev/null 2>&1
	mount $dev "${MNT_TARGET}" 2>/dev/null || continue
	test -e "${INITRD}" || continue

	cd "${MNT_TARGET}"

	echo "proccessing valid boot partition: $dev"
	cp "${NEWINITRD}" "${INITRD}"

	for p in $(ls ${LOCALDIR}/boot-patch/*.patch); do
		patch -p1 < $p >/dev/null
	done

	cd "${OLDPWD}"
	
	umount "${MNT_TARGET}" >/dev/null 2>&1
done

echo "Finished"

exit 0
