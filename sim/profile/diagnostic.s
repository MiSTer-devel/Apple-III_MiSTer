; Exercise the ProFile card on the real CPU the way Apple's .PROFILE driver
; does: the CMD/BSY handshakes through the soft switches, command bytes and
; data through WBUF/RBUF, and page transfers through the ROM's pseudo-DMA
; ladder at $F800, including the driver's partial-page trick that relies on
; the 6502's dummy fetches during a taken branch. The bench installs the
; card in slot 4 with a 40-block image whose byte i of block b is
; b * 17 + i * 3, and checks the host image after the write.
.setcpu "6502"
.segment "CODE"
.org $f000
.macro phase number
    lda #number
    sta $0201
.endmacro
.macro fail_if_ne
    beq :+
    jmp fail
:
.endmacro
.macro switch offset
    lda $c400 + offset
.endmacro
; One pseudo-DMA run: the driver's GO_DMA. Interrupts are off already; the
; environment loses I/O and gains write protection of the upper 16K, the
; zero-page register points at the target page, and only the accumulator
; and absolute addresses are touched until the zero page is back.
.macro dma_run target, count, zpage
    lda $ffdf
    pha
    and #$24
    ora #$8b
    sta $ffdf
    lda #zpage
    sta $ffd0
    lda #count
    sec
    jsr target
    lda #0
    sta $ffd0
    pla
    sta $ffdf
.endmacro
; Expect the pattern from start, step 3, over the count bytes at address.
.macro check address, count, start
    lda #<address
    sta ptr
    lda #>address
    sta ptr+1
    lda #start
    sta value
    ldx #<count
    jsr check_range
.endmacro
.macro expect_byte address, want
    lda address
    cmp #want
    fail_if_ne
.endmacro

wbuf    = $c0c0
rbuf    = $c0c1
rstat   = $c0c2
clrpe   = $c0c3

cmdbuf  = $50                     ; six command bytes
status  = $56                     ; four status bytes
want    = $5a                     ; expected handshake response
ptr     = $60
value   = $62

reset:
    sei
    cld
    ldx #$ff
    txs
    lda #$d7                      ; 1 MHz, I/O and ROM enabled, screen off
    sta $ffd1
    lda #$ff
    sta $ffd3
    lda #0
    sta $ffd0
    lda #$ff
    sta $ffd2
    lda #$0f
    sta $ffe3
    lda #0
    sta $ffef
    lda #$3f
    sta $ffe2
    sta $ffe0
    lda #$7f
    sta $ffde
    sta $ffee

    ; Phase 1: the card answers, the drive is idle and connected. DINIT's
    ; switch settings, then the driver's entry: clear parity, read status.
    phase 1
    switch 5
    switch 7
    switch 2
    sta clrpe
    lda rstat
    cmp #$80
    fail_if_ne
    lda rstat + 4                 ; the registers repeat every four bytes
    cmp #$80
    fail_if_ne

    ; Phase 2: read block 5 through RBUF into $2000.
    phase 2
    lda #0
    sta cmdbuf
    lda #5
    jsr read_command              ; handshakes and status; data pending
    lda #0
    sta ptr
    lda #$20
    sta ptr+1
    jsr move_in                   ; 512 bytes through RBUF
    check $2000, 0, 85
    check $2100, 0, 85

    ; Phase 3: block 6 by two whole-page pseudo-DMA transfers to $3000.
    phase 3
    lda #6
    jsr read_command
    dma_run $f800, $ff, $30
    dma_run $f800, $ff, $31
    check $3000, 0, 102
    check $3100, 0, 102

    ; Phase 4: block 7 into a buffer at $4038: the first partial page enters
    ; the ladder at $F838, then a whole page, then RBUF for the rest.
    phase 4
    lda #$40
    jsr fill_page
    lda #$41
    jsr fill_page
    lda #7
    jsr read_command
    dma_run $f838, $c7, $40
    dma_run $f800, $ff, $41
    lda #0
    sta ptr
    lda #$42
    sta ptr+1
    ldy #0
:   lda rbuf
    sta (ptr),y
    iny
    cpy #56
    bne :-
    check $4038, 200, 119
    check $4100, 0, 207
    check $4200, 56, 207
    expect_byte $4037, $ea        ; untouched fill left by the bench

    ; Phase 5: block 8 with the driver's last-page trick. The ladder is
    ; entered at $F802 with the count that makes a BEQ exit early: bytes
    ; land at offsets 2 to Y-5, then the branch's dummy fetch puts one at
    ; Y-4 and its page-crossing fetch puts one at $FE (first half of the
    ; page) or $00 (second half). Y = $40 first, then Y = $C0.
    phase 5
    lda #$50
    jsr fill_page
    lda #$51
    jsr fill_page
    lda #8
    jsr read_command
    dma_run $f802, $0e, $50
    check $5002, 58, 136
    expect_byte $503c, 54
    expect_byte $50fe, 57
    expect_byte $5000, $ea
    expect_byte $5001, $ea
    expect_byte $503d, $ea
    expect_byte $50ff, $ea
    dma_run $f802, $2e, $51
    check $5102, 186, 60
    expect_byte $51bc, 106
    expect_byte $5100, 109
    expect_byte $5101, $ea
    expect_byte $51bd, $ea
    lda rbuf                      ; the drive's pointer is at byte 248
    cmp #112
    fail_if_ne

    ; Phase 6: write block 9 from $6000 by pseudo-DMA, tag bytes by WBUF,
    ; then the third handshake and a clean status.
    phase 6
    ldy #0
:   tya
    eor #$5a
    sta $6000,y
    tya
    eor #$a5
    sta $6100,y
    iny
    bne :-
    lda #1
    sta want
    jsr handshake
    lda #2                        ; write/verify
    sta cmdbuf
    lda #9
    sta cmdbuf+3
    jsr send_command
    lda #4
    sta want
    jsr handshake
    switch 1                      ; SETUPWRITE
    switch 3
    dma_run $f800, $ff, $60
    dma_run $f800, $ff, $61
    ldy #0
:   tya
    sta wbuf
    iny
    cpy #6
    bne :-
    switch 5                      ; SETUPREAD
    switch 7
    lda #6
    sta want
    jsr handshake
    jsr read_status
    lda #6                        ; the bench checks the host image now
    sta $0202

    ; Phase 7: deselected by C02x, the card ignores the ladder.
    phase 7
    lda #$70
    jsr fill_page
    lda $c020
    dma_run $f800, $ff, $70
    expect_byte $7000, $ea
    expect_byte $7080, $ea
    expect_byte $70ff, $ea

    ; Phase 8: GOODEXIT's dummy handshake with an invalid command and no
    ; waiting, then a deselect; the drive is idle for the next caller.
    phase 8
    lda #1
    sta want
    jsr handshake
    lda #$ff
    sta cmdbuf
    jsr send_command
    switch 4
    switch 4
    switch 0
    lda $c020
    jsr wait_idle
    lda rstat
    cmp #$80
    fail_if_ne

    lda #$5a
    sta $0200
halt:
    jmp halt

fail:
    lda #$ee
    sta $0200
:   jmp :-

; Read block A: first handshake, command bytes, second handshake, status.
read_command:
    sta cmdbuf+3
    lda #0
    sta cmdbuf
    sta cmdbuf+1
    sta cmdbuf+2
    lda #1
    sta want
    jsr handshake
    jsr send_command
    lda #2
    sta want
    jsr handshake
    jmp read_status

; SNDCMD: CMD up, compare the response, answer $55, CMD down.
handshake:
    jsr wait_idle
    switch 4
    jsr wait_busy
    lda rbuf
    cmp want
    fail_if_ne
    lda #$55
    sta wbuf
    switch 1
    switch 3
    switch 0
    jsr wait_idle
    switch 5
    switch 7
    rts

; SND_CMDBYTES: the six bytes at cmdbuf; retries and threshold are fixed.
send_command:
    lda #10
    sta cmdbuf+4
    lda #3
    sta cmdbuf+5
    switch 1
    switch 3
    ldx #0
:   lda cmdbuf,x
    sta wbuf
    inx
    cpx #6
    bne :-
    switch 5
    switch 7
    rts

; GETSTAT: four bytes, all of which must be zero here.
read_status:
    ldx #0
:   lda rbuf
    sta status,x
    bne status_fail
    inx
    cpx #4
    bne :-
    rts
status_fail:
    jmp fail

wait_idle:
    lda rstat
    bpl wait_idle
    rts

wait_busy:
    lda rstat
    bmi wait_busy
    rts

; Fill page A with $EA.
fill_page:
    sta ptr+1
    lda #0
    sta ptr
    lda #$ea
    ldy #0
:   sta (ptr),y
    iny
    bne :-
    rts

; 512 bytes from RBUF to (ptr).
move_in:
    ldy #0
:   lda rbuf
    sta (ptr),y
    iny
    bne :-
    inc ptr+1
:   lda rbuf
    sta (ptr),y
    iny
    bne :-
    rts

; X bytes (0 = 256) at (ptr) must hold value, value + 3, ...
check_range:
    ldy #0
:   lda (ptr),y
    cmp value
    fail_if_ne
    lda value
    clc
    adc #3
    sta value
    iny
    dex
    bne :-
    rts

; The monitor's pseudo-DMA block, as in Apple's ROM: an RTS at $F7FE, 64
; pairs of SBC #1 / BEQ from $F800, the branches from the first half going
; back to $F7FE, the pair at $F87C hopping through $F882, and the rest
; forward to the RTS at $F900. A = count; the fetches do the transfer.
.res $f7fe - *, $ea
ladder_low_exit:
    rts
    .byte $3f
.repeat 64, k
    sbc #1
    .if k < 31
    beq ladder_low_exit
    .elseif k = 31
    beq ladder_mid
    .else
    .if k = 32
ladder_mid:
    .endif
    beq ladder_high_exit
    .endif
.endrepeat
ladder_high_exit:
    rts

.res $fffa - *, $ea
    .word reset
    .word reset
    .word reset
