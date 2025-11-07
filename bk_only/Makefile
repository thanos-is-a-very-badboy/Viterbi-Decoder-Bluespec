# ====================================================
# Bluespec System Verilog Simplified Project Makefile 
# ====================================================

TOPFILE      = Testbench.bsv
TOPMODULE    = mkTestbench
BSVINCDIR    = .:%/Libraries
BSCDEFINES   = RV64
VERILOGDIR   = verilog/
BUILDDIR     = intermediate/

.PHONY: all generate_verilog b_sim clean 

all: generate_verilog

generate_verilog:
	@mkdir -p $(VERILOGDIR) $(BUILDDIR)
	@bsc -u -verilog -elab \
		-vdir $(VERILOGDIR) -bdir $(BUILDDIR) -info-dir $(BUILDDIR) \
		+RTS -K4000M -RTS \
		-check-assert -keep-fires -opt-undetermined-vals \
		-remove-false-rules -remove-empty-rules -remove-starved-rules \
		-remove-dollar -unspecified-to X \
		-show-schedule -show-module-use \
		-suppress-warnings G0010:T0054:G0020:G0024:G0023:G0096:G0036:G0117:G0015 \
		-D $(BSCDEFINES) -p $(BSVINCDIR) $(TOPFILE)

b_sim:
	@mkdir -p $(BUILDDIR)
	@bsc -u -sim -elab \
		-simdir $(BUILDDIR) -bdir $(BUILDDIR) -info-dir $(BUILDDIR) \
		-g $(TOPMODULE) $(TOPFILE)
	@bsc -e $(TOPMODULE) -sim \
		-o $(BUILDDIR)/$(TOPMODULE)_bsim \
		-simdir $(BUILDDIR) -bdir $(BUILDDIR) -info-dir $(BUILDDIR)
	@$(BUILDDIR)/$(TOPMODULE)_bsim -V


clean:
	@rm -rf $(BUILDDIR) $(VERILOGDIR) *.vcd
	@echo "Build directories cleaned"

