%ifndef SYS_ASM
%define SYS_ASM

struc termios
  resb 12
.c_lflag: resb 12
  resb 44
endstruc

struc sockaddr_in
.sin_family: resw 1
.sin_port: resw 1
.sin_addr: resd 1
.sin_zero: resq 1
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
  xor esi, esi
  inc esi                       ; esi = 1 = SOCK_STREAM
  mov edi, esi
  inc edi                       ; edi = 2 = AF_INET
  xor edx, edx
  syscall
  mov byte [sock_fd], al             ; store return val in sock_fd

  mov dil, al                  ; fd in param 1 of most calls
  ret

create_tcp_server:
  call prompt_addr
  call open_socket
  
  ; bind(sock_fd, sock_addr_buf, sockaddr_in_size)
  mov al, 49                   ; bind
  mov esi, sock_addr_buf
  mov edx, sockaddr_in_size
  syscall

  ; listen(sock_fd, 0)
  mov al, 50
  xor esi, esi                  ; backlog
  syscall

  ; accept(sock_fd, NULL, NULL, 0)
  mov al, 43
  xor esi, esi
  xor edx, edx
  xor ecx, ecx
  syscall

  mov byte [conn_fd], al        ; store connection fd
  
  ret

create_tcp_client:
  call prompt_addr
  call open_socket

  ; connect(sock_fd, sock_addr_buf, sockaddr_in_size)
  mov al, 42
  mov esi, sock_addr_buf
  mov dl, sockaddr_in_size
  syscall

  ; conn_fd == sock_fd for clients
  mov byte [conn_fd], dil

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

prompt_addr:
  ; enable canon
  or dword [termios_buf + termios.c_lflag], 0x0A ; CANON + ECHO
  mov esi, TCSETS
  call tcgetorset

  mov esi, addr_prompt
  mov edx, addr_prompt_len
  call print

  ; read
  xor eax, eax                  ; 0 (read)
  xor edi, edi                  ; 0 (stdin)
  mov esi, input_addr
  mov edx, 22                   ; max len
  syscall

  ; start parsing ip addr
  xor r8d, r8d
  mov r9d, input_addr
  mov r13d, 10
  xor r11d, r11d

  mov r12b, 4
.ip_addr_loop:
  xor eax, eax
  shl r8d, 8
  
  mov ecx, 3
.octet_loop:
  cmp byte [r9d], '.'
  je .octet_loop_end
  cmp byte [r9d], ':'
  je .octet_loop_end
  mul r13d
  mov byte r11b, [r9d]
  sub r11b, '0'
  add eax, r11d
  inc r9d                       ; next digit
  loop .octet_loop
  
.octet_loop_end:
  or r8d, eax                   ; OR it in

  inc r9d                       ; move past "." or ":"

  dec r12b
  jnz .ip_addr_loop

  ; port - 5 digits
  xor eax, eax
  mov ecx, 5
.port_loop:
  cmp byte [r9d], 0xA
  je .port_loop_end
  mul r13d
  mov byte r11b, [r9d]
  sub r11b, '0'
  add eax, r11d
  inc r9d
  loop .port_loop

.port_loop_end:
  ; set fields
  mov word [sock_addr_buf + sockaddr_in.sin_family], 2 ; AF_INET
  movbe word [sock_addr_buf + sockaddr_in.sin_port], ax ; port - swap bytes (big-endian)
  movbe dword [sock_addr_buf + sockaddr_in.sin_addr], r8d ; address - reverse byte order (big endian)
  
  ; disable canon, print waiting msg
  and dword [termios_buf + termios.c_lflag], ~(0x0A) ; ~(CANON | ECHO)
  mov esi, TCSETS
  call tcgetorset

  mov esi, waiting
  mov edx, waiting_len
  call print
  ret

section .data
addr_prompt: db '[2H[J[?25hAddr: '
addr_prompt_len: equ $ - addr_prompt
waiting: db '[?25lWaiting...'
waiting_len: equ $ - waiting
section .bss
termios_buf: resb termios_size
sock_fd: resb 1
conn_fd: resb 1
rand: resb 51
input_addr: resb 22             ; 000.000.000.000:00000\n
sock_addr_buf: resb sockaddr_in_size
%endif
