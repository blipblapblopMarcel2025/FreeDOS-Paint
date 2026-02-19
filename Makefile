ASM=nasm
TARGET=paint16.com
SRC=paint16.asm

all: $(TARGET)

$(TARGET): $(SRC)
	$(ASM) -f bin $(SRC) -o $(TARGET)

clean:
	rm -f $(TARGET)
