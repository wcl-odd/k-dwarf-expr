KOMPILE ?= kompile
BUILD_DIR ?= build
LLVM_DEFINITION ?= $(BUILD_DIR)/llvm-kompiled

.PHONY: all
all:
	$(MAKE) --no-print-directory -C semantics BACKEND=llvm BUILD_DIR="$(abspath $(BUILD_DIR))" DEFINITION="$(abspath $(LLVM_DEFINITION))" KOMPILE="$(KOMPILE)"
