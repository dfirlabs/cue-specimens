#!/bin/bash
#
# Script to generate CUE test files
# Requires Linux with cdrdao

EXIT_SUCCESS=0
EXIT_FAILURE=1

# Checks the availability of a binary and exits if not available.
#
# Arguments:
#   a string containing the name of the binary
#
assert_availability_binary()
{
	local BINARY=$1

	which ${BINARY} > /dev/null 2>&1
	if test $? -ne ${EXIT_SUCCESS}
	then
		echo "Missing binary: ${BINARY}"
		echo ""

		exit ${EXIT_FAILURE}
	fi
}

# Creates test file entries.
#
# Arguments:
#   a string containing the mount point of the image file
#
create_test_file_entries()
{
	MOUNT_POINT=$1

	# Create an empty file
	touch ${MOUNT_POINT}/emptyfile

	# Create a directory
	mkdir ${MOUNT_POINT}/testdir1

	# Create a file that can be stored as inline data
	echo "My file" > ${MOUNT_POINT}/testdir1/testfile1

	# Create a file that cannot be stored as inline data
	cp LICENSE ${MOUNT_POINT}/testdir1/TestFile2

	# Create a hard link to a file
	ln ${MOUNT_POINT}/testdir1/testfile1 ${MOUNT_POINT}/file_hardlink1

	# Create a symbolic link to a file
	ln -s ${MOUNT_POINT}/testdir1/testfile1 ${MOUNT_POINT}/file_symboliclink1

	# Create a hard link to a directory
	# ln: hard link not allowed for directory

	# Create a symbolic link to a directory
	ln -s ${MOUNT_POINT}/testdir1 ${MOUNT_POINT}/directory_symboliclink1

	# Create a file with an UTF-8 NFC encoded filename
	touch `printf "${MOUNT_POINT}/nfc_t\xc3\xa9stfil\xc3\xa8"`

	# Create a file with an UTF-8 NFD encoded filename
	touch `printf "${MOUNT_POINT}/nfd_te\xcc\x81stfile\xcc\x80"`

	# Create a file with an UTF-8 NFD encoded filename
	touch `printf "${MOUNT_POINT}/nfd_\xc2\xbe"`

	# Create a file with an UTF-8 NFKD encoded filename
	touch `printf "${MOUNT_POINT}/nfkd_3\xe2\x81\x844"`

	# Create a file with an extended attribute
	touch ${MOUNT_POINT}/testdir1/xattr1
	setfattr -n "user.myxattr1" -v "My 1st extended attribute" ${MOUNT_POINT}/testdir1/xattr1

	# Create a directory with an extended attribute
	mkdir ${MOUNT_POINT}/testdir1/xattr2
	setfattr -n "user.myxattr2" -v "My 2nd extended attribute" ${MOUNT_POINT}/testdir1/xattr2

	# Create a file with an initial (implict) sparse extent
	truncate -s $(( 1 * 1024 * 1024 )) ${MOUNT_POINT}/testdir1/initial_sparse1
	echo "File with an initial sparse extent" >> ${MOUNT_POINT}/testdir1/initial_sparse1

	# Create a file with a trailing (implict) sparse extent
	echo "File with a trailing sparse extent" > ${MOUNT_POINT}/testdir1/trailing_sparse1
	truncate -s $(( 1 * 1024 * 1024 )) ${MOUNT_POINT}/testdir1/trailing_sparse1

	# Create a file with an uninitialized extent
	fallocate -x -l 4096 ${MOUNT_POINT}/testdir1/uninitialized1
	echo "File with an uninitialized extent" >> ${MOUNT_POINT}/testdir1/uninitialized1
}

# Creates a test image file.
#
# Arguments:
#   a string containing the path of the image file
#   an integer containing the size of the image file
#   an integer containing the sector size
#   an array containing the arguments for mke2fs
#
create_test_image_file()
{
	IMAGE_FILE=$1
	IMAGE_SIZE=$2
	SECTOR_SIZE=$3
	shift 3
	local ARGUMENTS=("$@")

	dd if=/dev/zero of=${IMAGE_FILE} bs=${SECTOR_SIZE} count=$(( ${IMAGE_SIZE} / ${SECTOR_SIZE} )) 2> /dev/null

	# Notes:
	# -N #  the minimum number of inodes seems to be 16
	mke2fs -q ${ARGUMENTS[@]} ${IMAGE_FILE}
}

# Creates a test image file with file entries.
#
# Arguments:
#   a string containing the path of the image file
#   an integer containing the size of the image file
#   an integer containing the sector size
#   an array containing the arguments for mke2fs
#
create_test_image_file_with_file_entries()
{
	IMAGE_FILE=$1
	IMAGE_SIZE=$2
	SECTOR_SIZE=$3
	shift 3
	local ARGUMENTS=("$@")

	create_test_image_file ${IMAGE_FILE} ${IMAGE_SIZE} ${SECTOR_SIZE} ${ARGUMENTS[@]}

	sudo mount -o loop,rw ${IMAGE_FILE} ${MOUNT_POINT}

	sudo chown ${USERNAME} ${MOUNT_POINT}

	create_test_file_entries ${MOUNT_POINT}

	sudo umount ${MOUNT_POINT}
}

assert_availability_binary cdrdao
assert_availability_binary dd
assert_availability_binary fallocate
assert_availability_binary mke2fs
assert_availability_binary modprobe
assert_availability_binary setfattr
assert_availability_binary targetcli
assert_availability_binary truncate

set -e

VERSION=$( cdrdao 2>&1 | head -n 1 | sed 's/Cdrdao version \(\S*\) .*/\1/' )

SPECIMENS_PATH="specimens/cdrdao-${VERSION}"

mkdir -p ${SPECIMENS_PATH}

set -e

USERNAME=$( whoami )

MOUNT_POINT="/mnt/ext"

sudo mkdir -p ${MOUNT_POINT}

set +e

sudo modprobe target_core_mod 
if test $? -ne 0
then
	echo "Missing kernel target_core_mod support"
else
	# Create an ext2 file system without a journal
	IMAGE_FILE="${SPECIMENS_PATH}/ext2.raw"
	IMAGE_SIZE=$(( 4096 * 1024 ))

	create_test_image_file_with_file_entries "${IMAGE_FILE}" $(( 4096 * 1024 )) 512 "-L ext2_test" "-t ext2"

	sudo targetcli <<EOT
/backstores/fileio create name=cd_image file_or_dev=${IMAGE_FILE}
/loopback create wwn=naa.5001405b8504f669
/loopback/naa.5001405b8504f669/tpg1/luns create /backstores/fileio/cd_image
EOT

	cdrdao read-cd --datafile ${SPECIMENS_PATH}/image.bin --device /dev/sr0 --driver generic-mmc --read-raw ${SPECIMENS_PATH}/image.cue

	rm -f ${IMAGE_FILE}
fi

exit ${EXIT_SUCCESS}
