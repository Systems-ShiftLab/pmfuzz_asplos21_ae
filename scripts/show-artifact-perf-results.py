#! /usr/bin/env python3

import csv
import matplotlib as mpl
import matplotlib.dates as dates
import matplotlib.patches as patches
import matplotlib.pyplot as plt
import numpy as np
import os
import pandas as pd
import re
import requests
import scipy
import time
import urllib.request
import warnings

from bs4 import BeautifulSoup
from datetime import datetime, timedelta
from os import path
from scipy import signal
from scipy.signal import butter, lfilter, freqz
from scipy.stats.mstats import gmean
from matplotlib.ticker import (
    MultipleLocator, FormatStrFormatter,
   AutoMinorLocator, ScalarFormatter, LogLocator
)

## Variables
hosts         = ['host1', 'host2']
wrklds        = ['hashmap_tx', 'hashmap_atomic', 'btree', 'rtree', 'rbtree', 'skiplist', 'memcached', 'redis']
wrklds_dnames = ['Hashmap Tx', 'Hashmap Atomic', 'BTree', 'RTree', 'RBTree', 'Skiplist', 'Memcached', 'Redis']
cfgs          = ['complete', 'primitivebaseline', 'baseline', 'imgfuzz']
cfgs_dname    = ['PMFuzz', 'Baseline', 'Optimized Baseline', 'Img Fuzzing']

## Config Matplotlib
font = {
    'family' : 'sans-serif',
    'weight' : 'normal',
    'size'   : 15
}
mpl.rc('font', **font)



def url_exists(url):
    try:
        request = requests.get(url)
        return True
    except:
        return False

def listFD(url, ext='.progress'):
    page = requests.get(url).text
    soup = BeautifulSoup(page, 'html.parser')
    return [url + '/' + node.get('href') for node in soup.find_all('a') if node.get('href').endswith(ext)]

def get_file_list():
    file_list = []    
    for host in hosts:
        for file in listFD(host, '.progress'):
            file_list.append(file)
    return file_list


def fix_df(df):
    reindexed_df = df.reindex(range(1, np.max(df.index)))
    filled_df = reindexed_df.fillna(method='ffill')
    filled_df = filled_df.fillna(method='bfill')

    interval = int(30*60/2) # 15 minutes
    clean_df = filled_df.copy()
    clean_df = filled_df.iloc[::interval]
    
    return clean_df

print('\n'.join(get_file_list()))

all_results = {}
for wrkld in wrklds:
    all_results[wrkld] = {}
    for cfg in cfgs:
        all_results[wrkld][cfg] = pd.DataFrame()

# lim = get_lim()

for url in get_file_list():
    tokens = os.path.basename(url).split('%2C')
    
    wrkld = tokens[0]
    cfg = tokens[1].replace('.progress', '')

    df = pd.read_csv(url, header=0, names=['tc_total', 'pm_tc_total', 'total_path', 'total_pm_path', 'exec_rate', 'actual_cases'])
    df.index = df.index - np.min(df.index)

    print(f"Fixing URL {url}")
    all_results[wrkld][cfg] = fix_df(df)

fig, axs = plt.subplots(2, 4, sharex=True, figsize=(14,5))

colors = {
    'complete': 'dodgerblue', 'primitivebaseline': 'black', 
    'baseline': 'darkorange', 'imgfuzz': 'red'
}
markers = {
    'complete': 's', 'primitivebaseline': '^', 
    'baseline': 'o', 'imgfuzz': 'D'
}

iter = 0

for wrkld in wrklds:
    row = int(iter/4)
    col = iter%4

    for cfg in cfgs:
        if not all_results[wrkld][cfg].empty:
            vals = all_results[wrkld][cfg]['tc_total']
            idx = vals.index
            print(f'Plotting {cfg} for {wrkld}')
            axs[row, col].plot(
                idx, 
                vals, 
                label = cfg,
                color = colors[cfg],
                marker= markers[cfg],
                fillstyle='full',
                markerfacecolor='white',
                markeredgewidth=2
            )
        else:
            axs[row, col].plot([0], [0], label=cfg)

    wrkld_dname = wrklds_dnames[wrklds.index(wrkld)]
    axs[row, col].set_xlim([0, 14400])
#    axs[row, col].set_xbound(0, 1400)
    print("xlims = " + str(axs[row,col].get_xlim()))
    axs[row,col].set_title(wrkld_dname)
    axs[row,col].grid(axis='both')
    # axs[row,col].set_ylim(0, axs[row, col].get_ylim()[1])
    iter += 1

handles, leglabels = axs[0,0].get_legend_handles_labels()
fixedLegLabels = []
for lbl in leglabels:
    fixedLegLabels.append(cfgs_dname[cfgs.index(lbl)])

print(fixedLegLabels, leglabels)

fig.legend(handles, fixedLegLabels, loc='lower center', bbox_to_anchor=(0.5, -0.01), frameon=True, fancybox=False, ncol=2)
fig.tight_layout()
plt.show()
plt.savefig('evaluation-perf-result.png', bbox_inches='tight', dpi=400, transparent=False)
