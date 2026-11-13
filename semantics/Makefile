KOMPILE ?= kompile
BACKEND ?= llvm
BUILD_DIR ?= build
DEFINITION ?= $(BUILD_DIR)/$(BACKEND)-kompiled
CORE_DEFINITION ?= $(BUILD_DIR)/core-$(BACKEND)-kompiled
TMP_ROOT ?= $(BUILD_DIR)/tmp
KOMPILE_JAVA_OPTIONS ?= -XX:ActiveProcessorCount=8 -XX:+UseSerialGC
KOMPILE_K_OPTIONS ?= -Xmx2g -Xss1m

.DEFAULT_GOAL := all
.PHONY: all core

ifneq ($(BACKEND),llvm)
ifneq ($(BACKEND),haskell)
$(error BACKEND must be llvm or haskell)
endif
endif

SOURCES := dwarf.k $(wildcard domains/*.k frontend/*.k execution/*.k)
CORE_SOURCES := execution/core.k execution/runtime.k execution/composition.k execution/expression.k execution/computations.k execution/floating.k domains/dwarf-domains.k

all: $(DEFINITION)/compiled.bin
core: $(CORE_DEFINITION)/compiled.bin

# Serialize writes to this build directory and use a private compiler directory.
# All arguments are passed separately so the recipe needs no project scripts.
define compile_definition
	mkdir -p "$(BUILD_DIR)" "$(TMP_ROOT)"
	flock "$(BUILD_DIR)/compile.lock" bash -eu -c '\
	  task_tmp=$$(mktemp -d "$$1/kframework-kompile-XXXXXX"); \
	  trap '\''rm -rf "$$task_tmp"'\'' EXIT; \
	  env JAVA_TOOL_OPTIONS="$$8 -Djava.io.tmpdir=$$task_tmp" K_OPTS="$$9" \
	    GHCRTS="-N1" OMP_NUM_THREADS=1 TMPDIR="$$task_tmp" \
	    "$$2" "$$3" --main-module "$$4" --syntax-module "$$5" \
	      --backend "$$6" --output-definition "$$7" --temp-dir "$$task_tmp/kompile"\
	' -- "$(abspath $(TMP_ROOT))" "$(KOMPILE)" "$(1)" "$(2)" "$(3)" "$(BACKEND)" "$(abspath $(4))" "$(KOMPILE_JAVA_OPTIONS)" "$(KOMPILE_K_OPTIONS)"
endef

$(DEFINITION)/compiled.bin: $(SOURCES) Makefile
	$(call compile_definition,dwarf.k,DWARF,DWARF-SYNTAX,$(DEFINITION))

$(CORE_DEFINITION)/compiled.bin: $(CORE_SOURCES) Makefile
	$(call compile_definition,execution/core.k,DWARF-CORE,DWARF-CORE,$(CORE_DEFINITION))
