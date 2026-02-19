org 100h
bits 16

jmp start

; ---------------------------
; Data
; ---------------------------
msg_title db 13,10,'FreeDOS Paint 1.0a (.COM)',13,10,'$'
msg_help  db 'Arrows=Move Space=Draw T=Text C=Color M=Mono R=Res L=Load B=Beep Q=Quit',13,10,'$'
msg_mode  db 'Mode switched.',13,10,'$'
msg_load_ok db 'Loaded BMP frame.',13,10,'$'
msg_load_gif db 'GIF detected (decode stub).',13,10,'$'
msg_load_bad db 'Only .BMP or .GIF allowed.',13,10,'$'
msg_open_err db 'Could not open file.',13,10,'$'
msg_bmp_bad db 'Unsupported BMP (need 8-bit uncompressed).',13,10,'$'

bar_title db 'FreeDOS Paint 1.0a',0
bar_file db 'File',0
bar_edit db 'Edit',0
bar_opts db 'Options',0
bar_help db 'Help',0
menu_new db 'New   Ctrl+N',0
menu_load db 'Load  Ctrl+L',0
menu_beep db 'Beep  Ctrl+B',0
menu_quit db 'Quit  Alt+X',0

filename db 'IMAGE.BMP',0

modes_count db 4
mode_index db 0
; type: 0=BIOS int10h mode, 1=VESA mode
modes:
  db 0,13h      ; VGA 320x200x256
  db 0,06h      ; CGA 640x200 mono
  db 1,01h,01h  ; VESA 640x480x256 (0x101)
  db 1,03h,01h  ; VESA 800x600x256 (0x103)

screen_w dw 320
screen_h dw 200
cursor_x dw 160
cursor_y dw 100
cur_color db 15
mono_mode db 0
text_mode db 0

menu_visible db 0
last_buttons dw 0
mouse_x dw 0
mouse_y dw 0

file_handle dw 0
row_stride dw 0
bmp_w dw 0
bmp_h dw 0

header_buf times 64 db 0
row_buf times 1024 db 0

; ---------------------------
; Code
; ---------------------------
start:
  mov ax, cs
  mov ds, ax
  mov es, ax

  call parse_cmdline

  mov dx, msg_title
  call print_dos
  mov dx, msg_help
  call print_dos

  call init_input_devices
  call apply_mode
  call clear_canvas
  call draw_ui

main_loop:
  call draw_cursor
  call poll_keyboard
  cmp al, 0
  jne handle_key

  call poll_mouse
  jmp main_loop

handle_key:
  cmp al, 'q'
  je exit_prog
  cmp al, 'Q'
  je exit_prog

  cmp al, ' '
  je do_draw
  cmp al, 'c'
  je do_color
  cmp al, 'C'
  je do_color
  cmp al, 'm'
  je do_mono
  cmp al, 'M'
  je do_mono
  cmp al, 'r'
  je do_res
  cmp al, 'R'
  je do_res
  cmp al, 'b'
  je do_beep
  cmp al, 'B'
  je do_beep
  cmp al, 'l'
  je do_load
  cmp al, 'L'
  je do_load
  cmp al, 't'
  je do_text_toggle
  cmp al, 'T'
  je do_text_toggle

  cmp al, 0
  jne check_printable
  ; extended key in AH
  cmp ah, 48h
  je key_up
  cmp ah, 50h
  je key_down
  cmp ah, 4Bh
  je key_left
  cmp ah, 4Dh
  je key_right
  jmp main_loop

check_printable:
  cmp byte [text_mode], 1
  jne main_loop
  cmp al, 32
  jb main_loop
  cmp al, 126
  ja main_loop
  call draw_char_at_cursor
  add word [cursor_x], 8
  mov ax, [screen_w]
  sub ax, 8
  cmp [cursor_x], ax
  jbe main_loop
  mov word [cursor_x], 0
  add word [cursor_y], 8
  jmp main_loop

key_up:
  cmp word [cursor_y], 16
  jbe main_loop
  dec word [cursor_y]
  jmp main_loop
key_down:
  mov ax, [screen_h]
  dec ax
  cmp [cursor_y], ax
  jae main_loop
  inc word [cursor_y]
  jmp main_loop
key_left:
  cmp word [cursor_x], 0
  je main_loop
  dec word [cursor_x]
  jmp main_loop
key_right:
  mov ax, [screen_w]
  dec ax
  cmp [cursor_x], ax
  jae main_loop
  inc word [cursor_x]
  jmp main_loop

do_draw:
  mov cx, [cursor_x]
  mov dx, [cursor_y]
  call put_pixel
  jmp main_loop

do_color:
  inc byte [cur_color]
  jmp main_loop

do_mono:
  xor byte [mono_mode], 1
  jmp main_loop

do_text_toggle:
  xor byte [text_mode], 1
  jmp main_loop

do_res:
  inc byte [mode_index]
  mov al, [mode_index]
  cmp al, [modes_count]
  jb .ok
  mov byte [mode_index], 0
.ok:
  call apply_mode
  call clear_canvas
  call draw_ui
  mov dx, msg_mode
  call print_dos
  jmp main_loop

do_beep:
  call pc_beep
  jmp main_loop

do_load:
  call load_image
  call draw_ui
  jmp main_loop

exit_prog:
  mov ax, 0003h
  int 10h
  mov ax, 4C00h
  int 21h

; ---------------------------
; Input/UI
; ---------------------------
poll_keyboard:
  mov ah, 01h
  int 16h
  jz .none
  mov ah, 00h
  int 16h
  ret
.none:
  xor ax, ax
  ret

poll_mouse:
  mov ax, 0003h
  int 33h
  mov [last_buttons+2], bx
  mov [mouse_x], cx
  mov [mouse_y], dx

  mov ax, [last_buttons]
  test ax, 1
  jnz .store
  test bx, 1
  jz .store
  call handle_left_click
.store:
  mov [last_buttons], bx
  ret

handle_left_click:
  ; top bar click zones
  mov ax, [mouse_y]
  cmp ax, 15
  ja .menu_items
  mov ax, [mouse_x]
  cmp ax, 40
  jbe .file
  jmp .done
.file:
  cmp byte [menu_visible], 0
  je .open
  call animate_close_menu
  jmp .done
.open:
  call animate_open_menu
  jmp .done

.menu_items:
  cmp byte [menu_visible], 1
  jne .done
  mov ax, [mouse_x]
  cmp ax, 140
  ja .done
  mov ax, [mouse_y]
  cmp ax, 16
  jb .done
  cmp ax, 48
  jb .item0
  cmp ax, 56
  jb .item1
  cmp ax, 64
  jb .item2
  cmp ax, 72
  jb .item3
  jmp .done
.item0:
  call clear_canvas
  call draw_ui
  call animate_close_menu
  jmp .done
.item1:
  call load_image
  call draw_ui
  call animate_close_menu
  jmp .done
.item2:
  call pc_beep
  call animate_close_menu
  jmp .done
.item3:
  jmp exit_prog
.done:
  ret

animate_open_menu:
  mov byte [menu_visible], 1
  mov cl, 1
.step:
  push cx
  call draw_ui
  pop cx
  call delay_50ms
  inc cl
  cmp cl, 6
  jb .step
  ret

animate_close_menu:
  mov cl, 5
.step:
  push cx
  call draw_ui
  pop cx
  call delay_50ms
  dec cl
  jnz .step
  mov byte [menu_visible], 0
  call draw_ui
  ret

draw_ui:
  call draw_top_bar
  cmp byte [menu_visible], 1
  jne .done
  call draw_file_menu
.done:
  ret

draw_top_bar:
  ; fill y=0..15
  xor dx, dx
.y:
  xor cx, cx
.x:
  mov al, 1
  mov ah, 0Ch
  int 10h
  inc cx
  cmp cx, [screen_w]
  jb .x
  inc dx
  cmp dx, 16
  jb .y

  mov dh, 0
  mov dl, 0
  mov si, bar_title
  mov bl, 15
  call draw_text_at
  mov dl, 24
  mov si, bar_file
  call draw_text_at
  mov dl, 30
  mov si, bar_edit
  call draw_text_at
  mov dl, 36
  mov si, bar_opts
  call draw_text_at
  mov dl, 45
  mov si, bar_help
  call draw_text_at
  ret

draw_file_menu:
  ; simple dropdown area x=0..140, y=16..79
  mov dx, 16
.y:
  xor cx, cx
.x:
  mov al, 8
  mov ah, 0Ch
  int 10h
  inc cx
  cmp cx, 141
  jb .x
  inc dx
  cmp dx, 80
  jb .y

  mov dh, 2
  mov dl, 1
  mov si, menu_new
  mov bl, 15
  call draw_text_at
  mov dh, 3
  mov si, menu_load
  call draw_text_at
  mov dh, 4
  mov si, menu_beep
  call draw_text_at
  mov dh, 5
  mov si, menu_quit
  call draw_text_at
  ret

draw_text_at:
  push ax
  push bx
  push cx
  push dx
  mov ah, 02h
  xor bh, bh
  int 10h
.next:
  lodsb
  cmp al, 0
  je .done
  mov ah, 0Eh
  xor bh, bh
  int 10h
  jmp .next
.done:
  pop dx
  pop cx
  pop bx
  pop ax
  ret

draw_char_at_cursor:
  push ax
  push bx
  push dx
  mov ax, [cursor_y]
  shr ax, 3
  mov dh, al
  mov ax, [cursor_x]
  shr ax, 3
  mov dl, al
  mov ah, 02h
  xor bh, bh
  int 10h
  mov bl, [cur_color]
  mov ah, 0Eh
  xor bh, bh
  int 10h
  pop dx
  pop bx
  pop ax
  ret

; ---------------------------
; Utils
; ---------------------------
print_dos:
  mov ah, 09h
  int 21h
  ret

init_input_devices:
  ; Mouse driver (PS/2 and many USB legacy BIOS paths expose int33h)
  mov ax, 0000h
  int 33h
  mov ax, 0001h
  int 33h
  ret

apply_mode:
  xor ax, ax
  mov al, [mode_index]
  mov bl, al
  xor bh, bh
  mov ax, bx
  shl bx, 1
  add bx, ax
  add bx, modes

  mov al, [bx]
  cmp al, 0
  jne .vesa
  mov al, [bx+1]
  mov ah, 00h
  int 10h
  cmp al, 13h
  jne .check_cga
  mov word [screen_w], 320
  mov word [screen_h], 200
  jmp .done
.check_cga:
  mov word [screen_w], 640
  mov word [screen_h], 200
  jmp .done
.vesa:
  mov ax, 4F02h
  mov bl, [bx+1]
  mov bh, [bx+2]
  int 10h
  cmp bx, 0101h
  jne .vesa800
  mov word [screen_w], 640
  mov word [screen_h], 480
  jmp .done
.vesa800:
  mov word [screen_w], 800
  mov word [screen_h], 600
.done:
  mov ax, [screen_w]
  shr ax, 1
  mov [cursor_x], ax
  mov ax, [screen_h]
  shr ax, 1
  mov [cursor_y], ax
  cmp word [cursor_y], 16
  jae .ok
  mov word [cursor_y], 16
.ok:
  ret

clear_canvas:
  mov dx, 16
.row:
  cmp dx, [screen_h]
  jae .done
  xor cx, cx
.col:
  mov al, 0
  mov ah, 0Ch
  int 10h
  inc cx
  cmp cx, [screen_w]
  jb .col
  inc dx
  jmp .row
.done:
  ret

draw_cursor:
  mov cx, [cursor_x]
  mov dx, [cursor_y]
  cmp dx, 16
  jb .done
  push ax
  mov al, [cur_color]
  xor al, 0Fh
  cmp byte [mono_mode], 0
  je .ok
  mov al, 15
.ok:
  mov ah, 0Ch
  xor bh, bh
  int 10h
  pop ax
.done:
  ret

put_pixel:
  push ax
  mov al, [cur_color]
  cmp byte [mono_mode], 0
  je .normal
  and al, 1
  shl al, 4
.normal:
  mov ah, 0Ch
  xor bh, bh
  int 10h
  pop ax
  ret

pc_beep:
  in al, 61h
  push ax
  or al, 03h
  out 61h, al
  mov al, 0B6h
  out 43h, al
  mov ax, 1193
  out 42h, al
  mov al, ah
  out 42h, al
  mov cx, 0FFFFh
.wait:
  loop .wait
  pop ax
  out 61h, al
  ret

delay_50ms:
  mov cx, 25000
.d:
  loop .d
  ret

; ---------------------------
; Loading (.BMP and .GIF only)
; ---------------------------
load_image:
  call has_supported_ext
  cmp al, 1
  jne .bad

  mov dx, filename
  mov ax, 3D00h
  int 21h
  jc .open_err
  mov [file_handle], ax

  mov bx, ax
  mov dx, header_buf
  mov cx, 64
  mov ah, 3Fh
  int 21h
  jc .close_bad

  cmp byte [header_buf], 'B'
  jne .maybe_gif
  cmp byte [header_buf+1], 'M'
  jne .maybe_gif
  call load_bmp_8bit
  jmp .close_ok

.maybe_gif:
  cmp byte [header_buf], 'G'
  jne .bad_type
  cmp byte [header_buf+1], 'I'
  jne .bad_type
  cmp byte [header_buf+2], 'F'
  jne .bad_type
  mov dx, msg_load_gif
  call print_dos
  jmp .close_ok

.bad_type:
  mov dx, msg_load_bad
  call print_dos
  jmp .close_ok

.open_err:
  mov dx, msg_open_err
  call print_dos
  ret

.close_bad:
  mov dx, msg_open_err
  call print_dos

.close_ok:
  mov bx, [file_handle]
  mov ah, 3Eh
  int 21h
  ret

.bad:
  mov dx, msg_load_bad
  call print_dos
  ret

load_bmp_8bit:
  mov ax, [header_buf+18]
  mov [bmp_w], ax
  mov ax, [header_buf+22]
  mov [bmp_h], ax

  mov ax, [header_buf+28]
  cmp ax, 8
  jne .bad
  mov ax, [header_buf+30]
  cmp ax, 0
  jne .bad

  mov ax, 4200h
  mov bx, [file_handle]
  mov dx, [header_buf+10]
  xor cx, cx
  int 21h

  mov ax, [bmp_w]
  add ax, 3
  and ax, 0FFCh
  mov [row_stride], ax

  mov si, [bmp_h]
.row_loop:
  cmp si, 0
  je .ok
  dec si

  mov bx, [file_handle]
  mov dx, row_buf
  mov cx, [row_stride]
  mov ah, 3Fh
  int 21h

  mov dx, si
  xor di, di
.pix_loop:
  cmp di, [bmp_w]
  jae .row_loop
  mov cx, di
  cmp cx, [screen_w]
  jae .next

  push dx
  mov ax, [bmp_h]
  dec ax
  sub ax, dx
  add ax, 16
  mov dx, ax
  cmp dx, [screen_h]
  jae .popnext

  mov al, [row_buf+di]
  mov [cur_color], al
  mov cx, di
  call put_pixel
.popnext:
  pop dx
.next:
  inc di
  jmp .pix_loop

.ok:
  mov dx, msg_load_ok
  call print_dos
  ret
.bad:
  mov dx, msg_bmp_bad
  call print_dos
  ret

has_supported_ext:
  mov si, filename
.find_end:
  lodsb
  cmp al, 0
  je .no
  cmp al, '.'
  jne .find_end
  mov al, [si]
  or al, 20h
  cmp al, 'b'
  je .check_bmp
  cmp al, 'g'
  je .check_gif
  jmp .no
.check_bmp:
  mov al, [si+1]
  or al, 20h
  cmp al, 'm'
  jne .no
  mov al, [si+2]
  or al, 20h
  cmp al, 'p'
  jne .no
  mov al, 1
  ret
.check_gif:
  mov al, [si+1]
  or al, 20h
  cmp al, 'i'
  jne .no
  mov al, [si+2]
  or al, 20h
  cmp al, 'f'
  jne .no
  mov al, 1
  ret
.no:
  xor al, al
  ret

parse_cmdline:
  mov si, 80h
  mov cl, [si]
  jcxz .done
  inc si
.skip_spaces:
  cmp cl, 0
  je .done
  mov al, [si]
  cmp al, ' '
  jne .copy
  inc si
  dec cl
  jmp .skip_spaces
.copy:
  mov di, filename
.copy_loop:
  cmp cl, 0
  je .term
  mov al, [si]
  cmp al, ' '
  je .term
  stosb
  inc si
  dec cl
  jmp .copy_loop
.term:
  mov al, 0
  stosb
.done:
  ret
