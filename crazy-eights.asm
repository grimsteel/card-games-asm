;; Crazy eights under 3KB in Intel x86-64 ASM
;; Multiplayer support using Linux UDP sockets
  
;; Built for Linux. Assembled using NASM.

struc termios
  resb 12
.c_lflag: resb 12
  resb 44
endstruc

struc sockaddr_in
.sin_len: resb 1
.sin_family: resb 1
.sin_port: resb 2
.sin_addr: resb 4
.sin_zero: resb 8
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
  ;xor edi, edi
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
  ; set all to 255 (two hands + deck + discard)
  xor cl, cl
.loop1:
  mov byte [deck + ecx], 255
  inc cl
  cmp cl, 50 * 4
  jl .loop1

  ; Ace of spades all the wy to King of hearts
  xor cl, cl
.loop2:
	mov byte [all_cards + ecx], r8b
  inc cl
  cmp cl, 52
	jl .loop2

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
.loop3:
  mov r9b, r8b
  add r9b, 2                    ; 0 <= j <= i, r8b = i - 1, so the range is r8b + 2
  xor eax, eax                  ; clear eax
  mov byte al, [r10]            ; j = rand[k] % (r8b + 2)
  div r9b                       ; now ah (lower 8 of eax) has j
  shr eax, 8                         ; take lower 8 bits (remainder
  mov byte r9b, [all_cards + r8 + 1]     ; r9b = all_cards[r8b + 1] = all_cards[i]
  mov byte r11b, [all_cards + eax]        ; r11b = all_cards[j]
  mov byte [all_cards + r8 + 1], r11b     ; all_cards[i] = r11b
  mov byte [all_cards + eax], r9b        ; all_cards[j] = r9b

  inc r10b
  
  dec r8b
  jnz .loop3
  
  ret

open_socket:
  ; sock_fd = socket(AF_INET, SOCK_STREAM_TCP)
  mov eax, 41                   ; socket
  mov edi, 2                    ; AF_INET
  mov esi, 1                    ; SOCK_STREAM
  xor edx, 6                    ; TCP
  syscall
  mov [sock_fd], al             ; store return val in sock_fd

  ; bind(sock_fd, sock_addr_buf, sockaddr_in_size)
  mov dil, al                  ; fd in param 1
  mov al, 49                   ; bind
  mov esi, sock_addr_buf
  mov dl, sockaddr_in_size
  syscall

  ; listen(sock_fd, 0)
  mov eax, 50
  xor edi, edi                  ; backlog
  syscall
  
  ret

close_socket:
  mov eax, 3                    ; close
  xor edi, edi
  mov dil, [sock_fd]            ; arg 1 = fd
  syscall
  ret
  
print_deck:
  mov r8b, 52
.loop:
  mov r9b, [all_cards + r8]

  dec r8b
  jnz .loop
  ret

section .data
welcome: db `\033[?25l\033[H\033[J\033[36mCrazy Eights:\033[m\n[h]ost [c]onnect [e]xit`
welcome_len: equ $ - welcome
bye: db `\nBye\033[?25h\n`
bye_len: equ $ - bye
sock_addr_buf:
istruc sockaddr_in
at .sin_len, db 0
at .sin_family, db 2            ; AF_INET
at .sin_port, dw 9999
at .sin_addr, dd 0              ; 0.0.0.0
at .sin_zero, dq 0 
iend
section .bss
termios_buf: resb termios_size
; all cards
all_cards: resb 52
; if the deck had 51 or 52 cards, somebody would have won
deck: resb 50
discard: resb 50
hand1: resb 50
hand2: resb 50
rand: resb 51
sock_fd: resb 1
;; DATA STRUCTURE
;; Bits [0, 2): [0]: Spades [1]: Clubs [2]: Diamonds [3]: Hearts
;; Bits [2, 6): 4 bit integer representing rank. 0 is Ace. 12 is King.
;; 255 represents a null card
