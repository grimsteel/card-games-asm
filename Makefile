SRCS:=$(wildcard *.asm)
BINS:=$(patsubst %.asm,bin/%,$(SRCS))
BINS_DEBUG:=$(patsubst %.asm,bin/%-debug,$(SRCS))

all: $(BINS)
debug: $(BINS_DEBUG)

qr-%-bin.png: bin/%
	qrencode -r $^ -o $@ -8

qr-%-gz-b64.png: bin/%.gz
	printf "data:application/gzip;base64,%s" $$(base64 $^ -w0) | qrencode -o $@

bin/%.gz: bin/%
	gzip -k -9 -n $^

bin/%: bin/%.o
	ld -o $@ $^ -s -z noseparate-code  && strip --strip-section-headers $@

bin/%-debug: bin/%.debug.o
	ld -o $@ $^

bin/%.o: %.asm include/sys.asm | bin
	nasm -f elf64 $(filter-out include/sys.asm, $^) -o $@ -O9

bin/%.debug.o: %.asm include/sys.asm | bin
	nasm -f elf64 $(filter-out include/sys.asm, $^) -o $@ -g

bin:
	mkdir -p bin

clean:
	rm -rf bin
