# PMFuzz

## Abstract

PMFuzz is a test case generator for PM programs, aiming for high coverage on crash consistency bugs. The key idea of PMFuzz is to perform a targeted fuzzing on PM-related code regions. The generated test cases include both program inputs and initial PM images (both normal images and crash images). 
Then, PMFuzz feed these test cases to PM programs, and use existing testing tools (XFDetector and PMemcheck) to detect crash consistency bugs. 

## Description


### Hardware dependencies.
1. CPU: Intel Xeon Cascade Lake 
2. DRAM: 32 GB at least
3. Persistent Memory: Intel DCPMM 
4. Hard Drive: 1 TB at least 

### Platform for AE.
The performance evaluation involves proprietary hardware and a large number of CPU cores for multi-threaded fuzzing. And, each workload has four design points for comparison and needs to be fuzzed continuously for 4 hours. 
Therefore, we will provide 6 servers for AE, where `SERVERA` serves as the main server that schedules the fuzzing tasks on other servers. 
Those servers have 240 cores in total. 
We will provide login credentials (i.e., SSH public key) through the chairs/HotCRP.


Software dependencies.
1. Ubuntu 18.04 or higher
2. NDCTL v64 or higher
3. `libunwind-dev`, `libini-config-dev` 
4.  Python 3.6, GNUMake >= 3.82, Bash >= 4.0, Linux Kernel version 5.4, autoconf, bash-completions, Valgrind, PMemcheck, Anaconda

## Data sets

We evaluated the following workloads:
1. PMDK libpmemobj examples:  Btree, RTree, RBTree, Skip List, Hashmap-Atomic, and Hashmap-TX 
2. Redis (based on PMDK libpmemobj)
3. Memcached (based on PMDK libpmem)



## Installation
This artifact has the following structure:

* `include/`: Runtime for pmfuzz (`libpmfuzz.so`) and tracing functions for XFDetector.
* `inputs/`: Inputs used as seeds for the PMFuzz.
* `scripts/`: Installation and artifact-evaluation scripts.
* `src/pmfuzz`: Source for our testcase generation tool.
* `vendor/{pmdk,memcached,redis}`: Workloads.
* `vendor/{pmdk,memcached,redis}-buggy`: Workloads with synthetic bugs.
* `vendor/xfdetector`: Source for XFDetector testing tool.
* `preeny`: git submodule for Preeny tools.


**Setup Environment.**
PMFuzz requires the environment variable for `PIN_ROOT` and `PMEM_MMAP_HINT` are set before execution.
To set these variables, please execute the following command:


```shell
export PIN_ROOT=<PMFuzz Root>/vendor/pin-3.13
export PMEM_MMAP_HINT=0x10000000000
```

It also requires disabling ASLR and core dump notifications disabled (needs to reset after power cycle). 
To disable them, please execute the follow commands:

```shell
echo core | sudo tee /proc/sys/kernel/core_pattern
echo 0 | sudo tee /proc/sys/kernel/randomize_va_space
```


**Setup Software Dependencies.**
To run PMFuzz, please make sure that you have all the prior dependencies installed. If some dependencies are not met, you can install them with our script:

```
cd <PMFuzz Root>
./scripts/install-dependencies.sh 
```

**Warning**: This command will remove the existing `libndctl} and update it to the required version.


**Setup Python Environment.**
In additional to the basic dependencies, PMFuzz requires a Python 3.6 environment with several Python packages. To install them, please execute the following 
commands:

```
pip3 install -r src/pmfuzz/requirements.txt
```

**Install PMFuzz and PM Workloads.**
To download the correct version of LLVM, compile PMFuzz's runtime, AFL and all the workloads, please execute the following commands (follow the order in the listing):
```
make
make redis memcached
```



## Experiment Workflow


The core functionality of PMFuzz is the fuzzing logic that generates test cases for PM programs. 
To Run the workloads using PMFuzz, please use the `run-workloads.sh` script which invokes PMFuzz with the correct arguments to run a workload. The script takes input in the following format:

```shell
scripts/run-workloads.sh \
    <workload name> <config name> <output dir>
```

These commands will run PMFuzz with correct configuration used for the evaluation section. The script by default uses 38 CPU cores. To adjust that, please modify line 69-72 of the script.
This script supports three design points (Section 5.1 of the paper):


1. **PMFuzz** (`pmfuzz`): this work with all features enabled.
2. **Optimized Baseline** (`optimizedbaseline`):AFL++ with integration of PMFuzz's system optimizations.
3. **Baseline** (`baseline`): an existing fuzzer AFL++.


The fourth design point  directly generates PM images through fuzzing. We support it with a separate script: 

```
scripts/run-imgfuzz.sh <workload> <output dir>
```



For example, to run PMDK's btree workload in the baseline configuration, run the following command:
```
scripts/run-workloads.sh btree baseline /tmp/
```
 
Running this command will create the directory `/tmp/btree,baseline` with all generated test cases and images.

## Evaluation and Expected Result

The main evaluation includes the performance evaluation that compares the PM path coverage (defined in Section 3.3 of the paper), and reproduction of the new real-world bugs found using our generated test cases.
In addition to the main experiments, we include  scripts to reproduce our synthetic bugs. 


## Performance Evaluation.
Considering the hardware requirements (both DCPMM and number of CPU cores), we provide access to 6 servers. 
We also include scripts to run and plot the performance evaluation results (Figure 5 of the paper). 
Each server has PMFuzz artifact source available under `/ae/master_src/pmfuzz`.

Before running any command, please make sure that you have the python environment correctly setup, all the dependencies are  installed and your current working directory (CWD) is the root of the PMFuzz artifact repository. On the servers we provide, the python environment can be activated using the following command and all other dependencies are pre-installed:

```shell
conda activate pmfuzz
```

To change CWD to the artifact root, please execute the following command:

```shell
cd /ae/master_src/pmfuzz
```

To run performance evaluation and automatically schedule fuzzing jobs across all  the 6 servers, please run the following commands on the main server:

```shell
./scripts/run-artifact-perf.py
```

The script will now ssh to all the other servers and start fuzzing processes. When all the fuzzers have completed, the script will exit with the message "All Done". To plot the results, please use the script `show-artifact-perf-results.py` using the following commands:

```
scripts/show-artifact-perf-results.py
python -m http.server 1010
```

After completing the prior steps, the result will be accessible from a browser: 
[http://main-server:1010/evaluation-perf-result.png](http://main-server:1010/evaluation-perf-result.png)


## Reproducing New Real-world Bugs.
To detect real bugs that we reported, please run the following script:
```
./scripts/test-real-bugs.sh [1..8]
```

where `[1..8]` corresponds to the bug IDs in Section 5.3 of the paper.

For example, to detect Bug 1 in Hashmap TX, please execute the following command:

```shell
./scripts/test-real-bugs.sh 1
```


## Synthetic Bugs.
To apply and check for synthetic bugs using the testcases that PMFuzz found, please execute on of the scripts in the directory `scripts/synth-bugs-scripts/`. For example, to check the first synthetic bug for BTree, run the following command:

```shell
./scripts/synth-bugs-scripts/btree_bug_1.sh
```

The script will automatically enable the corresponding bug in PMDK, recompile it, and perform testing (XFDetector and Pmemcheck) with testcases generated by PMFuzz.



## Experiment Customization

**Direct execution PMFuzz.**
To run PMFuzz without using any driver scripts, run the following command:

```shell
./src/pmfuzz/pmfuzz-fuzz.py \
    <Input dir> <Output dir> <Config file>
```


* `<Input dir>`: PMFuzz uses testcases from this directory as the fuzzer's seed input.
* `<Output dir>`: All the generated outputs will be placed in this directory.
* `<Config file>`: A config file that specifies the fuzzing target and different PMFuzz parameters.

**PMFuzz Configuration.** PMFuzz uses a YML-based configuration to set different parameters for fuzzing (including the fuzzing target). To write a custom configuration, please follow one of the existing examples in `src/pmfuzz/configs/examples/` directory.


## Notes


### Reasons for Common errors

#### 1. FileNotFoundError for instance's pid file
Raised when AFL cannot bind to a free core or no core is free.
#### 2. Random tar command failed
Check if no free disk space is left on the device
#### 3. shmget (2): No space left on device
Run:
```
ipcrm -a
```
Warning: This removes all user owned shared memory segments, don't run with superuser privilege or on a machine with other critical applications running.

[config_examples]: src/pmfuzz/configs/examples/
[pmfuzz-fuzz.py]: src/pmfuzz/pmfuzz-fuzz.py
[1]: src/pmfuzz/README.md
