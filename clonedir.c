// clonedir - clone a directory tree with one atomic APFS clonefile(2) syscall.
// Copy-on-write: instant, zero disk cost until files diverge.
//
//   usage: clonedir <src> <dst>
//
// dst must not exist; dst's parent must exist; src and dst must be on the
// same APFS volume.

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/clonefile.h>

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: clonedir <src> <dst>\n");
        return 2;
    }
    if (clonefile(argv[1], argv[2], 0) != 0) {
        fprintf(stderr, "clonedir: %s -> %s: %s\n", argv[1], argv[2], strerror(errno));
        return 1;
    }
    return 0;
}
