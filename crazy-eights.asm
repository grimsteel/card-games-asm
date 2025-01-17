;; Crazy eights under 3KB in Intel x86-64 ASM
;; Multiplayer support using Linux UDP sockets
  
;; Built for Linux. Assembled using NASM.

%include "include/sys.asm"
  
global _start
section .text
_start:
  ; disable terminal line buffering
  mov esi, TCGETS
  call tcgetorset
  and dword [termios_buf + termios.c_lflag], ~(0b1010) ; CANON + ECHO
  inc esi
  call tcgetorset
  call open_socket

main_loop:
  mov esi, welcome
  mov edx, welcome_len
  call print

  call getc
  sub eax, 'e'
  jz exit ; quit when they press q

  call init_shuffle_cards
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

  call close_socket
  
  mov eax, 60
  ; already done in close_socket
  xor edi, edi
  syscall

init_shuffle_cards:
  ; set all to 255 (two hands + deck + discard)
  xor ecx, ecx
.resetDeckLoop:
  mov byte [deck + ecx], 255
  inc cl
  cmp cl, 50 * 4
  jl .resetDeckLoop

  ; Ace of spades all the wy to King of hearts
  xor cl, cl
.initCardsLoop:
	mov byte [all_cards + ecx], cl
  inc cl
  cmp cl, 52
	jl .initCardsLoop

  ; shuffle
  ; generate random nums - getrandom(buf, 51, 0)
  mov eax, 318                  ; getrandom
  mov edi, rand                 ; buf
  mov esi, 51                   ; len
  xor edx, edx                  ; flags
  syscall

  ; fisher-yates shuffle the array
  mov r8b, 50
  mov r10d, rand                ; iterate through rand (let's call the idx k)
.shuffleLoop:
  mov r9b, r8b
  add r9b, 2                    ; 0 <= j <= i, r8b = i - 1, so the range is r8b + 2
  xor eax, eax                  ; clear eax
  mov byte al, [r10]            ; j = rand[k] % (r8b + 2)
  div r9b                       ; now ah (lower 8 of eax) has j
  shr eax, 8                         ; take lower 8 bits (remainder
  mov byte r9b, [all_cards + r8d + 1]     ; r9b = all_cards[r8b + 1] = all_cards[i]
  mov byte r11b, [all_cards + eax]        ; r11b = all_cards[j]
  mov byte [all_cards + r8d + 1], r11b     ; all_cards[i] = r11b
  mov byte [all_cards + eax], r9b        ; all_cards[j] = r9b

  inc r10b
  
  dec r8b
  jnz .shuffleLoop

  ; move first 14 into hand1 + hand2
  xor ecx, ecx
  mov r8d, all_cards
.initHandsLoop:
  mov byte r9b, [r8d]
  mov byte [hand1 + ecx], r9b
  inc r8d
  mov byte r9b, [r8d]
  mov byte [hand2 + ecx], r9b
  inc r8d
  inc cl
  cmp cl, 7
  jl .initHandsLoop

  mov byte [hand1_len], cl
  mov byte [hand2_len], cl
  ; move next one into discard
  mov byte r9b, [r8d]
  inc r8d
  mov byte [discard], r9b
  mov byte [discard_len], 1

  xor cl, cl
.initDeckLoop:
  mov byte r9b, [r8d]
  mov byte [deck + ecx], r9b
  inc r8d
  inc cl
  cmp cl, 37                    ; 52 - 15
  jl .initDeckLoop

  mov byte [deck_len], cl
  
  ret
  
; card in r8b
print_card:
  ; rank = 1 byte
  xor edx, edx
  inc edx
  
  xor esi, esi
  mov byte sil, r8b
  shr sil, 2                    ; get upper 4 bits
  add esi, ranks                ; get rank letter
  call print

  ; each card symbol is a 3-byte UTF-8 sequence
  mov edx, 3

  xor eax, eax
  mov byte al, r8b
  and al, 0b11                  ; get suit (lower 2 bits)
  mov cl, 3                     ; multiply by 3 (because 3 byte)
  mul cl                        ; mul only works with rax
  add eax, suits                ; get suit symbol
  mov esi, eax                  ; move into esi
  call print
  
  ret

section .data
welcome: db `\033[?25l\033[36mCrazy Eights:\033[m\n[h]ost [c]onnect [e]xit`
welcome_len: equ $ - welcome
clear: db `\033[H\033[J`
clear_len: equ $ - clear
bye: db `\nBye\033[?25h\n`
bye_len: equ $ - bye
ranks: db `A23456789TJQK`
suits: db `♠♣♦♥`
section .bss
; all cards
all_cards: resb 52
; if the deck had 51 or 52 cards, somebody would have won
deck: resb 50
deck_len: resb 1
discard: resb 50
discard_len: resb 1
hand1: resb 50
hand1_len: resb 1
hand2: resb 50
hand2_len: resb 1
rand: resb 51
;; DATA STRUCTURE
;; Bits [0, 2): [0]: Spades [1]: Clubs [2]: Diamonds [3]: Hearts
;; Bits [2, 6): 4 bit integer representing rank. 0 is Ace. 12 is King.
;; 255 represents a null card
