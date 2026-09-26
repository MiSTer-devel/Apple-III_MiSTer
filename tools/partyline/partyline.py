#!/usr/bin/env python3
"""Party line relay: several telnet callers share one room hosted by the Apple ///.

The Apple /// has one serial port, so this relay stands in for a bank of
modems. It answers telnet callers, asks each for a name and handles their
typing, and sends each finished line to the Apple /// as "[NAME] text". The
MAILBOX program on the Apple /// shows the line, logs it and sends it back, and
only lines the Apple /// sends are passed to the callers. When the Apple /// is
not in the room, callers are told so.

It replaces MidiLink on the UART while it runs (partyline.sh stops and restarts
MidiLink). Python 3.9, standard library only.

  partyline.py [--serial /dev/ttyS1] [--port 23] [--baud 2400]
"""

import argparse
import collections
import os
import selectors
import socket
import termios
import time

IAC, SB, SE, WILL, DO = 255, 250, 240, 251, 253
ECHO, SUPPRESS_GO_AHEAD = 1, 3
HELLO = b"PARTY LINE\r"
MAX_CALLERS = 6
MAX_LINE = 60
CHAR_GAP = 0.006  # seconds between characters to the Apple ///, a little idle time per byte
ACK_WAIT = 20.0  # seconds to wait for the Apple /// to send a line back; BASIC takes about 5
HELP = ("Type and press Return to talk. /who lists who is here, /bye hangs up.",)


class Caller:
    def __init__(self, sock, address):
        self.sock, self.address = sock, address
        self.name = None
        self.typed = ""
        self.telnet = 0  # 0 data, 1 after IAC, 2 option byte, 3 in SB, 4 IAC in SB
        self.last = 0
        self.pending = bytearray()


class Relay:
    def __init__(self, serial, port, baud):
        self.selector = selectors.DefaultSelector()
        self.serial = open_serial(serial, baud)
        self.selector.register(self.serial, selectors.EVENT_READ, "serial")
        self.listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.listener.bind(("", port))
        self.listener.listen(8)
        self.listener.setblocking(False)
        self.selector.register(self.listener, selectors.EVENT_READ, "listen")
        self.callers = {}
        self.from_apple = bytearray()
        self.to_apple = collections.deque()  # (line, caller who sent it or None)
        self.waiting = None  # (sent time, caller) while a line is out at the Apple ///
        self.history = collections.deque(maxlen=12)
        self.apple_out = bytearray(b"\r" + HELLO)  # sent a byte at a time
        self.next_byte = 0.0
        log(f"listening on port {port}, {serial} at {baud} baud")

    def run(self):
        while True:
            for key, mask in self.selector.select(timeout=CHAR_GAP if self.apple_out else 0.5):
                if key.data == "listen":
                    self.accept()
                elif key.data == "serial":
                    self.read_apple()
                elif mask & selectors.EVENT_WRITE:
                    self.flush(key.data)
                else:
                    self.read_caller(key.data)
            self.feed_apple()
            self.drip()

    def drip(self):
        """Send the Apple /// one byte, spaced so its serial port never sees them back to back."""
        now = time.monotonic()
        if self.apple_out and now >= self.next_byte:
            os.write(self.serial, self.apple_out[:1])
            del self.apple_out[:1]
            self.next_byte = now + CHAR_GAP

    # --- the Apple /// side

    def feed_apple(self):
        if self.waiting and time.monotonic() - self.waiting[0] > ACK_WAIT:
            caller = self.waiting[1]
            self.waiting = None
            if caller in self.callers.values():
                self.notice(caller, "(The Apple /// is not in the room right now.)")
        if not self.waiting and self.to_apple:
            line, caller = self.to_apple.popleft()
            self.apple_out += line.encode("latin-1") + b"\r"
            self.waiting = (time.monotonic(), caller)

    def read_apple(self):
        self.from_apple += os.read(self.serial, 512)
        while b"\r" in self.from_apple:
            raw, _, rest = self.from_apple.partition(b"\r")
            self.from_apple = bytearray(rest)
            line = bytes(b for b in raw if 32 <= b < 127).decode("latin-1").strip()
            if not line:
                continue
            if line.upper().startswith("AT"):  # the MAILBOX program looking for a modem
                self.apple_out += b"\r" + HELLO
                continue
            self.waiting = None
            self.history.append(line)
            for caller in list(self.callers.values()):
                if caller.name:
                    self.show(caller, line)

    # --- the callers

    def accept(self):
        sock, address = self.listener.accept()
        sock.setblocking(False)
        caller = Caller(sock, address)
        if len(self.callers) >= MAX_CALLERS:
            self.send(caller, b"The party line is full. Try again later.\r\n")
            sock.close()
            return
        self.callers[sock.fileno()] = caller
        self.selector.register(sock, selectors.EVENT_READ, caller)
        # The relay echoes, a character at a time, as a BBS does.
        self.send(caller, bytes([IAC, WILL, ECHO, IAC, WILL, SUPPRESS_GO_AHEAD]))
        self.send(caller, b"Apple /// party line\r\n\r\nYour name? ")
        log(f"call from {address[0]}")

    def read_caller(self, caller):
        try:
            data = caller.sock.recv(512)
        except (BlockingIOError, InterruptedError):
            return
        except OSError:
            data = b""
        if not data:
            self.hang_up(caller)
            return
        for byte in data:
            if caller.telnet or byte == IAC:
                self.telnet(caller, byte)
            elif byte in (13, 10):
                if not (byte == 10 and caller.last == 13):
                    self.enter(caller)
            elif byte in (8, 127):
                if caller.typed:
                    caller.typed = caller.typed[:-1]
                    self.send(caller, b"\b \b")
            elif 32 <= byte < 127:
                limit = 15 if caller.name is None else MAX_LINE
                if len(caller.typed) < limit:
                    caller.typed += chr(byte)
                    self.send(caller, bytes([byte]))
                else:
                    self.send(caller, b"\a")
            caller.last = byte
            if caller.sock.fileno() not in self.callers:
                return

    def telnet(self, caller, byte):
        state = caller.telnet
        if state == 0:
            caller.telnet = 1
        elif state == 1:
            caller.telnet = 2 if byte > SB else 3 if byte == SB else 0
        elif state == 2:
            caller.telnet = 0
        elif state == 3:
            caller.telnet = 4 if byte == IAC else 3
        else:
            caller.telnet = 0 if byte == SE else 3

    def enter(self, caller):
        text, caller.typed = caller.typed.strip(), ""
        if caller.name is None:
            self.name(caller, text.upper())
            return
        self.send(caller, b"\r\x1b[K")
        if not text:
            return
        command = text.lower()
        if command in ("/bye", "/quit"):
            self.send(caller, b"Goodbye!\r\n")
            self.hang_up(caller)
        elif command == "/who":
            names = ", ".join(c.name for c in self.callers.values() if c.name)
            self.notice(caller, f"On the line: {names}, and the Apple ///.")
        elif command in ("/help", "/?"):
            self.notice(caller, HELP[0])
        else:
            self.to_apple.append((f"[{caller.name}] {text}", caller))

    def name(self, caller, name):
        taken = {c.name for c in self.callers.values() if c.name}
        if not name or not all(ch.isalnum() or ch == " " for ch in name):
            self.send(caller, b"\r\nLetters and digits, please. Your name? ")
        elif name in taken:
            self.send(caller, b"\r\nThat name is here already. Your name? ")
        else:
            caller.name = name
            self.send(caller, b"\r\n" + HELP[0].encode() + b"\r\n\r\n")
            for line in self.history:
                self.send(caller, line.encode("latin-1") + b"\r\n")
            self.to_apple.append((f"* {name} joined.", caller))
            log(f"{caller.address[0]} is {name}")

    def hang_up(self, caller):
        if caller.sock.fileno() in self.callers:
            del self.callers[caller.sock.fileno()]
            self.selector.unregister(caller.sock)
        try:
            caller.sock.close()
        except OSError:
            pass
        if caller.name:
            self.to_apple.append((f"* {caller.name} left.", None))
            log(f"{caller.name} left")

    def show(self, caller, line):
        """A room line, printed above whatever the caller is typing."""
        self.send(caller, b"\r\x1b[K" + line.encode("latin-1") + b"\r\n" + caller.typed.encode("latin-1"))

    def notice(self, caller, text):
        self.show(caller, text)

    def send(self, caller, data):
        caller.pending += data
        self.flush(caller)

    def flush(self, caller):
        try:
            sent = caller.sock.send(caller.pending)
            del caller.pending[:sent]
        except (BlockingIOError, InterruptedError):
            pass
        except OSError:
            caller.pending.clear()
        if caller.sock.fileno() in self.callers:
            events = selectors.EVENT_READ | (selectors.EVENT_WRITE if caller.pending else 0)
            self.selector.modify(caller.sock, events, caller)


def open_serial(path, baud):
    fd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    iflag, oflag, cflag, lflag, _, _, cc = termios.tcgetattr(fd)
    speed = getattr(termios, f"B{baud}")
    iflag = 0
    oflag = 0
    lflag = 0
    cflag = termios.CS8 | termios.CREAD | termios.CLOCAL
    cc[termios.VMIN], cc[termios.VTIME] = 0, 0
    termios.tcsetattr(fd, termios.TCSANOW, [iflag, oflag, cflag, lflag, speed, speed, cc])
    termios.tcflush(fd, termios.TCIOFLUSH)
    return fd


def log(text):
    print(time.strftime("%H:%M:%S"), text, flush=True)


def main():
    parser = argparse.ArgumentParser(description="Party line relay for the Apple /// MAILBOX.")
    parser.add_argument("--serial", default="/dev/ttyS1", help="the UART to the core (default /dev/ttyS1)")
    parser.add_argument("--port", type=int, default=23, help="TCP port for callers (default 23)")
    parser.add_argument("--baud", type=int, default=2400, help="serial speed, as MAILBOX sets it (default 2400)")
    args = parser.parse_args()
    Relay(args.serial, args.port, args.baud).run()


if __name__ == "__main__":
    main()
