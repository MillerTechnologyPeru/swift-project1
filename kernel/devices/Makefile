TOPDIR := ../..
include $(TOPDIR)/Makedefs

SWIFT_MODULE := Devices
SWIFT_OBJS := tty.o pci.o
SWIFT_SRCS := $(patsubst %.o,%.swift,$(SWIFT_OBJS))
OBJS :=

all:

devices.o: $(OBJS)
	ld -r -no_eh_labels -o $@ $^

$(SWIFT_OBJS): $(SWIFT_SRCS)
	$(KSWIFTC) $(KSWIFTC_FLAGS) -emit-object -module-name $(SWIFT_MODULE) $^
	$(KSWIFTC) $(KSWIFTC_FLAGS) -emit-module -module-name $(SWIFT_MODULE) -o $(MODULE_DIR)/$(SWIFT_MODULE).swiftmodule $^

clean:
	rm -f *.bin *.o *.s $(MODULE_DIR)/$(SWIFT_MODULE).*

