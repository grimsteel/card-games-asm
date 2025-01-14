;; Crazy eights under 3KB in Intel x86-64 ASM
;; Multiplayer support using Linux UDP sockets
  
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
  call open_socket

main_loop:
  mov esi, welcome
  mov edx, welcome_len
  call print

  call getc
  sub eax, 'e'
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

  call close_socket
  
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
  ; set all to 255 (two hands + deck + discard)
  xor r8d, r8d                  ; clear r8
  mov r8b, 50 * 4
.loop1:
  mov byte [deck + r8], 255
  dec r8b
  jnz .loop1

  ; Ace of spades all the wy to King of hearts
	mov r8b, 52
.loop2:
	mov byte [all_cards + r8], r8b
	dec r8b
	jnz .loop2

  ; shuffle
  ; generate random nums
  mov eax, 318                  ; getrandom
  mov edi, rand                 ; buf
  mov esi, 51                   ; len
  xor edx, edx                  ; flags
  syscall

  ; fisher-yates (n-2 to 0)
  mov r8b, 50
  mov r10d, rand                ; iterate through rand (let's call the idx k)
.loop3:
  mov r9b, r8b
  add r9b, 2                    ; 0 <= j <= i, r8b = i - 1, so the range is r8b + 2
  mov eax, [r10]                ; j = rand[k] % (r8b + 2)
  xor edx, edx
  div r9b                       ; now edx has j
  mov r11b, [rand + r8 + 1]     ; r11b = rand[r8b + 1] = rand[i]
  mov r12b, [rand + edx]        ; r12b = rand[j]
  mov [rand + r8 + 1], r12b     ; rand[i] = r12b
  mov [rand + edx], r11b        ; rand[j] = r11b
  
  dec r8b
  inc r10b
  jnz .loop3
  
  ret

open_socket:
  mov eax, 41                   ; socket
  mov edi, 2                    ; AF_INET
  mov esi, edi                  ; SOCK_DGRAM
  xor edx, edx                  ; protocol (0)
  syscall
  mov [sock_fd], al             ; store return val in sock_fd

  mov edi, eax                  ; fd in param 1
  mov eax, 49                   ; bind
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
