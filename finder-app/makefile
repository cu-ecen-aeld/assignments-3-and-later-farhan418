CROSS_COMPILE=gcc

writer: writer.c
ifeq ($(CROSS_COMPILE),gcc)
	gcc -o writer writer.c
else
	$(CROSS_COMPILE) -o writer writer.c
endif

clean:
	-rm writer
	-rm *.o