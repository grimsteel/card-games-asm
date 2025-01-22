;; Crazy eights under 3KB in Intel x86-64 ASM
;; Multiplayer support using Linux UDP sockets
  
;; Built for Linux. Assembled using NASM.

;; Copyright (C) 2025 Siddhant Kameswar (@grimsteel)

;; This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

;; This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License along with this program. If not, see <https://www.gnu.org/licenses/>. 

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
  mov esi, welcome
  mov edx, welcome_len
  call print

  call getc
  cmp eax, 'e'
  je quit.exit ; quit when they press e
  cmp eax, 'c'
  je connect
host:
  ; create server and wait for connection
  call create_tcp_server
  ; shuffle cards
  call init_shuffle_cards
  ; send data over
  inc eax                       ; eax = 1
  xor edi, edi
  mov byte dil, [conn_fd]
  mov esi, all_cards
  mov edx, 52
  syscall
  call initial_print
  jmp game_loop_host_start
connect:
  call create_tcp_client
  ; recv data
  xor edi, edi
  mov byte dil, [conn_fd]

  ; first 7 into hand2
  mov esi, hand2
  mov edx, 7
  mov byte [hand2_len], dl
  syscall
  ; next 7 into hand1
  mov esi, hand1
  mov edx, eax                  ; eax = 7
  xor eax, eax
  mov byte [hand1_len], dl
  syscall
  ; next 1 into discard
  mov esi, discard
  mov1 edx
  xor eax, eax
  mov byte [discard_len], dl
  syscall
  ; next 37 into deck
  mov esi, deck
  mov edx, 37
  dec eax                       ; eax = 1, -> eax = 0
  mov byte [deck_len], dl
  syscall

  ; wait for host move
  call initial_print
game_loop:
  call print_board_values
  call wait_other_player
game_loop_no_wait:
  call print_board_values
  
  ; print menu
game_loop_host_start:
  mov esi, turn_commands
  mov edx, turn_commands_len
  call print
  call getc

  xor r8d, r8d

  cmp eax, 'e'
  je quit
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
  xor r13b, r12b                ; lower 2 bits will be 0 if same suit
  and r13b, 0x3                 ; clear other bits
  cmp byte r13b, 0              ; if 0, then same suit
  je .place_card_exec
  mov r13b, r11b
  and r13b, 0x3C                ; upper 4 bits
  cmp r13b, 0x1C               ; rank 8
  je .place_card_exec
  xor r13b, r12b                ; upper 4 bits will be 0 if same rank
  cmp byte r13b, 3              ; if 0, 1, 2, or 3, then same rank
  jg game_loop_no_wait                ; invalid selection
.place_card_exec:
  ; dec hand size
  mov byte [hand1_len], r10b
  cmp r10b, 0
  je player1_win
  ; swap with last
  mov byte r10b, [hand1 + r10d] ; last card
  mov byte [hand1 + r8d], r10b
  ; add this card to the discard
  mov byte [discard + r9d], r11b
  ; inc discard size
  inc r9b
  mov byte [discard_len], r9b

  mov r13b, r11b                ; store for below

  ; notify other player (r8 already has card idx)
  mov1 eax                      ; write
  call stack_read_write_conn

  ; eight card - change suit
  shr r13b, 2
  cmp r13b, 0x7
  jne game_loop
.change_suit:
  mov esi, select_suit_commands
  mov byte dl, select_suit_commands_len
  call print
  call getc
  sub al, '0'
  shl r13b, 2
  or r13b, al
  dec r9b
  ; update discard
  mov byte [discard + r9d], r13b
  ; notify other player
  add al, 0x38
  mov byte r8b, al
  mov1 eax                      ; write
  call stack_read_write_conn
  jmp game_loop

draw_card:
  mov byte r8b, [deck_len]
  cmp r8b, 0
  jg .exec_draw_card
  ; handle empty deck
  xor r9d, r9d

  xor esi, esi
  mov byte sil, [discard_len]                   ; len
  dec esi                                       ; will shuffle discard_len - 1 elements to the deck
  jz game_loop_no_wait                          ; only 1 element in discard
  ; store the top element in the discard
  mov byte r13b, [discard + esi] ; esi = discard_len - 1
  mov r8b, sil                   ; r8b = loop idx
  dec esi                        ; need discard_len - 2 random numbers
  
  ; shuffle
  ; generate random nums - getrandom(buf, discard_len - 2, 0)
  call getrandom

  ; fisher-yates shuffle the discard back into the deck
  mov byte [deck_len], r8b        ; deck will now have discard_len - 1 elements
  mov r9b, r8b                    ; for writing the deck below
  mov r10d, rand                  ; init rand_ptr
.shuffleLoop:
  mov byte al, [r10]              ; j = rand_ptr % r8b -> r8b = i + 1
  div r8b                         ; now ah (upper 8 of eax) has j
  shr eax, 8
  dec r8b                         ; r8b--  -> r8b = i
  mov byte r11b, [discard + eax]  ; r11b = all_cards[j]
  mov byte r12b, [discard + r8d]
  mov byte [deck + r8d], r11b     ; all_cards[i] = r11b
  mov byte [discard + eax], r12b  ; all_cards[j] = r12b

  inc r10d                        ; advance rand_ptr

  cmp r8b, 0
  jg .shuffleLoop

  ; move the last element in
  mov byte r11b, [discard]
  mov byte [deck], r11b
  ; top in discard
  mov byte [discard], r13b
  mov byte [discard_len], 1

  ; notify other player
  mov r8d, 0x33
  mov1 eax
  call stack_read_write_conn
  ; eax is 1 (wrote 1 byte)
  ; edi is conn_fd
  mov esi, deck
  mov dl, r9b
  syscall
  mov r8b, r9b                  ; for exec_draw_card
  
.exec_draw_card:
  dec r8b
  mov byte [deck_len], r8b      ; decrement deck_len
  mov byte r8b, [deck + r8d]    ; fetch item at pos
  mov byte r9b, [hand1_len]
  mov byte [hand1 + r9d], r8b; store
  inc r9b
  mov byte [hand1_len], r9b
  ; notify other player
  mov r8d, 0x32
  mov1 eax
  call stack_read_write_conn
  
  jmp game_loop_no_wait

;; wait for complete from the other player
;; see bottom of file for protocol
wait_other_player:
  ; print message
  mov esi, waiting_for_other
  mov edx, waiting_for_other_len
  call print
.move_loop:
  xor eax, eax
  xor r8d, r8d
  call stack_read_write_conn
  cmp r8b, 0x32
  jl .place
  je .draw                      ; 0x32
  cmp r8b, 0x33
  je .reshuffle                 ; 0x33
  cmp r8b, 0x34
  je quit.exit                  ; 0x34
  cmp r8b, 0x35
  je player2_win                ; 0x35
.eight_card:                    ; 0x38 0x39 0x3A 0x3B
  and r8b, 0x3                  ; lower 2 bits
  or r8b, 0x1C                  ; rank 8 = 7 (0-indexed)  7 << 2 = 28 = 0x1C
  mov byte r9b, [discard_len]
  dec r9b
  ; replace top discard with the new 8
  mov byte [discard + r9d], r8b
  ret
.draw:                          ; 0x32
  mov byte r8b, [deck_len]
  dec r8b
  mov byte [deck_len], r8b      ; decrement deck_len
  mov byte r8b, [deck + r8d]    ; fetch item at pos
  mov byte r9b, [hand2_len]
  mov byte [hand2 + r9d], r8b; store
  inc r9b
  mov byte [hand2_len], r9b
  jmp .move_loop
.reshuffle:                     ; 0x33
  mov byte r8b, [discard_len]                   ; len
  dec r8b                                       
  mov byte r9b, [discard + r8d]                 ; move last element in discard to discard
  mov byte [discard], r9b
  mov byte [discard_len], 1                     ; make discard length 1
  mov byte [deck_len], r8b                      ; deck now has discard_len - 1 elements
  ; read shuffled cards into deck
  xor eax, eax
  mov esi, deck
  mov dl, r8b
  syscall
  jmp .move_loop
.place:                         ; less than 0x32 - place a card
  xor r10d, r10d
  mov byte r11b, [hand2 + r8d]
  mov byte r10b, [hand2_len]
  dec r10b
  mov byte [hand2_len], r10b
  ; swap with last
  mov byte r10b, [hand2 + r10d] ; last card
  mov byte [hand2 + r8d], r10b
  mov byte r9b, [discard_len]
  ; add this card to the discard
  mov byte [discard + r9d], r11b
  ; inc discard size
  inc r9b
  mov byte [discard_len], r9b
  shr r11b, 2
  cmp r11b, 0x7
  je .move_loop                 ; if it's an 8, wait for decision
  ret

initial_print:
  mov esi, board
  mov edx, board_len
  call print
  call print_board_values
  ret

player1_win:
  ; notify other player
  mov1 eax                      ; write
  mov r8d, 0x35
  call stack_read_write_conn
  
  mov esi, player1_win_msg
  mov edx, player1_win_msg_len
  call print
  jmp quit.exit

player2_win:
  mov esi, player2_win_msg
  mov edx, player2_win_msg_len
  call print
  jmp quit.exit
  
;; print hand, deck, and discard lengths
print_board_values:
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
.initHand1Loop:
  mov byte r9b, [r8d]
  mov byte [hand1 + ecx], r9b
  inc r8d
  inc cl
  cmp cl, 7
  jl .initHand1Loop

  mov byte [hand1_len], cl

  xor ecx, ecx
.initHand2Loop:
  mov byte r9b, [r8d]
  mov byte [hand2 + ecx], r9b
  inc r8d
  inc cl
  cmp cl, 7
  jl .initHand2Loop

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
  mov1 edx
  
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
welcome: db '[H[J[?25l[36mCrazy Eights:', 0xA, '[32m[h][most [32m[c][monnect'
welcome_len: equ $ - welcome
board: db '[2H[JThem:    [  ]', 0xA, 0xA, 'Discard: [  ]', 0xA, 'Deck:    [  ]', 0xA, 0xA, 'You:     [  ]'
board_len: equ $ - board
turn_commands: db '[9H[J', 0xA, 'Your turn:', 0xA, '[32m[d][mraw [32m[p][mlace [32m[e][mxit'
turn_commands_len: equ $ - turn_commands
waiting_for_other: db '[9H[J', 0xA, 'Waiting for other player…'
waiting_for_other_len: equ $ - waiting_for_other
select_card_commands: db '[10H[JSelect card:', 0xA, '[32m[←][m left [32m[→][m right [32m[⏎][m select'
select_card_commands_len: equ $ - select_card_commands
select_suit_commands: db '[9H[J', 0xA, 'Select suit:', 0xA, '[0] ♠ [1] ♣ [2] ♦ [3] ♥'
select_suit_commands_len: equ $ - select_suit_commands
player1_win_msg: db '[H[JYou won!'
player1_win_msg_len: equ $ - player1_win_msg
player2_win_msg: db '[H[JThe other player won.'
player2_win_msg_len: equ $ - player2_win_msg
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
;; CARD DATA STRUCTURE
;; Bits [0, 2): [0]: Spades [1]: Clubs [2]: Diamonds [3]: Hearts
;; Bits [2, 6): 4 bit integer representing rank. 0 is Ace. 12 is King.
;; 255 represents a null card

;; NETWORK PROTOCOL
;; Initially, 52 bytes are sent over the network. These are:
;; [0, 7): host player cards (hand1 on host, hand2 on guest)
;; [7, 14): guest player cards (hand2 on host, hand1 on guest)
;; [14, 15): discard
;; [15, 52): deck
;; A turn is a sequence of move bytes
;; [0x0, 0x32): place card at this index (max 50/0x32 cards in a hand). this ends a turn
;; [0x32, 0x33): draw top card
;; [0x33, 0x34): reshuffle deck. followed by n bytes, indicating the new cards in the deck. n is the current length of the discard - 1. the discard is emptied, with only the top card remaining
;; [0x34, 0x35): quit game early
;; [0x35, 0x36): sender has won
;; [0x38, 0x3C): eight card, spades, clubs, diamonds, hearts
;; Both the host and the guest are expected to keep track of state independently
;; The protocol is designed with the assumption that transmission is reliable
;; Both the host and the guest are expected to conform to this protocol
;; Player 1 always refers to the player this process is representing
;; Player 2 is the remote player
;; (Player 1 does not always mean host, or vice versa)
