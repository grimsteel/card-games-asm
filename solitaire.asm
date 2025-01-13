;; Solitaire under 3KB in Intel x86-64 ASM
  
;; Built for Linux. Assembled using NASM.

struc termios
  resb 12
.c_lflag: resb 12
  resb 44
endstruc
  
global _start
section .text
_start:
  ; disable terminal line buffering
  xor esi, esi
  call tcgetorset
  and dword [termios_buf + termios.c_lflag], ~(0b1010) ; CANON + ECHO
  xor esi, esi
  inc esi
  call tcgetorset
  
  xor eax, eax
  inc eax                       ; 1 (write)
  mov edi, eax                  ; 1 (stdout)

  mov esi, message ; message
  xor edx, edx
  mov dl, message_len
  syscall

  xor eax, eax                  ; 0 (read)
  xor edi, edi                  ; 0 (stdin)
  mov esi, input
  mov edx, 2
  syscall

  ; re-enable buffering
  or dword [termios_buf + termios.c_lflag], 0b1010 ; CANON + ECHO
  xor esi, esi
  inc esi
  call tcgetorset
  
  mov al, 60
  xor edi, edi
  syscall

tcgetorset:
  mov eax, 16                   ; IOCTL
  xor edi, edi                  ; 0 (stdin)
  add esi, 21505                ; TCGETS if 0, TCSETS if 1
  mov edx, termios_buf
  syscall
  ret

section .data
message: db `\033[36m\033[1mWelcome to Solitaire!\033[m\nPlay: space\nExit: q\n> `
message_len: equ $ - message
section .bss
input: resb 2
termios_buf: resb termios_size
  
