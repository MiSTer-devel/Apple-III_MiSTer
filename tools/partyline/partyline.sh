#!/bin/bash
# Turns the Apple /// party line on or off. Copy this and partyline.py to
# /media/fat/Scripts and run it from the Scripts menu once the Apple-III core
# is running the MAILBOX disk. MiSTer's modem (MidiLink) stops while the party
# line runs, and a second run brings it back.

dir=$(dirname "$(readlink -f "$0")")
pid_file=/tmp/partyline.pid

if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
	kill "$(cat "$pid_file")"
	rm -f "$pid_file"
	uartmode "$(cat /tmp/partyline.uartmode 2>/dev/null || echo 0)" >/dev/null 2>&1
	echo "Party line off. MiSTer's modem is back."
	exit 0
fi

mode=0
for flag in /tmp/uartmode[0-9]; do
	[ -e "$flag" ] && mode=${flag#/tmp/uartmode}
done
echo "$mode" >/tmp/partyline.uartmode
uartmode 0 >/dev/null 2>&1
killall -q midilink 2>/dev/null
for _ in 1 2 3 4 5 6 7 8 9 10; do  # MidiLink can take a moment to let go of port 23
	netstat -tln 2>/dev/null | grep -q ":23 " || break
	sleep 0.5
done
setsid python3 "$dir/partyline.py" >/tmp/partyline.log 2>&1 </dev/null &
echo $! >"$pid_file"
sleep 2
if kill -0 "$(cat "$pid_file")" 2>/dev/null; then
	address=$(ip -4 -o addr show scope global | awk '{print $4}' | cut -d/ -f1 | head -1)
	echo "Party line on. Callers telnet to $address, port 23."
	echo "Run this script again to turn it off."
else
	echo "The party line did not start:"
	cat /tmp/partyline.log
	uartmode "$(cat /tmp/partyline.uartmode)" >/dev/null 2>&1
fi
