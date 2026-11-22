#!/usr/bin/env python3
"""make_basic.py - add our computer to Microsoft's BASIC as configuration 6.

Build Your Own 6502 Computer on an FPGA - Adrian Velcourt.  MIT licence.

Reads Microsoft's m6502.asm (MIT licence, Copyright (c) Microsoft
Corporation) and writes m6502_velcourt.asm with REALIO=6 selected and
the few blocks our machine needs. Each edit is anchored on text that
must appear exactly once, so a changed original fails loudly.
Every added line is marked ;VELCOURT: so you can find them.
"""
import sys

src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding="latin-1").read().replace("\r\n", "\n")

EDITS = [
# 1. choose our configuration
("REALIO=4\t\t\t;5=STM\n",
 "REALIO=6\t\t\t;6=VELCOURT FPGA COMPUTER  ;VELCOURT:\n\t\t\t\t;5=STM\n"),

# 2. the switches and kernel entry points for configuration 6
("\tRORSW==1\n\tSTKEND=507>\n",
 "\tRORSW==1\n\tSTKEND=507>\n"
 "IFE\tREALIO-6,<\t\t\t;VELCOURT: OUR FPGA COMPUTER.\n"
 "\tRORSW==1\t\t\t;VELCOURT: OUR 6502 HAS ROR.\n"
 "\tDISKO==1\t\t\t;VELCOURT: SAVE AND LOAD ON THE SD CARD.\n"
 "\tNULCMD==0\t\t\t;VELCOURT:\n"
 "\tGETCMD==1\t\t\t;VELCOURT:\n"
 "\tLINLEN==40\t\t\t;VELCOURT: 40 COLUMNS ON THE SCREEN.\n"
 "\tROMLOC==^O140000\t\t;VELCOURT: BASIC STARTS AT $C000.\n"
 "\tRAMLOC==^O3000\t\t\t;VELCOURT: PROGRAMS START AT $0600.\n"
 "\tOUTCH==^O177400\t\t\t;VELCOURT: KERNEL CHROUT AT $FF00.\n"
 "\tCQINCH==^O177403\t\t;VELCOURT: KERNEL CHRIN  AT $FF03.\n"
 "\tCZGETL==^O177406\t\t;VELCOURT: KERNEL GETKEY AT $FF06.\n"
 "\tCQSAVE==^O177411\t\t;VELCOURT: KERNEL SAVE   AT $FF09.\n"
 "\tCQLOAD==^O177414>\t\t;VELCOURT: KERNEL LOAD   AT $FF0C.\n"),

# 3. reading a character: ask the kernel (it echoes, like a terminal)
("\tJSR\tCQINCH\t\t;FD0C FOR APPLE COMPUTER.\n\tANDI\t127>\n",
 "\tJSR\tCQINCH\t\t;FD0C FOR APPLE COMPUTER.\n\tANDI\t127>\n"
 "IFE\tREALIO-6,<\t\t\t;VELCOURT:\n"
 "\tJSR\tCQINCH>\t\t\t;VELCOURT: WAIT FOR A KEY.\n"),

# 4. checking for control-C while a program runs
("ISCCAP: JSR\tINCHR\n\tCMPI\t^O203>\n",
 "ISCCAP: JSR\tINCHR\n\tCMPI\t^O203>\n"
 "IFE\tREALIO-6,<\t\t\t;VELCOURT:\n"
 "ISCNTC: JSR\t^O177452\t\t;VELCOURT: KERNEL STOPKEY $FF2A: [A]=3 IF\n"
 "\t\t\t\t;VELCOURT: CONTROL-C, ELSE 0 (KEYS ARE KEPT).\n"
 "\tBEQ\tISCRTS\t\t\t;VELCOURT: NO, CARRY ON.\n"
 "\tCMPI\t3>\t\t\t;VELCOURT: CONTROL-C STOPS THE PROGRAM.\n"),

# 5. SAVE "NAME" and LOAD "NAME" through the kernel
("TPDONE: DT\"LOADED\"\n\t0\n",
 "TPDONE: DT\"LOADED\"\n\t0\n"),
("PROGIO: LDWD\tTXTTAB\n\tSTWD\t^O74\n\tLDWD\tVARTAB\n\tSTWD\t^O76\n\tRTS>\n",
 "PROGIO: LDWD\tTXTTAB\n\tSTWD\t^O74\n\tLDWD\tVARTAB\n\tSTWD\t^O76\n\tRTS>\n"
 "IFE\tREALIO-6,<\t\t\t;VELCOURT: SAVE \"NAME\" AND LOAD \"NAME\".\n"
 "SAVE:\tJSR\tGETNAM\t\t\t;VELCOURT: NAME AT [INDEX], LENGTH IN [A].\n"
 "\tLDXY\tVARTAB\t\t\t;VELCOURT: THE PROGRAM ENDS AT [X,Y].\n"
 "\tJMP\tCQSAVE\t\t\t;VELCOURT: KERNEL WRITES [TXTTAB] TO [X,Y].\n"
 "LOAD:\tJSR\tGETNAM\t\t\t;VELCOURT:\n"
 "\tJSR\tCQLOAD\t\t\t;VELCOURT: KERNEL READS IT TO [TXTTAB],\n"
 "\tBCS\tLODERR\t\t\t;VELCOURT: CARRY SET IF NOTHING WAS LOADED.\n"
 "\tSTXY\tVARTAB\t\t\t;VELCOURT: THE END IT RETURNED.\n"
 "\tLDWDI\tLODMSG\t\t\t;VELCOURT:\n"
 "\tJSR\tSTROUT\t\t\t;VELCOURT:\n"
 "\tJSR\tRUNC\t\t\t;VELCOURT: CLEAR THE VARIABLES,\n"
 "\tJSR\tLNKPRG\t\t\t;VELCOURT: RELINK THE LINES,\n"
 "\tJMP\tREADY\t\t\t;VELCOURT: AND SAY OK.\n"
 "LODERR: JMP\tREADY\t\t\t;VELCOURT:\n"
 "GETNAM: JSR\tFRMEVL\t\t\t;VELCOURT: EVALUATE THE NAME,\n"
 "\tJMP\tFRESTR\t\t\t;VELCOURT: WHICH MUST BE A STRING.\n"
 "LODMSG: DT\"LOADED\"\t\t;VELCOURT:\n"
 "\tACRLF\t\t\t\t;VELCOURT:\n"
 "\t0>\t\t\t\t;VELCOURT:\n"),

# 6. no memory size typed: use all of the RAM, not the picture above it
("\tSTWD\tLINNUM\nIFE\tREALIO-3,<\n\tTAY>\n",
 "\tSTWD\tLINNUM\n"
 "IFE\tREALIO-6,<\t\t\t;VELCOURT: NOTHING TYPED, SO USE ALL OF\n"
 "\tLDWDI\t^O40000\t\t\t;VELCOURT: THE RAM, UP TO $4000 WHERE THE\n"
 "\tSTWD\tLINNUM\t\t\t;VELCOURT: PICTURE STARTS. PROBING WOULD\n"
 "\tBNE\tUSEDEC>\t\t\t;VELCOURT: RUN STRAIGHT INTO IT.\n"
 "IFE\tREALIO-3,<\n\tTAY>\n"),

# 7. the dispatch table must have one address per statement word. The
#    original adds two placeholders for any machine that is not 1, 3 or 4;
#    our machine already supplies LOAD and SAVE, so leave them out.
("IFN\tREALIO-4,<\n\tADR(511)\t\t;ADDRESS OF LOAD\n\tADR(511)>>>>\t\t;ADDRESS OF SAVE\n",
 "IFN\tREALIO-4,<\n"
 "IFN\tREALIO-6,<\t\t\t;VELCOURT: NOT FOR US.\n"
 "\tADR(511)\t\t;ADDRESS OF LOAD\n\tADR(511)>>>>>\t\t;ADDRESS OF SAVE\n"
 "IFE\tREALIO-6,<\t\t\t;VELCOURT: OUR NEW STATEMENTS.\n"
 "\tADR(CLS-1)\t\t\t;VELCOURT:\n"
 "\tADR(COLOR-1)\t\t\t;VELCOURT:\n"
 "\tADR(PLOT-1)\t\t\t;VELCOURT:\n"
 "\tADR(LINE-1)\t\t\t;VELCOURT:\n"
 "\tADR(SOUND-1)\t\t\t;VELCOURT:\n"
 "\tADR(PAUSE-1)>\t\t\t;VELCOURT:\n"),

# 8. ...and their names, in the same order, in the reserved word list
("IFE\tREALIO-3,<\n\tDCI\"VERIFY\">>\n\tDCI\"DEF\"\n",
 "IFE\tREALIO-3,<\n\tDCI\"VERIFY\">>\n"
 "IFE\tREALIO-6,<\t\t\t;VELCOURT:\n"
 "\tDCI\"CLS\"\t\t\t;VELCOURT: CLEAR THE SCREEN.\n"
 "\tDCI\"COLOR\"\t\t\t;VELCOURT: COLOR INK[,PAPER]\n"
 "\tDCI\"PLOT\"\t\t\t;VELCOURT: PLOT X,Y,C\n"
 "\tDCI\"LINE\"\t\t\t;VELCOURT: LINE X1,Y1,X2,Y2,C\n"
 "\tDCI\"SOUND\"\t\t\t;VELCOURT: SOUND VOICE,HZ,VOLUME\n"
 "\tDCI\"PAUSE\">\t\t\t;VELCOURT: PAUSE SIXTIETHS\n"
 "\tDCI\"DEF\"\n"),

# 9. the code for the new statements: read the numbers, call the kernel
("POKE:\tJSR\tGETNUM\n",
 "IFE\tREALIO-6,<\t\t\t;VELCOURT: GRAPHICS AND SOUND.\n"
 "GX0=^D640\t\t\t\t;VELCOURT: KERNEL PARAMETER BLOCK\n"
 "GY0=^D642\t\t\t\t;VELCOURT: AT $0280 (SEE KERNEL.S).\n"
 "GX1=^D643\t\t\t\t;VELCOURT:\n"
 "GY1=^D645\t\t\t\t;VELCOURT:\n"
 "GCOL=^D646\t\t\t\t;VELCOURT:\n"
 "SVOICE=^D647\t\t\t\t;VELCOURT:\n"
 "SFREQ=^D648\t\t\t\t;VELCOURT:\n"
 "SVOL=^D650\t\t\t\t;VELCOURT:\n"
 "PTICKS=^D651\t\t\t\t;VELCOURT:\n"
 "CFG=^D652\t\t\t\t;VELCOURT:\n"
 "CBG=^D653\t\t\t\t;VELCOURT:\n"
 "CLS:\tJMP\t^O177417\t\t;VELCOURT: KERNEL CLS    $FF0F\n"
 "COLOR:\tJSR\tGETBYT\t\t\t;VELCOURT: INK COLOUR.\n"
 "\tSTX\tCFG\t\t\t;VELCOURT:\n"
 "\tJSR\tCHRGOT\t\t\t;VELCOURT: PAPER TOO?\n"
 "\tBEQ\tCOLOR1\t\t\t;VELCOURT:\n"
 "\tJSR\tCOMBYT\t\t\t;VELCOURT:\n"
 "\tSTX\tCBG\t\t\t;VELCOURT:\n"
 "COLOR1: JMP\t^O177422\t\t;VELCOURT: KERNEL COLOR  $FF12\n"
 "PLOT:\tJSR\tGETXY\t\t\t;VELCOURT:\n"
 "\tJSR\tCOMBYT\t\t\t;VELCOURT:\n"
 "\tSTX\tGCOL\t\t\t;VELCOURT:\n"
 "\tJMP\t^O177425\t\t;VELCOURT: KERNEL PLOT   $FF15\n"
 "LINE:\tJSR\tGETXY\t\t\t;VELCOURT: FIRST END...\n"
 "\tLDA\tGX0\t\t\t;VELCOURT:\n"
 "\tSTA\tGX1\t\t\t;VELCOURT:\n"
 "\tLDA\tGX0+1\t\t\t;VELCOURT:\n"
 "\tSTA\tGX1+1\t\t\t;VELCOURT:\n"
 "\tLDA\tGY0\t\t\t;VELCOURT:\n"
 "\tSTA\tGY1\t\t\t;VELCOURT:\n"
 "\tJSR\tCHKCOM\t\t\t;VELCOURT:\n"
 "\tJSR\tGETXY\t\t\t;VELCOURT: ...AND THE OTHER.\n"
 "\tJSR\tCOMBYT\t\t\t;VELCOURT:\n"
 "\tSTX\tGCOL\t\t\t;VELCOURT:\n"
 "\tJMP\t^O177430\t\t;VELCOURT: KERNEL LINE   $FF18\n"
 "SOUND:\tJSR\tGETBYT\t\t\t;VELCOURT: VOICE 0-3.\n"
 "\tSTX\tSVOICE\t\t\t;VELCOURT:\n"
 "\tJSR\tCHKCOM\t\t\t;VELCOURT:\n"
 "\tJSR\tFRMNUM\t\t\t;VELCOURT: FREQUENCY IN HZ,\n"
 "\tJSR\tGETADR\t\t\t;VELCOURT: 0-65535.\n"
 "\tLDWD\tPOKER\t\t\t;VELCOURT:\n"
 "\tSTWD\tSFREQ\t\t\t;VELCOURT:\n"
 "\tJSR\tCOMBYT\t\t\t;VELCOURT: VOLUME 0-15.\n"
 "\tSTX\tSVOL\t\t\t;VELCOURT:\n"
 "\tJMP\t^O177433\t\t;VELCOURT: KERNEL SOUND  $FF1B\n"
 "PAUSE:\tJSR\tGETBYT\t\t\t;VELCOURT: SIXTIETHS OF A SECOND.\n"
 "\tSTX\tPTICKS\t\t\t;VELCOURT:\n"
 "\tJMP\t^O177436\t\t;VELCOURT: KERNEL PAUSE  $FF1E\n"
 "GETXY:\tJSR\tFRMNUM\t\t\t;VELCOURT: X, 0-319,\n"
 "\tJSR\tGETADR\t\t\t;VELCOURT:\n"
 "\tLDWD\tPOKER\t\t\t;VELCOURT:\n"
 "\tSTWD\tGX0\t\t\t;VELCOURT:\n"
 "\tJSR\tCOMBYT\t\t\t;VELCOURT: Y, 0-199.\n"
 "\tSTX\tGY0\t\t\t;VELCOURT:\n"
 "\tRTS>\t\t\t\t;VELCOURT:\n"
 "POKE:\tJSR\tGETNUM\n"),

# 10. the greeting
("IFE\tREALIO-5,<DT\"STM BASIC V1.1\">\n",
 "IFE\tREALIO-5,<DT\"STM BASIC V1.1\">\n"
 "IFE\tREALIO-6,<DT\"6502 BASIC V1.1\">\t;VELCOURT:\n"),
]

for old, new in EDITS:
    n = text.count(old)
    if n != 1:
        sys.exit("anchor found %d times (need 1):\n%s" % (n, old))
    text = text.replace(old, new)

open(dst, "w", encoding="latin-1").write(text)
print("wrote", dst)
