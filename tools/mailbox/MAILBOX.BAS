10 REM MAILBOX: messages and chat through MiSTer's modem, or a party line
20 REM The Apple /// answers one caller through MidiLink, or hosts a room
25 REM through tools/partyline/partyline.py. Callers use any telnet program.
30 REM Set your name and the caller's here.
40 me$="JACOB":you$="DARREN"
50 inbox$="INBOX":outbox$="OUTBOX":log$="PARTYLOG"
60 cr$= CHR$(13):nl$=cr$+ CHR$(10):w=0
100 INVOKE "REQUEST.INV"
110 OPEN #1,".RS232"
120 REM Status and control lists must be as long as the driver's reply.
130 d$= CHR$(15)+"123456789012345":s$="12345678"
140 PERFORM STATUS(%1,@d$)".RS232"
150 REM 2400 baud, 8 data bits, no parity, no handshake, as MiSTer's modem.
160 SUB$(d$,2,1)= CHR$(10):SUB$(d$,3,1)= CHR$(0):SUB$(d$,7,1)= CHR$(0)
165 PERFORM CONTROL(%1,@d$)".RS232"
170 REM Text files; OPEN AS EXTENSION alone would make typeless ones.
171 ON ERR GOTO 173
172 CREATE inbox$,TEXT
173 ON ERR GOTO 175
174 CREATE outbox$,TEXT
175 ON ERR GOTO 177
176 CREATE log$,TEXT
177 OFF ERR
178 k=0:ON KBD GOTO 9000
180 REM MidiLink ignores the first command after the core starts.
190 PRINT #1;cr$;:GOSUB 8000:PRINT #1;"AT";cr$;
1000 REM --- Waiting for a call
1010 HOME:f$=inbox$:GOSUB 7000
1020 PRINT "MAILBOX":PRINT
1030 PRINT "Waiting for ";you$;" to call."
1040 PRINT n;" message(s) from ";you$;".":PRINT
1050 PRINT "R  Read messages     W  Write a message"
1060 PRINT "D  Delete messages   C  Clear yours"
1070 PRINT "P  Party line        L  Party line log"
1075 PRINT "Q  Quit"
1080 l$=""
1100 IF k THEN GOTO 1200
1110 GOSUB 2000:IF c$="" THEN GOTO 1100
1120 IF c$=cr$ OR c$= CHR$(10) THEN GOTO 1150
1130 IF LEN(l$)<60 THEN l$=l$+c$
1140 GOTO 1100
1150 IF INSTR(l$,"CONNECT") THEN GOTO 3000
1155 IF l$="PARTY LINE" OR RIGHT$(l$,8)=" joined." THEN t$=l$:GOTO 8100
1160 l$="":GOTO 1100
1200 key=k:k=0:IF key>96 THEN key=key-32
1210 IF key=82 THEN f$=inbox$:h$="Messages from "+you$:GOSUB 4000:GOTO 1000
1220 IF key=87 THEN GOSUB 4200:GOTO 1000
1230 IF key=68 THEN f$=inbox$:GOSUB 4400:GOTO 1000
1240 IF key=67 THEN f$=outbox$:GOSUB 4400:GOTO 1000
1245 IF key=80 THEN t$="":GOTO 8100
1247 IF key=76 THEN f$=log$:h$="Party line log":GOSUB 4000:GOTO 1000
1250 IF key=81 THEN OFF KBD:CLOSE:END
1260 GOTO 1100
2000 REM --- One character from the port in c$, or ""; telnet commands are dropped
2010 c$="":IF w=0 THEN PERFORM STATUS(%3,@s$)".RS232":w= ASC( MID$(s$,7,1))
2020 IF w=0 THEN RETURN
2030 GET #1;c$:w=w-1:a= ASC(c$)
2040 IF tel=0 AND a<>255 THEN RETURN
2050 c$="":IF tel=0 THEN tel=1:RETURN
2060 IF tel=2 THEN tel=0:RETURN
2070 IF tel=1 AND a>250 THEN tel=2:RETURN
2080 IF tel=1 AND a=250 THEN tel=3:RETURN
2090 IF tel=1 THEN tel=0:RETURN
2100 IF tel=3 AND a=255 THEN tel=4:RETURN
2110 IF tel=4 AND a=240 THEN tel=0:RETURN
2120 IF tel=4 THEN tel=3
2130 RETURN
3000 REM --- A caller is connected
3010 HOME:PRINT CHR$(7);you$;" called.  ESC hangs up.":PRINT:tel=0
3020 REM Telnet: the Apple /// echoes, a character at a time.
3030 PRINT #1; CHR$(255); CHR$(251); CHR$(1); CHR$(255); CHR$(251); CHR$(3);
3040 o$="Welcome to "+me$+"'s Apple /// mailbox.":GOSUB 5000
3050 f$=outbox$:GOSUB 7000
3060 o$="You have "+ STR$(n)+" message(s) from "+me$+".":GOSUB 5000
3070 o$="":GOSUB 5000
3080 o$="R Read  L Leave a message  C Chat  G Goodbye":GOSUB 5000
3090 o$="Choice? ":GOSUB 5000:GOSUB 5500:IF gone THEN GOTO 1000
3100 IF a$="" THEN GOTO 3090
3110 a= ASC(a$):IF a>96 THEN a=a-32
3120 IF a=82 THEN GOSUB 6000
3130 IF a=76 THEN GOSUB 6200
3140 IF a=67 THEN GOSUB 6400
3150 IF a=71 THEN GOSUB 6800:GOTO 1000
3160 IF gone THEN GOTO 1000
3170 GOTO 3070
4000 REM --- Show file f$ here under the heading h$
4010 OFF KBD:HOME:PRINT h$;":":PRINT
4020 OPEN #2 AS INPUT,f$:ON EOF#2 GOTO 4060
4030 INPUT #2;t$:PRINT t$
4040 IF VPOS>21 THEN PRINT "-- more --";:GET a$:HOME
4050 GOTO 4030
4060 CLOSE #2:PRINT:PRINT "-- end, press a key --";:GET a$
4070 k=0:ON KBD GOTO 9000
4080 RETURN
4200 REM --- Write a message for the caller
4210 OFF KBD:HOME:PRINT "Message for ";you$;". An empty line ends it.":PRINT
4220 OPEN #2 AS EXTENSION,outbox$
4230 GOSUB 7500:PRINT #2;"== From ";me$;", ";when$
4240 INPUT "";t$:IF t$<>"" THEN PRINT #2;t$:GOTO 4240
4250 CLOSE #2
4260 k=0:ON KBD GOTO 9000
4270 RETURN
4400 REM --- Empty file f$ after asking
4410 OFF KBD:PRINT:PRINT "Delete all of ";f$;"? (Y/N) ";:GET a$
4420 IF a$="Y" OR a$="y" THEN DELETE f$:CREATE f$,TEXT
4430 k=0:ON KBD GOTO 9000
4440 RETURN
5000 REM --- Send o$ to the caller and show it here; a new line unless o$ ends in a space
5010 PRINT #1;o$;:PRINT o$;
5020 IF RIGHT$(o$,1)<>" " THEN PRINT #1;nl$;:PRINT
5030 RETURN
5500 REM --- A line from the caller in a$, echoed; gone=1 once the call ends
5510 a$="":gone=0
5520 IF k=27 THEN k=0:GOSUB 6800:gone=1:RETURN
5530 k=0:GOSUB 2000:IF c$="" THEN GOTO 5520
5540 a= ASC(c$)
5550 IF a=13 THEN PRINT #1;nl$;:PRINT:GOTO 5590
5560 IF a=8 OR a=127 THEN GOSUB 5700:GOTO 5520
5570 IF a>31 AND a<127 AND LEN(a$)<70 THEN a$=a$+c$:PRINT #1;c$;:PRINT c$;
5580 GOTO 5520
5590 IF INSTR(a$,"NO CARRIER") THEN gone=1
5600 RETURN
5700 REM --- Backspace over the last character of a$
5710 IF a$="" THEN RETURN
5720 IF LEN(a$)>1 THEN a$= LEFT$(a$, LEN(a$)-1):ELSE a$=""
5730 PRINT #1; CHR$(8);" "; CHR$(8);:PRINT CHR$(8);" "; CHR$(8);:RETURN
6000 REM --- Send the messages left for the caller
6005 f$=outbox$:GOSUB 7000:IF n=0 THEN o$="No messages from "+me$+" yet.":GOSUB 5000:RETURN
6010 OPEN #2 AS INPUT,outbox$:ON EOF#2 GOTO 6050
6020 INPUT #2;t$:o$=t$:GOSUB 5000
6030 GOTO 6020
6050 CLOSE #2:RETURN
6200 REM --- Take a message from the caller
6210 o$="Type your message. An empty line ends it.":GOSUB 5000
6220 OPEN #2 AS EXTENSION,inbox$
6230 GOSUB 7500:PRINT #2;"== From ";you$;", ";when$
6240 GOSUB 5500:IF gone THEN GOTO 6270
6250 IF a$<>"" THEN PRINT #2;a$:GOTO 6240
6260 o$="Saved. Thank you.":GOSUB 5000:PRINT CHR$(7);
6270 CLOSE #2:RETURN
6400 REM --- Chat: both sides type; ESC on either ends it
6410 o$="Calling "+me$+". ESC leaves the chat.":GOSUB 5000
6420 PRINT CHR$(7); CHR$(7);"Chat: type to talk, ESC ends it.":l$=""
6430 IF k=0 THEN GOTO 6500
6440 a=k:k=0:IF a=27 THEN GOTO 6600
6450 IF a=13 THEN PRINT #1;nl$;:PRINT:GOTO 6430
6460 IF a>31 AND a<127 THEN PRINT #1; CHR$(a);:PRINT CHR$(a);
6470 GOTO 6430
6500 GOSUB 2000:IF c$="" THEN GOTO 6430
6510 a= ASC(c$):IF a=27 THEN GOTO 6600
6520 IF a=13 THEN PRINT #1;nl$;:PRINT:GOTO 6560
6530 IF a>31 AND a<127 THEN PRINT #1;c$;:PRINT c$;:IF LEN(l$)<40 THEN l$=l$+c$
6540 GOTO 6430
6560 IF INSTR(l$,"NO CARRIER") THEN gone=1:RETURN
6570 l$="":GOTO 6430
6600 o$="":GOSUB 5000:o$="Chat ended.":GOSUB 5000:RETURN
6800 REM --- Say goodbye and hang up
6810 o$="Goodbye!":GOSUB 5000:GOSUB 8000
6820 PRINT #1;"+++";:GOSUB 8000:GOSUB 8000:PRINT #1;"ATH";cr$;:GOSUB 8000
6830 RETURN
7000 REM --- n = messages in f$
7010 n=0:OPEN #2 AS INPUT,f$:ON EOF#2 GOTO 7040
7020 INPUT #2;t$:IF LEFT$(t$,3)="== " THEN n=n+1
7030 GOTO 7020
7040 CLOSE #2:RETURN
7500 REM --- when$ = the date and time as MM/DD/YY HH:MM
7510 t$= DATE$:when$= MID$(t$,4,2)+"/"+ RIGHT$(t$,2)+"/"+ LEFT$(t$,2)+" "+ LEFT$( TIME$,5)
7520 RETURN
8000 REM --- Wait about a second
8010 t$= TIME$
8020 IF t$= TIME$ THEN GOTO 8020
8030 RETURN
8100 REM --- Party line: the relay brings the callers; the Apple /// runs the room.
8105 REM Every room line comes here, is shown and logged, and goes back out.
8110 HOME:PRINT "PARTY LINE on ";me$;"'s Apple ///"
8120 PRINT "Type and press Return to talk.  ESC leaves the party line.":PRINT
8130 OPEN #3 AS EXTENSION,log$:in$="":esc=0
8140 IF LEFT$(t$,1)="*" OR LEFT$(t$,1)="[" THEN GOSUB 8400
8150 IF k THEN GOTO 8300
8160 PERFORM STATUS(%3,@s$)".RS232":IF ASC( MID$(s$,7,1))=0 THEN GOTO 8150
8170 REM The relay sends whole lines, so INPUT# reads one at machine speed.
8180 INPUT #1;t$:w=0
8200 IF t$="" OR t$="PARTY LINE" THEN GOTO 8150
8210 GOSUB 8400:GOTO 8150
8300 a=k:k=0
8305 IF a=27 AND esc THEN GOTO 8500
8310 IF a=27 THEN esc=1:GOSUB 8430:PRINT "(Press ESC again to leave the party line.)":PRINT in$;:GOTO 8150
8315 esc=0
8320 IF a=13 THEN GOTO 8360
8330 IF a=8 OR a=127 THEN GOSUB 8450:GOTO 8150
8340 IF a<32 OR a>126 THEN GOTO 8150
8342 REM A full line goes out by itself instead of dropping what follows.
8344 IF LEN(in$)>=60 THEN GOSUB 8430:t$="["+me$+"] "+in$:in$="":GOSUB 8400
8346 in$=in$+ CHR$(a):PRINT CHR$(a);
8350 GOTO 8150
8360 IF in$="" THEN GOTO 8150
8370 GOSUB 8430:t$="["+me$+"] "+in$:in$="":GOSUB 8400:GOTO 8150
8400 REM --- Room line t$: show it above the unfinished line, log it, send it out
8410 GOSUB 8430:PRINT t$:PRINT #3;t$:PRINT #1;t$;cr$;
8420 PRINT in$;:RETURN
8430 REM --- Erase the unfinished line from the screen
8440 IF in$<>"" THEN HPOS=1:PRINT SPC( LEN(in$));:HPOS=1
8445 RETURN
8450 REM --- Backspace in in$
8460 IF in$="" THEN RETURN
8470 IF LEN(in$)>1 THEN in$= LEFT$(in$, LEN(in$)-1):ELSE in$=""
8480 PRINT CHR$(8);" "; CHR$(8);:RETURN
8500 t$="* "+me$+" left the party line.":GOSUB 8400
8510 CLOSE #3:GOTO 1000
9000 REM --- Keyboard: keep the key for the main loop.
9001 REM ON KBD and ON EOF skip the rest of their line, so RETURN goes below.
9010 k= KBD:ON KBD GOTO 9000
9020 RETURN
