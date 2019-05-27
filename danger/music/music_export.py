#!/usr/bin/env python3
import sys
assert sys.version_info[0] == 3, "Python 3 required."

# Lizard Music Engine
# Copyright Brad Smith 2019
# http://lizardnes.com

import os
import datetime

INPUT_DIR = "."
OUTPUT_DIR = "../output"
FAMITRACKER = "FamiTracker.exe"
MUSIC_SEGMENT = "DATA"

skip_text_export = False
#skip_text_export = True

now_string = datetime.datetime.now().strftime("%a %b %d %H:%M:%S %Y")

# text FTM reader
class FTM:
    # title - song title
    # speed - initial song speed
    # pattern_length - length of patterns in song
    # pattern[channel][pattern][row][data]
    # order[frame][channel]
    # macro[type][data]
    # instrument[inst][macro 0,1,2,3,4,name]

    def __init__(self):
        self.debug = False
        self.macro = [[],[],[],[],[]]
        self.instrument = []
        self.speed = 6
        self.pattern_length = 64
        self.pattern = []
        for i in range(0,5):
            empty_channel = []
            for j in range(0,128):
                empty_pattern = []
                for i in range(0,256):
                    empty_pattern.append(["...","..",".","..."])
                empty_channel.append(empty_pattern)
            self.pattern.append(empty_channel)
        self.order = []
        self.tracks = 0
        self.read_pattern = 0
        self.inst = [-1,-1,-1,-1,-1] * 64
        self.error = ""

    def load_txt(self,filename,track=1):
        f = open(filename,"rt")
        for line in f.readlines():
            token = line.split()
            if (len(token) < 1):
                continue
            elif (token[0] == "TITLE"):
                self.title = token[1].replace('"','')
            elif (token[0] == "MACRO"):
                mtype = int(token[1])
                index = int(token[2])
                loop = int(token[3])
                if (int(token[4]) != -1):
                    self.error += "Macro release unsupported (macro %d, %d).\n" % (mtype,index)
                if (int(token[5]) != 0):
                    self.error += "Only absolute macro mode supported (macro %d, %d).\n" % (mtype,index)
                while (len(self.macro[mtype]) <= index):
                    self.macro[mtype].append([0,-128,0])
                m = []
                for i in range(7,len(token)):
                    m.append(int(token[i]))
                if (mtype == 2) and (loop < 0):
                    m.append(0) # pitch needs to be halted with 0 before terminating loop
                m.append(-128)
                if (loop >= 0):
                    m.append(loop)
                else:
                    m.append(len(m)-2)
                self.macro[mtype][index] = m
                if self.debug:
                    print(("macro[%d][%d] " % (mtype,index))+"".join(str(i)+" " for i in self.macro[mtype][index]))
            elif (token[0] == "INST2A03"):
                index = int(token[1])
                while len(self.instrument) <= index:
                    self.instrument.append([-1,-1,-1,-1,-1])
                m = []
                for i in range(2,7):
                    m.append(int(token[i]))
                inst_name_start = line.find(token[7]) + 1
                inst_name_end = line.find('"',inst_name_start)
                m.append(line[inst_name_start:inst_name_end]) # name
                self.instrument[index] = m
                if self.debug:
                    print(("instrument[%d] " % index)+"".join(str(i)+" " for i in self.instrument[index]))               
            elif (token[0] == "TRACK"):
                self.tracks += 1
                if (self.tracks == track):
                    self.pattern_length = int(token[1])
                    self.speed = int(token[2])
                    if (int(token[3]) != 150):
                        self.error += "Only tempo 150 supported.\n"
                if self.debug:
                    print("Track: %d, %d" % (self.pattern_length, self.speed))
            elif (token[0] == "ORDER"):
                if (self.tracks != track):
                    continue
                frame = int(token[1],16)
                while len(self.order) <= frame:
                    self.order.append([0,0,0,0,0])
                m = []
                for i in range(3,8):
                    m.append(int(token[i],16))
                self.order[frame] = m
                if (self.debug):
                    print(("Order: %X : "%frame)+"".join(str(i)+" " for i in self.order[frame]))
            elif (token[0] == "PATTERN"):
                if (self.tracks != track):
                    continue
                self.read_pattern = int(token[1],16)
                if self.debug:
                    print("read pattern: %X" % self.read_pattern)
            elif (token[0] == "ROW"):
                if (self.tracks != track):
                    continue
                row = int(token[1],16)
                channel = 0
                m = []
                for i in range(3,len(token)):
                    if (token[i] == ':'):
                        self.pattern[channel][self.read_pattern][row] = m
                        channel += 1
                        m = []
                    else:
                        m.append(token[i])
                self.pattern[channel][self.read_pattern][row] = m
                if self.debug:
                    s = ""
                    s += " : "+"".join(x+" " for x in self.pattern[0][self.read_pattern][row])
                    s += " : "+"".join(x+" " for x in self.pattern[1][self.read_pattern][row])
                    s += " : "+"".join(x+" " for x in self.pattern[2][self.read_pattern][row])
                    s += " : "+"".join(x+" " for x in self.pattern[3][self.read_pattern][row])
                    s += " : "+"".join(x+" " for x in self.pattern[4][self.read_pattern][row])
                    print(("row %d: "%row)+s)
        return len(self.error) == 0

# constant values for packing

NOTE_HALT = 0x80

EFF_VOL = 0xE0
EFF_INS = 0xF0
EFF_BXX = 0xF1
EFF_D00 = 0xF2
EFF_FXX = 0xF3
EFF_GXX = 0xF4
EFF_PXX = 0xF5
EFF_3XX = 0xF6

SFX_VOL = 0xE0
SFX_DUT = 0xF0

PATTERN_DICT = {
    NOTE_HALT :"HALT",
    EFF_BXX   :"B_XX",
    EFF_D00   :"D_00",
    EFF_FXX   :"F_XX",
    EFF_GXX   :"G_XX",
    EFF_PXX   :"P_XX",
    EFF_3XX   :"E_XX",
    EFF_INS   :"INST",
    EFF_VOL+0 :"VOL0",
    EFF_VOL+1 :"VOL1",
    EFF_VOL+2 :"VOL2",
    EFF_VOL+3 :"VOL3",
    EFF_VOL+4 :"VOL4",
    EFF_VOL+5 :"VOL5",
    EFF_VOL+6 :"VOL6",
    EFF_VOL+7 :"VOL7",
    EFF_VOL+8 :"VOL8",
    EFF_VOL+9 :"VOL9",
    EFF_VOL+10:"VOLA",
    EFF_VOL+11:"VOLB",
    EFF_VOL+12:"VOLC",
    EFF_VOL+13:"VOLD",
    EFF_VOL+14:"VOLE",
    EFF_VOL+15:"VOLF"
}

SFX_DICT = {
    NOTE_HALT :"SHLT",
    SFX_VOL+ 0:"SVL0",
    SFX_VOL+ 1:"SVL1",
    SFX_VOL+ 2:"SVL2",
    SFX_VOL+ 3:"SVL3",
    SFX_VOL+ 4:"SVL4",
    SFX_VOL+ 5:"SVL5",
    SFX_VOL+ 6:"SVL6",
    SFX_VOL+ 7:"SVL7",
    SFX_VOL+ 8:"SVL8",
    SFX_VOL+ 9:"SVL9",
    SFX_VOL+10:"SVLA",
    SFX_VOL+11:"SVLB",
    SFX_VOL+12:"SVLC",
    SFX_VOL+13:"SVLD",
    SFX_VOL+14:"SVLE",
    SFX_VOL+15:"SVLF",
    SFX_DUT+ 0:"SDT0",
    SFX_DUT+ 1:"SDT1",
    SFX_DUT+ 2:"SDT2",
    SFX_DUT+ 3:"SDT3"
}

NOTE_NAME = {
    "C-":0,
    "C#":1,
    "D-":2,
    "D#":3,
    "E-":4,
    "F-":5,
    "F#":6,
    "G-":7,
    "G#":8,
    "A-":9,
    "A#":10,
    "B-":11
}
NOISE_NAME = {
    "F-":15,
    "E-":14,
    "D-":13,
    "C-":12,
    "B-":11,
    "A-":10,
    "9-":9,
    "8-":8,
    "7-":7,
    "6-":6,
    "5-":5,
    "4-":4,
    "3-":3,
    "2-":2,
    "1-":1,
    "0-":0
}
MACRO_TYPE_NAMES = [
    "volume",
    "arpeggio",
    "pitch",
    "hi-pitch",
    "duty",
    "default"
]

# global packing

all_titles = []
all_macros = []
all_instruments = []

all_speeds = []
all_pattern_lengths = []
all_orders = []
all_patterns = []

all_sfx = []
all_sfx_titles = []
all_sfx_modes = []

macro_type = []
macro_src_ftm = []
macro_src_idx = []
macro_rle_stat = 0
instrument_src_ftm = []
instrument_name = []

all_macros.append([0,-128,0])  # any macro -1 except volume
macro_type.append(5)
macro_src_ftm.append("DEFAULT 0")
macro_src_idx.append(0)

all_macros.append([15,-128,0]) # volume macro -1
macro_type.append(5)
macro_src_ftm.append("DEFAULT 15")
macro_src_idx.append(1)

all_sfx.append([NOTE_HALT]) # SFX 0 halts immediately
all_sfx_titles.append("NONE") # SFX 0 is none
all_sfx_modes.append(0) # SFX 0 is square mode

def pack_macro(m):
    for i in range(0,len(all_macros)):
        if (m == all_macros[i]):
            return i
    all_macros.append(m)
    # count bytes that could be saved by macro RLE
    global macro_rle_stat
    rle_count = 0
    rle_last = -1
    for e in m:
        if e == rle_last:
            rle_count += 1
            if rle_count > 1:
                macro_rle_stat += 1
        else:
            rle_count = 0
            rle_last = e
    # return index
    return len(all_macros) - 1

def pack_instrument(m):
    for i in range(0,len(all_instruments)):
        if (m == all_instruments[i]):
            return i
    all_instruments.append(m)
    return len(all_instruments) - 1

def pack_ftm(ftm):
    # errors
    error = ""
    loop_set = False
    # pack global macros and map them to this FTM
    macro_map = [[],[],[],[],[]]
    for t in range(0,5):
        for i in range(0,len(ftm.macro[t])):
            mapping = pack_macro(ftm.macro[t][i])
            macro_map[t].append(mapping)
            if mapping == (len(all_macros) - 1):
                macro_type.append(t)
                macro_src_ftm.append(ftm.title)
                macro_src_idx.append(i)
    # pack global instruments and map them to this FTM
    instrument_map = []
    for i in range(0,len(ftm.instrument)):
        m = list(ftm.instrument[i]) # copy the instrument
        for t in range(0,5):
            if m[t] == -1 or m[t] >= len(macro_map[t]):
                if t == 0:
                    m[t] = 1 # volume macro -1
                else:
                    m[t] = 0 # generic 0 macro
            else:
                m[t] = macro_map[t][m[t]]
                if (t == 3):
                    error += "Hi-pitch unsupported in instrument: %d" % i
        mapping = pack_instrument(m[0:5]) # strip name from instrument for packing
        instrument_map.append(mapping)
        if mapping == (len(all_instruments) - 1):
            instrument_src_ftm.append(ftm.title)
            instrument_name.append(m[5])
    # find max used patterns
    max_order = [0,0,0,0] # note: no DPCM
    for p in range(0,len(ftm.order)):
        for c in range(0,len(max_order)):
            o = ftm.order[p][c]
            if o > max_order[c]:
                max_order[c] = o
    # pack patterns
    packed_patterns = []
    pattern_map = [[],[],[],[]] # note: no DPCM
    for p in range(0,max_order[c]+1):
        for c in range(0,4):
            pat = ftm.pattern[c][p]
            packed_pattern = []
            skip = 0
            last_inst = -1
            last_vol = -1
            for r in range(0,ftm.pattern_length):
                row = pat[r]
                m = []
                note_on_row = False
                for i in range(3,len(row)):
                    eff = row[i]
                    e = eff[0]
                    if e == ".":
                        pass
                    elif e == 'B':
                        m.append(EFF_BXX)
                        m.append(int(eff[1:3],16))
                        if loop_set:
                            error += "Multiple BXX effects found in channel, pattern, row: %d, %d, %d\n" % (c,p,r)
                        loop_set = True
                    elif e == 'D':
                        m.append(EFF_D00)
                        if (int(eff[1:3],16) != 0):
                            error += "DXX parameter must be 00 in channel, pattern, row: %d, %d, %d\n" % (c,p,r)
                    elif e == 'F':
                        m.append(EFF_FXX)
                        m.append(int(eff[1:3],16))
                    #elif e == 'G':
                    #    m.append(EFF_GXX)
                    #    m.append(int(eff[1:3],16))
                    #elif e == 'P':
                    #    m.append(EFF_PXX)
                    #    m.append(int(eff[1:3],16))
                    #elif e == '3':
                    #    m.append(EFF_3XX)
                    #    m.append(int(eff[1:3],16))
                    else:
                        error += "Unknown effect in channel, pattern, row: %d, %d, %d\n" % (c,p,r)
                if row[2] != '.':
                    v = int(row[2],16)
                    if (v != last_vol): # eliminate unnecessary volumes
                        last_vol = v
                        m.append(EFF_VOL + v)
                if row[1] != '..':
                    v = int(row[1],16)
                    if (v != last_inst): # eliminate unnecessary instruments
                        last_inst = v
                        m.append(EFF_INS)
                        m.append(instrument_map[v])
                if row[0] != '...':
                    note_on_row = True
                    if row[0] == "---":
                        m.append(NOTE_HALT)
                    elif c == 3:
                        n = NOISE_NAME[row[0][0:2]]
                        m.append(NOTE_HALT+1+n)
                    else:
                        n = NOTE_NAME[row[0][0:2]]
                        octave = int(row[0][2:3])
                        m.append(NOTE_HALT+1+n+(octave*12))
                # row is processed
                if (len(m) < 1):
                    skip += 1
                else:
                    if (skip > 0):
                        if (skip >= 0x80):
                            error += "Too many skipped rows in channel, pattern, row: %d, %d, %d\n" % (c,p,r)
                        packed_pattern.append(skip-1)
                        skip = 0
                    packed_pattern.extend(m)
                    if not note_on_row:
                        skip = 1
            if skip > 0:
                if (skip >= 0x80):
                    error += "Too many skipped rows at end of channel, pattern: %d, %d\n" % (c,p)
                packed_pattern.append(skip)
            duplicate_pattern = -1
            for i in range(0,len(packed_patterns)):
                if (packed_pattern == packed_patterns[i]):
                    duplicate_pattern = i
                    break
            if (duplicate_pattern < 0):
                packed_patterns.append(packed_pattern)
                pattern_map[c].append(len(packed_patterns)-1)
            else:
                pattern_map[c].append(duplicate_pattern)
    # pack order
    packed_order = []
    for o in range(0,len(ftm.order)):
        m = []
        for c in range(0,4): # note: no DPCM
            p = ftm.order[o][c]
            m.append(pattern_map[c][p])
        packed_order.append(m)
    # finished
    if not loop_set:
        error += "No loop point found. Use BXX effect.\n"
    return (packed_order,packed_patterns,error)

def pack_sfx(ftm):
    # errors
    error = ""
    # pack pattern
    if ftm.speed != 1:
        error += "FTM speed is not 1. SFX assumes speed 1.\n"
    pat_square = ftm.pattern[0][0]
    pat_noise  = ftm.pattern[3][0]
    pat = None
    mode = 0
    if pat_square[0][0] != "...":
        pat = pat_square
        mode = 0
    elif pat_noise[0][0] != "...":
        pat = pat_noise
        mode = 1
    if (pat == None):
        error += "Note not found on pattern 0 row 0 of square 1 or noise.\n"
        return ([NOTE_HALT],mode,error)
    sfx = []
    halted = False
    skip = 0
    last_vol = -1
    for r in range(0,ftm.pattern_length):
        row = pat[r]
        m = []
        note_on_row = False
        for i in range(3,len(row)):
            eff = row[i]
            e = eff[0]
            if e == ".":
                pass
            elif e == "V":
                v = int(eff[1:3],16)
                if mode == 1:
                    v &= 1
                else:
                    v &= 3
                m.append(SFX_DUT + v)
            else:
                error += "Unknown effect on row: %d\n" % (r)
        if row[2] != '.':
            v = int(row[2],16)
            if (v != last_vol): # eliminate unnecessary volumes
                last_vol = v
                m.append(SFX_VOL + v)
        if row[0] != "...":
            note_on_row = True
            if row[0] == "---":
                halted = True
            elif mode == 0: # square
                n = NOTE_NAME[row[0][0:2]]
                octave = int(row[0][2:3])
                m.append(NOTE_HALT+1+n+(octave*12))
            else: # noise
                n = NOISE_NAME[row[0][0:2]]
                m.append(NOTE_HALT+1+n)
        # row is processed, handle skips
        if (len(m) < 1):
            skip += 1
        else:
            if (skip > 0):
                if (skip >= 0x80):
                    error += "Too many skipped rows at row: %d\n" % (r)
                sfx.append(skip-1)
                skip = 0
            sfx.extend(m)
            if not note_on_row:
                skip = 1
        if halted:
            break
    if not halted:
        error += "No note halt found."
    sfx.append(NOTE_HALT)
    return (sfx,mode,error)

# generate data set

def generate_asm():
    s = "; automatically generated by music_export.py\n"
    s += "; " + now_string + "\n"
    s += "\n"
    s += "MUSIC_COUNT = %d\n" % (len(all_orders))
    s += "SFX_COUNT = %d\n" % (len(all_sfx))
    s += "MACRO_COUNT = %d\n" % (len(all_macros))
    s += "INSTRUMENT_COUNT = %d\n" % (len(all_instruments))
    s += "\n"
    s += "LOOP = -128\n"
    for k in PATTERN_DICT.keys():
        s += ""+PATTERN_DICT[k]+(" = $%02X\n" % k)
    for k in SFX_DICT.keys():
        s += ""+SFX_DICT[k]+(" = $%02X\n" % k)
    s += "\n"
    s += ".segment \"" + MUSIC_SEGMENT + "\"\n"
    s += "\n"
    # macros
    for i in range(0,len(all_macros)):
        s += "data_macro_%02X: ; %s %s %d\n" % (
            i,
            macro_src_ftm[i],
            MACRO_TYPE_NAMES[macro_type[i]],
            macro_src_idx[i])
        s += ".byte "
        for b in all_macros[i]:
            if (b == -128):
                s += "LOOP,"
            else:
                s += "%d," % b
        s += "\n"
    s += "\n"
    s += "data_music_macro_low:\n"
    for i in range(0,len(all_macros)):
        s += ".byte <data_macro_%02X\n" % i
    s += "\n"
    s += "data_music_macro_high:\n"
    for i in range(0,len(all_macros)):
        s += ".byte >data_macro_%02X\n" % i
    s += "\n"
    # instruments
    s += "data_music_instrument:\n"
    for i in range(0,len(all_instruments)):
        inst = all_instruments[i]
        s += ".byte $%02X, $%02X, $%02X, $%02X ; %02X %s: %s\n" % \
            (inst[0], inst[1], inst[2], inst[4], i, instrument_src_ftm[i], instrument_name[i]) # note: skipping hi-pitch
    s += "\n"
    # speeds
    s += "data_music_speed:\n"
    s += ".byte "
    for i in range(0,len(all_speeds)):
        s += "%d," % all_speeds[i]
    s += "\n"
    s += "\n"
    # pattern lengths
    s += "data_music_pattern_length:\n"
    s += ".byte "
    for i in range(0,len(all_pattern_lengths)):
        s += "%d," % all_pattern_lengths[i]
    s += "\n"
    s += "\n"
    # order data
    for i in range(0,len(all_orders)):
        o = all_orders[i]
        s += "data_order_%02X: ; %s\n" % (i,all_titles[i])
        for j in range(0,len(o)):
            oo = o[j]
            s += ".byte $%02X, $%02X, $%02X, $%02X ; %02X\n" % \
                (oo[0],oo[1],oo[2],oo[3],j)
        s += "\n"
    s += "data_music_order_low:\n"
    for i in range(0,len(all_orders)):
        s += ".byte <data_order_%02X,\n" % i
    s += "\n"
    s += "data_music_order_high:\n"
    for i in range(0,len(all_orders)):
        s += ".byte >data_order_%02X,\n" % i
    s += "\n"
    # pattern data
    for i in range(0,len(all_patterns)):
        p = all_patterns[i]
        s += "; patterns: %s\n" % (all_titles[i])
        s += "\n"
        for j in range(0,len(p)):
            s += "data_music_pattern_%02X_%02X:\n" % (i,j)
            s += ".byte "
            count16 = 0
            for b in p[j]:
                if (count16 >= 16):
                    count16 = 0
                    s += "\n.byte "
                if b in PATTERN_DICT:
                    s += PATTERN_DICT[b] + ","
                else:
                    s += " $%02X," % b
                count16 += 1
            s += "\n"
            s += "\n"
        s += "data_music_pattern_%02X:\n" % (i)
        for j in range(0,len(p)):
            s += ".word data_music_pattern_%02X_%02X,\n" % (i,j)
        s += "\n"
    s += "data_music_pattern:\n"
    for i in range(0,len(all_patterns)):
        s += ".word data_music_pattern_%02X,\n" % i
    s += "\n"
    # sfx data
    for i in range(0,len(all_sfx)):
        sfx = all_sfx[i]
        s += "data_sfx_%02X: ; %s\n" % (i,all_sfx_titles[i])
        s += ".byte "
        count16 = 0
        for b in sfx:
            if (count16 >= 16):
                count16 = 0
                s += "\n.byte "
            if b in SFX_DICT:
                s += SFX_DICT[b] + ","
            else:
                s += " $%02X," % b
            count16 += 1
        s += "\n"
        s += "\n"
    s += "data_sfx_low:\n"
    for i in range(0,len(all_sfx)):
        s += ".byte <data_sfx_%02X,\n" % i
    s += "\n"
    s += "data_sfx_high:\n"
    for i in range(0,len(all_sfx)):
        s += ".byte >data_sfx_%02X,\n" % i
    s += "\n"
    s += "\n"
    # tuning table
    s += ".segment \"DATA\"\n"
    s += "\n"
    s += "data_music_tuning_low:\n"
    s += ".byte "
    count12 = 0
    tuning_note = 9+(3*12) # A-3 = A440
    tuning_freq = 440.0
    for i in range(0,96):
        if (count12 >= 12):
            count12 = 0
            s += "\n.byte "
        freq = tuning_freq * pow(2.0, float(i-tuning_note)/12.0)
        period = int((1789772.0 / (16.0 * freq)) - 0.5)
        if period > 0x7FF:
            period = 0x7FF
        s += "$%02X," % (period & 0xFF)
        count12 += 1
    s += "\n"
    s += "\n"
    s += "data_music_tuning_high:\n"
    s += ".byte "
    count12 = 0
    for i in range(0,96):
        if (count12 >= 12):
            count12 = 0
            s += "\n.byte "
        freq = tuning_freq * pow(2.0, float(i-tuning_note)/12.0)
        period = int((1789772.0 / (16.0 * freq)) - 0.5)
        if period > 0x7FF:
            period = 0x7FF
        s += "$%02X," % (period >> 8)
        count12 += 1
    s += "\n"
    s += "\n"
    # multiply table
    s += "data_music_multiply:\n"
    for a in range(0,16):
        s += ".byte "
        for b in range(0,16):
            m = (a * b) // 15
            if a>0 and b>0 and m<1:
                m = 1
            s += "$%X," % m
        s += "\n"
    s += "\n"
    # done
    s += "; end of file\n"
    # eliminate trailing commas
    s = s.replace(",\n","\n")
    return s

def generate_asm_enums():
    s = "; automatically generated by music_export.py\n"
    s += "; " + now_string + "\n"
    s += "\n"
    s += "MUSIC_COUNT = %d\n" % (len(all_titles))
    s += "SFX_COUNT = %d\n" % (len(all_sfx))
    s += "\n"
    s += ".enum\n"
    for i in range(0,len(all_titles)):
        s += "MUSIC_%s = %d\n" % (all_titles[i],i)
    s += ".endenum\n"
    s += "\n"
    s += ".enum\n"
    for i in range(0,len(all_sfx_titles)):
        s += "SOUND_%s = %d\n" % (all_sfx_titles[i],i)
    s += ".endenum\n"
    s += "\n"
    for i in range(0,len(all_sfx_modes)):
        s += "SOUND_MODE__%d = %d\n" % (i,all_sfx_modes[i])
    s += "\n"
    # done
    s += "; end of file\n"
    # eliminate trailing commas
    s = s.replace(",\n","\n")
    return s

def generate_stats():
    size_macros = len(all_macros)*2 # pointers
    for m in all_macros:
        size_macros += len(m)
    size_instruments = len(all_instruments)*4
    size_orders = len(all_orders)*2 # pointers
    for o in all_orders:
        size_orders += len(o) * 4
    size_patterns = len(all_patterns)*2 # pointers
    for p in all_patterns:
        size_patterns += len(p)*2 # pointers
        for pp in p:
            size_patterns += len(pp) # data
    size_sfx = len(all_sfx)*3 # pointers + mode
    for sfx in all_sfx:
        size_sfx += len(sfx)
    size_misc = len(all_speeds)+len(all_pattern_lengths)
    s = "Macro count: %d\n" % len(all_macros)
    s += "Instrument count: %d\n" % len(all_instruments)
    s += "\n"
    s += "Macro size:      %5d bytes\n" % size_macros
    s += "Instrument size: %5d bytes\n" % size_instruments
    s += "Order size:      %5d bytes\n" % size_orders
    s += "Pattern size:    %5d bytes\n" % size_patterns
    s += "SFX size:        %5d bytes\n" % size_sfx
    s += "Misc:            %5d bytes\n" % size_misc
    s += "TOTAL:           %5d bytes\n" % (size_macros+size_instruments+size_orders+size_patterns+size_misc+size_sfx)
    s += "\n"
    for t in range(0,5):
        size = 0
        count = 0
        for m in range(len(all_macros)):
            if (macro_type[m]) != t:
                continue
            size += len(all_macros[m]) + 2
            count += 1
        s += "Macro type %d:    %5d bytes in %3d macros (%s)\n" % (t,size,count,MACRO_TYPE_NAMES[t])
    s += "\n"
    # Hypothetical if macros were RLE compressed, requiring extra code and 16 bytes of RAM:
    #s += "Macro RLE savings: %d bytes\n" % macro_rle_stat
    #s += "n"
    for i in range(0,len(all_patterns)):
        p = all_patterns[i]
        sp = 2 + len(p)*2 # pattern table and pointer
        for pp in p:
            sp += len(pp) # pattern data
        sp += 2 + len(all_orders[i])*4 # order table and pointer
        sp += 2 # misc
        s += "Song %2d:         %5d bytes in %3d patterns (%s)\n" % (i,sp,len(p),all_titles[i])
    s += "\n"
    for i in range(0,len(all_sfx)):
        sfx = all_sfx[i]
        s += "SFX %2d:          %5d bytes (%s)\n" % (i,3+len(sfx),all_sfx_titles[i])
    return s

# do it all

error_log = ""

for i in range(0,100):
    ftm_file = os.path.join(INPUT_DIR,"music_%02d.ftm" % i)
    txt_file = os.path.join(OUTPUT_DIR,"music_%02d.txt" % i)
    log_file = os.path.join(OUTPUT_DIR,"music_%02d_log.txt" % i)
    if not (os.path.exists(ftm_file)):
        break
    print ("Processing: "+ftm_file)
    if not skip_text_export:
        if (not os.path.exists(txt_file)) or (os.path.getmtime(txt_file) < os.path.getmtime(ftm_file)):
            print ("Exported to text.")
            os.system(FAMITRACKER + " "+ftm_file+" -export "+txt_file+" "+log_file)
    ftm = FTM()
    if not ftm.load_txt(txt_file):
        error_log += "Load errors for: "+txt_file+"\n"
        error_log += ftm.error_log
    (po, pp, e) = pack_ftm(ftm)
    if (len(e) > 0):
        error_log += "Packing errors for: "+txt_file+"\n"
        error_log += e
    all_titles.append(ftm.title.upper())
    all_speeds.append(ftm.speed)
    all_pattern_lengths.append(ftm.pattern_length)
    all_orders.append(po)
    all_patterns.append(pp)

for i in range(1,100):
    ftm_file = os.path.join(INPUT_DIR,"sfx_%02d.ftm" % i)
    txt_file = os.path.join(OUTPUT_DIR,"sfx_%02d.txt" % i)
    log_file = os.path.join(OUTPUT_DIR,"sfx_%02d_log.txt" % i)
    if not os.path.exists(ftm_file):
        break
    print ("Processing: "+ftm_file)
    if not skip_text_export:
        if (not os.path.exists(txt_file)) or (os.path.getmtime(txt_file) < os.path.getmtime(ftm_file)):
            print ("Exported to text.")
            os.system(FAMITRACKER+" "+ftm_file+" -export "+txt_file+" "+log_file)
    ftm = FTM()
    if not ftm.load_txt(txt_file):
        error_log += "Load errors for: "+txt_file+"\n"
        error_log += ftm.error_log
    (sfx, mode, e) = pack_sfx(ftm)
    if (len(e) > 0):
        error_log += "Packing errors for: "+txt_file+"\n"
        error_log += e
    all_sfx.append(sfx)
    all_sfx_titles.append(ftm.title.upper())
    all_sfx_modes.append(mode)

f = open(os.path.join(OUTPUT_DIR,"data_music.inc"), "wt")
f.write(generate_asm())
f.close()

f = open(os.path.join(OUTPUT_DIR,"data_music_enums.inc"), "wt")
f.write(generate_asm_enums())
f.close()

f = open(os.path.join(OUTPUT_DIR,"music_stats.txt"), "wt")
s = generate_stats()
if len(error_log) > 0:
    s += "\n\nReported errors:\n"
    s += error_log
f.write(s)
f.close()

print(error_log)
print("Done.")

# end of file
