#!/usr/bin/env python3
"""Check partyline.py with three telnet callers and a stand-in Apple /// on a pty.

The stand-in sends every room line back, as MAILBOX does in party mode, and can
leave the room to check the relay's "not in the room" notice.

  tools/partyline/test_partyline.py
"""

import os
import pty
import socket
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
PORT = 16502


class Apple(threading.Thread):
    """Sends each room line back after a short delay; records what it got."""

    def __init__(self, master):
        super().__init__(daemon=True)
        self.master, self.present, self.lines = master, True, []

    def run(self):
        buffer = b""
        while True:
            buffer += os.read(self.master, 256)
            while b"\r" in buffer:
                line, _, buffer = buffer.partition(b"\r")
                line = line.strip().decode()
                self.lines.append(line)
                if line and line != "PARTY LINE" and self.present:
                    time.sleep(0.05)
                    os.write(self.master, line.encode() + b"\r")

    def say(self, text):
        os.write(self.master, text.encode() + b"\r")


class Caller:
    def __init__(self, name):
        self.sock = socket.create_connection(("127.0.0.1", PORT), timeout=5)
        self.sock.settimeout(0.1)
        self.seen = b""
        self.expect(b"Your name? ")
        self.type(name + "\r\n")
        self.expect(b"/bye hangs up.")

    def type(self, text):
        for ch in text.encode():
            self.sock.sendall(bytes([ch]))

    def expect(self, text, wait=5.0):
        end = time.time() + wait
        while time.time() < end:
            if text in self.seen:
                self.seen = self.seen[self.seen.index(text) + len(text):]
                return
            try:
                data = self.sock.recv(4096)
                if not data:
                    break
                self.seen += data
            except TimeoutError:
                pass
        sys.exit(f"FAIL: never saw {text!r}; got {self.seen!r}")


def main():
    master, slave = pty.openpty()
    relay = subprocess.Popen([sys.executable, os.path.join(HERE, "partyline.py"),
                              "--serial", os.ttyname(slave), "--port", str(PORT)],
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    apple = Apple(master)
    apple.start()
    try:
        time.sleep(0.8)
        apple.say("AT")
        ada = Caller("ada")
        ada.expect(b"* ADA joined.")
        bob = Caller("Bob")
        ada.expect(b"* BOB joined.")
        bob.expect(b"* BOB joined.")
        bob.sock.sendall(bytes([255, 253, 1, 255, 250, 24, 1, 255, 240]))  # telnet noise
        bob.type("hello, everyone\r\n")
        ada.expect(b"[BOB] hello, everyone")
        bob.expect(b"[BOB] hello, everyone")
        apple.say("[SYSOP] welcome to the Apple ///")
        ada.expect(b"[SYSOP] welcome to the Apple ///")
        bob.expect(b"[SYSOP] welcome to the Apple ///")
        cy = Caller("cy")
        cy.expect(b"[SYSOP] welcome to the Apple ///")  # history for a late caller
        bob.type("/who\r")
        bob.expect(b"On the line: ADA, BOB, CY, and the Apple ///.")
        ada.type("bye all\r/bye\r")
        ada.expect(b"Goodbye!")
        cy.expect(b"[ADA] bye all")
        cy.expect(b"* ADA left.")
        apple.present = False
        cy.type("anyone?\r")
        cy.expect(b"(The Apple /// is not in the room right now.)", wait=25)
        bob.sock.close()
        time.sleep(0.5)
        for want in ("PARTY LINE", "[BOB] hello, everyone", "* BOB left."):
            if not any(want in line for line in apple.lines):
                sys.exit(f"FAIL: the Apple never got {want!r}: {apple.lines}")
        if any("\xff" in line or "\x18" in line for line in apple.lines):
            sys.exit(f"FAIL: telnet bytes reached the Apple: {apple.lines}")
        print("PASS party line: join, chat, history, /who, /bye, hang-up notices, Apple away")
    finally:
        relay.terminate()
        output = relay.communicate(timeout=5)[0].decode()
        if relay.returncode not in (0, -15):
            print(output)


if __name__ == "__main__":
    main()
