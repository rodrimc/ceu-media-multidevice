#Dependencies
CEU_DIR    		= $(error set CEU_DIR to Céu directory)
CEU_MEDIA_DIR	= $(error set CEU_MEDIA_DIR to Céu-Media directory)
CEU_UV_DIR 		= $(error set CEU_UV_DIR to Céu-libuv directory)
CEU_LIB_DIR		= $(error set CEU_LIB_DIR to Céu-r-util installation)

#all target
all: PROG 					= $(error set PROG to a CÉU program)
all: PROG_SED 			= $(PROG://=\/)
all: MODULES 				= play lua5.3 libuv
all: SRC_NAME				= $(notdir $(PROG))
all: override SYNC := include/sync/mirror.ceu

#server target
server: MODULES = lua5.3 libuv
server: SRC_NAME= $(notdir $(SRC))

#both targets
server all: override CFLAGS := $(shell pkg-config $(MODULES) --libs --cflags)\
																-lpthread $(CFLAGS) -lm -DDEBUG -g

#variables
BIN					= $(SRC_NAME:%.ceu=%)
BUILD_PATH 	= build
TEMP 				:= $(BUILD_PATH)/temp-$(shell date --iso=ns).ceu

all:
	mkdir -p $(BUILD_PATH)
	cp $(SYNC) $(TEMP)
	sed s:PROG:"\"$(PROG_SED)\"":g -i $(TEMP)
	ceu --pre --pre-args="-I$(CEU_DIR)/include -I$(CEU_MEDIA_DIR)/include	-I./ \
						-I$(CEU_UV_DIR)/include -I$(CEU_LIB_DIR) -I./include"  	 				 \
	          --pre-input=$(TEMP)																							 \
	    --ceu --ceu-err-unused=pass --ceu-err-uninitialized=pass							 \
						--ceu-features-exception=true --ceu-features-thread=true				 \
						--ceu-features-lua=true																					 \
	    --env --env-types=$(CEU_DIR)/env/types.h															 \
	          --env-threads=$(CEU_DIR)/env/threads.h													 \
	          --env-main=$(CEU_DIR)/env/main.c																 \
	          --env-output=/tmp/x.c																						 \
	    --cc --cc-args="$(CFLAGS)"																						 \
	         --cc-output=build/$(BIN)
	rm $(TEMP)
	$(BUILD_PATH)/$(BIN)

server:
	mkdir -p $(BUILD_PATH)
	ceu --pre --pre-args="-I$(CEU_DIR)/include -I$(CEU_MEDIA_DIR)/include		\
						-I$(CEU_UV_DIR)/include -I$(CEU_LIB_DIR) -I./include"					\
	          --pre-input=$(SRC)																						\
	    --ceu --ceu-err-unused=pass --ceu-err-uninitialized=pass						\
						--ceu-features-exception=true --ceu-features-thread=true			\
						--ceu-features-lua=true																				\
	    --env --env-types=$(CEU_DIR)/env/types.h														\
	          --env-threads=$(CEU_DIR)/env/threads.h												\
	          --env-main=$(CEU_DIR)/env/main.c															\
	          --env-output=/tmp/x.c																					\
	    --cc --cc-args="$(CFLAGS)"																					\
	         --cc-output=build/$(BIN)
	$(BUILD_PATH)/$(BIN)

clean:
	rm -rf $(BUILD_PATH)
