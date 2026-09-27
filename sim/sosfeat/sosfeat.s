; SOS features test: a SOS.INTERP that checks, on the machine, the features
; Rick Sidwell's "Undocumented Apple /// SOS Features" (1989) describes, as
; far as they rest on the hardware.  It runs under SOS 1.3 in place of a
; disk's own interpreter and shows P or F for each group:
;   1  MEMSIZE and SYSBANK: $08, $10 or $20 for 128K, 256K or 512K, and
;      MEMSIZE = SYSBANK * 2 + 4
;   2  D_READ .D1 block 0 (the boot block) and block 2 (the volume header)
;   3  D_READ errors: BYTECNT ($2C) for 256 bytes, BLKNUM ($2D) for block 280
;   4  D_WRITE .D2 block 279 and D_READ it back, then restore it
;   5  CLRBACK: SET_FILE_INFO keeps a new file's backup bit unless CLRBACK
;      comes first
;   6  globals: NMIPEND bit 7 clear, DISKBUSY 0, DFLTNMI set
;   7  keyboard NMI: RESET runs the interpreter's USRNMI handler
;   8  NMIDSBL: environment bit 4 clear, RESET and CONTROL-RESET ignored
;   9  NMIENBL: environment bit 4 set, RESET handled again
;   A  SUSPFLSH bit 7: CONTROL-7 on the keypad suspends, again resumes
;   B  SUSPFLSH bit 6: CONTROL-9 on the keypad flushes, again stops
;   C  DISKSW ($2E) from D_READ after drive 2's disk is swapped, then a read
;   D  NODRIVE ($28) with drive 2 empty
; It then calls SYSFAIL with $42, which shows SYSTEM FAILURE and saves the
; registers at $19F6-$19FF.  REQBUF, GETBUFADR and RELBUF are for device
; drivers only; SOS's own file buffers go through them in groups 4 and 5.
;
; The prompts say what to do; README.md has the harness script that does it.

        .setcpu "6502"

; SOS calls
D_READ   = $80
D_WRITE  = $81
GETDEVNM = $84
CREATE   = $C0
DESTROY  = $C1
SETINFO  = $C3
GETINFO  = $C4
OPEN     = $C8
READ     = $CA
WRITE    = $CB
CLOSE    = $CC

; SOS globals and entry points (page $19)
MEMSIZE  = $1900
SYSBANK  = $1901
SUSPFLSH = $1902
NMIPEND  = $1903
DFLTNMI  = $1904
SCRNMODE = $1906
GRAFMEM  = $1907
DISKBUSY = $1908
USRNMI   = $1910
NMIDSBL  = $1919
NMIENBL  = $191C
SYSFAIL  = $1925
CLRBACK  = $1934
EREG     = $FFDF

BYTECNT  = $2C
BLKNUM   = $2D
DISKSW   = $2E
NODRIVE  = $28
CR       = $0D
LF       = $0A                  ; the console's CR only returns the cursor

PTR      = $E0                  ; interpreter zero page ($1A00)
XPTR     = $1600 + PTR + 1      ; its X byte (page $16): 0, a plain address
GROUP    = $E2
TEMP     = $E3
WAIT     = $E4                  ; 3 bytes

.macro say string
        ldx #<string
        ldy #>string
        jsr puts
.endmacro

; A branch on carry set that reaches anywhere.
.macro jcs target
        bcc :+
        jmp target
:
.endmacro

; SOS returns its error code in A, 0 for none; carry is then set for an error.
.macro sos call, parms
        brk
        .byte call
        .word parms
        cmp #1
.endmacro

        .segment "HEADER"
        .byte "SOS NTRP"
        .word 0                 ; no extra header
        .word start
        .word code_end - start

        .segment "CODE"
start:  lda #0
        sta XPTR
        sta GROUP
        sta nmicount
        sos OPEN, open_con
        lda con_ref
        sta wr_ref
        sta rd_ref
        say options             ; the console's standard text options
        say title

; 1. MEMSIZE and SYSBANK
        say t_mem
        lda MEMSIZE
        jsr hex
        say t_sysbank
        lda SYSBANK
        jsr hex
        lda SYSBANK
        and #$0F
        asl a
        clc
        adc #4
        cmp MEMSIZE
        bne :+
        lda MEMSIZE
        cmp #$08
        beq :++
        cmp #$10
        beq :++
        cmp #$20
        beq :++
:       jmp fail1
:       jsr pass
        jmp group2
fail1:  jsr fail

; 2. D_READ .D1 blocks 0 and 2
group2: say t_dread
        sos GETDEVNM, dev_d1
        lda d1_num
        sta dr_dev
        lda #0
        sta dr_block
        sta dr_block+1
        sos D_READ, dread
        bcs @bad
        lda buffer
        cmp #$4C                ; a boot block starts with JMP
        bne @bad
        lda dr_xfer+1
        cmp #2
        bne @bad
        lda #2
        sta dr_block
        sos D_READ, dread
        bcs @bad
        lda buffer+4
        and #$F0
        cmp #$F0                ; volume directory header
        bne @bad
        jsr pass
        jmp group3
@bad:   jsr errcode
        jsr fail

; 3. D_READ errors
group3: say t_derr
        lda #0
        sta dr_count+1
        lda #1                  ; 256 bytes
        sta dr_count+1
        lda #0
        sta dr_block
        sos D_READ, dread
        sta TEMP
        jsr hex
        lda #2
        sta dr_count+1
        lda #<280
        sta dr_block
        lda #>280
        sta dr_block+1
        sos D_READ, dread
        pha
        jsr space
        pla
        pha
        jsr hex
        pla
        cmp #BLKNUM
        bne :+
        lda TEMP
        cmp #BYTECNT
        bne :+
        jsr pass
        jmp group4
:       jsr fail

; 4. D_WRITE .D2 block 279
group4: say t_dwrite
        sos GETDEVNM, dev_d2
        lda d2_num
        sta dr_dev
        sta dw_dev
        lda #<279
        sta dr_block
        sta dw_block
        lda #>279
        sta dr_block+1
        sta dw_block+1
        sos D_READ, dread       ; keep the block
        bcs @bad
        ldx #0
:       lda buffer,x
        sta saved,x
        lda buffer+256,x
        sta saved+256,x
        txa                     ; a pattern
        eor #$5A
        sta buffer,x
        eor #$FF
        sta buffer+256,x
        inx
        bne :-
        sos D_WRITE, dwrite
        bcs @bad
        ldx #0                  ; clear, read back, compare
        txa
:       sta buffer,x
        sta buffer+256,x
        inx
        bne :-
        sos D_READ, dread
        bcs @bad
        ldx #0
:       txa
        eor #$5A
        cmp buffer,x
        bne @differ
        eor #$FF
        cmp buffer+256,x
        bne @differ
        inx
        bne :-
        ldx #0                  ; put the block back
:       lda saved,x
        sta buffer,x
        lda saved+256,x
        sta buffer+256,x
        inx
        bne :-
        sos D_WRITE, dwrite
        bcs @bad
        jsr pass
        jmp group5
@differ:
        lda #$FF
@bad:   jsr errcode
        jsr fail

; 5. CLRBACK
group5: say t_clrback
        sos DESTROY, destroy_f  ; a leftover from an earlier run
        sos CREATE, create_f
        jcs @bad
        sos OPEN, open_f
        jcs @bad
        lda file_ref
        sta fw_ref
        sta cl_ref
        sos WRITE, fwrite
        jcs @bad
        sos CLOSE, close_f
        jsr getaccess
        jcs @bad
        sta TEMP                ; after the write: backup bit set
        jsr hex
        lda #$C3                ; set access without it
        sta si_access
        sos SETINFO, setinfo_f
        jcs @bad
        jsr getaccess
        jcs @bad
        pha                     ; SOS set it again
        jsr space
        pla
        pha
        jsr hex
        lda #0
        jsr CLRBACK
        sos SETINFO, setinfo_f
        jcs @bad2
        jsr getaccess
        jcs @bad2
        pha                     ; now clear
        jsr space
        pla
        pha
        jsr hex
        sos DESTROY, destroy_f
        pla
        and #$20
        bne @no
        pla
        and #$20
        beq @no2
        lda TEMP
        and #$20
        beq @no2
        jsr pass
        jmp group6
@no:    pla
@no2:   jsr fail
        jmp group6
@bad2:  tax
        pla
        txa
@bad:   jsr errcode
        jsr fail

; 6. Globals
group6: say t_globals
        lda NMIPEND
        jsr hex
        jsr space
        lda DISKBUSY
        jsr hex
        jsr space
        lda DFLTNMI+1
        jsr hex
        lda DFLTNMI
        jsr hex
        jsr space
        lda GRAFMEM
        jsr hex
        jsr space
        lda SCRNMODE
        jsr hex
        lda NMIPEND
        bmi :+
        lda DISKBUSY
        bne :+
        lda DFLTNMI
        ora DFLTNMI+1
        beq :+
        jsr pass
        jmp group7
:       jsr fail

; 7. Keyboard NMI through USRNMI
group7: lda #<nmi               ; USRNMI is a JMP
        sta USRNMI+1
        lda #>nmi
        sta USRNMI+2
        say t_nmi
        jsr getkey
        lda nmicount
        jsr hex
        lda nmicount
        bne :+
        jsr fail
        jmp group8
:       jsr pass

; 8. NMIDSBL
group8: jsr NMIDSBL
        say t_dsbl
        lda EREG
        pha
        jsr hex
        lda nmicount
        sta TEMP
        jsr getkey
        pla
        and #$10
        bne :+
        lda nmicount
        cmp TEMP
        bne :+
        jsr pass
        jmp group9
:       jsr fail

; 9. NMIENBL
group9: jsr NMIENBL
        say t_enbl
        lda EREG
        pha
        jsr hex
        lda nmicount
        sta TEMP
        jsr getkey
        lda DFLTNMI             ; hand keyboard NMIs back to SOS
        sta USRNMI+1
        lda DFLTNMI+1
        sta USRNMI+2
        pla
        and #$10
        beq :+
        lda nmicount
        cmp TEMP
        beq :+
        jsr pass
        jmp groupa
:       jsr fail

; A. Suspend: CONTROL-7 on the keypad, twice.  Nothing may be written while
; output is suspended, so the result waits for the second press.
groupa: say t_susp
        lda #$80
        jsr waitset
        bcs @no
        lda #$80
        jsr waitclear
        bcs @no
        jsr pass
        jmp groupb
@no:    jsr fail

; B. Flush: CONTROL-9 on the keypad, twice.
groupb: say t_flush
        lda #$40
        jsr waitset
        bcs @no
        lda #$40
        jsr waitclear
        bcs @no
        jsr pass
        jmp groupc
@no:    jsr fail

; C. Disk switched
groupc: say t_swap
        jsr getkey
        lda #<279
        sta dr_block
        lda #>279
        sta dr_block+1
        sos D_READ, dread
        sta TEMP
        jsr hex
        sos D_READ, dread       ; the second read finds the new disk
        pha
        jsr space
        pla
        pha
        jsr hex
        pla
        bne :+
        lda TEMP
        cmp #DISKSW
        bne :+
        jsr pass
        jmp groupd
:       jsr fail

; D. No drive
groupd: say t_empty
        jsr getkey
        sos D_READ, dread
        pha
        jsr hex
        pla
        cmp #NODRIVE
        bne :+
        jsr pass
        jmp summary
:       jsr fail

summary:
        say t_summary
        ldx #<results
        ldy #>results
        jsr puts
        say t_sysfail
        jsr getkey
        lda #$42
        jmp SYSFAIL

; The interpreter's keyboard NMI handler: count, nothing else.  SOS calls it
; in its own environment, so the count is not in the interpreter's zero page.
nmi:    inc nmicount
        rts

; Carry clear and A = the test file's access byte, or carry set and A an error.
getaccess:
        sos GETINFO, getinfo_f
        bcs :+
        lda gi_access
:       rts

; Wait for SUSPFLSH & A to become set (waitset) or clear (waitclear), about
; 20 seconds at most; carry set if it never does.
waitset:
        sta TEMP
        jsr settimer
:       lda SUSPFLSH
        and TEMP
        bne done
        jsr tick
        bne :-
        sec
        rts
waitclear:
        sta TEMP
        jsr settimer
:       lda SUSPFLSH
        and TEMP
        beq done
        jsr tick
        bne :-
        sec
        rts
done:   clc
        rts
settimer:
        lda #0
        sta WAIT
        sta WAIT+1
        lda #16
        sta WAIT+2
        rts
tick:   dec WAIT
        bne :+
        dec WAIT+1
        bne :+
        dec WAIT+2
:       rts

; Read one key from .CONSOLE.
getkey: sos READ, rd_parms
        rts

; Record P or F for the next group and show it.
pass:   lda #'P'
        bne mark
fail:   lda #'F'
mark:   ldx GROUP
        sta results,x
        inc GROUP
        pha
        jsr space
        pla
        jsr putc
        lda #CR
        jsr putc
        lda #LF
        jmp putc

; Show " ERR xx" for the error code in A.
errcode:
        pha
        say t_err
        pla
        jmp hex

space:  lda #' '
putc:   sta onechar
        lda #<onechar
        sta wr_buf
        lda #>onechar
        sta wr_buf+1
        lda #1
        sta wr_count
        lda #0
        sta wr_count+1
        sos WRITE, wr_parms
        rts

hex:    pha
        lsr a
        lsr a
        lsr a
        lsr a
        jsr digit
        pla
        and #$0F
digit:  cmp #10
        bcc :+
        adc #6
:       adc #'0'
        jmp putc

; Write the zero-terminated string at Y:X.
puts:   stx PTR
        sty PTR+1
        stx wr_buf
        sty wr_buf+1
        ldy #0
:       lda (PTR),y
        beq :+
        iny
        bne :-
:       sty wr_count
        lda #0
        sta wr_count+1
        tya
        beq :+
        sos WRITE, wr_parms
:       rts

; Parameter lists
open_con:
        .byte 4
        .word con_name
con_ref:
        .byte 0
        .word 0
        .byte 0
con_name:
        .byte 8, ".CONSOLE"
wr_parms:
        .byte 3
wr_ref: .byte 0
wr_buf: .word 0
wr_count:
        .word 0
rd_parms:
        .byte 4
rd_ref: .byte 0
        .word onechar
        .word 1
        .word 0
dev_d1: .byte 2
        .word d1_name
d1_num: .byte 0
d1_name:
        .byte 3, ".D1"
dev_d2: .byte 2
        .word d2_name
d2_num: .byte 0
d2_name:
        .byte 3, ".D2"
dread:  .byte 5
dr_dev: .byte 0
        .word buffer
dr_count:
        .word 512
dr_block:
        .word 0
dr_xfer:
        .word 0
dwrite: .byte 4
dw_dev: .byte 0
        .word buffer
        .word 512
dw_block:
        .word 0
file_name:
        .byte 15, ".D2/SOSFEAT.TMP"
create_f:
        .byte 3
        .word file_name
        .word 0
        .byte 0
destroy_f:
        .byte 1
        .word file_name
open_f: .byte 4
        .word file_name
file_ref:
        .byte 0
        .word 0
        .byte 0
fwrite: .byte 3
fw_ref: .byte 0
        .word onechar
        .word 1
close_f:
        .byte 1
cl_ref: .byte 0
getinfo_f:
        .byte 3
        .word file_name
        .word gi_access
        .byte 1
gi_access:
        .byte 0
setinfo_f:
        .byte 3
        .word file_name
        .word si_access
        .byte 1
si_access:
        .byte 0
onechar:
        .byte 0
nmicount:
        .byte 0

options:
        .byte 21, 13, 0         ; CHR$(21) sets them; 13 = advance, line feed, wrap, scroll
title:  .byte CR, LF, "SOS FEATURES (SIDWELL 1989)", CR, LF, 0
t_mem:  .byte "1 MEMSIZE ", 0
t_sysbank:
        .byte " SYSBANK ", 0
t_dread:
        .byte "2 D_READ .D1 BLOCKS 0, 2", 0
t_derr: .byte "3 D_READ BYTECNT, BLKNUM ", 0
t_dwrite:
        .byte "4 D_WRITE .D2 BLOCK 279", 0
t_clrback:
        .byte "5 CLRBACK ", 0
t_globals:
        .byte "6 NMIPEND DISKBUSY DFLTNMI GRAFMEM SCRNMODE ", 0
t_nmi:  .byte "7 PRESS RESET, THEN RETURN. NMIS ", 0
t_dsbl: .byte "8 NMIDSBL: PRESS RESET AND CONTROL-RESET,", CR, LF
        .byte "  THEN RETURN. E ", 0
t_enbl: .byte "9 NMIENBL: PRESS RESET, THEN RETURN. E ", 0
t_susp: .byte "A PRESS CONTROL-7 ON THE KEYPAD TWICE", 0
t_flush:
        .byte "B PRESS CONTROL-9 ON THE KEYPAD TWICE", 0
t_swap: .byte "C SWAP THE DISK IN DRIVE 2, THEN RETURN. ", 0
t_empty:
        .byte "D EMPTY DRIVE 2, THEN RETURN. ", 0
t_err:  .byte " ERR ", 0
t_summary:
        .byte CR, LF, "SOS FEATURES 123456789ABCD", CR, LF, "             ", 0
t_sysfail:
        .byte CR, LF, "RETURN: SYSFAIL $42", 0
results:
        .byte "-------------", 0
code_end:

        .segment "BSS"
buffer: .res 512
saved:  .res 512
