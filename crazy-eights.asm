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
  and dword [termios_buf + termios.c_lflag], ~(0x0A) ; ~(CANON | ECHO)
  inc esi
  call tcgetorset

main_loop:
  mov esi, clear
  mov edx, clear_len
  call print
  mov esi, welcome
  mov edx, welcome_len
  call print

  call getc
  cmp eax, 'e'
  je exit ; quit when they press e
  cmp eax, 'h'
  
game_start:
  ; shuffle cards
  call init_shuffle_cards

  mov esi, board
  mov edx, board_len
  call print
  call print_board_values
game_loop:
  call print_board_values

  ; print menu
  mov esi, turn_commands
  mov edx, turn_commands_len
  call print
  call getc

  cmp eax, 'e'
  je exit
  cmp eax, 'd'
  je draw_card

place_card:
  jmp game_loop

draw_card:
  xor r8d, r8d
  xor r9d, r9d
  mov byte r8b, [deck_len]
  dec r8b
  ; TODO: shuffle empty deck
  mov byte [deck_len], r8b      ; decrement deck_len
  mov byte r8b, [deck + r8d]    ; fetch item at pos
  mov byte r9b, [hand1_len]
  inc r9b
  mov byte [hand1 + r9d], r9b; store
  mov byte [hand1_len], r9b
  jmp game_loop

exit:  
  ; re-enable buffering
  or dword [termios_buf + termios.c_lflag], 0x0A ; CANON + ECHO
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

print_board_values:
  ; print hand, deck, and discard lengths
  mov r12b, 4
  mov r10d, hand2_len
  mov r13d, hand2_pos
.print_nums_loop:
  ; move to pos
  mov esi, r13d
  mov edx, pos_len
  add r13d, edx
  call print
  
  mov byte dil, [r10d]
  call print_num
  
  inc r10d
  dec r12b
  jnz .print_nums_loop

  ; print discard card
  mov esi, dis_card_pos
  mov edx, pos_len
  call print
  xor edi, edi
  mov byte dil, [discard_len]
  dec edi
  mov byte r8b, [discard + edi]
  call print_card

  ; print hand
  mov esi, hand1_card_pos
  mov edx, hand1_card_pos_len
  call print

  xor r9d, r9d
.print_hand_loop:
  mov byte r8b, [hand1 + r9d]
  call print_card
  inc r9b
  cmp r9b, [hand1_len]
  jl .print_hand_loop

  ret

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

  ; each card symbol is a 3-byte UTF-8 sequence + 1 byte space
  mov edx, 4

  xor esi, esi
  mov byte sil, r8b
  and sil, 0x3                  ; get suit (lower 2 bits)
  shl sil, 2                    ; multiply by 4 (4 bytes)
  add esi, suits                ; get suit symbol
  call print
  
  ret

section .data
welcome: db '[?25l[36mCrazy Eights:[m', 0xA, '[h]ost [c]onnect [e]xit'
welcome_len: equ $ - welcome
board: db '[2H[JThem:    [  ]', 0xA, 0xA, 'Discard: [  ]', 0xA, 'Deck:    [  ]', 0xA, 0xA, 'You:     [  ]'
board_len: equ $ - board
turn_commands: db '[10H[JYour turn:', 0xA, '[d]raw [p]lace [e]xit'
turn_commands_len: equ $ - turn_commands
hand2_pos: db '[2;11H'
hand1_pos: db '[7;11H'
dis_pos: db '[4;11H'
deck_pos: db '[5;11H'
pos_len: equ $ - deck_pos
dis_card_pos: db '[4;15H'
hand1_card_pos: db '[8;1H[K'
hand1_card_pos_len: equ $ - hand1_card_pos
clear: db '[H[J'
clear_len: equ $ - clear
bye: db '[?25h'
bye_len: equ $ - bye
ranks: db 'A23456789TJQK'
suits: db '♠ ♣ ♦ ♥ '
section .bss
; all cards
all_cards: resb 52
; if the deck had 51 or 52 cards, somebody would have won
deck: resb 50
discard: resb 50
hand1: resb 50
hand2: resb 50
hand2_len: resb 1
hand1_len: resb 1
discard_len: resb 1
deck_len: resb 1
rand: resb 51
;; DATA STRUCTURE
;; Bits [0, 2): [0]: Spades [1]: Clubs [2]: Diamonds [3]: Hearts
;; Bits [2, 6): 4 bit integer representing rank. 0 is Ace. 12 is King.
;; 255 represents a null card
