#!/bin/bash
#
# Script to generate CUE test files
# Requires Linux with cdrdao

EXIT_SUCCESS=0;
EXIT_FAILURE=1;

# Checks the availability of a binary and exits if not available.
#
# Arguments:
#   a string containing the name of the binary
#
assert_availability_binary()
{
	local BINARY=$1;

	which ${BINARY} > /dev/null 2>&1;
	if test $? -ne ${EXIT_SUCCESS};
	then
		echo "Missing binary: ${BINARY}";
		echo "";

		exit ${EXIT_FAILURE};
	fi
}

assert_availability_binary cdrdao;

set -e;

SPECIMENS_PATH="specimens/cdrdao";

mkdir -p ${SPECIMENS_PATH};

cdrdao read-cd --read-raw --datafile ${SPECIMENS_PATH}/image.bin --device /dev/sr0 ${SPECIMENS_PATH}/image.cue

exit ${EXIT_SUCCESS};

