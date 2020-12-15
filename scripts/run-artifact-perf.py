#! /usr/bin/env python3

import os
import paramiko
import stdiomask
import threading
import time

from multiprocessing.pool import ThreadPool

MINUTE = 60 # seconds
HOUR = 60 * MINUTE


LOG_F='/var/tmp/ae_log'

user = 'asplos21ae'
hosts = ['shiftlab%02d.cs.virginia.edu' % i for i in [8, 9, 10, 11, 13, 14]]
dests = [f'{user}@{host}' for host in hosts]
ssh_cmds = [f'ssh -p2222 {dest}' for dest in dests]

ENV = 'export PIN_ROOT=/opt/pin-3.11'
PMFUZZ_LOC = '/ae/master_src/pmfuzz'

CONDA_ACT_CMD = f'source /home/{user}/anaconda3/etc/profile.d/conda.sh; conda activate pmfuzz'
PMFUZZ_COMPILE_CMD = f'rm -r /ae/artifact_evaluation_results/*; {ENV}; cd {PMFUZZ_LOC}; make clean-all -j100; make -j100; make redis memcached -j100'
#PMFUZZ_COMPILE_CMD = f'rm -r /ae/artifact_evaluation_results/*; {ENV}; cd {PMFUZZ_LOC}; make -j100; make redis memcached -j100'
PMFUZZ_PY_SRV_CMD = f'{CONDA_ACT_CMD}; cd /ae/artifact_evaluation_results && python -m http.server 8900'

# Create all possible combinations of workload and configurations
WORKLOADS = ['hashmap_tx', 'hashmap_atomic', 'btree', 'rtree', 'rbtree', 'skiplist', 'memcached', 'redis']
CONFIGS = ['pmfuzz', 'baseline', 'primitivebaseline']
wrkld_cfg_mix = [(wrkld, cfg) for wrkld in WORKLOADS for cfg in CONFIGS]
wrkld_cmds = [f"{CONDA_ACT_CMD}; /ae/master_src/pmfuzz/scripts/run-workloads.sh {wrkld} {mode} /ae/artifact_evaluation_results > /tmp/live_ae" \
    for (wrkld, mode) in wrkld_cfg_mix]
wrkld_cmds += [f"{CONDA_ACT_CMD}; /ae/master_src/pmfuzz/scripts/run-imgfuzz.sh {wrkld} /ae/artifact_evaluation_results > /tmp/live_ae" \
    for wrkld in WORKLOADS]
    
# For splitting a list into n parts
def chunkIt(seq, num):
    avg = len(seq) / float(num)
    out = []
    last = 0.0

    while last < len(seq):
        out.append(seq[int(last):int(last + avg)])
        last += avg

    return out

# Set of commands each host will run
host_wrlkd_cmds = chunkIt(wrkld_cmds, len(hosts))

# Map from hostname to a set of commands from host_wrkld_cmds
wrkld_host_map = {}
iter = 0
for host in hosts:
    wrkld_host_map[host] = host_wrlkd_cmds[iter]
    iter += 1

# How long each config would run
RUNTIME = 2 * HOUR

def echo(msg, prefix='++ '):
    print(prefix + msg)

def get_ssh_obj(host):
    echo(f'Creating SSH object for {host}')

    ssh = paramiko.SSHClient()
    ssh.load_system_host_keys()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(host, username=user, look_for_keys=True)

    return ssh

def run_results_server(ssh_obj, hostname):
    echo(f'Spinning up result server for {hostname}')
    ssh_obj.exec_command(PMFUZZ_PY_SRV_CMD)

def compile_pmfuzz(ssh_obj, hostname):
    echo(f'Executing "{PMFUZZ_COMPILE_CMD}". This will take couple of minutes...')

    _, stdout, stderr = ssh_obj.exec_command(PMFUZZ_COMPILE_CMD, get_pty=True)
    
    output_stdout = stdout.readlines()
    output_stderr = stderr.readlines()

    with open(f'{LOG_F}/{hostname}.stdout', 'a') as stdout_obj:
        stdout_obj.write(''.join(output_stdout))

    with open(f'{LOG_F}/{hostname}.stderr', 'a') as stderr_obj:
        stderr_obj.write(''.join(output_stderr))

    echo(f'Done with {hostname}.')

def run_pmfuzz(ssh_obj, cmd):
    echo(f"Running: {cmd}")
    _, stdout, stderr = ssh_obj.exec_command(cmd, get_pty=True)
    time.sleep(RUNTIME)

def run_thread(host):
    ssh_obj = get_ssh_obj(host)

    run_results_server(ssh_obj, host)
    compile_pmfuzz(ssh_obj, host)

    for cmd in wrkld_host_map[host]:
        run_pmfuzz(ssh_obj, cmd)

def collect_results():
    return


def print_hdr():
    print("PMFuzz artifact evaluation script.")
    print("==================================")
    print("")
    print("This script will ssh to the following hosts and automatically")
    print("compile and run PMFuzz to generate Figure TODO of the paper.")
    print("")
    print("Compiling PMFuzz is slow and may take couple of minutes. To track")
    print("the compilation progress, check the logs under:")
    print(f'{LOG_F}' + '.{stdout,stderr}')
    print("")
    print("")

def mkdirs():
    try:
        os.mkdir(LOG_F)
    except FileExistsError:
        pass

def main():
    print_hdr()
    mkdirs()

    
    pool = ThreadPool(len(hosts))
    results = pool.map(run_thread, hosts)

    pool.close()
    pool.join()

    echo("All done")    

main()