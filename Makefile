solitaire: solitaire.o
	ld -o $@ $^ -s -z noseparate-code  && strip --strip-section-headers $@
solitaire-debug: solitaire-debug.o
	ld -o $@ $^

solitaire.o: solitaire.asm
	nasm -f elf64 $^ -o $@

solitaire-debug.o: solitaire.asm
	nasm -f elf64 $^ -o $@ -g

clean:
	rm -f solitaire solitaire.o
