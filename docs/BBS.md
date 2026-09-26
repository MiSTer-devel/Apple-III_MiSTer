# Calling a BBS

The Apple ///'s serial port is wired to MiSTer's UART. In MiSTer's **Modem**
mode, MidiLink answers Hayes `AT` commands and dials telnet addresses, so the
Apple /// can call today's BBSes with Access ///, Apple's terminal program for
it. Checked on a MiSTer with Level 29 and RetroCampus BBS at 2400 baud.

## 1. Make the Access /// disk

Access /// is on the hard disk of datajerk's
[Apple /// Ready-to-Run](https://github.com/datajerk/apple3rtr) bundle, next to
a bootable Access 3270 floppy. `tools/access_disk.py` puts Access /// on a copy
of that floppy. It needs MAME's `chdman` and AppleCommander's command-line jar:

```sh
git clone https://github.com/datajerk/apple3rtr
tools/access_disk.py apple3rtr Access3_MiSTer.dsk --ac AppleCommander-ac.jar
```

Copy `Access3_MiSTer.dsk` to `games/Apple-III`. At boot its `ACCESS.CMD` sets
2400 baud, 8 bits, no parity and VT100 emulation, lists the dial commands and
sends `AT`. MidiLink ignores the first command after the core starts, so the
disk sends an empty line first; the `OK` that follows shows the modem is there.

## 2. Set up the MiSTer

With the Apple /// core loaded, open MiSTer's system menu (Win+F12) and set
**UART Connection** to **Modem**, **Link** to **TCP** and **Baud** to **2400**.
MiSTer keeps these for the core.

Leave the core's **Hardware** page at its defaults: **Serial CTS** and
**Serial DSR** at **Always ready** and **Serial DCD** at **Always on**. MiSTer's
modem never raises the line behind DSR, and Apple's serial driver sends nothing
while DSR is false.

## 3. Call

Mount `Access3_MiSTer.dsk` as Drive 1 and reset. Once `OK` appears below the
list, type

```
ATDTBBS.FOZZTEXX.COM:23
```

and press Return. MidiLink answers `DIALING` and `CONNECT 2400`, and Level 29
shows its banner. Log in as `VISITOR`, accept `80x24` with Return, and give
`vt100` as the terminal type. **O** logs off.

RetroCampus BBS is `ATDTBBS.RETROCAMPUS.COM:23`. Choose **4**, plain ASCII at
80 × 24, for its news, games, chat and text web browser.

Open Apple (the Windows or Command key) + **C** runs a command file instead:
`/ACCESS/LEVEL29.CMD` or `/ACCESS/RETRO.CMD`.

## 4. Hang up

Type `+++`, wait a second, then `ATH` and Return. MidiLink answers
`NO CARRIER` and `OK`.

## Hosting a mailbox

`tools/mailbox/MAILBOX.BAS` turns the Apple /// into a one-line mailbox for a
friend. They call in with any telnet program to read your messages, leave
theirs, or chat with you live. MiSTer's modem answers the call, so the Apple ///
must be running the Mailbox when they call.

Build the disk from Apple's Business BASIC 1.23 disk (`Apple3BusBasic1.23.dsk`
from apple3.org or the Asimov archive). Set the two names at the top of
`MAILBOX.BAS` first:

```sh
tools/mailbox_disk.py Apple3BusBasic1.23.dsk Mailbox.dsk
```

Set the MiSTer's UART as in step 2, mount `Mailbox.dsk` as Drive 1 and reset.
Business BASIC runs the Mailbox at boot. At the waiting screen, **R** reads
their messages, **W** writes one for them (an empty line ends it), **D**
deletes theirs, **C** clears yours and **Q** quits. During a call, **ESC** hangs
up, and when they choose chat, whatever you type goes to them.

Your friend connects to the MiSTer's address on port 23, for example
`telnet 192.168.1.20`, or with PuTTY or SyncTERM. From another MiSTer, Access ///
dials `ATDT192.168.1.20:23`. Their menu is **R** read, **L** leave a message,
**C** chat and **G** goodbye.

To reach it from outside your home, forward one TCP port on your router to the
MiSTer's port 23 and give them your public address and that port. Use an
unusual outside port such as 6502: bots scan port 23 constantly and would keep
the one line busy. Forward nothing else; the MiSTer's ssh logs in as root with
password `1`.

* Messages are the text files `INBOX` and `OUTBOX` on the disk, so leave Write
  Protect off.
* One caller at a time. A second caller's connection waits, silent, until the
  first hangs up, and is then answered; MidiLink says `BUSY` only while the
  Apple /// is itself dialing out.
* The caller sees `+++` as the Mailbox hangs up: that is the modem's hang-up
  command, which MidiLink passes through.
* `tools/business_basic.py` lists and tokenizes Business BASIC programs, so
  `MAILBOX.BAS` stays plain text.

### Party line

For more than one caller, the MiSTer stands in for a bank of modems.
`tools/partyline/partyline.py` answers up to six telnet callers, asks their
names and handles their typing; the Mailbox is still the host. Every line goes
to the Apple ///, which shows it, logs it to `PARTYLOG` and sends it back to
everyone, so nobody hears anybody while the Apple /// is out of the room.

Copy `tools/partyline/partyline.sh` and `partyline.py` to `/media/fat/Scripts`,
boot the Mailbox and run **partyline** from the Scripts menu. MiSTer's modem
stops while it runs; run it again to bring the modem back, before loading
another core. The Apple /// joins the room when the party line starts or
someone joins. Type there to talk, **ESC** leaves, and **P** at the waiting
screen rejoins; **L** reads the log. Callers connect as before, give a name, and
have `/who` and `/bye`. `tools/partyline/test_partyline.py` checks the relay
with a stand-in Apple ///.

`tools/mailbox_disk.py --messages-from OLD.dsk` keeps `INBOX`, `OUTBOX` and
`PARTYLOG` when rebuilding the disk.

## Notes

* Level 29's first line can show a few stray characters from its telnet
  negotiation.
* Access /// also runs at 4800 and 9600 baud (`@XR5` and `@XR6` in
  `ACCESS.CMD`); set MiSTer's modem to the same speed. Only 2400 has been tried.
* If there is no `OK` at startup, or `ATDT` shows nothing, check **Serial DSR**
  and that the UART is in Modem mode at Access ///'s speed. With **Serial DSR**
  at **Host DTR** the Apple /// sends nothing.
* Rob Justice's `sos_selector_hd.po` also has Access /// in
  `/SOS/PROGRAMS/ACCESS3`, with its original settings rather than these.
* MidiLink's other commands, such as `ATIP` and its dialing directory, are in
  [its README](https://github.com/MiSTer-devel/MidiLink_MiSTer).
