format PE console
entry start
 
include "include/win32a.inc"

;======================================
section '.data' data readable writeable
;======================================
        URL             db "http://xxx.xxx.xxx.xxx/a.htm", 0         ; The link of the file we'd like to download.
        SaveAs          db "mytest.txt", 0                                            ; The name the file should receive after it has been downloaded. (e.g. 'test.txt')
        InetHandle      dd ?
        UrlHandle       dd ?
        FileHandle      dd ?
        ReadNext        dd ?
        DownloadBuffer  rb 1024d
        BufferLength    = $ - DownloadBuffer                            ; BufferLength = 1024 as well
        BytesWritten    dd ?
        TmpDir            rb 256d
;=======================================
section '.code' code readable executable
;=======================================
 
start:
        ;;=== build the saveAs file name
        invoke GetTempPath,TmpDir, TmpDir
        ;Copy tempdir into aSTR
        invoke  lstrcat,TmpDir,SaveAs

        invoke InternetOpen,URL,0,0,0,0                                 ; Initializes use of the WinINet functions
 
        cmp eax, 0                                                      ; Check if an error occured
        je DownloadFileError                                            ; Error occured - Jump to DownloadFileError
        mov dword [InetHandle], eax                                     ; Else - Save the Internet handle
 
        invoke InternetOpenUrl,dword [InetHandle],URL,0,0,0,0           ; Open internet resource (specified by a complete FTP or HTTP URL)
 
        cmp eax, 0                                                      ; Check if an error occured
        je DownloadFileError                                            ; Error occured - Jump to DownloadFileError
        mov dword [UrlHandle], eax                                      ; Else - Save the URL handle
 
        ; Now create the file on our harddisk drive:
        invoke CreateFile,TmpDir,GENERIC_WRITE,FILE_SHARE_WRITE,0,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,0
 
        cmp eax, 0                                                      ; Check if an error occured
        je DownloadFileError                                            ; Error occured - Jump to DownloadFileError
        mov dword [FileHandle], eax                                     ; Else - Save the File Handle
        inc dword [ReadNext]                                            ; Read more data from the download stream
 
ReadNextBytes:
        cmp dword [ReadNext], 0                                         ; No bytes read? That would mean we finished the download
        je DownloadComplete                                             ; Yes? Ok finish the download.
 
        ; Read data from the internet resource
        invoke InternetReadFile,dword [UrlHandle],DownloadBuffer,BufferLength,ReadNext
 
        ; And write the read data to our local file
        invoke WriteFile,dword [FileHandle],DownloadBuffer,dword [ReadNext],BytesWritten,0
 
        ; Continue reading bytes from the internet resource
        jmp ReadNextBytes
 
DownloadComplete:
        invoke CloseHandle,dword [FileHandle]                           ; 1. Close the file handle
        invoke InternetCloseHandle,dword [UrlHandle]                    ; 2. Close the Url handle
        invoke InternetCloseHandle,dword [InetHandle]                   ; 3. Close the Internet handle
 
DownloadFileError:
        jmp Exit                                                        ; In case an error occurs, we simply quit the application rather than doing error handling. Todo?
 
Exit:
        invoke ExitProcess,0                                            ; Here's where we exit the application.
 
;====================================
section '.idata' import data readable
;====================================
library kernel,              "kernel32.dll",\
        wininet,             "wininet.dll"
 
import  kernel,\
        WriteFile,           "WriteFile",\
        CreateFile,          "CreateFileA",\
        CloseHandle,         "CloseHandle",\
        ExitProcess,         "ExitProcess",\
        GetTempPath,            "GetTempPathA",\
        lstrcat,                "lstrcat"

 
import  wininet,\
        InternetOpen,        "InternetOpenA",\
        InternetOpenUrl,     "InternetOpenUrlA",\
        InternetReadFile,    "InternetReadFile",\
        InternetCloseHandle, "InternetCloseHandle"