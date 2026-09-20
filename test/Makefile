SIM ?= icarus
TOPLEVEL_LANG ?= verilog

SRC_DIR = $(PWD)/../src
PROJECT_SOURCES = \
	tt_um_mips_i2c.v \
	top.v \
	i2c_slave_mmio.v \
	mmio_decoder.v \
	instruction_memory.v \
	data_memory.v \
	reg_file.v \
	Pc.v \
	IF_ID_register.v \
	ID_EX_register.v \
	EX_MEM_register.v \
	M_WB_register.v \
	control_unit.v \
	ALU.v \
	comparator.v \
	Sign_extender.v \
	Forwarding_unit.v \
	Forward_rs.v \
	forward_rt.v \
	Flushing_unit.v \
	branching_unit.v \
	stalling_unit.v \
	PHT.v \
	BHT.v \
	BTB.v \
	Xor_result.v \
	mux_1.v \
	mux_2.v \
	mux_1_execution.v \
	mux_2_execution.v \
	mux_3_execution.v \
	Write_back_mux.v

ifeq ($(SIM), icarus)
	COMPILE_ARGS += -g2005-sv
endif

VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))

# The top-level module for the TT harness pin contract.
TOPLEVEL = tt_um_mips_i2c

MODULE = test

include $(shell cocotb-config --makefiles)/Makefile.sim
