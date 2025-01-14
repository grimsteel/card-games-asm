;; Solitaire under 3KB in Intel x86-64 ASM
  
;; Built for Linux. Assembled using NASM.

struc termios
  resb 12
.c_lflag: resb 12
  resb 44
endstruc

%define TCGETS 21505
%define TCSETS 21506
  
global _start
section .text
_start:
  ; disable terminal line buffering
  mov esi, TCGETS
  call tcgetorset
  and dword [termios_buf + termios.c_lflag], ~(0b1010) ; CANON + ECHO
  inc esi
  call tcgetorset

main_loop:
  mov esi, welcome
  mov edx, welcome_len
  call print

  call getc
  sub eax, 'q'
  jz exit ; quit when they press q

;; shuffle cards
game_loop:
  

exit:  
  ; re-enable buffering
  or dword [termios_buf + termios.c_lflag], 0b1010 ; CANON + ECHO
  mov esi, TCSETS
  call tcgetorset

  mov esi, bye
  mov edx, bye_len
  call print
  
  mov al, 60
  xor edi, edi
  syscall

;; Execute TCGETS or TCSETS from/into `termios_buf`
;; Parameters: esi (either TCGETS or TCSETS)
tcgetorset:
  mov eax, 16                   ; IOCTL
  xor edi, edi                  ; 0 (stdin)
  mov edx, termios_buf
  syscall
  ret

;; Get a single character from STDIN into `eax`
getc:
  push 0
  xor eax, eax                  ; 0 (read)
  xor edi, edi                  ; 0 (stdin)
  mov rsi, rsp
  mov edx, 1                    ; 1 char
  syscall
  pop rax
  ret

;; Print a string to the screen
;; Parameters: esi (str pointer), edx/dl (str len)
print:
  xor eax, eax
  inc eax                       ; 1 (write)
  mov edi, eax                  ; 1 (stdout)
  syscall
  ret

init_shuffle_cards:
  ; set all that we won't touch to 255 (discard + 7 piles + 4 foundation)
  xor r8d, r8d                  ; clear r8
  mov r8b, 24 + 7 * 19 + 4 * 13
.loop1:
  mov byte [discard + r8], 255
  dec r8b
  jnz .loop1

  ; Ace of spades all the wy to King of hearts
	mov r8b, 52
.loop2:
	mov byte [all_cards + r8], r8b
	dec r8b
	jnz .loop2
	ret

print_deck:
  mov r8b, 52
.loop:
  mov r9b, [all_cards + r8]
  dec r8b
  jnz .loop
  ret

section .data
welcome: db `\033[?25l\033[H\033[J\033[36mSolitaire:\033[m\n[⏎] Play [q] Exit`
welcome_len: equ $ - welcome
bye: db `\nBye\033[?25h\n`
bye_len: equ $ - bye
section .bss
termios_buf: resb termios_size
; all cards
all_cards: resb 52
; 24 length deck
deck: resb 24
discard: resb 24
; 7 piles of max 19 each
piles: resb 7 * 19
; 4 piles of max 13 each
foundations: resb 4 * 13

;; DATA STRUCTURE
;; Bits [0, 2): [0]: Spades [1]: Clubs [2]: Diamonds [3]: Hearts
;; Bits [2, 6): 4 bit integer representing rank. 0 is Ace. 12 is King.
;; 255 represents a null card
