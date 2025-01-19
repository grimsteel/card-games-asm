%ifndef SYS_ASM
%define SYS_ASM

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

;; Print a number in dil between 0 and 99, inclusive
print_num:
  xor eax, eax
  xor r9d, r9d
  mov al, dil                   ; al = r8b / 10, dh = r8b % 10
  mov r9b, 10
  div r9b
  
  ; make the numbers digits
  or eax, '00'

  push rax
  mov rsi, rsp

  mov edx, 2
  call print

  pop rax
  ret

open_socket:
  ; sock_fd = socket(AF_INET, SOCK_STREAM, TCP)
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

;; get `esi` random bytes into `rand` (max 51)
getrandom:
  mov eax, 318                  ; getrandom
  mov edi, rand                 ; buf
  xor edx, edx                  ; flags
  syscall
  ret

section .data
sock_addr_buf:
istruc sockaddr_in
at sockaddr_in.sin_len, db 0
at sockaddr_in.sin_family, db 2            ; AF_INET
at sockaddr_in.sin_port, dw 9999
at sockaddr_in.sin_addr, dd 0              ; 0.0.0.0
at sockaddr_in.sin_zero, dq 0 
iend
section .bss
termios_buf: resb termios_size
sock_fd: resb 1
rand: resb 51
%endif
