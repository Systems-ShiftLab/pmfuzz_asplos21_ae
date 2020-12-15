#!/usr/bin/env bash

export DISABLE_CHECK=1

ABSOLUTE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

wrklds=(hashmap_tx hashmap_atomic btree rtree rbtree skiplist memcached redis)
modes=(pmfuzz pmfuzzunfocused baseline primitivebaseline)
DIR="$(dirname $(dirname ${ABSOLUTE_PATH}))"
PYDIR="${DIR}/src/pmfuzz"

function join_by { local IFS="$1"; shift; echo "$*"; }
function phelp {
    printf "Usage:\n  $0 [-h|--help] workload mode dest\n"
    printf "\n"
    printf "Required Parameters:\n"
    printf "  %s {%s}\n" "workload" $(join_by \| "${wrklds[@]}")
    printf "  %20s %s\n"  "" "Workload to run"
    printf "  %s {%s}\n" "mode" $(join_by \| "${modes[@]}")
    printf "  %20s %s\n" "" "Mode to run"
    printf "  %-20s %s\n" "dest" "directory to write the results in, a subdirectory is created with workload's name.%\n"
    printf "\n"
    printf "Optional Parameters:\n"
    printf "  %-20s %s\n"  "-h|--help" "Show this message and exit"
    printf "\n"
    printf "$(cat ${DIR}/VERSION | grep PMFUZZ_INFO_LN | cut -c 25- | sed 's/\"//g')\n"
}

function checkversion {
    if ((BASH_VERSINFO[0] < 4)); then 
        echo "Sorry, you need at least bash-4.0 to run this script." 
        exit 1 
    fi
}

function checkargs {
    checkversion

    if [[ " $* " =~ " --help " ]] || [[ " $* " =~ " -h " ]]; then
        phelp
        exit 0
    fi

    if [ "$#" != 3 ]; then
        printf "Incorrect number of arguments, should be 3\n\n"
        phelp
        exit 1
    fi

    if [[ ! " ${wrklds[@]} " =~ " ${1} " ]]; then
        phelp
        printf "\nWorkload $1 is not supported, supported workloads:\n\t${wrklds[*]}\n"
        exit 1
    fi

    if [[ ! " ${modes[@]} " =~ " ${2} " ]]; then
        phelp
        printf "\nMode $2 is not supported, supported modes:\n\t${modes[*]}\n"
        exit 1
    fi
}

function setup {
    local wrkld=$1
    local mode=$2
    dest=$3

    declare -A PARAMS
    PARAMS[pmfuzz]="-c1=20 -c2=10"
    PARAMS[pmfuzzunfocused]="-c1=20 -c2=10"
    PARAMS[baseline]="-c1=38"
    PARAMS[primitivebaseline]="-c1=38"
    params="${PARAMS[$mode]}"

    declare -A NAMEPREFIX
    NAMEPREFIX[pmfuzz]="complete,255"
    NAMEPREFIX[pmfuzzunfocused]="completeunfocused,255"
    NAMEPREFIX[baseline]="baseline"
    NAMEPREFIX[primitivebaseline]="primitivebaseline"
    nameprefix="${NAMEPREFIX[$mode]}"

    declare -A CFGNAMES
    CFGNAMES[pmfuzz]="complete"
    CFGNAMES[pmfuzzunfocused]="completeunfocused"
    CFGNAMES[baseline]="baseline"
    CFGNAMES[primitivebaseline]="primitivebaseline"
    cfgname="${CFGNAMES[$mode]}"

    case "$wrkld" in
        hashmap_tx | hashmap_atomic | btree | rtree | rbtree | skiplist)
            name="${wrkld},${nameprefix},empty,hm_a_fixed"
            ;;
        redis | memcached)
            name="${wrkld},${nameprefix},nonempty,hm_a_fixed"
            ;;
        *)
            fatal "Unknown workload ${wrkld}"
    esac
}

function cleanup {
	echo 'Deleting /mnt/pmem0/*'
    rm -rf /mnt/pmem0/*

    vals="$(ps -eaf | egrep '(pmfuzz)|(afl-fuzz)|mapcli' | grep -v 'run-workloads' | grep -v grep | awk '{print $2}')"
    if [ "$vals" != "" ]; then
        ps -eaf | egrep '(pmfuzz)|(afl-fuzz)|mapcli' | grep -v 'run-workloads' | grep -v grep | awk '{print $2}' | xargs kill -9 $1
    fi

    kill_pid=$(ps -eaf | egrep 'imgfuzz' | grep -v grep | awk '{print $2}')
    if [ ! -z "$kill_pid" ]; then
        { kill -9 $kill_pid; } || { :; }
    fi

}

function getcmd {
    local wrkld=$1

    case "$wrkld" in
        hashmap_tx | hashmap_atomic | btree | rtree | rbtree | skiplist)
            echo "unbuffer ${PYDIR}/pmfuzz-fuzz.py -o ${DIR}/inputs/mapcli_inputs_empty \"${dest}/${name}\" configs/examples/mapcli.${wrkld}.${cfgname}.yml \"--progress-file=${dest}/${name}.progress\" ${params} 2>&1 > \"${dest}/${name}.log\" & disown;"
            ;;
        redis)
            echo "unbuffer ${PYDIR}/pmfuzz-fuzz.py -o ${DIR}/inputs/redis \"${dest}/${name}\" configs/examples/redis.${cfgname}.yml \"--progress-file=${dest}/${name}.progress\" ${params} 2>&1 > \"${dest}/${name}.log\" & disown;"
            ;;
        memcached)
            echo "unbuffer ${PYDIR}/pmfuzz-fuzz.py -o ${DIR}/inputs/memcached \"${dest}/${name}\" configs/examples/memcached.${cfgname}.yml \"--progress-file=${dest}/${name}.progress\" ${params} 2>&1 > \"${dest}/${name}.log\" & disown;"
            ;;
        *)
            fatal "Unknown workload ${wrkld}"
    esac
}

# * fix_env -- Change the language env variables to make sure the python's function don't
# break
function fix_env {
    export LANG='en_US.UTF-8'
    export LC_ALL='en_US.UTF-8'
}

function main {
    local wrkld=$1
    local mode=$2
    local dest=$3

    checkargs $*

    fix_env

    setup $wrkld $mode $dest
    cleanup

    local cmd=$(getcmd $wrkld)
    echo -e "Running:\n\t${cmd}"
    eval "cd ${PYDIR}; ${cmd}"
    echo "Waiting for 60 seconds..." && sleep 60
    eval "tail -f ${dest}/${name}.log -n100"
}

main $*
