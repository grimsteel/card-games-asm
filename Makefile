SRCS:=$(wildcard *.asm)
BINS:=$(patsubst %.asm,bin/%,$(SRCS))
BINS_DEBUG:=$(patsubst %.asm,bin/%-debug,$(SRCS))

all: $(BINS)
debug: $(BINS_DEBUG)

bin/%: bin/%.o
	ld -o $@ $^ -s -z noseparate-code  && strip --strip-section-headers $@

bin/%-debug: bin/%.debug.o
	ld -o $@ $^

bin/%.o: %.asm | bin
	nasm -f elf64 $^ -o $@ -O9

bin/%.debug.o: %.asm | bin
	nasm -f elf64 $^ -o $@ -g

bin:
	mkdir -p bin

clean:
	rm -rf bin
