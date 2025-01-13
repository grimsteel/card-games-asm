solitaire: solitaire.o
	ld -o $@ $^ -s -z noseparate-code  && strip --strip-section-headers $@

solitaire.o: solitaire.asm
	nasm -f elf64 $^ -o $@

clean:
	rm -f solitaire solitaire.o
