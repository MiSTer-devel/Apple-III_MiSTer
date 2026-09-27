; Reads and writes across the memory-map boundaries on the real T65, MMU,
; bank latch and RAM.  Every expectation is what the decoder PROMs and the
; schematic give (prom_reference.py --report): phases 1-10 for the 256 KiB
; board, then the bench switches to the 128 KiB board and resets for 12-13,
; and to the ON THREE 512K board for 15-19, whose banks 7-14 are the
; external memory (--board 512).
.setcpu "6502"
.segment "CODE"
.org $f000

ZREG   = $ffd0                  ; zero page register
ENVREG = $ffdf
BANK   = $ffef
PTR    = $e8                    ; pointer in zero page $1A, X byte at $16E9
XBYTE  = $16e9
ENV_PRIMARY = $d7               ; 1 MHz, I/O, screen off, reset on, stack $01xx, ROM
ENV_ALT     = $d3               ; the same with the alternate stack

.macro phase number
    lda #number
    sta $0201
.endmacro
.macro bank number
    lda #number
    sta BANK
.endmacro
.macro store location, value
    lda #value
    sta location
.endmacro
.macro expect location, value
    lda location
    cmp #value
    beq :+
    jmp fail
:
.endmacro
.macro xptr address, xbyte
    lda #<(address)
    sta PTR
    lda #>(address)
    sta PTR+1
    lda #xbyte
    sta XBYTE
.endmacro
.macro xstore address, xbyte, value
    xptr address, xbyte
    lda #value
    sta (PTR),y
.endmacro
.macro xexpect address, xbyte, value
    xptr address, xbyte
    lda (PTR),y
    cmp #value
    beq :+
    jmp fail
:
.endmacro

reset:
    sei
    cld
    ldx #$ff
    txs
    lda #ENV_PRIMARY
    sta $ffd1
    lda #$ff
    sta $ffd3
    sta $ffd2
    lda #$0f
    sta $ffe3                   ; bank bits out
    bank 0
    lda #$1a
    sta ZREG
    ldy #0
    sty XBYTE-1
    lda $0204                   ; RAM survives the reset into the next board
    cmp #$a8
    bne :+
    jmp small
:   cmp #$a5
    bne :+
    jmp big
:

    ; 1. Bank pairs: $8n:0000-7FFF is bank n, $8n:8000-FFFF bank n+1.
    phase 1
    bank 1
    store $2100, $11
    store $9fff, $12
    bank 2
    store $2000, $21
    store $2100, $22
    bank 1
    xexpect $0100, $81, $11
    xexpect $7fff, $81, $12
    xexpect $8000, $81, $21     ; one byte on, in the next bank
    xexpect $8100, $81, $22
    xptr $7fff, $81             ; the index carries across the pair boundary
    ldy #1
    lda (PTR),y
    ldy #0
    cmp #$21
    beq :+
    jmp fail
:
    xstore $ffff, $85, $6f      ; last byte of bank 6
    xstore $8000, $80, $10      ; first byte of bank 1
    bank 6
    expect $9fff, $6f
    bank 1
    expect $2000, $10
    expect $2100, $11

    ; 2. $8F: the system map with bank 0 in the window, all of it RAM.
    phase 2
    bank 3
    store $1fff, $e1
    store $a000, $e2
    xstore $2000, $8f, $01
    xstore $9fff, $8f, $02
    xexpect $1fff, $8f, $e1
    xexpect $a000, $8f, $e2
    bank 0
    expect $2000, $01
    expect $9fff, $02
    bank 3
    xstore $ffd0, $8f, $c3      ; under the zero page register
    xstore $ffef, $8f, $c4      ; under the bank register
    xstore $c000, $8f, $c5      ; under the keyboard
    xstore $f000, $8f, $c6      ; under the ROM's first opcode
    xexpect $ffd0, $8f, $c3
    xexpect $ffef, $8f, $c4
    xexpect $c000, $8f, $c5
    xexpect $f000, $8f, $c6
    expect ZREG, $1a            ; the registers were not written
    expect $f000, $78           ; and the ROM still reads as ROM
    lda BANK
    and #$0f
    cmp #3
    beq :+
    jmp fail
:

    ; 3. The bank latch has no fourth bit: $87 is $8F on the stock board.
    phase 3
    store $a345, $5a            ; what a linear bank 7 would have reached
    xstore $2345, $87, $77
    xexpect $2345, $8f, $77
    xexpect $ffd0, $87, $c3
    bank 0
    expect $2345, $77
    expect $a345, $5a
    xstore $4000, $8e, $e6      ; and $8E is $86
    bank 6
    expect $6000, $e6
    xexpect $0100, $d1, $11     ; bits 6-4 are not wired either

    ; 4. There is no bank 7 behind the upper half of pair 6.
    phase 4
    store $1000, $31
    bank 2
    store $3000, $32
    xstore $9000, $86, $ee
    xexpect $9000, $86, $ff
    expect $1000, $31
    expect $3000, $32
    xstore $1000, $86, $66      ; the lower half is bank 6
    bank 6
    expect $3000, $66

    ; 5. Bank register: only three bits, and 7 selects bank 2.
    phase 5
    bank 2
    store $2222, $b2
    bank 7
    expect $2222, $b2
    store $2223, $b7
    bank $0a
    expect $2222, $b2
    expect $2223, $b7
    bank 2
    expect $2223, $b7

    ; 6. An X byte with bit 7 clear leaves ordinary addressing alone.
    phase 6
    bank 4
    store $2100, $44
    xexpect $2100, $01, $44
    xexpect $f000, $0f, $78     ; ROM, not the RAM under it

    ; 7. Relocated zero page and the adjacent alternate stack.
    phase 7
    expect $1ae8, $00           ; the pointer written through zero page
    expect $1ae9, $f0
    store $0140, $a1            ; true stack page
    store $1b40, $a2
    store $1a40, $a3
    lda #ENV_ALT
    sta ENVREG
    expect $0140, $a2           ; zero page $1A: stack in $1B
    lda #$1b
    sta ZREG
    expect $0140, $a3           ; zero page $1B: stack in $1A
    lda #$1a
    sta ZREG
    ldx #$40
    txs
    lda #$a4
    pha
    expect $1b40, $a4
    xexpect $0140, $8f, $a1     ; the latch switches the alternate stack off
    xstore $0141, $8f, $a5
    lda #ENV_PRIMARY
    sta ENVREG
    expect $0141, $a5
    expect $1b41, $00

    ; 8. The bank latch is a register: the opcode after a store to the bank
    ;    register still comes from the old bank, its operand from the new one.
    phase 8
    bank 2
    jsr copylag
    store $3005, $a0            ; bank 2: LDY #$22
    store $3006, $22
    bank 1
    jsr copylag                 ; bank 1: LDX #$11
    ldx #0
    ldy #0
    jmp $3000
lagback:
    cpx #$22
    beq :+
    jmp fail
:   cpy #0
    beq :+
    jmp fail
:

    ; 9. An opcode fetched from a zero page of $18-$1F latches its X byte.  PLA
    ;    at $00FF leaves no later zero-page read to replace it, so it pulls
    ;    through $81: from bank 1, not from the stack page.
    phase 9
    bank 1
    store $2141, $b1            ; $81:0141
    bank 0
    store $0141, $a1
    store $1aff, $68            ; PLA
    store $0100, $4c            ; then JMP pullback, in the true stack page
    store $0101, <pullback
    store $0102, >pullback
    store $16ff, $81
    ldx #$40
    txs
    jmp $00ff
pullback:
    ldx #$ff
    txs
    ldy #0
    sty $16ff
    cmp #$b1
    beq :+
    jmp fail
:

    ; 10. The zero-page register's page goes through the whole decode: it can
    ;     name a slot, the ROM or a VIA, and write protection covers it.
    phase 10
    store $d010, $11
    lda #$c0
    sta ZREG
    lda $90                     ; $C090: slot 1's device select
    cmp #$5a
    bne zfail
    lda #$f0
    sta ZREG
    lda $00                     ; $F000: the ROM's first opcode
    cmp #$78
    bne zfail
    lda #$ff
    sta ZREG
    lda $d0                     ; $FFD0: the zero-page register itself
    cmp #$ff
    bne zfail
    lda #$d0
    sta ZREG
    lda #ENV_PRIMARY | $08      ; write protect $C000-$FFFF
    sta ENVREG
    lda #$77
    sta $10
    lda #ENV_PRIMARY
    sta ENVREG
    lda #$1a
    sta ZREG
    expect $d010, $11
    jmp zdone
zfail:
    lda #$1a
    sta ZREG
    jmp fail
zdone:

    ; 11. Ask the bench for the 128 KiB board and a reset.
    phase 11
    store $0204, $a8
    sta $0203
wait128:
    jmp wait128

    ; 12. 128 KiB: banks 0-2, nothing behind bank register 3-6, 7 is bank 0.
small:
    phase 12
    store $0204, $00
    bank 2
    store $2000, $c2
    bank 3
    store $2000, $c3
    expect $2000, $ff
    bank 6
    expect $2000, $ff
    bank 2
    expect $2000, $c2
    bank 0
    store $2001, $c0
    bank 7
    expect $2001, $c0

    ; 13. 128 KiB pairs: $81 ends in bank 2, $82 has no upper half, $83 nothing.
    phase 13
    xexpect $8000, $81, $c2
    xstore $8000, $82, $ee
    xexpect $8000, $82, $ff
    xexpect $0100, $83, $ff
    xexpect $2001, $87, $c0
    bank 2
    expect $2000, $c2
    expect $0204, $00

    ; 14. Ask the bench for the 512K board and a reset.
    phase 14
    store $0204, $a5
    sta $0203
wait512:
    jmp wait512

    ; 15. 512K: fifteen banks, bit 3 of the bank register works, and 15 is
    ;     bank 0, as C11A gives the chips bank + 1.  A write to one byte of an
    ;     external word leaves its sister byte alone.
big:
    phase 15
    store $0204, $00
    ldx #14
:   stx BANK
    txa
    ora #$e0
    sta $2000
    sta $2100
    dex
    bpl :-
    ldx #14
:   stx BANK
    txa
    ora #$e0
    cmp $2100
    beq :+
    jmp fail
:   dex
    bpl :--
    bank 15
    expect $2000, $e0
    bank 9                      ; both bytes of an SDRAM word: $2100 and its
    store $2100, $a9            ; sister byte, $2100 xor $0C00
    store $2d00, $b9
    expect $2100, $a9
    expect $2d00, $b9
    store $2100, $e9            ; phase 16 reads the bank's mark here

    ; 16. Pairs through bank 14: $87 is banks 7 and 8, not $8F; the index
    ;     carries from bank 7 into 8; and $8E ends in bank 14.  (An X byte
    ;     never redirects page 0.)
    phase 16
    xexpect $0100, $87, $e7
    xexpect $8000, $87, $e8
    xexpect $0100, $8d, $ed
    xexpect $8100, $8d, $ee
    xexpect $0100, $8e, $ee
    xstore $7fff, $86, $76      ; last byte of bank 6
    xstore $ffff, $86, $77      ; last byte of bank 7
    xstore $7fff, $87, $78      ; the same byte, through $87
    xexpect $ffff, $86, $78
    xptr $7fff, $87
    ldy #1
    lda (PTR),y                 ; bank 8's first byte
    ldy #0
    cmp #$e8
    beq :+
    jmp fail
:   bank 6
    expect $9fff, $76
    bank 7
    expect $9fff, $78
    xstore $2345, $8f, $5f      ; $8F is still bank 0 in the window
    bank 0
    expect $2345, $5f

    ; 17. Nothing behind the upper half of $8E, the system bank's place.
    phase 17
    store $1000, $31
    xstore $8000, $8e, $ee
    xexpect $8000, $8e, $ff
    xexpect $9000, $8e, $ff
    expect $1000, $31
    bank 0
    expect $2000, $e0

    ; 18. X byte bit 3 selects the upper banks, bits 6-4 are ignored; a zero
    ;     page and a stack in an upper bank.
    phase 18
    xexpect $0100, $f9, $e9
    xexpect $0100, $b1, $e1
    bank 3
    store $4010, $03
    bank 11
    lda #$40                    ; zero page $40: $4000 in bank 11
    sta ZREG
    lda #$4b
    sta $10
    lda #ENV_ALT
    sta ENVREG
    ldx #$20
    txs
    lda #$b4
    pha                         ; alternate stack $41: $4120 in bank 11
    lda #ENV_PRIMARY
    sta ENVREG
    ldx #$ff
    txs
    lda #$1a
    sta ZREG
    expect $4010, $4b
    expect $4120, $b4
    bank 3
    expect $4010, $03

    ; 19. The bank register's bit 3 comes from the VIA pin, not the latch: the
    ;     opcode after a store from bank 1 to bank 9 is already bank 9's.
    phase 19
    bank 9
    jsr copylag9
    store $3005, $a2            ; bank 9: LDX #$99
    store $3006, $99
    bank 1
    jsr copylag9                ; bank 1: LDX #$11
    ldx #0
    jmp $3000
lag9back:
    cpx #$99
    beq :+
    jmp fail
:

    lda #$5a
    sta $0200
done:
    jmp done
fail:
    lda #ENV_PRIMARY
    sta ENVREG
    lda #$ff
    sta $0200
    jmp fail
nmi:
    rti
; The routine run from the window in phase 8.
copylag:
    ldx #lagend-lagcode-1
:   lda lagcode,x
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
copylag9:
    ldx #lag9end-lag9code-1
:   lda lag9code,x
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
.res $fffa-*, $ea
.word nmi, reset, fail
