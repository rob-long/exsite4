/*
 * publish program:  a setuid wrapper for the page.cgi script
 * so that it can write files to the htdocs area
 *
 * usage:
 * cc -o publish.cgi publish.c
 * chmod +s publish.cgi
 *
 */

#include <unistd.h>
#include <string.h>
#include <stdlib.h>

#define MAXPATHLEN 250
char buf[MAXPATHLEN];

main(ac, av)
     char **av;
{
  /* fetch the CGIpath directory */
  getcwd(buf,MAXPATHLEN);

  /* build path to CGI script */
  strcat(buf,"/publish.pl");

  /* set the QUERY_STRING */
  /* setenv("QUERY_STRING", "publish", 1); */

  /* run the CGI script setuid */
  execv(buf, av);
}

