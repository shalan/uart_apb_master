RTL_DIR  = rtl
TB_DIR   = tb
SIM_DIR  = sim_build

RTL_SRC  = $(RTL_DIR)/baud_gen.v \
           $(RTL_DIR)/uart_rx.v \
           $(RTL_DIR)/uart_tx.v \
           $(RTL_DIR)/cmd_parser.v \
           $(RTL_DIR)/resp_builder.v \
           $(RTL_DIR)/apb_master.v \
           $(RTL_DIR)/uart_apb_master.v \
           $(RTL_DIR)/apb_splitter.v \
           $(RTL_DIR)/uart_apb_sys.v

# Bridge-only testbench
TB_BRIDGE  = $(TB_DIR)/uart_apb_master_tb.v
TOP_BRIDGE = uart_apb_master_tb

# System testbench (bridge + splitter)
TB_SYS  = $(TB_DIR)/uart_apb_sys_tb.v
TOP_SYS = uart_apb_sys_tb

.PHONY: all sim sim-bridge sim-sys waves waves-sys lint clean

all: sim

$(SIM_DIR):
	mkdir -p $(SIM_DIR)

# --- Bridge only ---
compile-bridge: $(SIM_DIR)
	iverilog -g2012 -Wall -o $(SIM_DIR)/$(TOP_BRIDGE) $(RTL_SRC) $(TB_BRIDGE)

sim-bridge: compile-bridge
	cd $(SIM_DIR) && vvp $(TOP_BRIDGE)

waves-bridge: sim-bridge
	gtkwave $(SIM_DIR)/$(TOP_BRIDGE).vcd &

# --- System (bridge + splitter) ---
compile-sys: $(SIM_DIR)
	iverilog -g2012 -Wall -o $(SIM_DIR)/$(TOP_SYS) $(RTL_SRC) $(TB_SYS)

sim-sys: compile-sys
	cd $(SIM_DIR) && vvp $(TOP_SYS)

sim: sim-sys

waves: sim-sys
	gtkwave $(SIM_DIR)/$(TOP_SYS).vcd &

# --- Both ---
sim-all: sim-bridge sim-sys

# --- Lint ---
lint:
	verilator --lint-only -Wall $(RTL_SRC)

clean:
	rm -rf $(SIM_DIR) *.vcd
