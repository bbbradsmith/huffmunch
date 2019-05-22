# huffmunch
This is the future home of a practical generic compression library for the NES or other 6502 platforms.

This is currently under construction, not yet ready for use.


The performance of this compression method is measured here on the
 data used for the Dangerous Game example. The average decompression
 speed is fairly consistent, but there is a lot of variation in the
 time it takes to read each individual byte, as substrings that are
 either more common or longer will spend less time traversing the
 huffman tree structure that compresses the data.

| Method       | Average Speed    | Code Size | RAM Required  | Compressed Data Size |
| ------------ | ---------------- | --------- | ------------- | -------------------- |
| Uncompressed |   13 cycles/byte |   9 bytes |      0 bytes  | 45418 bytes (100.0%) |
| Standard     |  260 cycles/byte | 330 bytes |      9 bytes  | 21520 bytes (47.69%) |
| Canonical    | 1000 cycles/byte | 578 bytes |     26 bytes  | 20751 bytes (45.99%) |

The compressed size performance will also vary a lot depending on
 the type of data used. Plain text seems to regularly do better
 than 50%. Random data may reverse-compress to larger than 100%.
 Typically huffmunch does not do as well as the DEFLATE algorithm
 which inspired it, but does at least reach the same ballpark.

Compression of NES CHR graphics tiles is adequate, though I would
 recommend the [donut CHR compressor](https://github.com/jroatch/donut-nes)
 by (https://github.com/jroatch)[jroatch] as a more effective alternative
 for that specific purpose.

Another useful reference is bregalad's
 [Compress Tools](https://www.romhacking.net/utilities/882/)
 which demonstrate several NES-viable compression methods.
