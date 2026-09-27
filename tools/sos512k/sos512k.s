; SOS 512K update: a boot disk that lets another SOS disk use a 512K Apple ///.
;
; SOS takes its memory size from the bank register its boot block leaves.
; Apple's boot block ("SOS BOOT 1.1", and "7.0", the same code) starts its
; search at bank register 7, so it never finds more than 256K; ON THREE's boot block, which ON THREE's
; upgrade put on its owners' disks, checks for the 512K board first.  This
; program gives the disk in drive 2 the same check by patching its own Apple
; boot block in place, so no Apple or ON THREE code comes with it.  Like ON
; THREE's updates it runs from memory, so the disk can go in the built-in
; drive in place of this one (RETURN), or in drive 2 (2).
;
; The patch probes with bank registers 15 and 7: it writes 15 through the
; first and 7 through the second, then reads back through 15.  Apple's 128K
; and 256K boards take three bank register bits, so both reach the same byte
; and the read gives 7; the 512K board takes four and gives 15.  That is
; where Apple's search then starts, finding bank 14 or bank 6 (or 2 with
; 128K) as before.  Like ON THREE's SOS BOOT 2.2 it also stores an opcode at
; $2034 of bank 6.  The board takes the bank register's fourth bit around
; the main board's bank latch, so when SOS 1.1-1.3's loader, running in bank
; 14, selects bank 0 at $2031, its next opcode comes from bank 6; $AD there
; is the LDA that SOS has at $2034, and SOS carries on.  The code goes where
; the boot block has room: its header text, which nothing reads, the spaces
; after the kernel's name, the zeros at its end, and seven bytes freed in
; Apple's setup at $A078 by dropping loads the search loop makes redundant.
;
; The ROM loads block 0 at $A000; this reads blocks 1 to 3 with the ROM's
; BLOCKIO and then uses it for the disk to update as well.  tools/onthree_boot.py
; --patch applies the same bytes to an image on a computer.

        .setcpu "6502"

ENV     = $FFDF
BLOCKIO = $F479
IBDRVN  = $82                   ; the ROM's disk parameters
IBBUFP  = $85
IBCMD   = $87
KBD     = $C000
KBDSTRB = $C010
PTR     = $E8
SRC     = $EA
COUNT   = $EC
CODE    = $ED
BUFFER  = $A800                 ; drive 2's block 0
CHECK   = $AA00                 ; the same block read back
RETURN  = $8D
KEY2    = $B2
IBSLOT  = $81
HEADPOS = $85                   ; + (IBSLOT/8 | drive): the ROM's half-track
NODRIVE = $80                   ; the ROM's error codes
WPROT   = $81

.define ROW(r) $0400 + ((r) .mod 8) * $80 + ((r) / 8) * $28

.macro print row, string
        lda #<(row)
        sta PTR
        lda #>(row)
        sta PTR+1
        ldx #<string
        ldy #>string
        jsr puts
.endmacro

        .segment "CODE"

start:  lda #1                  ; the rest of this program, from drive 1
        sta IBCMD
        lda #0
        sta IBDRVN
        sta IBBUFP
        lda #$A2
        sta IBBUFP+1
        lda #1
        ldx #0
        jsr BLOCKIO
        lda #$A4
        sta IBBUFP+1
        lda #2
        ldx #0
        jsr BLOCKIO
        lda #$A6
        sta IBBUFP+1
        lda #3
        ldx #0
        jsr BLOCKIO

        sei
        cld
        ldx #$FF
        txs
        lda #$F7                ; 1 MHz, I/O, screen, reset, ROM
        sta ENV
        lda $C050               ; 40-column text, page 1
        lda $C052
        lda $C054
        lda $C056
        lda #$A0
        ldx #0
:       sta $0400,x
        sta $0500,x
        sta $0600,x
        sta $0700,x
        inx
        bne :-
        print $0400+12, title    ; row 0, centred (ROW(0)+12 would be ROW(12))
        print ROW(3), intro1
        print ROW(4), intro2
        print ROW(6), intro3
        print ROW(7), intro4
        print ROW(8), intro5
        print ROW(10), intro6
        print ROW(11), intro7
        print ROW(13), prompt1
        print ROW(14), prompt2
        print ROW(15), prompt3

waitkey:
        lda KBD
        bpl waitkey
        sta KBDSTRB
        ldx #0                  ; RETURN: the built-in drive, .D1
        cmp #RETURN
        beq :+
        cmp #KEY2
        bne waitkey
        lda $C0D1               ; 2: the Disk III on external address 1, .D2
        lda $C0D2
        inx
:       stx IBDRVN
        ldx #39                 ; clear the status lines
        lda #$A0
:       sta ROW(18),x
        sta ROW(19),x
        sta ROW(21),x
        dex
        bpl :-
        print ROW(18), working

        lda #<BUFFER
        ldx #>BUFFER
        jsr read0
        bcc :+
        jmp readerr

:       ldx #0                  ; this disk, still in the built-in drive?
:       lda BUFFER,x
        cmp $A000,x
        bne :+
        inx
        bne :-
        print ROW(18), itself
        jmp next

:       ldx #<new_bytes         ; already patched?
        ldy #>new_bytes
        jsr compare
        bne :+
        print ROW(18), already
        jmp next

:       ldx #<probe             ; ON THREE's boot block, or another with its check
        ldy #>probe
        lda #probe_end-probe
        jsr find
        bcc @apple
        ldx #<bank6fix          ; 2.2 and later plant bank 6's byte; 2.0 did not
        ldy #>bank6fix
        lda #bank6fix_end-bank6fix
        jsr find
        bcc :+
        print ROW(18), onthree
        jmp next
:       print ROW(18), onthree20
        print ROW(19), onthree20b
        jmp next

@apple: ldx #<old_bytes         ; Apple's SOS BOOT 1.1, where the patch goes?
        ldy #>old_bytes
        jsr compare
        beq :+
        ldx #<old_bytes_70      ; or its 7.0
        ldy #>old_bytes_70
        jsr compare
        beq :+
        print ROW(18), not_apple
        jmp next

:       jsr patch
        lda #2                  ; write the block back
        sta IBCMD
        lda #<BUFFER
        sta IBBUFP
        lda #>BUFFER
        sta IBBUFP+1
        lda #0
        ldx #0
        jsr BLOCKIO
        bcs writeerr
        lda #<CHECK             ; and read it again
        ldx #>CHECK
        jsr read0
        bcs readerr
        ldx #0
:       lda BUFFER,x
        cmp CHECK,x
        bne verr
        lda BUFFER+256,x
        cmp CHECK+256,x
        bne verr
        inx
        bne :-
        print ROW(18), updated
        print ROW(19), updated2
        jmp next
verr:   print ROW(18), mismatch
        jmp next

readerr:
        sta CODE
        cmp #NODRIVE
        bne :+
        print ROW(18), no_disk
        jmp next
:       print ROW(18), read_bad
        jmp error
writeerr:
        sta CODE
        cmp #WPROT
        bne :+
        print ROW(18), protected
        jmp next
:       print ROW(18), write_bad
error:  iny                     ; after the message
        lda CODE
        jsr hex
next:   print ROW(21), again
        jmp waitkey

; Read block 0 of the selected drive into the buffer at X:A.  The drive
; hides a newly inserted disk until the head steps through phase 1, as the
; Disk /// analog card does, and the ROM would find the head already on track
; 0 and report no drive.  Recording it on track 1 makes BLOCKIO step it back.
read0:  sta IBBUFP
        stx IBBUFP+1
        lda IBSLOT
        lsr a
        lsr a
        lsr a
        ora IBDRVN
        tax
        lda #2
        sta HEADPOS,x
        lda #1
        sta IBCMD
        lda #0
        ldx #0
        jmp BLOCKIO

; Carry set when the A bytes at Y:X appear in BUFFER's first page.
find:   stx SRC
        sty SRC+1
        sta COUNT
        lda #<BUFFER
        sta PTR
        lda #>BUFFER
        sta PTR+1
@at:    ldy COUNT
        dey
@byte:  lda (PTR),y
        cmp (SRC),y
        bne @next
        dey
        bpl @byte
        sec
        rts
@next:  inc PTR
        lda PTR
        cmp #0
        bne @at
        clc
        rts

; Z set when every region of BUFFER holds the bytes of the table at Y:X.
compare:
        stx SRC
        sty SRC+1
        ldx #0
@region:
        jsr region
        ldy #0
@byte:  lda (PTR),y
        cmp (SRC),y
        bne @differs
        iny
        cpy COUNT
        bne @byte
        jsr advance
        bne @region
        lda #0                  ; Z set
        rts
@differs:
        lda #1                  ; Z clear
        rts

; Copy new_bytes into BUFFER's regions.
patch:  lda #<new_bytes
        sta SRC
        lda #>new_bytes
        sta SRC+1
        ldx #0
@region:
        jsr region
        ldy #0
@byte:  lda (SRC),y
        sta (PTR),y
        iny
        cpy COUNT
        bne @byte
        jsr advance
        bne @region
        rts

; Point PTR at region X/2 of BUFFER and COUNT at its length.
region: lda offsets,x
        sta PTR
        lda offsets+1,x
        clc
        adc #>BUFFER
        sta PTR+1
        txa
        lsr a
        tay
        lda lengths,y
        sta COUNT
        rts

; Step SRC past the region and X to the next; Z set after the last.
advance:
        clc
        lda SRC
        adc COUNT
        sta SRC
        bcc :+
        inc SRC+1
:       inx
        inx
        cpx #offsets_end-offsets
        rts

; Print the zero-terminated string at Y:X to PTR; Y ends at its length.
puts:   stx SRC
        sty SRC+1
        ldy #0
:       lda (SRC),y
        beq :+
        ora #$80
        sta (PTR),y
        iny
        bne :-
:       rts

; Show A in hex at column Y of row 18.
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
:       adc #$B0
        sta ROW(18),y
        iny
        rts

; LDA #$0E, STA $FFEF, STA $2000, LDA #$06, STA $FFEF, STA $2000: the start of
; the 512K check in ON THREE's boot blocks and in soshdboot's loader.
probe:  .byte $A9, $0E, $8D, $EF, $FF, $8D, $00, $20
        .byte $A9, $06, $8D, $EF, $FF, $8D, $00, $20
probe_end:
; LDA #$FF, STA $2034: SOS BOOT 2.2's byte in bank 6, which 2.0 lacks.
bank6fix:
        .byte $A9, $FF, $8D, $34, $20
bank6fix_end:

title:  .byte "SOS 512K UPDATE", 0
intro1: .byte "LETS A SOS DISK USE ALL 512K OF THE", 0
intro2: .byte "ON THREE 512K BOARD (MEMORY: 512K).", 0
intro3: .byte "APPLE'S BOOT BLOCK STOPS AT 256K. THIS", 0
intro4: .byte "ADDS THE 512K CHECK TO IT; THE DISK", 0
intro5: .byte "BOOTS AS BEFORE WITH 128K OR 256K.", 0
intro6: .byte "ONLY BLOCK 0 CHANGES. IF IT IS YOUR", 0
intro7: .byte "ONLY COPY, UPDATE A COPY OF IT.", 0
prompt1:
        .byte "PUT THE DISK TO UPDATE IN THE BUILT-IN", 0
prompt2:
        .byte "DRIVE AND PRESS RETURN, OR PUT IT IN", 0
prompt3:
        .byte "DRIVE 2 AND PRESS 2.", 0
working:
        .byte "WORKING...", 0
updated:
        .byte "UPDATED: IT NOW BOOTS WITH 512K.", 0
updated2:
        .byte "SOS WILL NOW SEE ALL 512K.", 0
already:
        .byte "THIS DISK IS ALREADY UPDATED.", 0
onthree:
        .byte "ALREADY 512K: ITS BOOT CHECKS FOR 512K.", 0
onthree20:
        .byte "ON THREE'S BOOT 2.0: SOS STOPS AT 512K.", 0
onthree20b:
        .byte "IT NEEDS 2.2; LEFT ALONE.", 0
not_apple:
        .byte "NOT APPLE'S SOS BOOT: LEFT ALONE.", 0
itself: .byte "THAT IS THIS DISK: SWAP IN YOURS.", 0
no_disk:
        .byte "NO DISK IN THE DRIVE.", 0
protected:
        .byte "THE DISK IS WRITE PROTECTED.", 0
read_bad:
        .byte "CAN'T READ THE DISK: ERROR", 0
write_bad:
        .byte "CAN'T WRITE THE DISK: ERROR", 0
mismatch:
        .byte "WRITTEN, BUT IT READS BACK DIFFERENT.", 0
again:  .byte "NEXT DISK: RETURN OR 2, AS ABOVE.", 0

; The patch: four regions of block 0, with Apple's bytes and the new ones.
; Keep in step with PATCH in tools/onthree_boot.py.

; Apple's setup at $A078, the same in SOS BOOT 1.1 and 7.0.
.macro apple_setup
        .byte $2C, $10, $C0                             ; BIT $C010
        .byte $A9, $40, $8D, $CA, $FF                   ; LDA #$40, STA $FFCA
        .byte $A9, $07, $8D, $EF, $FF                   ; LDA #$07, STA $FFEF
        .byte $A2, $00, $CE, $EF, $FF, $8E, $00, $20    ; the search loop
        .byte $AD, $00, $20, $D0, $F5
        .byte $A9, $01, $85, $E0                        ; LDA #$01, STA $E0
        .byte $A9, $00, $85, $E1                        ; LDA #$00, STA $E1
        .byte $A9, $00, $85, $85                        ; LDA #$00, STA $85
        .byte $A9, $A2, $85, $86                        ; LDA #$A2, STA $86
.endmacro

offsets:
        .word $0003, $001C, $0078, $01F2
offsets_end:
lengths:
        .byte 14, 5, 42, 14
old_bytes:
        .byte "SOS BOOT  1.1 "                          ; $A003: header text
        .byte "     "                                   ; $A01C: after SOS.KERNEL
        apple_setup                                     ; $A078
        .res 14, 0                                      ; $A1F2: unused
new_bytes:
        .byte $CA                                       ; $A003: DEX
        .byte $8E, $EF, $FF                             ;   STX $FFEF   bank register 6
        .byte $8C, $34, $20                             ;   STY $2034   $AD, SOS's opcode there
        .byte $8D, $EF, $FF                             ;   STA $FFEF   back to 15
        .byte $AD, $00, $20                             ;   LDA $2000   15 with 512K, else 7
        .byte $60                                       ;   RTS
        .byte $8E, $00, $20                             ; $A01C: STX $2000
        .byte $D0, $E2                                  ;   BNE $A003   (X is 7)
        .byte $2C, $10, $C0                             ; $A078: BIT $C010
        .byte $A9, $40, $8D, $CA, $FF                   ;   LDA #$40, STA $FFCA
        .byte $A0, $AD                                  ;   LDY #$AD
        .byte $A9, $0F                                  ;   LDA #$0F
        .byte $20, $F2, $A1                             ;   JSR $A1F2
        .byte $8D, $EF, $FF                             ;   STA $FFEF   where the search starts
        .byte $A2, $00, $CE, $EF, $FF, $8E, $00, $20    ;   the search loop, unchanged,
        .byte $AD, $00, $20, $D0, $F5                   ;   leaving A = X = 0
        .byte $85, $E1                                  ;   STA $E1
        .byte $85, $85                                  ;   STA $85
        .byte $E8                                       ;   INX
        .byte $86, $E0                                  ;   STX $E0
        .byte $A9, $A2, $85, $86                        ;   LDA #$A2, STA $86
        .byte $8D, $EF, $FF                             ; $A1F2: STA $FFEF   bank register 15
        .byte $8D, $00, $20                             ;   STA $2000
        .byte $A2, $07                                  ;   LDX #$07
        .byte $8E, $EF, $FF                             ;   STX $FFEF   bank register 7
        .byte $4C, $1C, $A0                             ;   JMP $A01C
old_bytes_70:                   ; SOS BOOT 7.0: 1.1 with two stray words in the tail
        .byte "SOS BOOT  7.0 "
        .byte "     "
        apple_setup
        .byte $00, $00, $00, $00, $00, $00, $00, $00, $FA, $01, $00, $00, $02, $00
