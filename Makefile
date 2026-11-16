.PHONY: all test test_member1 test_member2 test_member3 clean

all: test

test: test_member1 test_member2 test_member3

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
	iverilog -g2012 -Wall -s tb_cache_controller -o build/member3 \
		rtl/address_decoder.v \
		rtl/tag_comparator.v \
		rtl/cache_data_ram.v \
		rtl/tag_ram.v \
		rtl/valid_bit_ram.v \
		rtl/cache_controller.v \
		tb/tb_cache_controller.v
	vvp build/member3

clean:
	rm -rf build
