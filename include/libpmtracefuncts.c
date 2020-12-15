#include "pm_trace_functs.h"

// PM Address range manipulation
void pm_trace_pm_addr_add(uint64_t addr __attribute__((unused)), uint64_t size  __attribute__((unused))) {
    return;
}

void pm_trace_pm_addr_remove(uint64_t addr  __attribute__((unused)), uint64_t size  __attribute__((unused))){
    return;
}

// Transaction annotation
void pm_trace_tx_begin(void){
    return;
}

void pm_trace_tx_end(void){
    return;
}

void pm_trace_tx_addr_add(uint64_t addr  __attribute__((unused)), uint64_t size  __attribute__((unused))){
    return;
}

void tx_commit_point(void){
    return;
}


// not necessary
/*
void pm_trace_pmdk_funct_begin(void){
    return;
}
void pm_trace_pmdk_funct_end(void){
    return;
}
*/