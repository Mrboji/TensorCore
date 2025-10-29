TOPNAME = shift_reg   #need modify
VERILATOR = verilator
BUILD_DIR = ./build
OBJ_DIR = $(BUILD_DIR)/obj_dir
BIN = $(OBJ_DIR)/V$(TOPNAME)
WAVES = $(BUILD_DIR)/waveform.fst

$(shell mkdir -p $(BUILD_DIR))

VSRCS = $(shell find $(abspath ./vsrc) -name "*.v")
CSRCS = $(abspath ./csrc)/tb_$(TOPNAME).cpp

VERILATOR_CFLAGS += --x-assign unique --x-initial unique\
                        --trace-fst --timescale "1ns/1ns"\
						 --no-timing --autoflush 
 
CXXFLAGS += -DTOP_MODULE=V$(TOPNAME)

$(WAVES):$(VSRCS) $(CSRCS) 
	@rm -rf $(OBJ_DIR)
	@echo "### VERILATING ###"
	$(VERILATOR) $(VERILATOR_CFLAGS) \
	--top-module $(TOPNAME) \
	-cc $(VSRCS) \
	--Mdir $(OBJ_DIR) --exe $(CSRCS) \
	$(addprefix -CFLAGS , $(CXXFLAGS))
	@make -C $(OBJ_DIR) -f V$(TOPNAME).mk V$(TOPNAME)

sim:$(WAVES)
	@$(BIN) 

waves:$(WAVES)
	@gtkwave $(WAVES)

lint:$(VSRCS)
	$(VERILATOR) $(VERILATOR_CFLAGS) --lint-only \
	--top-module $(TOPNAME) $(VSRCS)

clean:
	@rm -rf ./build

.PHONY: sim waves lint clean


