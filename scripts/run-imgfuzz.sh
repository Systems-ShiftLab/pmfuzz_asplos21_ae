#!/usr/bin/env bash

set -e

ABSOLUTE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
DIR="$(dirname $(dirname ${ABSOLUTE_PATH}))"

wrkld="$1"
dest="$2"

function GetFuzzerName {
    if [ "$iter" = "0" ]; then
        echo "-M master_fuzzer"
    else
        echo "-S slave_fuzzer_$iter"
    fi
}

function Setup {
    ps -eaf | egrep '(pmfuzz)|(afl-fuzz)|mapcli|memcached' \
        | grep -v grep | awk '{print $2}' \
        | xargs kill -9 $1 >/dev/null 2>&1 || { :; }

    pkill afl-fuzz || { :; }
    kill_pid=$(ps -eaf | egrep 'imgfuzz' | grep -v grep | grep -vP $USER'[[:space:]]+'$$ | awk '{print $2}')
    if [ ! -z "$kill_ppid" ]; then
	    { kill -9 $kill_pid; } || { :; }
	fi

    local wrkld="$1"

    if [ "$#" != "2" ]; then
        echo "Usage: $0 workload dest"
        exit 1
    fi


    if [ -d "/mnt/pmem0/$wrkld" ]; then
        echo "Deleting directory '/mnt/pmem0/$wrkld'"
        rm -r "/mnt/pmem0/$wrkld"
    fi

    indir="/mnt/pmem0/$wrkld"
    
    set -o xtrace
    
    # Create the input directory
    mkdir -p "${indir}"

    echo "Extracting empty image to ${indir}"
    tar xzf "${DIR}/inputs/pool_imgs/${wrkld}.pool.tar.gz" -C "${indir}"

    resultsdir="${dest}/$wrkld,imgfuzz/stage=1,iter=1/.afl-results"
    echo "Results directory ${resultsdir}"

    echo "${resultsdir}/"'*fuzzer*'

    rm -rf "${resultsdir}/"*fuzzer* || { :; }

    mkdir -p "${resultsdir}"

    set +o xtrace
}

PMFUZZ_DIR="${DIR}"
AFL="${PMFUZZ_DIR}/build/bin/afl-fuzz"

export LD_PRELOAD=${PMFUZZ_DIR}/build/lib/libdesock.so
export LD_LIBRARY_PATH=/usr/local/lib64/ 
export DONT_PRIORITIZE_PM_PATH=1
export PMFUZZ_SKIP_TC_CHECK=1
export AFL_NO_FORKSRV=1
export PMEM_IS_PMEM_FORCE=1
export AFL_SKIP_BIN_CHECK=1
export PMFUZZ_MEMCACHED_EXIT_ON_COMMAND_READ=1

function GetCmd {
    local outfile="${dest}/$wrkld,imgfuzz/stage=1,iter=1/output_$iter"

    case "$wrkld" in
        redis)
            tgt="${PMFUZZ_DIR}/build/bin/redis-server ${PMFUZZ_DIR}/vendor/redis-3.2-nvml/redis.conf --pmfile @@ 8mb"
            cat_cmd="${PMFUZZ_DIR}/inputs/redis/1.txt"
            ;;
        memcached)
            tgt="${PMFUZZ_DIR}/build/bin/memcached -A -p 11211 -m 0 -j @@ -o pslab_force"
            cat_cmd=""
            ;;
        hashmap_tx | hashmap_atomic | btree | rtree | rbtree | skiplist)
            tgt="${PMFUZZ_DIR}/vendor/pmdk/src/examples/libpmemobj/map/mapcli ${wrkld} @@ 0"
            cat_cmd="${PMFUZZ_DIR}/inputs/mapcli_inputs_empty/0.txt"
            ;;
        *)
            echo "$wrkld unknown."
            exit 1
            ;;
    esac

    CMD="${AFL} -i ${indir} -o ${resultsdir} -s 1024 -t 2500 -m 3000 $(GetFuzzerName) -- ${tgt} ${cat_cmd} >${outfile} 2>&1 3>&1 4>&1 & disown"
    echo "$CMD"
}

function Main {
    Setup $*

    for iter in {0..37..1}; do
        echo "Running $iter"
        cmd="$(GetCmd)"
        echo "$cmd"
        eval "$cmd"
        sleep 3
    done

    rm ${dest}/$wrkld,imgfuzz.progress || { :; }

    while true; do
        cnt=$(find ${resultsdir} -mindepth 1 -name 'pm_map_id*' -exec sha256sum {} \; | cut -d " " -f 1 | uniq -c | wc -l)
        echo "$(date +%s),$cnt,$cnt,0,0,0,0" >> ${dest}/$wrkld,imgfuzz.progress
        sleep 2
    done
}

Main $*
