import os

OUTDIR = "output\\"
BANKCOUNT = 1
BANKSIZE = 32768
W = 28
H = 25

def centre(s):
    global W
    w = len(s)
    return (" " * ((W-len(s))//2)) + s

title_text = [
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    centre("The Most Dangerous Game"),
    "",
    centre("by Richard Connell"),
    "",
    centre("1924"),
    "",
    "",
    "",
    "",
    "",
    "",
    centre("NES Edition"),
    centre("Brad Smith"),
    centre("2019")]
TT = (H-len(title_text))//2
TB = H-(TT+len(title_text))
title = ([""]*TT) + title_text + ([""]*TB)

appendix = [
    #---------------------------
    "`Un bel di vedremo'",
    "from `Madama Butterfly'",
    "Giacomo Puccini, 1904.",
    "Arranged for NES by",
    "Brad Smith, 2019.",
    "",
    "",
    "",
    "This was a demonstration of",
    "the huffmunch compression",
    "tool for NES, written by",
    "Brad Smith, 2019.",
    "",
    "For more information,",
    "please visit:",
    "",
    " https://github.com/",
    "  bbbradsmith/huffmunch",
    "",
    ]

paragraphs = []
for line in open("danger.txt","rt").readlines()[3:]:
    l = line.rstrip();
    if l == "":
        paragraphs.append([])
    else:
        for word in l.split():
            paragraphs[len(paragraphs)-1].append(word)

pages = [""]
page_line = 0
def add_line(s):
    global pages
    global page_line
    pages[len(pages)-1] += s + "\n"
    page_line += 1
    if (page_line >= H):
        pages.append("")
        page_line = 0

for l in title:
    add_line(l)

for p in paragraphs:
    s = "   "
    for word in p:
        if len(s) > 0:
            ts = s + " " + word
            if len(ts) <= W:
                s = ts
            else:
                add_line(s)
                s = word
    if len(s) > 0:
        add_line(s)
for i in range(page_line,H): # finish last page
    pages[len(pages)-1] += "\n"

pages.append("") # appendix page
assert(len(appendix) <= H)
for i in range(0,H):
    l = ""
    if i >= (H - len(appendix)):
        l = appendix[i - (H - len(appendix))]
    pages[len(pages)-1] += l + "\n"

s = "%d %d\n" % (BANKCOUNT, BANKSIZE)
b = bytearray()
for p in pages:
    bs = len(b)
    for c in p:
        if c == "\n":
            c = 0
        elif c == "ê":
            c = ord('e') # de-ornament crêpes suzette
        elif c == "¶":
            c = ord(' ') # hide a paragraph break
        else:
            c = ord(c)
        b.append(c)
    be = len(b)
    s += "%d %d %sdanger.bin\n" % (bs,be,OUTDIR)

try:
    os.mkdir(OUTDIR)
except FileExistsError:
    pass
    
open(OUTDIR+"danger.bin","wb").write(b)
open(OUTDIR+"danger.lst","wt").write(s)
