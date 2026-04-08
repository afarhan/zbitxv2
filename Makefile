CC      = gcc
CFLAGS  = -g $(shell pkg-config --cflags gtk+-3.0)
LDFLAGS = -lwiringPi -lasound -lm -lfftw3 -lfftw3f -pthread -lncurses -lsqlite3           $(shell pkg-config --libs gtk+-3.0)

TARGET  = sbitx

SRCS = vfo.c si570.c sbitx_sound.c fft_filter.c sbitx_gtk.c sbitx_utils.c        i2cbb.c si5351v2.c ini.c hamlib.c queue.c modems.c logbook.c        modem_cw.c settings_ui.c oled.c hist_disp.c ntputil.c        telnet.c macros.c modem_ft8.c remote.c mongoose.c webserver.c $(TARGET).c

OBJS    = $(SRCS:.c=.o)
FT8_LIB = ft8_lib/libft8.a

.PHONY: all clean

all: audio data web data/sbitx.db $(TARGET)

$(TARGET): $(OBJS) $(FT8_LIB)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

audio data web:
	mkdir $@

data/sbitx.db: | data
	cd data && sqlite3 sbitx.db < create_db.sql

clean:
	rm -f $(OBJS) $(TARGET)
