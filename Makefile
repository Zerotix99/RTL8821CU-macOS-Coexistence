CC = clang
CFLAGS = -O2 -Wall
IOKIT_FLAGS = -framework IOKit
BT_FLAGS = -framework Foundation -framework IOBluetooth
AUDIO_FLAGS = -framework Foundation -framework CoreAudio

BUILD_DIR = build
SRC_DIR = src

TARGETS = $(BUILD_DIR)/rtwcoexd $(BUILD_DIR)/btconnect $(BUILD_DIR)/set_audio

all: $(TARGETS)

$(BUILD_DIR)/rtwcoexd: $(SRC_DIR)/rtwcoexd.c
	@mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) $(IOKIT_FLAGS) $< -o $@

$(BUILD_DIR)/btconnect: $(SRC_DIR)/btconnect.m
	@mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) $(BT_FLAGS) $< -o $@

$(BUILD_DIR)/set_audio: $(SRC_DIR)/set_audio.m
	@mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) $(AUDIO_FLAGS) $< -o $@

build: $(TARGETS)

install: build
	sudo ./scripts/install.sh

uninstall:
	sudo ./scripts/uninstall.sh

status:
	./scripts/status.sh

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all build install uninstall status clean
