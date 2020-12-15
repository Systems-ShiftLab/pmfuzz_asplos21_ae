#!/usr/bin/env bash

ABSOLUTE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
PMFUZZ_DIR="$(dirname $(dirname ${ABSOLUTE_PATH}))"

source $PMFUZZ_DIR/scripts/libs/helper.lib.bash

declare -A bugs
bugs[hashmap_tx]="HASHMAP_TX_1 HASHMAP_TX_2 HASHMAP_TX_4 HASHMAP_TX_5 HASHMAP_TX_6 HASHMAP_TX_PERF_3"
bugs[skiplist]="SKIPLIST_1 SKIPLIST_2 SKIPLIST_3 SKIPLIST_PERF_3"
bugs[btree]="OBJ_3 HEAP_1 BTREE_9 BTREE_8 BTREE_7 BTREE_4 BTREE_1 BTREE_6 BTREE_3 BTREE_2 OBJ_1"
bugs[rtree]="RTREE_10 RTREE_8 RTREE_7 RTREE_6 RTREE_5 RTREE_3"
bugs[hashmap_atomic]="HASHMAP_ATOMIC_3 HASHMAP_ATOMIC_2 HASHMAP_ATOMIC_1 HASHMAP_ATOMIC_7 HASHMAP_ATOMIC_6 HASHMAP_ATOMIC_4 HASHMAP_ATOMIC_8"
bugs[memcached]="MEMCACHED_5 ITEMS_2 MEMCACHED_8 MEMCACHED_9"
bugs[rbtree]="RBTREE_1 RBTREE_3 RBTREE_4 RBTREE_5 RBTREE_PERF_1 RBTREE_PERF_2"
bugs[redis]="PMEM_2 PMEM_3 PMEM_4 PMEM_PERF_1"

declare -A timeout
timeout[pmdk]=$((60*60))
timeout[memcached]=$((15*60))
timeout[redis]=$((15*60))

wrklds=(hashmap_tx hashmap_atomic btree rtree rbtree skiplist memcached redis)
pmemchk_bugids=(OBJ_3 HEAP_1 OBJ_1)

XFD_BIN="${PMFUZZ_DIR}/build/bin/xfdetector"
PINTOOL_PATH="${PMFUZZ_DIR}/vendor/xfdetector/xfdetector/pintool/obj-intel64/pintool.so"
BUGGY_PMDK_DIR="${PMFUZZ_DIR}/vendor/pmdk-buggy"
SYNTH_BUG_DIR="${PMFUZZ_DIR}/synthetic_bugs"
EMPTY_IMG_DIR="${PMFUZZ_DIR}/inputs/pool_imgs"

if [ -z "$JOBS" ]; then
    export JOBS=-j8
fi

function join_by { local IFS="$1"; shift; echo "$*"; }

function GetCmd {
    wrkld="$1"
    testcase="$2"
    pmimg="$3"


    ENV="PREENY_DESOCK_INFILE=$testcase XFD_LD_PRELOAD=$PMFUZZ_DIR/build/lib/libdesock.so"

    case "$wrkld" in
        redis)
            tgt="${PMFUZZ_DIR}/build/bin/buggy_redis-server ${PMFUZZ_DIR}/vendor/redis-3.2-nvml/redis.conf --pmfile __POOL_IMAGE__ 8mb"
            timeout_val=${timeout[redis]}
            ;;
        memcached)
            tgt="${PMFUZZ_DIR}/build/bin/buggy_memcached -A -p 11211 -m 0 -j __POOL_IMAGE__ -o pslab_force"
            timeout_val=${timeout[memcached]}
            ;;
        hashmap_tx | hashmap_atomic | btree | rtree | rbtree | skiplist)
            ENV=""
            if echo $testcase | grep -q 'img_creation'; then
                showtc="${PMFUZZ_DIR}/synthetic_bugs/pmdk_terminating_input.txt"
            else
                showtc=$testcase
            fi
            tgt="${PMFUZZ_DIR}/vendor/pmdk-buggy/src/examples/libpmemobj/map/mapcli ${wrkld} __POOL_IMAGE__ 0 $showtc"
            timeout_val=${timeout[pmdk]}
            ;;
        *)
            echo "$wrkld unknown."
            exit 1
            ;;
    esac
}

function checkversion {
    if ((BASH_VERSINFO[0] < 4)); then 
        echo "Sorry, you need at least bash-4.0 to run this script." 
        exit 1 
    fi
}

function compile() {
    bugid=$1

    set -o xtrace
    {
        make $JOBS -C "${BUGGY_PMDK_DIR}" clean >"$logf" 2>&1;
        make $JOBS -C "${PMFUZZ_DIR}/vendor/memcached-pmem-buggy" clean >"$logf" 2>&1;
        make $JOBS -C "${PMFUZZ_DIR}/vendor/redis-3.2-nvml-buggy" clean >"$logf" 2>&1;
    } && {
        make $JOBS buggy-pmdk BUG_SWITCH="-D$bugid" >>"$logf" 2>&1;
        make $JOBS buggy-memcached BUG_SWITCH="-D$bugid" >>"$logf" 2>&1;
        make $JOBS buggy-redis BUG_SWITCH="-D$bugid" >>"$logf" 2>&1;        
    } || {
        set +o xtrace  
        echo ""
        echo "-----"
        echo "Compilation failed, check log at '$logf'"
        exit 1
    }
    set +o xtrace
}

function run_xfd {
    wrkld="$1"
    testcase="$2"
    img="$3"

    GetCmd "$wrkld" "$testcase" "$img"

    xfd_cmd=$(printf "%s timeout $timeout_val %s %s %s %s %s\n" \
        "$ENV" \
        "$XFD_BIN" \
        "$PINTOOL_PATH" \
        "$img" \
        "--" \
        "$tgt" \
    )

    echo -e "Running:\n$xfd_cmd"

    echo ""

    LOOK_FOR=""
    if echo "$bugid" | grep -q 'PERF'; then
        LOOK_FOR="(Performance Bug)|(Unnecessary Flush)"
    else
        LOOK_FOR="(Consistency Bug)|(Unnecessary Flush)"
    fi

    if [ "$wrkld" = "redis" ]; then
    	LOOK_FOR="(Consistency Bug)|(Performance Bug)"
	fi

    start=$SECONDS
    if eval "$xfd_cmd" 2>&1 | tail -n+28 | tee -a "$logf" | grep -Eq "$LOOK_FOR"; then
        echo "Bug confirmed in $(($SECONDS-$start)) seconds using XFD."
    else
        echo "No bug found"
    fi        
}

function run_pmemcheck {
    wrkld="$1"
    testcase="$2"
    img="$3"

    GetCmd "$wrkld" "$testcase" "$img"

    translated_tgt=`echo "$tgt" | sed "s|__POOL_IMAGE__|$img|g"`

    pmemchk_cmd=$(printf "%s valgrind --tool=pmemcheck %s\n" \
        "$ENV" \
        "$translated_tgt"
    )

    echo -e "$pmemchk_cmd"
    start=$SECONDS

    error_count=`$pmemchk_cmd 2>&1 | grep -Eo '[0-9]+' | tail -n1`
    if [ "$error_count" = "0" ]; then
        echo "No bug found"
    else
        echo "Bug confirmed in $(($SECONDS-$start)) seconds using PMemcheck."
    fi  
}
    
function main {
    bugid="$1" 
    wrkld="$2"

    logf=$(tempfile)
    echo "Writing logs to ${logf}"

    echo "Trying $wrkld: $bugid"
    
    tcname=$(cat $SYNTH_BUG_DIR/$wrkld/*.csv | grep -i $bugid, | sed 's/,CONFIRMED//g' | cut -d, -f4-)
    tcpath=$SYNTH_BUG_DIR/$wrkld/$tcname

    compile $bugid

    if [ ! "$tcname" = "img_creation" ]; then
        if hasparent "$tcname"; then
            parentimgname=$(getparentimgname $tcname)
            parentimgpath="$(ls $SYNTH_BUG_DIR/$wrkld/images/$parentimgname)"
        else 
            parentimgname="$wrkld.pool.tar.gz"
            parentimgpath="$EMPTY_IMG_DIR/$wrkld.pool.tar.gz"
        fi                
        
        if [ -f "$parentimgpath" ]; then
            echo $parentimgpath
        fi
    else
        parentimgpath=$(tempfile -d /mnt/pmem0)
        rm "$parentimgpath"
        parentimgname=$(basename $parentimgpath)
    fi
    
    if echo "$parentimgname" | grep -q '.tar.gz'; then
        echo "+ tar vxzf $parentimgpath -C /mnt/pmem0/"
        decmprparentimgname="$(tar vxzf $parentimgpath -C /mnt/pmem0/)"
        decmprparentimgpath="/mnt/pmem0/$decmprparentimgname"
    else
        decmprparentimgname="$parentimgname"
        decmprparentimgpath="$parentimgpath"
    fi            

    # Check if the wrkld runs using pmemcheck
    if (printf '%s\n' "${pmemchk_bugids[@]}" | grep -xq $bugid); then
        run_pmemcheck "$wrkld" "$tcpath" "$decmprparentimgpath"
    else
        run_xfd "$wrkld" "$tcpath" "$decmprparentimgpath"
    fi

    exit    
}

main $*
