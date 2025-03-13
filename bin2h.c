/*
 * bin2h.c: ANSI C (C89) program to convert binary file to C .h header
 * by pts@fazekas.hu at Thu Mar 13 15:56:25 CET 2025
 */

#include <stdio.h>

int main(int argc, char **argv) {
  char line[67], *linep;
  FILE *fin, *fout;
  int c;
  (void)argc;
  if (!argv[0] || !argv[1] || !argv[2] || argv[3]) {
    fprintf(stderr, "Usage: %s <input.bin> <output.h>\n", argv[0]);
    return 1;
  }
  if (!(fin = fopen(argv[1], "rb"))) {
    fprintf(stderr, "fatal: error opening input .bin file: %s\n", argv[1]);
    return 2;
  }
  if (!(fout = fopen(argv[2], "wb"))) {
    fprintf(stderr, "fatal: error opening output .h file: %s\n", argv[2]);
    return 2;
  }
 next_line:
  linep = line; *linep++ = '"';
  while ((c = getc(fin)) >= 0) {
    *linep++ = '\\';
    *linep++ = '0' + ((unsigned char)c >> 6);
    *linep++ = '0' + ((c >> 3) & 7);
    *linep++ = '0' + (c & 7);
    if (linep == line + 65) {
      *linep++ = '"';
      *linep = '\n';
      if (fwrite(line, 1, 67, fout) != 67) goto error_writing;
      goto next_line;
    }
  }
  if (linep != line + 1) {
    *linep++ = '"';
    *linep++ = '\n';
    if ((int)fwrite(line, 1, linep - line, fout) != linep - line) goto error_writing;
  }
  if (ferror(fin)) {
    fprintf(stderr, "fatal: error reading input .bin file: %s\n", argv[1]);
    return 1;
  }
  if (fflush(fout) || ferror(fout)) { error_writing:
    fprintf(stderr, "fatal: error writing output .h file: %s\n", argv[2]);
    return 1;
  }
  /*fclose(fout);*/  /* Not needed, the operating system will close it at process exit. */
  /*fclose(fin;*/  /* Not needed, the operating system will close it at process exit. */
  return 0;
}
