#mkfile_path := $(abspath $(lastword $($(MAKE)FILE_LIST)))

ifeq ($(PIN_ROOT),)
$(error "PIN_ROOT env variable not set, check XFDetector's Readme")
endif

all: xfdetector driver

xfdetector:
	$(MAKE) -C xfdetector

pmdk:
	$(MAKE) -C pmdk EXTRA_CFLAGS="-Wno-error"

driver:
	$(MAKE) -C driver

redis:
	./init_redis.sh

memcached:
	cd memcached-pmem && env LIBS="-levent -L$(shell pwd)/xfdetector/build/lib/ -Wl,-rpath=$(shell pwd)/xfdetector/build/lib/ -lxfdetector_interface" CFLAGS="-I$(shell pwd)/xfdetector/include" ./configure --enable-pslab
	$(MAKE) -C memcached-pmem

clean:
	$(MAKE) clean -C xfdetector
	$(MAKE) clean -C pmdk
	$(MAKE) clean -C driver
	rm -rf redis-nvml
	$(MAKE) clean -C memcached-pmem

.PHONY: clean xfdetector pmdk redis memcached
