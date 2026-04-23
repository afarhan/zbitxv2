#include <stdio.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <string.h>
#include <arpa/inet.h>
#include <stdlib.h>
#include <errno.h>
#include <fcntl.h>
#include <complex.h>
#include <math.h>
#include <fcntl.h>
#include <complex.h>
#include <fftw3.h>
#include <assert.h>
#include <stdint.h>
#include <wiringPi.h>
#include <pthread.h>
#include <stdbool.h>
#include "sdr.h"
#include "sdr_ui.h"
#include "logbook.h"

static int welcome_socket = -1, data_socket = -1;
#define MAX_DATA 1000
static char incoming_data[MAX_DATA];
static unsigned int remote_updated_on = 0;

#define MAX_THREADS 10
int nthreads = 0;

struct remote {
	unsigned int updated_on;
	int fd;
};

static struct remote remote_table[MAX_THREADS];

static void remote_send(int fd, char *m) {
 //send(fd, m, strlen(m), MSG_DONTWAIT);
 printf("sock %d %s\n", fd, m);
 send(fd, m, strlen(m), MSG_NOSIGNAL);
}

static void remote_update(struct remote *r){
	int i;
	uint32_t timestamp;
	char buff[5000];
	//get_console(c);

	unsigned int  now = millis();	
	i = 0;
	while(1){
		if(get_field_timestamped(i, buff, &timestamp) == -1)
			break;
		i++;
		if (timestamp >= r->updated_on){
			strcat(buff, "\n");
			remote_send(r->fd, buff);
		}
	}
	remote_get_spectrum(buff);
	strcat(buff, "\n");
	remote_send(r->fd, buff);	
	//web_get_spectrum(buff);
	//strcat(buff, "\n");
	//remote_send(buff);
	r->updated_on = now;
}

//called from the main loop with notifications 
void remote_write(char *m){
	int i;

	for (int i = 0; i < nthreads; i++)
		//if (remote_table[i].fd)
			remote_send(remote_table[i].fd, m);
}

static void get_logs(struct remote *r){
	char logbook_path[200];
	char row_response[1000], row[1000];
	char query[100];
	int	row_id;

	printf("remote: sending logs\n");
	query[0] = 0;
	row_id = -1;
	logbook_query(NULL, row_id, logbook_path);
	FILE *pf = fopen(logbook_path, "r");
	if (!pf)
		return;
	while(fgets(row, sizeof(row), pf)){
		sprintf(row_response, "QSO %s\n", row);
		printf("remote: log > %s\n", row_response);
		remote_send(r->fd, row_response); 
	}
	fclose(pf);
}

struct remote *remote_new(int fd){
	//see if an existing socket has the same fd
	for (int i = 0; i < MAX_THREADS; i++)
		if (remote_table[i].fd == fd)
			return remote_table + i;
	
	for (int i = 0; i < MAX_THREADS; i++)
		if (remote_table[i].fd == 0)
			return remote_table + i;
	return NULL;
}

void *fn_remote_client(void *fd_client){
	char buffer[5000];
	unsigned int last_request, now;
  struct timeval tv;
	int len, data_socket;
	int update_logs = 0;

	struct sched_param sch;

	//switch to maximum priority
	sch.sched_priority = sched_get_priority_max(SCHED_FIFO);
	pthread_setschedparam(pthread_self(), SCHED_FIFO, &sch);

	data_socket = (intptr_t)fd_client;
	{ int one = 1; setsockopt(data_socket, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one)); }
	struct remote *r = remote_new(data_socket);
	r->fd = data_socket;
	r->updated_on = millis();
	printf("remote: new thread with sock %d\n", data_socket);
	if (!r){
		printf("remote: max clients reached\n");
		return NULL;
	}
	printf("remote: insidie  a new thread for socketc %d\n", data_socket);
  
	//this section was changed by W9JES
  tv.tv_sec = 2; //gone in 2 seconds
  tv.tv_usec = 0;
	//setsockopt(data_socket, SOL_SOCKET, SO_RCVTIMEO, (const char*)&tv, sizeof tv);

	printf("remote: started new client, connection count is %d\n", nthreads);
	while(1){

		now = millis();
		memset(buffer, 0, sizeof(buffer));
		printf("<--recv");
  	int len = recv(data_socket, buffer, sizeof(buffer), 0);
		printf(" %d>\n", len);
		//printf("remote [%s]\n", buffer);
  	if (len > 0){
    	buffer[len] = '\0'; // Ensure the buffer is null-terminated: W9JES
    	// Strip off the last \r or \n
			char *context;
			char *t = strtok_r(buffer, "\r\n", &context);
			int update_count = 0;
			while (t){
				putchar('.');
				//buffer[strcspn(buffer, "\r\n")] = '\0';
				if (*t == '?'){ 
					if (update_count == 0){
						remote_update(r);
						putchar('#');
					}
					else 
						printf("!");
					update_count++;
				}
				else if (!strcmp(buffer, "OPEN "))
					get_logs(r);
				else if(strlen(t)){
					//printf("Received on remote : [%s]\n", t);
					remote_execute(t);
				}
				last_request = now;
				t = strtok_r(NULL, "\r\n", &context);
			}
		}
		else if (len == 0){
			printf("remote: eof on %d\n", data_socket);
			break;
		}
		else if (update_logs){
				get_logs(r);
				update_logs = 0;
   	} else if (last_request + 5000 < now){
			printf("remote: timeout\n");
			break;
		}
	}
  puts("remote:  client closed the connection.\n");
  close(r->fd);
	//release the remote structure
  r->fd = 0;
	r->updated_on = 0;
	
	nthreads--;
}

void *fn_remote_listener(void *nothing){
	char buffer[MAX_DATA];
  struct sockaddr_in server_addr;
  struct sockaddr_in client_addr;
 	struct sockaddr_storage serverStorage;
  socklen_t addr_size;
	int server_socket;

  server_socket = socket(PF_INET, SOCK_STREAM, 0);
	memset(remote_table, 0, sizeof(remote_table));
  
  server_addr.sin_family = AF_INET;
  server_addr.sin_port = htons(8081);
  server_addr.sin_addr.s_addr = INADDR_ANY;
  memset(server_addr.sin_zero, '\0', sizeof server_addr.sin_zero);  

  /* Bind the address struct to the socket */
  if(bind(server_socket, (struct sockaddr *) &server_addr, sizeof(server_addr)) != 0){
		printf("remote: server couldn't start on port 8081\n");
		return NULL;
	}

  /* Listen on the socket, with 5 max connection requests queued */
  if(listen(server_socket,5) != 0){
    printf("remote: tcp listen() Error\n");
		return NULL;
	}
	printf("remote: listening to connections on port 8081\n");

	while(1){
		int fd = -1;
		pthread_t new_client;
		addr_size = sizeof(client_addr);
		if ((fd = accept(server_socket, (struct sockaddr *)&client_addr, &addr_size)) < 0){
			printf("remote: client connection failed\n");
			continue;
		}
		else if (nthreads < MAX_THREADS-1){
			printf("remote: spawing a new thread for socketc %d\n", fd);
			pthread_create(&new_client, NULL, fn_remote_client, (void*)(intptr_t)fd);
		}
		else{
			printf("remote: dropped connection as too many clients are connected\n");
			close(fd);
		}

	}
	printf("remote: never reaches here\n");
	return NULL;
}


void udp_thread(void *udp){
	//create a udp listener socket
	
}

void remote_start_thread(){
	pthread_t listener_thread;
	pthread_create(&listener_thread, NULL, fn_remote_listener, (void*)NULL);
}
