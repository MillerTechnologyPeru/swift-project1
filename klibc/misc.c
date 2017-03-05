/*
 * klibc/misc.c
 *
 * Created by Simon Evans on 21/05/2016.
 * Copyright © 2016 Simon Evans. All rights reserved.
 *
 * Fake libc calls used by Linux/ELF libswiftCore
 *
 */

#include "klibc.h"

#define _UNISTD_H   // Avoid including all of unistd.h
#include <bits/confname.h>
#include <elf.h>

#pragma GCC diagnostic ignored "-Wunused-parameter"


extern void (*__init_array_start [])(void);
extern void (*__init_array_end [])(void);
extern Elf64_Rela __rela_iplt_start[];
extern Elf64_Rela __rela_iplt_end[];


void
klibc_start()
{
        // Call the static constructors held in the .init_array
        const size_t count = __init_array_end - __init_array_start;
        for (size_t idx = 0; idx < count; idx++) {
                void (*func)(void) = __init_array_start[idx];
                func();
        }

        // Setup relocations in the .rela.iplt array
        const size_t relocs = __rela_iplt_end - __rela_iplt_start;
        for (size_t idx = 0; idx < relocs; idx++) {
                Elf64_Rela *reloc = &__rela_iplt_start[idx];
                if (ELF64_R_TYPE(reloc->r_info) != R_X86_64_IRELATIVE) {
                        kprintf("Bad reloc type: %ld\n",
                                ELF64_R_TYPE(reloc->r_info));
                } else {
                        Elf64_Addr (*func)(void) = (void *)reloc->r_addend;
                        Elf64_Addr addr = func();
                        Elf64_Addr *const reloc_addr = (void *)reloc->r_offset;
                        *reloc_addr = addr;
                }
        }
}


void
__assert_fail(const char *err, const char *file,
               unsigned int line, const char *function)
{
        koops("assert:%s:%s:%d:%s\n", file, function, line, err);
        hlt();
}


void
__stack_chk_fail()
{
        koops("stack check fail !");
}


void
abort()
{
        koops("abort() called");
}


/* Only works for anonymous mmap (fd == -1), ignore protection settings for now
 * This is used to emulate the large malloc that stdlib does in
 * stdlib/public/runtime/Metadata.cpp (which is remapped to malloc here anyway)
 */
void
*mmap(void *addr, size_t len, int prot, int flags, int fd, unsigned long offset)
{
        if (fd != -1) {
                koops("mmap with fd=%d!", fd);
        }

        void *result = malloc(len);
        debugf("mmap(addr=%p, len=%lX, prot=%X, flags=%X, fd=%d, offset=%lX)=%p\n",
                addr, len, prot, flags, fd, offset, result);

        return result;
}


/* This is hopefully only used on the result of the above mmap */
int
munmap(void *addr, size_t length)
{
        debugf("munmap(addr=%p, len=%lX\n", addr, length);
        free(addr);

        return 0;
}


long
sysconf(int name)
{
        switch(name) {
        case _SC_PAGESIZE:
                return PAGE_SIZE;

        case _SC_NPROCESSORS_ONLN:
                return 1;

        default:
                koops("UNIMPLEMENTED sysconf: name = %d\n", name);
        }
}


UNIMPLEMENTED(__divti3)
UNIMPLEMENTED(backtrace)


// Unicode (libicu)
UNIMPLEMENTED(ucol_closeElements_52)
UNIMPLEMENTED(ucol_next_52)
UNIMPLEMENTED(ucol_open_52)
UNIMPLEMENTED(ucol_openElements_52)
UNIMPLEMENTED(ucol_setAttribute_52)
UNIMPLEMENTED(ucol_strcoll_52)
UNIMPLEMENTED(uiter_setString_52)
UNIMPLEMENTED(uiter_setUTF8_52)
UNIMPLEMENTED(u_strToLower_52)
UNIMPLEMENTED(u_strToUpper_52)
UNIMPLEMENTED(ucol_strcollIter_52)
UNIMPLEMENTED(ucol_closeElements_55)
UNIMPLEMENTED(ucol_next_55)
UNIMPLEMENTED(ucol_open_55)
UNIMPLEMENTED(ucol_openElements_55)
UNIMPLEMENTED(ucol_setAttribute_55)
UNIMPLEMENTED(ucol_strcoll_55)
UNIMPLEMENTED(uiter_setString_55)
UNIMPLEMENTED(uiter_setUTF8_55)
UNIMPLEMENTED(u_strToLower_55)
UNIMPLEMENTED(u_strToUpper_55)
UNIMPLEMENTED(ucol_strcollIter_55)