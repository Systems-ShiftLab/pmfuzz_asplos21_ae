#!/usr/bin/env bash

ABSOLUTE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
PMFUZZ_DIR="$(dirname $(dirname ${ABSOLUTE_PATH}))"

XFD_BIN="${PMFUZZ_DIR}/build/bin/xfdetector"
PINTOOL_PATH="${PMFUZZ_DIR}/vendor/xfdetector/xfdetector/pintool/obj-intel64/pintool.so"
BUGGY_PMDK_DIR="${PMFUZZ_DIR}/vendor/pmdk-buggy"
SYNTH_BUG_DIR="${PMFUZZ_DIR}/synthetic_bugs"
EMPTY_IMG_DIR="${PMFUZZ_DIR}/inputs/pool_imgs"

declare -A WRKLD
WRKLD[1]=hashmap_tx
WRKLD[2]=btree
WRKLD[3]=rbtree
WRKLD[4]=rtree
WRKLD[5]=skiplist
WRKLD[6]=rbtree
WRKLD[7]=rbtree
WRKLD[8]=hashmap_atomic

if [ -z "$JOBS" ]; then
    JOBS=-j8
fi

test_sigsegv() {
    cmd="$1"
    echo -e "\n"
}

main() {
    bug_num="$1"

    case "$bug_num" in
        1 | 2 | 3 | 4 | 5 | 6 | 7 | 8)
            wrkld=${WRKLD[$bug_num]}
    esac

    PMFUZZ_BIN=$PMFUZZ_DIR/src/pmfuzz/pmfuzz-fuzz.py
    PMFUZZ_INPUT=$PMFUZZ_DIR/inputs/mapcli_inputs

    case "$bug_num" in
        1 | 2 | 3 | 4 | 5)
            PMFUZZ_CFG=$PMFUZZ_DIR/src/pmfuzz/configs/examples/mapcli.${WRKLD[$bug_num]}.complete.yml
            set -o xtrace
            make -C $PMFUZZ_DIR pmdk $JOBS  > $logf 2>&1
            if "$PMFUZZ_BIN" -ov -c1=1 -c2=1 "$PMFUZZ_INPUT" /tmp/out "$PMFUZZ_CFG" --progress-file=/tmp/bport 2>&1 | tee $logf | grep -q 'Possible bug report'; then
                set +o xtrace 2>/dev/null 1>&1
                ps -eaf | egrep '(pmfuzz)|(afl-fuzz)|mapcli|memcached' | grep -v grep | awk '{print $2}' | xargs kill -9 $1 >/dev/null 2>&1
                echo ""
                echo "Bug $bug_num confirmed on workload $wrkld."
                echo "PMFuzz reported crashes on initial testing"
            fi
            ;;  
        6 | 7)
            set -o xtrace
            { 
                make $JOBS -C "${BUGGY_PMDK_DIR}" clean >"$logf" 2>&1;
            } && {
                make $JOBS -C "${PMFUZZ_DIR}" buggy-pmdk BUG_SWITCH="-DBUG_$bug_num" >>"$logf" 2>&1;
            } && {
                tar xvzf "$EMPTY_IMG_DIR/rbtree.pool.tar.gz" -C /mnt/pmem0;
            } || {
                set +o xtrace  
                echo ""
                echo "-----"
                echo "Compilation failed, check log at '$logf'"
                exit 1
            }

            set +o xtrace

            img="/mnt/pmem0/rbtree.pool"
            tgt="${PMFUZZ_DIR}/vendor/pmdk-buggy/src/examples/libpmemobj/map/mapcli rbtree __POOL_IMAGE__ 0 $SYNTH_BUG_DIR/rbtree/id=000166.testcase"
            timeout_val=$((20*60))
            xfd_cmd=$(printf "timeout $timeout_val %s %s %s %s %s\n" \
                    "$XFD_BIN" \
                    "$PINTOOL_PATH" \
                    "$img" \
                    "--" \
                    "$tgt" \
                )

            img=$(tempfile -d /mnt/pmem0 -p tmpimg-)

            echo -e "Running XFD with command: \n\n$xfd_cmd\n\n"
            
            start=$SECONDS

            set -o xtrace
            if eval "stdbuf -oL $xfd_cmd" 2>&1 | tail -n+28 | tee -a "$logf" | grep -Eq 'Performance Bug'; then
                echo "Bug confirmed in $(($SECONDS-$start)) seconds using XFDetector."
            else
                echo "No bug found"
            fi    
            set +o xtrace
            ;;
        8)
            set -o xtrace
            make clean -C $PMFUZZ_DIR/vendor/pmdk > $logf 2>&1
            make -C $PMFUZZ_DIR pmdk BUG_SWITCH="-DDISABLE_HASHMAP_ATOMIC_FIX" $JOBS  > $logf 2>&1

            PMFUZZ_CFG=$PMFUZZ_DIR/src/pmfuzz/configs/examples/mapcli.${WRKLD[$bug_num]}.complete.yml

            if "$PMFUZZ_BIN" -ov -c1=1 -c2=1 "$PMFUZZ_INPUT" /tmp/out "$PMFUZZ_CFG" --progress-file=/tmp/bport 2>&1 | tee $logf | grep -q 'Possible bug report'; then
                set +o xtrace 2>/dev/null 1>&1
                ps -eaf | egrep '(pmfuzz)|(afl-fuzz)|mapcli|memcached' | grep -v grep | awk '{print $2}' | xargs kill -9 $1 >/dev/null 2>&1
                echo ""
                echo "Bug $bug_num confirmed on workload $wrkld."
                echo "PMFuzz reported crashes on initial testing"
            else
                echo "Did not confirm the bug"
            fi
          
            echo "Cleaning up stuff now"
            make clean -C $PMFUZZ_DIR/vendor/pmdk > $logf 2>&1
            make -C $PMFUZZ_DIR pmdk $JOBS  > $logf 2>&1
            ;;
        *)
            echo "Invalid bug number \`$bug_num\`"
            exit 1
            ;;
    esac

    tgt="${PMFUZZ_DIR}/vendor/pmdk-buggy/src/examples/libpmemobj/map/mapcli ${wrkld} $img 0 $showtc"

    echo "$tgt"
}

logf=$(tempfile)
echo "Writing logs to $logf"

main "$@"