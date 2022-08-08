#include <stdio.h>
#include <syslog.h>

int main(int argc, char *argv[])
{
    openlog(NULL, 0, LOG_USER);

    if (3 != argc)
    {
        fprintf(stderr, "Please provide two cmd line arguments as shown below\n ./writer <path/to/filename> <string>\n\n");
        syslog(LOG_ERR, "Invalid no. of arguments, argc = %d", argc);
        return 1;
    }

    FILE *fp;
    fp = fopen(argv[1], "w");

    if (!fp)
    {
        syslog(LOG_ERR, "File %s could not be opened in write mode.", argv[1]);
        return 1;
    }

    syslog(LOG_DEBUG, "Writing %s to %s", argv[2], argv[1]);
    fprintf(fp, "Writing %s to %s", argv[2], argv[1]);

    fclose(fp);

    return 0;
}