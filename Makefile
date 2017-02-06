BOARD ?= arduino_101

# Dump memory information: on = print allocs, full = print allocs + dump pools
TRACE ?= off
# Generate and run snapshot as byte code instead of running JS directly
SNAPSHOT ?= on

ifndef ZJS_BASE
$(error ZJS_BASE not defined. You need to source zjs-env.sh)
endif

OCF_ROOT ?= deps/iotivity-constrained
JS ?= samples/HelloWorld.js
VARIANT ?= release
BLE_NAME ?= "Zephyr OCF Node"
# JerryScript options
JERRY_BASE ?= $(ZJS_BASE)/deps/jerryscript
EXT_JERRY_FLAGS ?= -DENABLE_ALL_IN_ONE=ON
ifneq ($(DEV), ashell)
ifeq ($(SNAPSHOT), on)
EXT_JERRY_FLAGS += -DFEATURE_JS_PARSER=OFF
endif
endif
ifeq ($(BOARD), arduino_101)
EXT_JERRY_FLAGS += -DENABLE_LTO=ON
endif

# if no config file passed use the ashell default
ifeq ($(DEV), ashell)
	CONFIG ?= fragments/zjs.conf.dev
	SNAPSHOT = off
endif

# Print callback statistics during runtime
CB_STATS ?= off
# Print floats (uses -u _printf_float flag). This is a workaround on the A101
# otherwise floats will not print correctly. It does use ~11k extra ROM though
PRINT_FLOAT ?= off
# Make target (linux or zephyr)
# MAKECMDGOALS is a Make variable that is set to the target your building for.
TARGET = $(MAKECMDGOALS)

ifeq ($(TARGET), linux)
	SNAPSHOT = off
endif
ifeq ($(BOARD), linux)
	SNAPSHOT = off
endif

# If target is one of these, ensure ZEPHYR_BASE is set
ZEPHYR_TARGETS = zephyr arc debug
ifeq ($(TARGET), $(filter $(ZEPHYR_TARGETS),$(TARGET)))
ifndef ZEPHYR_BASE
$(error ZEPHYR_BASE not set. Source deps/zephyr/zephyr-env.sh)
endif
ifneq ($(shell pwd)/deps/zephyr, $(ZEPHYR_BASE))
$(info Note: ZEPHYR_BASE is set outside the current ZJS tree ($(ZEPHYR_BASE)))
endif
endif

.PHONY: all
ifeq ($(BOARD), linux)
all: linux
else
all: zephyr arc
endif

# Build for zephyr, default target
.PHONY: zephyr
zephyr: analyze generate jerryscript
	@make -f Makefile.zephyr	BOARD=$(BOARD) \
					VARIANT=$(VARIANT) \
					MEM_STATS=$(MEM_STATS) \
					CB_STATS=$(CB_STATS) \
					PRINT_FLOAT=$(PRINT_FLOAT) \
					SNAPSHOT=$(SNAPSHOT)

# Build JerryScript as a library (libjerry-core.a)
jerryscript:
	@echo "Building" $@
	$(MAKE) -C $(JERRY_BASE) -f targets/zephyr/Makefile.zephyr BOARD=$(BOARD) EXT_JERRY_FLAGS="$(EXT_JERRY_FLAGS)" jerry
	mkdir -p outdir/$(BOARD)/
	cp $(JERRY_BASE)/build/$(BOARD)/obj-$(BOARD)/lib/libjerry-core.a outdir/$(BOARD)/

# Give an error if we're asked to create the JS file
$(JS):
	$(error The file $(JS) does not exist.)

# Find the modules the JS file depends on
.PHONY: analyze
analyze: $(JS)
	@echo "% This is a generated file" > prj.mdef
	@echo "# This is a generated file" > src/Makefile
	@cat src/Makefile.base >> src/Makefile
	@echo "# This is a generated file" > arc/src/Makefile
	@cat arc/src/Makefile.base >> arc/src/Makefile
	@if [ "$(TRACE)" = "on" ] || [ "$(TRACE)" = "full" ]; then \
		echo "ccflags-y += -DZJS_TRACE_MALLOC" >> src/Makefile; \
	fi
	@if [ "$(SNAPSHOT)" = "on" ]; then \
		echo "ccflags-y += -DZJS_SNAPSHOT_BUILD" >> src/Makefile; \
	fi
ifeq ($(DEV), ashell)
	@cat fragments/prj.mdef.dev >> prj.mdef
else
	@cat fragments/prj.mdef.base >> prj.mdef
	@cat fragments/prj.mdef.heap >> prj.mdef
endif

	@echo "ccflags-y += $(shell ./scripts/analyze.sh $(BOARD) $(JS) $(CONFIG) $(DEV))" | tee -a src/Makefile arc/src/Makefile
	@sed -i '/This is a generated file/r./zjs.conf.tmp' src/Makefile
	@# Add the include for the OCF Makefile only if the script is using OCF
	@if grep BUILD_MODULE_OCF src/Makefile; then \
		echo "CONFIG_BLUETOOTH_DEVICE_NAME=\"$(BLE_NAME)\"" >> prj.conf.tmp; \
		echo "include \$$(ZJS_BASE)/Makefile.ocf_zephyr" >> src/Makefile; \
	fi

# Update dependency repos
.PHONY: update
update:
	@git submodule update --init
	@cd $(OCF_ROOT); git submodule update --init;

# set up prj.conf file
-.PHONY: setup
setup:
	@echo "# This is a generated file" > prj.conf
ifeq ($(BOARD), qemu_x86)
	@cat fragments/prj.conf.qemu_x86 >> prj.conf
else
ifeq ($(DEV), ashell)
	@cat fragments/prj.conf.arduino_101_dev >> prj.conf
else
	@cat fragments/prj.conf.base >> prj.conf
endif
ifeq ($(BOARD), arduino_101)
	cat fragments/prj.conf.arduino_101 >> prj.conf
ifeq ($(ZJS_PARTITION), 256)
	@cat fragments/prj.conf.partition_256 >> prj.conf
endif
endif
endif
# Append script specific modules to prj.conf
	@if [ -e prj.conf.tmp ]; then \
		cat prj.conf.tmp >> prj.conf; \
	fi

.PHONY: cleanlocal
cleanlocal:
	@rm -f src/*.o
	@rm -f src/zjs_script_gen.c
	@rm -f src/zjs_snapshot_gen.c
	@rm -f src/Makefile
	@rm -f arc/prj.conf
	@rm -f arc/prj.conf.tmp
	@rm -f arc/src/Makefile
	@rm -f prj.conf
	@rm -f prj.conf.tmp
	@rm -f prj.mdef
	@rm -f zjs.conf.tmp

# Explicit clean
.PHONY: clean
clean: cleanlocal
ifeq ($(BOARD), linux)
	make -f Makefile.linux clean
else
	rm -rf $(JERRY_BASE)/build/$(BOARD)/; \
	rm -f outdir/$(BOARD)/libjerry-core.a; \
	make -f Makefile.zephyr clean BOARD=$(BOARD); \
	cd arc/; make clean;
endif

.PHONY: pristine
pristine: cleanlocal
	@rm -rf $(JERRY_BASE)/build;
	@make -f Makefile.zephyr pristine;
	@cd arc; make pristine;

# Flash Arduino 101 x86 image
.PHONY: dfu
dfu:
	dfu-util -a x86_app -D outdir/arduino_101/zephyr.bin

# Flash Arduino 101 ARC image
.PHONY: dfu-arc
dfu-arc:
	dfu-util -a sensor_core -D arc/outdir/arduino_101_sss/zephyr.bin

# Flash both
.PHONY: dfu-all
dfu-all: dfu dfu-arc

# Generate the script file from the JS variable
.PHONY: generate
generate: $(JS) setup
ifeq ($(SNAPSHOT), on)
	@echo Building snapshot generator...
	@if ! [ -e outdir/snapshot/snapshot ]; then \
		make -f Makefile.snapshot; \
	fi
	@echo Creating snapshot bytecode from JS application...
	@outdir/snapshot/snapshot $(JS) src/zjs_snapshot_gen.c
# SNAPSHOT=on, check if rebuilding JerryScript is needed
ifeq ("$(wildcard .snapshot.last_build)", "")
	@rm -rf $(JERRY_BASE)/build/$(BOARD)/
	@rm -f outdir/$(BOARD)/libjerry-core.a
endif
	echo "" > .snapshot.last_build
else
	@echo Creating C string from JS application...
ifeq ($(TARGET), linux)
	@./scripts/convert.sh $(JS) src/zjs_script_gen.c
else
	@./scripts/convert.sh /tmp/zjs.js src/zjs_script_gen.c
endif
# SNAPSHOT=off, check if rebuilding JerryScript is needed
ifneq ("$(wildcard .snapshot.last_build)", "")
	@rm -rf $(JERRY_BASE)/build/$(BOARD)/
	@rm -f outdir/$(BOARD)/libjerry-core.a
endif
	@rm -f .snapshot.last_build
endif

NET_BUILD=$(shell grep -q BUILD_MODULE_OCF src/Makefile && echo y)

# Run QEMU target
.PHONY: qemu
qemu: zephyr
	make -f Makefile.zephyr qemu \
		MEM_STATS=$(MEM_STATS) \
		CB_STATS=$(CB_STATS) \
		SNAPSHOT=$(SNAPSHOT) \
		NETWORK_BUILD=$(NET_BUILD)

# Builds ARC binary
.PHONY: arc
arc: analyze
	@echo "# This is a generated file" > arc/prj.conf
	@cat arc/fragments/prj.conf.base >> arc/prj.conf
	@if [ -e arc/prj.conf.tmp ]; then \
		cat arc/prj.conf.tmp >> arc/prj.conf; \
	fi
ifeq ($(ZJS_PARTITION), 256)
	@cat arc/fragments/prj.conf.partition_256 >> arc/prj.conf
endif
	@cd arc; make BOARD=arduino_101_sss

# Run debug server over JTAG
.PHONY: debug
debug:
	make -f Makefile.zephyr BOARD=arduino_101 ARCH=x86 debugserver

# Run gdb to connect to debug server for x86
.PHONY: gdb
gdb:
	$$ZEPHYR_SDK_INSTALL_DIR/sysroots/i686-pokysdk-linux/usr/bin/iamcu-poky-elfiamcu/i586-poky-elfiamcu-gdb outdir/arduino_101/zephyr.elf -ex "target remote :3333"

# Run gdb to connect to debug server for ARC
.PHONY: arcgdb
arcgdb:
	$$ZEPHYR_SDK_INSTALL_DIR/sysroots/i686-pokysdk-linux/usr/bin/arc-poky-elf/arc-poky-elf-gdb arc/outdir/zephyr.elf -ex "target remote :3334"

# Linux target
.PHONY: linux
# Linux command line target, script can be specified on the command line
linux: generate
	make -f Makefile.linux JS=$(JS) VARIANT=$(VARIANT) CB_STATS=$(CB_STATS) V=$(V) SNAPSHOT=$(SNAPSHOT)

.PHONY: help
help:
	@echo "Build targets:"
	@echo "    zephyr:    Build the main Zephyr target (default)"
	@echo "    arc:       Build the ARC Zephyr target for Arduino 101"
	@echo "    all:       Build the zephyr and arc targets"
	@echo "    linux:     Build the Linux target"
	@echo "    dfu:       Flash the x86 core binary with dfu-util"
	@echo "    dfu-arc:   Flash the ARC binary with dfu-util"
	@echo "    dfu-all:   Flash both binaries with dfu-util"
	@echo "    debug:     Run debug server using JTAG"
	@echo "    gdb:       Run gdb to connect to debug server for x86"
	@echo "    arcgdb:    Run gdb to connect to debug server for ARC"
	@echo "    qemu:      Run QEMU after building"
	@echo "    clean:     Clean stale build objects"
	@echo "    setup:     Sets up dependencies"
	@echo "    update:    Updates dependencies"
	@echo
	@echo "Build options:"
	@echo "    BOARD=     Specify a Zephyr board to build for"
	@echo "    JS=        Specify a JS script to compile into the binary"
	@echo
