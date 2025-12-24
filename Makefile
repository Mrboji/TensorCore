TOPNAME ?= fadd_tree
VERILATOR = verilator
BUILD_DIR = ./build
OBJ_DIR = $(BUILD_DIR)/obj_dir
BIN = $(OBJ_DIR)/V$(TOPNAME)
WAVES = $(BUILD_DIR)/waveform.fst

$(shell mkdir -p $(BUILD_DIR))

VSRCS = $(shell find $(abspath ./vsrc) -name "*.v")
CSRCS = $(abspath ./csrc)/tb_$(TOPNAME).cpp

VERILATOR_FLAGS = --x-assign unique --x-initial unique \
                  --trace-fst --timescale "1ns/1ns" \
                  --no-timing --autoflush

CXXFLAGS += -DTOP_MODULE=V$(TOPNAME)

$(BIN): $(VSRCS) $(CSRCS)
	@echo "### VERILATING ###"
	$(VERILATOR) $(VERILATOR_FLAGS) \
		--top-module $(TOPNAME) \
		$(addprefix -CFLAGS , $(CXXFLAGS))\
		--cc $(VSRCS) \
		--exe $(CSRCS) \
		--build \
		-Mdir $(OBJ_DIR)

sim: $(BIN)
	@echo "### SIMULATING ###"
	$(BIN)

waves: $(WAVES)
	@gtkwave $(WAVES)

lint: $(VSRCS)
	$(VERILATOR) $(VERILATOR_FLAGS) --lint-only \
		--top-module $(TOPNAME) $(VSRCS)

clean:
	rm -rf $(BUILD_DIR)

.PHONY: sim waves lint clean


