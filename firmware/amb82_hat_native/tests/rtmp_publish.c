// Host integration driver for the exact same packetizer/client used on the board.
// Input must have AUDs and repeated headers, with no B frames (see README).
#include "hat_rtmp_client.h"
#include "hat_rtmp_transport.h"
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <signal.h>
static volatile sig_atomic_t stopped;
static void stop(int sig) { (void)sig; stopped = 1; }
static bool cancelled(void *ctx) { (void)ctx; return stopped != 0; }
static size_t aud(const uint8_t *p, size_t n) {
    if (n >= 5 && !p[0] && !p[1] && !p[2] && p[3]==1 && (p[4]&31)==9) return 4;
    if (n >= 4 && !p[0] && !p[1] && p[2]==1 && (p[3]&31)==9) return 3;
    return 0;
}
int main(int argc, char **argv)
{
    if (argc != 3) { fprintf(stderr,"Usage: %s rtmp-url annexb-file\n",argv[0]); return 2; }
    signal(SIGINT,stop); signal(SIGTERM,stop); signal(SIGPIPE,SIG_IGN);
    hat_rtmp_set_cancel(cancelled,NULL);
    FILE *file=fopen(argv[2],"rb"); if (!file) return 2;
    fseek(file,0,SEEK_END); long size=ftell(file); rewind(file);
    if (size <= 0 || size > 32*1024*1024) return 2;
    uint8_t *data=malloc(size); if (!data) return 2;
    if (fread(data,1,size,file)!=(size_t)size) return 2; fclose(file);
    hat_rtmp_client *client=hat_rtmp_open(argv[1]);
    if (!client) { fprintf(stderr,"RTMP publish handshake failed\n"); free(data); return 1; }
    fprintf(stderr,"RTMP publish accepted\n");
    size_t start=0; unsigned frames=0; bool ok=true;
    while (start<(size_t)size && !stopped) {
        size_t code=aud(data+start,size-start);
        if (!code) { fprintf(stderr,"Missing AUD\n"); ok=false; break; }
        size_t end=start+code+1;
        while (end<(size_t)size && !aud(data+end,size-end)) end++;
        if (!hat_rtmp_poll(client) || !hat_rtmp_video(client,data+start,end-start,frames*1000/30)) { ok=false; break; }
        frames++; start=end;
        struct timespec pause={0,33333333}; nanosleep(&pause,NULL);
    }
    fprintf(stderr,"Published %u frames; video=%d; cancelled=%d\n",frames,hat_rtmp_has_video(client),stopped);
    hat_rtmp_close(client); free(data);
    return ok ? 0 : 1;
}
