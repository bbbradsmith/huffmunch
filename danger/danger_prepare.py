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

TT = (H-5)//2
TB = H-(TT+5)
title = ([""]*TT) + [
    centre("The Most Dangerous Game"),
    "",
    centre("by Richard Connell"),
    "",
    centre("(1893-1949)")] + \
    ([""]*TB)

paragraphs = []
for line in title + open("danger.txt","rt").readlines()[3:-1]:
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

s = "%d %d\n" % (BANKCOUNT, BANKSIZE)
b = bytearray()
for p in pages:
    bs = len(b)
    for c in p:
        if c == "\n":
            c = 0
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
