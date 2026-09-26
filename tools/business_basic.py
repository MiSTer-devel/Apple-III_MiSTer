#!/usr/bin/env python3
"""Convert Apple /// Business BASIC programs (SOS file type $09, BA3) to and from text.

A BA3 file is a word holding the offset of its last two bytes, then one record
per line: a length byte counting the whole record, the line number, the line's
bytes and a zero. A zero length ends the program, and two zero bytes follow.
Keywords are one byte from $80, or $FF and a second byte for the table's upper
half; names, numbers, operators and strings stay ASCII. The interpreter drops
spaces outside strings, but keeps the rest of a line after REM, DATA or IMAGE
as typed.

The keyword table is AppleCommander's (BusinessBASICTokenizer.java). Every
keyword it lists in both halves (TO, THEN, STEP, AND, OR and the rest) appears
in real programs only in the upper half, so that is the one written here.

  tools/business_basic.py list PROGRAM.BA3
  tools/business_basic.py tokenize PROGRAM.TXT PROGRAM.BA3
"""

import argparse
import re
import sys

# Index 0 is $80. Indexes from $80 are written as $FF, index.
_TABLE = """
END FOR NEXT INPUT OUTPUT DIM READ WRITE
OPEN CLOSE - TEXT - BYE - -
- - - WINDOW INVOKE PERFORM - -
FRE HPOS VPOS ERRLIN ERR KBD EOF TIME$
DATE$ PREFIX$ EXFN. EXFN%. OUTREC INDENT - -
- - - - - POP HOME -
SUB$( OFF TRACE NOTRACE NORMAL INVERSE SCALE( RESUME
- LET GOTO IF RESTORE SWAP GOSUB RETURN
REM STOP ON - LOAD SAVE DELETE RUN
RENAME LOCK UNLOCK CREATE EXEC CHAIN - -
- CATALOG - - DATA IMAGE CAT DEF
- PRINT DEL ELSE CONT LIST CLEAR GET
NEW - - - - - - -
- - - - - - - -
- - - - - - - -
- - - - - - - -
TAB( TO SPC( USING THEN - MOD STEP
AND OR EXTENSION DIV - FN NOT -
- - - - - - - -
- - - - AS SGN( INT( ABS(
- TYP( REC( - - - - -
- - - - - PDL( BUTTON( SQR(
RND( LOG( EXP( COS( SIN( TAN( ATN( -
- - - - - - - -
- - - STR$( HEX$( CHR$( LEN( VAL(
ASC( TEN( - - CONV( CONV&( CONV$( CONV%(
LEFT$( RIGHT$( MID$( INSTR( - - - -
""".split()  # noqa: SIM905 (the table reads as the interpreter lays it out)
NAMES = {index: name for index, name in enumerate(_TABLE) if name != "-"}
CODES = {name: bytes([0xFF, index]) if index >= 0x80 else bytes([0x80 + index])
         for index, name in NAMES.items()}
RAW_REST = {"REM", "DATA", "IMAGE"}
WORD = re.compile(r"[A-Za-z][A-Za-z0-9.]*[$%&]?")


def detokenize(data):
    """Yield (line number, text) for each line, with a space around keywords."""
    offset = 2
    while offset < len(data) and data[offset]:
        length = data[offset]
        number = int.from_bytes(data[offset + 1:offset + 3], "little")
        body = data[offset + 3:offset + length - 1]
        offset += length
        parts, i = [], 0
        while i < len(body):
            byte = body[i]
            if byte & 0x80:
                index = body[i + 1] if byte == 0xFF else byte - 0x80
                i += 2 if byte == 0xFF else 1
                name = NAMES.get(index, f"<${index:02X}>")
                parts.append(("key", name))
                if name in RAW_REST:
                    parts.append(("raw", body[i:].decode("latin-1")))
                    break
                continue
            j = i + 1
            if byte == 0x22:
                j = body.find(b'"', i + 1) + 1 or len(body)
            else:
                while j < len(body) and not body[j] & 0x80 and body[j] != 0x22:
                    j += 1
            parts.append(("text", body[i:j].decode("latin-1")))
            i = j
        text = ""
        for kind, value in parts:
            if kind == "key":
                if text and not text.endswith(" "):
                    text += " "
                text += value if value.endswith("(") or value in RAW_REST else value + " "
            else:
                text += value
        yield number, text.rstrip() if parts and parts[-1][0] != "raw" else text


def tokenize_line(text):
    """Tokenize the text of one line, after its number."""
    out, i = bytearray(), 0
    while i < len(text):
        ch = text[i]
        if ch == " ":
            i += 1
        elif ch == '"':
            end = text.find('"', i + 1)
            end = len(text) if end < 0 else end + 1
            out += text[i:end].encode("latin-1")
            i = end
        elif word_match := WORD.match(text, i):
            word = word_match.group()
            paren = text.startswith("(", i + len(word))
            key = word.upper()
            if paren and key + "(" in CODES:
                out += CODES[key + "("]
                i += len(word) + 1
            elif key in CODES:
                out += CODES[key]
                i += len(word)
                if key in RAW_REST:
                    out += text[i:].encode("latin-1")
                    break
            else:
                out += word.encode("latin-1")
                i += len(word)
        else:
            out.append(ord(ch))
            i += 1
    return bytes(out)


def tokenize(source):
    """Tokenize numbered source lines into a BA3 file."""
    program, last = bytearray(), -1
    for row, line in enumerate(source.replace("\r\n", "\n").split("\n"), start=1):
        if not line.strip():
            continue
        match = re.match(r"\s*(\d+)\s?(.*)$", line)
        if not match:
            raise ValueError(f"line {row}: no line number")
        number = int(match.group(1))
        if not last < number <= 63999:
            raise ValueError(f"line {row}: line {number} is out of order or too large")
        body = tokenize_line(match.group(2))
        if len(body) + 4 > 255:
            raise ValueError(f"line {row}: line {number} is too long once tokenized")
        program += bytes([len(body) + 4]) + number.to_bytes(2, "little") + body + b"\0"
        last = number
    program += b"\0"
    return (len(program) + 2).to_bytes(2, "little") + bytes(program) + b"\0\0"


def main():
    parser = argparse.ArgumentParser(description="Convert Business BASIC programs to and from text.")
    commands = parser.add_subparsers(dest="command", required=True)
    listing = commands.add_parser("list", help="print a BA3 file as text")
    listing.add_argument("program")
    tokens = commands.add_parser("tokenize", help="write a BA3 file from text")
    tokens.add_argument("source")
    tokens.add_argument("program")
    args = parser.parse_args()
    if args.command == "list":
        with open(args.program, "rb") as program:
            for number, text in detokenize(program.read()):
                print(number, text)
    else:
        with open(args.source, encoding="latin-1") as source:
            try:
                data = tokenize(source.read())
            except ValueError as error:
                sys.exit(f"{args.source}: {error}")
        with open(args.program, "wb") as program:
            program.write(data)


if __name__ == "__main__":
    main()
