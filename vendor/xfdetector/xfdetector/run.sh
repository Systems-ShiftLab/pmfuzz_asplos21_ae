#!/bin/bash
# set -x
RED='\033[0;31m'
GRN='\033[0;32m'
NC='\033[0m' # No Color

usage()
{
    echo ""
    echo "  Usage: ./run.sh WORKLOAD INITSIZE TESTSIZE [PATCH]"
    echo ""
    echo "    WORKLOAD:   The workload to test."
    echo "    INITSIZE:   The number of data insertions when initializing the image. This is for fast-forwarding the initialization."
    echo "    TESTSIZE:   The number of additional data insertions when reproducing bugs with XFDetector."
    echo "    PATCH:      The name of the patch that reproduces bugs for WORKLOAD. If not specified, then we test the original program without bugs."
    echo ""
}

if [[ $1 == "-h" ]]; then
    usage; exit 1
fi

if [[ ${PIN_ROOT} == "" ]]; then
    echo  -e "${RED}Error:${NC} Environment variable PIN_ROOT not set. Please specify the full path." >&2; exit 1
fi


# Workload
WORKLOAD=$1
# Sizes of the workloads on initialization and testing
INITSIZE=$2
TESTSIZE=$3
# patchname
PATCH=$4

# PM Image file
PMIMAGE=/mnt/pmem0/${WORKLOAD}
TEST_ROOT=../


TIMING_OUT=${WORKLOAD}_${TESTSIZE}_time.txt
DEBUG_OUT=${WORKLOAD}_${TESTSIZE}_debug.txt

if ! [[ ${INITSIZE} =~ ^[0-9]+$ ]] ; then
   echo -e "${RED}Error:${NC} Invalid INITSIZE ${INITSIZE}." >&2; usage; exit 1
fi

if ! [[ ${TESTSIZE} =~ ^[0-9]+$ ]] ; then
   echo -e "${RED}Error:${NC} Invalid TESTSIZE ${TESTSIZE}." >&2; usage; exit 1
fi

if [[ ${WORKLOAD} =~ ^(btree|ctree|rbtree)$ ]]; then
    if [[ ${PATCH} != "" && ${PATCH} != "hash" ]]; then
        WORKLOAD_LOC=${TEST_ROOT}/pmdk/src/examples/libpmemobj/tree_map/${WORKLOAD}_map.c
        PATCH_LOC=${TEST_ROOT}/patch/${WORKLOAD}_${PATCH}.patch
        echo "Applying bug patch: ${WORKLOAD}_${PATCH}.patch."
        patch ${WORKLOAD_LOC} < ${PATCH_LOC} || exit 1
    fi
elif [[ ${WORKLOAD} =~ ^(hashmap_atomic|hashmap_tx)$ ]]; then
    if [[ ${PATCH} != "" && ${PATCH} != "hash" ]]; then
        WORKLOAD_LOC=${TEST_ROOT}/pmdk/src/examples/libpmemobj/hashmap/${WORKLOAD}.c
        PATCH_LOC=${TEST_ROOT}/patch/${WORKLOAD}_${PATCH}.patch
        echo "Applying bug patch: ${WORKLOAD}_${PATCH}.patch."
        patch ${WORKLOAD_LOC} < ${PATCH_LOC} || exit 1
    fi
else
    echo -e "${RED}Error:${NC} Invalid workload name ${WORKLOAD}." >&2; usage; exit 1
fi

echo -e "${GRN}Info:${NC} Testing ${WORKLOAD}. Init size = ${INITSIZE}. Test size = ${TESTSIZE}."

# variables to use
PMRACE_EXE=${TEST_ROOT}/xfdetector/build/app/xfdetector
PINTOOL_SO=${TEST_ROOT}/xfdetector/pintool/obj-intel64/pintool.so
if [[ ${WORKLOAD} == "hashmap_atomic" && ${PATCH} != "" ]]; then
	DATASTORE_EXE=${TEST_ROOT}/driver/data_store_hash
else
	DATASTORE_EXE=${TEST_ROOT}/driver/data_store
fi
PIN_EXE=${TEST_ROOT}/pin-3.10/pin

# Generate config file
CONFIG_FILE=${WORKLOAD}_${TESTSIZE}_config.txt
rm -f ${CONFIG_FILE}
echo "PINTOOL_PATH ${PINTOOL_SO}" >> ${CONFIG_FILE}
echo "EXEC_PATH ${DATASTORE_EXE}" >> ${CONFIG_FILE}
echo "PM_IMAGE ${PMIMAGE}" >> ${CONFIG_FILE}
echo "PRE_FAILURE_COMMAND ${DATASTORE_EXE} ${WORKLOAD} ${PMIMAGE} ${TESTSIZE}" >> ${CONFIG_FILE}
echo "POST_FAILURE_COMMAND ${DATASTORE_EXE} ${WORKLOAD} ${PMIMAGE} 2" >> ${CONFIG_FILE}

# Remove old pmimage and fifo files
rm -f /mnt/pmem0/*
rm -f /tmp/*fifo
rm -f /tmp/func_map

echo "Recompiling workload, suppressing make output."
make clean -C ${TEST_ROOT}/pmdk/src/examples -j > /dev/null
make -C ${TEST_ROOT}/pmdk/src/examples EXTRA_CFLAGS="-Wno-error" -j > /dev/null
make clean -C ${TEST_ROOT}/driver > /dev/null
make -C ${TEST_ROOT}/driver > /dev/null

# unapply patch
if [[ ${PATCH} != "" && ${PATCH} != "hash" ]]; then
    echo "Reverting patch: ${WORKLOAD}_${PATCH}.patch."
    patch -R ${WORKLOAD_LOC} < ${PATCH_LOC} || exit 1
fi

MAX_TIMEOUT=600

export PMEM_MMAP_HINT=0x10000000000

# Init the pmImage
if [[ ${INITSIZE} -gt 0 ]]; then
    ${DATASTORE_EXE} ${WORKLOAD} ${PMIMAGE} ${INITSIZE}
fi

# Run realworkload
# Start XFDetector
echo -e "${GRN}Info:${NC} We kill the post program after running some time, so don't panic if you see a process gets killed."
(timeout ${MAX_TIMEOUT} ${PMRACE_EXE} ${CONFIG_FILE} | tee ${TIMING_OUT}) 3>&1 1>&2 2>&3 | tee ${DEBUG_OUT} &
sleep 1
timeout ${MAX_TIMEOUT} ${PIN_EXE} -t ${PINTOOL_SO} -o xfdetector.out -t 1 -f 1 -- ${DATASTORE_EXE} ${WORKLOAD} ${PMIMAGE} ${TESTSIZE} > /dev/null
wait
