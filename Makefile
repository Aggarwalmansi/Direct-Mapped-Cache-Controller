.PHONY: all test test_member1 test_member2 test_member3 test_member4 test_member5 traces synth synth_generic synth_xc7 clean

# Synthesizable RTL (main_memory_model.v is simulation-only and excluded)
RTL_SYNTH = rtl/address_decoder.v \
	rtl/tag_comparator.v \
	rtl/cache_data_ram.v \
	rtl/tag_ram.v \
	rtl/valid_bit_ram.v \
	rtl/cache_controller.v \
	rtl/main_memory_interface.v \
	rtl/cache_top.v

# Extra vvp plusargs for the Member 5 testbench, e.g. make test_member5 SIMFLAGS=+VCD
SIMFLAGS ?=

all: test

test: test_member1 test_member2 test_member3 test_member4 test_member5

test_member1:
	mkdir -p build
	iverilog -g2012 -Wall -s tb_member1 -o build/member1 rtl/address_decoder.v rtl/tag_comparator.v tb/tb_member1.v
	vvp build/member1

test_member2:
	mkdir -p build
	iverilog -g2012 -Wall -s tb_member2 -o build/member2 rtl/cache_data_ram.v rtl/tag_ram.v rtl/valid_bit_ram.v tb/tb_member2.v
	vvp build/member2

test_member3:
	mkdir -p build
	iverilog -g2012 -Wall -s tb_member3 -o build/member3 \
		rtl/address_decoder.v \
		rtl/tag_comparator.v \
		rtl/cache_data_ram.v \
		rtl/tag_ram.v \
		rtl/valid_bit_ram.v \
		rtl/cache_controller.v \
		tb/tb_member3.v
	vvp build/member3

test_member4:
	mkdir -p build
	iverilog -g2012 -Wall -s tb_member4 -o build/member4 \
		rtl/address_decoder.v \
		rtl/tag_comparator.v \
		rtl/cache_data_ram.v \
		rtl/tag_ram.v \
		rtl/valid_bit_ram.v \
		rtl/cache_controller.v \
		rtl/main_memory_interface.v \
		rtl/main_memory_model.v \
		tb/tb_member4.v
	vvp build/member4

test_member5:
	mkdir -p build
	iverilog -g2012 -Wall -s tb_cache_top -o build/member5 \
		$(RTL_SYNTH) \
		rtl/main_memory_model.v \
		tb/tb_cache_top.v
	vvp -n build/member5 +TRACE_DIR=traces $(SIMFLAGS)

# Regenerate traces/*.trace (deterministic; the generated files are committed)
traces:
	python3 scripts/gen_traces.py traces

synth: synth_generic synth_xc7

synth_generic:
	mkdir -p build/synth
	yosys -q -l build/synth/generic.log -s synth/synth_generic.ys
	@grep -A40 'Number of cells\|cells$$' build/synth/generic_stat.txt | head -25
	@grep 'Longest topological path' build/synth/generic_ltp.txt

synth_xc7:
	mkdir -p build/synth
	yosys -q -l build/synth/xc7.log -s synth/synth_xc7.ys
	@grep -E '^ +[0-9]+ +(LUT|FD|RAM|BUFG|IBUF|OBUF|CARRY|MUX)' build/synth/xc7_stat.txt

clean:
	rm -rf build
