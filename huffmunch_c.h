#ifndef HUFFMUNCH_C_H
#define HUFFMUNCH_C_H

// Call huffmunch_init to set the data pointer before using huffmunch_load
// Recommend defining EXTERN_ZPBLOCK when building huffmunch_c.s for better performance. See huffmunch_c.s for details.

extern unsigned int fastcall huffmunch_init(void* data); // sets data pointer, returns number of blocks in data
extern unsigned int fastcall huffmunch_load(unsigned int index); // begins loading a block, returns length of block
extern unsigned char fastcall huffmunch_read(void); // returns the next byte in the block

#endif
