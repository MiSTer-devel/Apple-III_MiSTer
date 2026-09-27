; Apple /// memory-map test: a boot disk, no SOS.
;
; Writes through one view of memory and reads through another across the map's
; boundaries, as the decoder PROMs of Apple's 128 and 256 KiB boards lay them
; out (docs/MEMORY_MAP.md), and as the ON THREE 512K board's decoder PROMs
; do.  It finds the memory size from bank 8, which only the 512K board has,
; and bank 3, which the 128 KiB board lacks, and shows P or F for each group:
;   1  bank pairs: $81:0100, $81:7FFF/$81:8000 and the last pair's top byte
;   2  $8F: bank 0 in the window, RAM under the zero page register and the ROM
;   3  $87 is $8F (the bank latch has three bits)
;   4  no RAM behind the last pair's upper half (and bank 3 with 128 KiB):
;      reads $FF, nothing else written
;   5  bank register 7, and bit 3: bank 2 with 256 KiB, bank 0 with 128 KiB
;   6  X byte bits 6-4 and bit 3 are ignored
;   7  alternate stack at zero page xor 1, and switched off by a latched X byte
;   8  the bank latch is a register: the opcode after a store to the bank
;      register comes from the old bank, its operand from the new one
;   9  an opcode fetched from zero page $1A latches its X byte: PLA at $00FF
;      pulls through $81
;   A  a zero page register of $F0 or $FF reads the ROM and the VIA
; On the 512K board groups 3 to 6 change and one is added:
;   3  $87 is banks 7 and 8, not $8F
;   4  no RAM behind the upper half of $8E; its lower half is bank 14
;   5  fifteen banks through the bank register; 15 selects bank 0; a byte
;      and its sister byte in bank 10, one SDRAM word, are written apart
;   6  X byte bits 6-4 are ignored and bit 3 selects banks 8-14
;   B  bit 3 of the bank register goes through the latch like bits 0-2: the
;      opcode after a store from bank 1 to bank 9 is bank 1's, its operand
;      bank 9's
; The ROM loads block 0; the program reads blocks 1 and 2 with the ROM's
; BLOCKIO before it changes anything.

        .setcpu "6502"

ENV     = $FFDF
ZREG    = $FFD0
BANK    = $FFEF
BLOCKIO = $F479
IBBUFP  = $85                   ; the boot ROM's zero page
IBCMD   = $87
PTR     = $E8                   ; zero page $1A; its X byte is at XPAGE+PTR+1
TP      = $EA
FAIL    = $EC
COL     = $ED
XPAGE   = $1600
PRIMARY = $F7                   ; 1 MHz, I/O, screen, reset, stack $01xx, ROM
ALTERNATE = $F3

.macro W address, xindex, value
        .byte $80 | xindex, <(address), >(address), value
.endmacro
.macro E address, xindex, value
        .byte $C0 | xindex, <(address), >(address), value
.endmacro
.macro B value
        .byte 1, value
.endmacro
.macro V value
        .byte 2, value
.endmacro
.macro G
        .byte 3
.endmacro
.macro N routine
        .byte 4, routine
.endmacro
X00 = 0
X81 = 1
X85 = 2
X86 = 3
X87 = 4
X8E = 5
X8F = 6
XD1 = 7
X80 = 8
X82 = 9
X8A = 10
X8D = 11
XF9 = 12

        .segment "CODE"

start:  lda #1
        sta IBCMD
        lda #0
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

        sei
        cld
        ldx #$FF
        txs
        lda #PRIMARY
        sta ENV
        lda #$0F
        sta $FFE3               ; bank bits out
        lda #$1A
        sta ZREG
        lda $C050               ; 40-column text, page 1
        lda $C052
        lda $C054
        lda $C056
        lda #$A0
        ldx #0
clear:  sta $0400,x
        sta $0500,x
        sta $0600,x
        sta $0700,x
        inx
        bne clear

        lda #0
        sta XPAGE+TP
        sta XPAGE+TP+1
        sta FAIL
        sta COL
        sta BANK                ; only the 512K board has a bank 8: Apple's
        sta $2000               ; boards take bank register 8 as 0
        lda #8
        sta BANK
        lda #$88
        sta $2000
        lda #0
        sta BANK
        lda $2000
        bne apple
        ldy #title512-title256
        ldx #<records512
        lda #>records512
        pha
        jmp chosen
apple:  lda #3                  ; only the 256 KiB board has a bank 3
        sta BANK
        lda #$55
        sta $2000
        ldy #0                  ; 256 KiB title and table
        ldx #<records256
        lda #>records256
        pha
        lda $2000
        cmp #$55
        beq chosen
        pla
        ldy #title128-title256
        ldx #<records128
        lda #>records128
        pha
chosen: pla
        stx TP
        sta TP+1
        ldx #0
title:  lda title256,y
        beq next
        ora #$80
        sta $0480,x
        iny
        inx
        bne title

next:   jsr fetch
        beq done
        bmi access
        cmp #3
        beq group
        pha
        jsr fetch
        tax
        pla
        cmp #4
        beq native
        lsr a
        bcc :+
        stx BANK
        bcs next
:       stx ENV
        bcc next

native: txa
        asl a
        tax
        lda routines+1,x
        pha
        lda routines,x
        pha
        rts                     ; to the routine; it returns to counted
counted:
        bcc next
        inc FAIL
        bne next

group:  ldx COL
        lda #$D0                ; P
        ldy FAIL
        beq :+
        lda #$C6                ; F
:       sta $0580,x
        inx
        stx COL
        lda #0
        sta FAIL
        beq next

done:   lda #$AE                ; a full stop after the last result
        ldx COL
        sta $0580,x
hold:   jmp hold

access: pha
        and #$0F
        tax
        lda xbytes,x
        sta XPAGE+PTR+1
        jsr fetch
        sta PTR
        jsr fetch
        sta PTR+1
        jsr fetch
        tax
        pla
        asl a
        bmi expect
        txa
        sta (PTR),y
        jmp next
expect: txa
        cmp (PTR),y
        beq :+
        inc FAIL
:       jmp next

fetch:  ldy #0
        lda (TP),y
        inc TP
        bne :+
        inc TP+1
:       cmp #0
        rts

; Group 8.  The same routine in banks 1 and 2, differing in the opcode and
; operand that follow the store to the bank register.
lag:    lda #2
        sta BANK
        jsr copylag
        lda #$A0                ; bank 2: LDY #$22
        sta $3005
        lda #$22
        sta $3006
        lda #1
        sta BANK
        jsr copylag             ; bank 1: LDX #$11
        ldx #0
        ldy #0
        jmp $3000
lagback:
        cpx #$22
        bne bad
        cpy #0
        bne bad
good:   clc
        jmp counted
bad:    sec
        jmp counted
copylag:
        ldx #lagend-lagcode-1
:       lda lagcode,x
        sta $3000,x
        dex
        bpl :-
        rts
lagcode:
        lda #2
        sta BANK
        ldx #$11
        jmp lagback
lagend:

; Group 9.  PLA at $00FF: the opcode fetch is the last zero-page read, so its
; X byte ($16FF) redirects the pull to bank 1.
pull:   lda #1
        sta BANK
        lda #$B1
        sta $2141               ; $81:0141
        lda #0
        sta BANK
        lda #$A1
        sta $0141
        lda #$68                ; PLA
        sta $1AFF
        lda #$4C                ; JMP pullback, in the true stack page
        sta $0100
        lda #<pullback
        sta $0101
        lda #>pullback
        sta $0102
        lda #$81
        sta XPAGE+$FF
        ldx #$40
        txs
        jmp $00FF
pullback:
        ldx #$FF
        txs
        ldy #0
        sty XPAGE+$FF
        cmp #$B1
        bne bad
        beq good

; Group A.  The zero page register's page goes through the whole decode.
zpdecode:
        lda $F000               ; make the RAM under the ROM differ from it
        sta scratch
        eor #$FF
        sta $F000
        lda #$F0
        sta ZREG
        lda $00                 ; $F000: the ROM
        ldx #$1A
        stx ZREG
        cmp scratch
        beq :+
        jmp bad
:       lda #$FF
        sta ZREG
        lda $D0                 ; $FFD0: the zero page register, not the RAM under it
        ldx #$1A
        stx ZREG
        cmp #$FF
        beq :+
        jmp bad
:       jmp good

; Group B, 512K.  Group 8 across bit 3: from bank 1, a store of 9 to the bank
; register.  The core latches PA3 with bits 0-2, so the opcode that follows
; is bank 1's LDX and its operand bank 9's; a board taking PA3 at once would
; run bank 9's LDY instead.
lag9:   lda #9
        sta BANK
        jsr copylag9
        lda #$A0                ; bank 9: LDY #$99
        sta $3005
        lda #$99
        sta $3006
        lda #1
        sta BANK
        jsr copylag9            ; bank 1: LDX #$11
        ldx #0
        ldy #0
        jmp $3000
lag9back:
        cpx #$99
        bne :+
        cpy #0
        bne :+
        jmp good
:       jmp bad
copylag9:
        ldx #lag9end-lag9code-1
:       lda lag9code,x
        sta $3000,x
        dex
        bpl :-
        rts
lag9code:
        lda #9
        sta BANK
        ldx #$11
        jmp lag9back
lag9end:

routines:
        .word lag-1, pull-1, zpdecode-1, lag9-1
scratch:
        .byte 0
xbytes: .byte $00, $81, $85, $86, $87, $8E, $8F, $D1, $80, $82, $8A, $8D, $F9
title256:
        .byte "MAP 256K 123456789A", 0
title128:
        .byte "MAP 128K 123456789A", 0
title512:
        .byte "MAP 512K 123456789AB", 0

records512:
        B 1
        W $2100, X00, $11
        W $9FFF, X00, $12
        B 2
        W $2000, X00, $21
        E $0100, X81, $11
        E $7FFF, X81, $12
        E $8000, X81, $21
        W $FFFF, X8D, $6F
        B 14
        E $9FFF, X00, $6F
        G
        B 3
        W $1FFF, X00, $E1
        W $2000, X8F, $01
        E $1FFF, X8F, $E1
        W $FFD0, X8F, $C3
        W $F000, X8F, $C6
        E $FFD0, X8F, $C3
        E $F000, X8F, $C6
        E $FFD0, X00, $1A
        B 0
        E $2000, X00, $01
        G
        W $2645, X00, $70
        W $2645, X87, $77
        W $8000, X87, $78
        E $2645, X00, $70
        B 7
        E $4645, X00, $77
        B 8
        E $2000, X00, $78
        G
        W $1000, X00, $31
        B 2
        W $3000, X00, $32
        W $9000, X8E, $EE
        E $9000, X8E, $FF
        E $1000, X00, $31
        E $3000, X00, $32
        W $1000, X8E, $6E
        B 14
        E $3000, X00, $6E
        G
        B 0
        W $2222, X00, $B0
        B 2
        W $2222, X00, $B2
        B 7
        W $2222, X00, $B7
        B 10
        W $2222, X00, $BA
        B 15
        E $2222, X00, $B0
        B 2
        E $2222, X00, $B2
        B 7
        E $2222, X00, $B7
        B 10
        E $2222, X00, $BA
        W $2E22, X00, $CA
        E $2222, X00, $BA
        E $2E22, X00, $CA
        G
        E $0100, XD1, $11
        W $0100, XF9, $99
        B 9
        E $2100, X00, $99
        G
        W $0140, X00, $A1
        W $1B40, X00, $A2
        V ALTERNATE
        E $0140, X00, $A2
        E $0140, X8F, $A1
        W $0141, X8F, $A5
        V PRIMARY
        E $0141, X00, $A5
        G
        N 0
        G
        N 1
        G
        N 2
        G
        N 3
        G
        .byte 0

records256:
        B 1
        W $2100, X00, $11
        W $9FFF, X00, $12
        B 2
        W $2000, X00, $21
        E $0100, X81, $11
        E $7FFF, X81, $12
        E $8000, X81, $21
        W $FFFF, X85, $6F
        B 6
        E $9FFF, X00, $6F
        G
        B 3
        W $1FFF, X00, $E1
        W $2000, X8F, $01
        E $1FFF, X8F, $E1
        W $FFD0, X8F, $C3
        W $F000, X8F, $C6
        E $FFD0, X8F, $C3
        E $F000, X8F, $C6
        E $FFD0, X00, $1A
        B 0
        E $2000, X00, $01
        G
        W $A645, X00, $5A
        W $2645, X87, $77
        E $2645, X8F, $77
        E $2645, X00, $77
        E $A645, X00, $5A
        G
        W $1000, X00, $31
        B 2
        W $3000, X00, $32
        W $9000, X86, $EE
        E $9000, X86, $FF
        E $1000, X00, $31
        E $3000, X00, $32
        G
        W $2222, X00, $B2
        B 7
        E $2222, X00, $B2
        B $0A
        E $2222, X00, $B2
        G
        E $0100, XD1, $11
        W $4000, X8E, $E6
        B 6
        E $6000, X00, $E6
        G
        W $0140, X00, $A1
        W $1B40, X00, $A2
        V ALTERNATE
        E $0140, X00, $A2
        E $0140, X8F, $A1
        W $0141, X8F, $A5
        V PRIMARY
        E $0141, X00, $A5
        G
        N 0
        G
        N 1
        G
        N 2
        G
        .byte 0

records128:
        B 1
        W $2100, X00, $11
        W $9FFF, X00, $12
        B 2
        W $2000, X00, $21
        E $0100, X81, $11
        E $7FFF, X81, $12
        E $8000, X81, $21
        W $FFFF, X80, $6F
        B 1
        E $9FFF, X00, $6F
        G
        B 2
        W $1FFF, X00, $E1
        W $2000, X8F, $01
        E $1FFF, X8F, $E1
        W $FFD0, X8F, $C3
        W $F000, X8F, $C6
        E $FFD0, X8F, $C3
        E $F000, X8F, $C6
        E $FFD0, X00, $1A
        B 0
        E $2000, X00, $01
        G
        W $A645, X00, $5A
        W $2645, X87, $77
        E $2645, X8F, $77
        E $2645, X00, $77
        E $A645, X00, $5A
        G
        W $1000, X00, $31
        B 0
        W $3000, X00, $32
        W $9000, X82, $EE
        E $9000, X82, $FF
        E $1000, X85, $FF
        B 3
        W $2000, X00, $C3
        E $2000, X00, $FF
        B 0
        E $1000, X00, $31
        E $3000, X00, $32
        G
        W $2222, X00, $B0
        B 7
        E $2222, X00, $B0
        B $08
        E $2222, X00, $B0
        G
        E $0100, XD1, $11
        W $4000, X8A, $E6
        B 2
        E $6000, X00, $E6
        G
        W $0140, X00, $A1
        W $1B40, X00, $A2
        V ALTERNATE
        E $0140, X00, $A2
        E $0140, X8F, $A1
        W $0141, X8F, $A5
        V PRIMARY
        E $0141, X00, $A5
        G
        N 0
        G
        N 1
        G
        N 2
        G
        .byte 0
