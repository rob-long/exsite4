/* 
-------------------------------------------------------------------------
crypt_tea

This is a 64-bit safe version of TEA encryption.
We program in C because Perl does not give us adequate control over
word sizes, and may fail on 64-bit architectures.

Two ciphers are supported: XTEA and XXTEA. XTEA is an improved version 
of the original TEA algorithm that ciphers 64-bit blocks; XXTEA is a 
improved variation that ciphers variable-sized blocks.

Usage:

Using command line parameters:
    crypt_tea [-d] [-n number_of_rounds] [-k keystring] [text]

You can also pass the text in via stdin:
    echo $text | crypt_tea -k keystring
Or, the keystring and text can be concatenated and passed in stdin:
    echo $key$text | crypt_tea
    echo $key$text | crypt_tea -d

-d decrypts the text;  otherwise it is encrypted.

Number_of_rounds is used only by XTEA; it defaults to 64.

The encryption key can be passed directly as a command line parameter
(using -k), but this has some disadvantages.  Firstly, the key is visible 
in process data, and second, the keyspace is limited by your typeable
character set.

If -k is not used, the program will use the first 128 bits (16 bytes) read
from stdin.  This keeps the key hidden from the process table, and also 
gives you a full binary keyspace to work with.  However, you have to make
sure you pass a full 128-bit key.  If using the ExSite::Crypt Perl module, 
this is managed for you automatically.

The text can be read from the final command line parameter, or it will
be read from stdin (after the first 128 key bits, if necessary).

-------------------------------------------------------------------------
Copyright 2007 Exware Solutions, Inc.  http://www.exware.com

This file is part of ExSite WebWare (ExSite, for short), although it
works as a stand-alone utility.

ExSite is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

ExSite is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with ExSite; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

Users requiring warranty coverage and/or support may arrange alternate
commercial licensing for ExSite, by contacting Exware Solutions 
via the website noted above.
-------------------------------------------------------------------------
*/

#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>

#define DELTA 0x9E3779B9
#define NROUND 64
#define INPUT_SIZE 8192

/* 

Two cipher algorithms available: XTEA and XXTEA
Use XTEA for compatibility with exsite v3 encryption; 
XXTEA is a newer algorithm with improvements/corrections.

*/

#define XXTEA

/* 

The key and the number of rounds are settable from the command line.
Number of rounds is ignored by XXTEA.

*/

unsigned int nround=NROUND, key[4] = { 0,0,0,0 };

/*

C strings are inadequate for our purposes, since we need to hold
binary data that may include null characters.  The binstring struct
includes the string length.

*/

struct binstring {
  unsigned char *s;
  unsigned int l;
};
typedef struct binstring BinStr;

/* 

This is our base-64 character set;  it's a little different from the
standard MIME set, because MIME has a few characters that are not
safe in URLs (/ and +).  We replace those with - and _.

*/

static unsigned char chartab[65] = 
  "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  "abcdefghijklmnopqrstuvwxyz"
  "0123456789-_" ;

/*

Base-64 encoding and decoding.
Note that we use a slightly different Base-64 character set (chartab)
than MIME, to ensure that we have URL-safe characters in our encoded output.

*/

unsigned char *encode_base64 ( BinStr in ) {
  int c, curr, res=0, opos=0, bpos=0, i;
  unsigned char *out = (unsigned char *) malloc( in.l * 4 / 3 + 4 );
  for (i=0; i < in.l; i++) {
    c = in.s[i];
    switch ( bpos ) {
    case 0: 
    case 8:
      curr = res | c;
      res = c >> 6;
      bpos = 6;
      break;
    case 4:
      curr = res | (c << 4);
      res = c >> 2;
      out[opos] = chartab[curr & 0x3f];
      opos++;
      curr = res;
      res = 0;
      bpos = 0;
      break ;
    case 6:
      curr = res | (c << 2);
      res = c >> 4;
      bpos = 4;
      break ;
    }
    out[opos] = chartab[curr & 0x3f];
    opos++;
  }
  if (bpos) {
    out[opos] = chartab[res & 0x3f];
    opos++;
  }
  out[opos] = '\0';
  return out;
}

BinStr decode_base64 ( unsigned char *s ) {
  int c, curr, res, bpos=0, i;
  BinStr out;
  out.s = (unsigned char *) malloc( strlen(s) );
  out.l = 0;
  for (i=0; i < strlen(s); i++) {
    c = (unsigned char *)strchr(chartab,s[i]) - chartab;
    switch ( bpos ) {
    case 0: 
    case 8:
      res = c;
      bpos = 6;
      break;
    case 2:
      curr = res | (c << 2);
      res = 0;
      bpos = 0;
      out.s[out.l] = curr & 0xff;
      out.l++;
      break;
    case 4:
      curr = res | (c << 4);
      res = c >> 4;
      bpos = 2;
      out.s[out.l] = curr & 0xff;
      out.l++;
      break ;
    case 6:
      curr = res | (c << 6);
      res = c >> 2;
      bpos = 4;
      out.s[out.l] = curr & 0xff;
      out.l++;
      break ;
    }
  }
  out.s[out.l] = '\0';
  return out;
}

/*

xtea : XTEA cipher algorithm

v: 64-bit value (treated as int[2]) to encipher
k: 128-bit key (treated as int[4]) to encipher with
N: the number of mixing rounds (+ve to encipher, -ve to decipher)

*/

xtea(int *v, int *k, int N) {
  unsigned int y=v[0],z=v[1];
  if (N>0) {
    unsigned int limit=DELTA*N, sum=0;
    while (sum != limit) {
      y += (z<<4 ^ z>>5) + z ^ sum + k[sum & 3];
      sum += DELTA;
      z+= (y<<4 ^ y>>5) + y ^ sum + k[sum>>11 & 3];
    }
  }
  else {
    unsigned int sum=DELTA*(-N);
    while (sum) {
      z -= (y<<4 ^ y>>5) + y ^ sum + k[sum>>11 & 3];
      sum -= DELTA;
      y -= (z<<4 ^ z>>5) + z ^ sum + k[sum & 3];
    }
  }
  v[0]=y, v[1]=z;
  return;
}

/*

xxtea : XXTEA cipher algorithm

v: n-word value to encipher
n: the length of v in words (+ve to encipher, -ve to decipher)
k: 128-bit key to encipher with

*/

#define MX (z>>5^y<<2) + (y>>3^z<<4) ^ (sum^y) + (key[p&3^e]^z);
void xxtea(uint32_t *v, int n, uint32_t const key[4]) {
  uint32_t y, z, sum;
  unsigned p, rounds, e;
  if (n > 1) {          /* Coding Part */
    rounds = 6 + 52/n;
    sum = 0;
    z = v[n-1];
    do {
      sum += DELTA;
      e = (sum >> 2) & 3;
      for (p=0; p<n-1; p++) {
	y = v[p+1]; 
	z = v[p] += MX;
      }
      y = v[0];
      z = v[n-1] += MX;
    } while (--rounds);
  } 
  else if (n < -1) {  /* Decoding Part */
    n = -n;
    rounds = 6 + 52/n;
    sum = rounds*DELTA;
    y = v[0];
    do {
      e = (sum >> 2) & 3;
      for (p=n-1; p>0; p--) {
	z = v[p-1];
	y = v[p] -= MX;
      }
      z = v[n-1];
      y = v[0] -= MX;
      sum -= DELTA;
    } while (--rounds);
  }
}

/* 

encrypt, decrypt : these perform all necessary encryption and encoding
steps to convert a plaintext string to a web-safe crypttext, and back.

The encryption/decryption cycle converts to/from a binary hash of the 
plaintext.  The encode/decode cycle converts to/from a web-safe Base-64
representation of the binary hash.

*/

unsigned char* encrypt(char *plaintext) {
  int len,i;
  unsigned int v[2];
  BinStr btext;

  /* copy the plaintext to a binary string */
  len = strlen(plaintext);
#ifdef XTEA
  /* pad it out to a 64-bit boundary */
  btext.l = len % 8 ? (len / 8 + 1) * 8 : len;
#endif /*xtea*/
#ifdef XXTEA
  /* pad it out to a 32-bit boundary */
  btext.l = len % 4 ? (len / 4 + 1) * 4 : len;
#endif /*xxtea*/
  btext.s = (char *) malloc(btext.l);
  strncpy(btext.s,plaintext,len);
  for (i=len; i<btext.l; i++) { btext.s[i] = '\0'; }

#ifdef DEBUG
  printf("Bintext: ");
  for (i=0; i<btext.l; i++) { printf("%02x ",btext.s[i]); }
  printf("\n");
#endif

  /* encrypt */

#ifdef XTEA
  for (i=0; i<len; i+=8) {
    xtea((unsigned int *)&(btext.s[i]),key,nround);
  }
#endif /*xtea*/
#ifdef XXTEA
  int wlen = btext.l % 4 ? (btext.l / 4 + 1) : (btext.l / 4);
  xxtea((long *)&(btext.s[0]),wlen,key);
#endif /*xxtea*/
#ifdef DEBUG
  printf("Bincrypt: ");
  for (i=0; i<btext.l; i++) { printf("%02x ",btext.s[i]); }
  printf("\n");
#endif

  /* encode */

  return encode_base64(btext);
}

unsigned char* decrypt(char *crypttext) {
  int len,i;
  unsigned int v[2];
  BinStr btext;

  /* decode */

  btext = decode_base64(crypttext);
#ifdef DEBUG
  printf("Bincrypt: ");
  for (i=0; i<btext.l; i++) { printf("%02x ",btext.s[i]); }
  printf("\n");
#endif

  /* decrypt */

#ifdef XTEA
  for (i=0; i<btext.l; i+=8) {
    xtea((unsigned int *)&(btext.s[i]),key,-nround);
  }
#endif /*xtea*/
#ifdef XXTEA
  int wlen = btext.l / 4;
  xxtea((unsigned int *)&(btext.s[0]),-wlen,key);
#endif /*xxtea*/
#ifdef DEBUG
  printf("Bintext: ");
  for (i=0; i<btext.l; i++) { printf("%02x ",btext.s[i]); }
  printf("\n");
#endif

  return btext.s;
}

/*

encrypt_tea -d -n number_of_rounds -k keystring text

*/

int main(int argc, char** argv) {
  unsigned char in[INPUT_SIZE],*out,*keyparm,keystr[16];
  int i, iw, ib, ichar, decipher=0, keylen=0, inlen=0, iarg=1;

  /* read parameters from command line */

  while (iarg < argc) {
    if (strcmp(argv[iarg],"-d")==0){
      decipher = 1;
    }
    else if (strcmp(argv[iarg],"-n")==0){
      nround = atoi(argv[++iarg]);
    }
    else if (strcmp(argv[iarg],"-k")==0){
      keyparm = argv[++iarg];
      keylen = strlen(keyparm);
      strncpy(keystr,keyparm,keylen > 16 ? keylen : 16);
      for (i=keylen; i<16; i++) { keystr[i] = '\0'; }
    }
    else {
      if (strlen(argv[iarg]) > INPUT_SIZE-1) {
	/* overflow trap */
	inlen = INPUT_SIZE;
	strncpy(in,argv[iarg],inlen-1);
	in[inlen-1] = '\0';
      }
      else {
	strcpy(in,argv[iarg]);
	inlen = strlen(in);
      }
    }
    iarg++;
  }

  /* read stdin, if necessary */

  if (keylen == 0) {
    for (i=0; i<16; i++) { keystr[i] = getchar(); }
    keylen = 16;
  }
#ifdef DEBUG
  printf("key: ");
  for (i=0; i<16; i++) { printf("%02x ",keystr[i]); }
  printf("\n");
#endif
  if (inlen == 0) {
    ichar = getchar();
    while (ichar != EOF) {
      in[inlen++] = (unsigned char) ichar;
      ichar = getchar();
      if (inlen == INPUT_SIZE) break; /* overflow trap */
    }
    in[inlen] = '\0';
  }
#ifdef DEBUG
  printf("text: %s\n",in);
#endif

  /* copy the key string into the binary key array */

  key[0] = key[1] = key[2] = key[3] = 0;
  for (i=0; i<keylen; i++) {
    if (i>15) break;
    iw = i/4;
    ib = i%4;
    key[iw] = key[iw] | (keystr[i] << (ib*8));
    /*    printf("%d %d %c\n",iw,ib,keystr[i]);*/
  }

#ifdef DEBUG
  printf("Binkey: ");
  for (i=0; i<4; i++) { printf("%08x ",key[i]); }
  printf("\n");
  if (decipher) { printf("Deciphering...\n"); }
#endif
  fputs( (decipher ? decrypt(in) : encrypt(in)), stdout );

  return 0;
}


/*

convert from 4-byte strings to 32-bit ints, and back

These methods turn out to be unnecessary if our ints are 32-bit aligned;
it's easier just to equivlance our string an int array.

void str2int(unsigned char *s, unsigned int *l) {
  *l = s[0];
  *l |= s[1]<<8;
  *l |= s[2]<<16;
  *l |= s[3]<<24;
}

void int2str(unsigned int l, char *s) {
  s[0] = l & 0xff;
  s[1] = (l>>8) & 0xff;
  s[2] = (l>>16) & 0xff;
  s[3] = (l>>24) & 0xff;
}

    str2int(&(btext.s[i]),&v[0]);
    str2int(&(btext.s[i+4]),&v[1]);
    xtea(v,key,nround);
    int2str(v[0],&(btext.s[i]));
    int2str(v[1],&(btext.s[i+4]));

*/
