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

  xor r8d, r8d

  cmp eax, 'e'
  je exit
  cmp eax, 'd'
  je draw_card

place_card:
  ; print instructions
  mov esi, select_card_commands
  mov edx, select_card_commands_len
  call print

  ; move hand len into r10b
  xor r10d, r10d
  mov byte r10b, [hand1_len]
  dec r10b
.place_card_loop:
  ; choose a card
  mov esi, hand1_select_pos
  mov edx, hand1_select_pos_len
  call print

  ; move the cursor to correct position
  ; dil = (r8b * 2) + r8b = r8b * 3
  mov dil, r8b
  shl dil, 1
  add dil, r8b                  
  inc dil                       ; ansi escapes are 1-indexed
  call print_num

  ; finish ansi escape, print symbol
  mov esi, hand1_select_icon
  mov edx, hand1_select_icon_len
  call print

  ; get input
  call getc                     ; \033, or enter
  cmp eax, 0x0A                 ; enter
  je .place_card_select
  call getc                     ; [
  call getc                     ; C = right, D = left
  cmp eax, 'C'
  je .move_right
.move_left:
  ; bounds check
  cmp r8b, 0
  je .place_card_loop
  dec r8b
  jmp .place_card_loop
.move_right:
  cmp r8b, r10b
  je .place_card_loop
  inc r8b
  jmp .place_card_loop
.place_card_select:
  ; make sure this card can be placed (same suit or same rank)
  mov byte r11b, [hand1 + r8d]  ; r11b = new card
  mov byte r9b, [discard_len]
  mov byte r12b, [discard + r9d - 1] ; r12b = top card
  mov r13b, r11b
  mov r14b, r12b
  and r13b, 0x3                 ; r13b now has only 2 bits
  and r14b, r13b                ; r14b = (r11b & 0b11) & r12b      - this ensures that r14b only has 2 bits too
  cmp byte r13b, r14b           ; if equal, then same suit
  je .place_card_exec
  mov r13b, r11b
  mov r14b, r12b
  and r13b, 0x3C                ; upper 4 bits
  and r14b, r13b                ; same principle as above
  cmp byte r13b, r14b           ; if equal, then same rank
  jne place_card                ; invalid selection
.place_card_exec:
  ; dec hand size
  mov byte [hand1_len], r10b
  ; swap with last
  mov byte r10b, [hand1 + r10d] ; last card
  mov byte [hand1 + r8d], r10b
  ; add this card to the discard
  mov byte [discard + r9d], r11b
  ; inc discard size
  mov byte r10b, [discard_len]
  inc r10b
  mov byte [discard_len], r10b
  jmp game_loop

draw_card:
  mov byte r8b, [deck_len]
  cmp r8b, 0
  jg .exec_draw_card
  ; handle empty deck
  xor r9d, r9d

  xor esi, esi
  mov byte sil, [discard_len]                   ; len
  dec esi                                       ; move discard_len - 1 elements to the deck
  jz game_loop
  ; store the top element in the discard
  mov byte r13b, [discard + esi]
  mov r9b, sil
  dec esi                       ; need discard_len - 2 random numbers
  
  ; shuffle
  ; generate random nums - getrandom(buf, 51, 0)
  call getrandom

  ; fisher-yates shuffle the discard back into the deck
  mov byte [deck_len], r9b
  mov r8b, r9b           ; for exec_draw_card below
  mov r10d, rand                ; iterate through rand (let's call the idx k)
.shuffleLoop:
  mov byte al, [r10]            ; j = rand[k] % (r8b + 2)
  div r9b                       ; now ah (upper 8 of eax) has j
  shr eax, 8
  dec r9b
  mov byte r11b, [discard + eax]        ; r11b = all_cards[j]
  mov byte r12b, [discard + r9d]
  mov byte [deck + r9d], r11b     ; all_cards[i] = r11b
  mov byte [discard + eax], r12b        ; all_cards[j] = r2b

  inc r10d

  cmp r9b, 0
  jg .shuffleLoop

  ; move the last element in
  mov byte r11b, [discard]
  mov byte [deck], r11b
  ; top in discard
  mov byte [discard], r13b
  mov byte [discard_len], 1
  
.exec_draw_card:
  dec r8b
  mov byte [deck_len], r8b      ; decrement deck_len
  mov byte r8b, [deck + r8d]    ; fetch item at pos
  mov byte r9b, [hand1_len]
  mov byte [hand1 + r9d], r8b; store
  inc r9b
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
  ; Ace of spades all the wy to King of hearts
  xor ecx, ecx
.initCardsLoop:
	mov byte [all_cards + ecx], cl
  inc cl
  cmp cl, 52
	jl .initCardsLoop

  ; shuffle
  ; generate random nums - getrandom(buf, 51, 0)
  mov esi, 51                   ; len
  call getrandom

  ; fisher-yates shuffle the array
  mov r9d, 52
  mov r10d, rand                ; iterate through rand (let's call the idx k)
.shuffleLoop:
  ;xor eax, eax                  ; clear eax
  mov byte al, [r10]            ; j = rand[k] % (r8b + 2)
  div r9b                       ; now ah (upper 8 of eax) has j
  shr eax, 8
  dec r9b
  mov byte r12b, [all_cards + r9d]     ; r12b = all_cards[i]
  mov byte r11b, [all_cards + eax]        ; r11b = all_cards[j]
  mov byte [all_cards + r9d], r11b     ; all_cards[i] = r11b
  mov byte [all_cards + eax], r12b        ; all_cards[j] = r12b

  inc r10d

  cmp r9b, 0
  jg .shuffleLoop

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
turn_commands: db '[9H[J', 0xA, 'Your turn:', 0xA, '[d]raw [p]lace [e]xit'
turn_commands_len: equ $ - turn_commands
select_card_commands: db '[10H[JSelect card:', 0xA, '[←] left [→] right [⏎] select'
select_card_commands_len: equ $ - select_card_commands
hand2_pos: db '[2;11H'
hand1_pos: db '[7;11H'
dis_pos: db '[4;11H'
deck_pos: db '[5;11H'
pos_len: equ $ - deck_pos
dis_card_pos: db '[4;15H'
hand1_card_pos: db '[8H[K'
hand1_card_pos_len: equ $ - hand1_card_pos
hand1_select_pos: db '[9H[K['    ; + column number
hand1_select_pos_len: equ $ - hand1_select_pos
hand1_select_icon: db 'G↑'       ; 'G' is remaining from the CSI sequence above
hand1_select_icon_len: equ $ - hand1_select_icon
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
;; DATA STRUCTURE
;; Bits [0, 2): [0]: Spades [1]: Clubs [2]: Diamonds [3]: Hearts
;; Bits [2, 6): 4 bit integer representing rank. 0 is Ace. 12 is King.
;; 255 represents a null card
