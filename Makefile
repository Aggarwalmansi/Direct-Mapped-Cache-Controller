.PHONY: test clean

test:
	mkdir -p build
	iverilog -g2012 -Wall -s tb_member1 -o build/member1 rtl/address_decoder.v rtl/tag_comparator.v tb/tb_member1.v
	vvp build/member1

clean:
	rm -rf build
