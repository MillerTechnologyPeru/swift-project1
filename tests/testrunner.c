/*
 * tests/tests.c
 *
 * Created by Simon Evans on 01/01/2016.
 * Copyright © 2016 Simon Evans. All rights reserved.
 *
 * Test wrapper
 */

#include <stdio.h>
#include <string.h>
#include <assert.h>


void runTests(void);
int ksnprintf(char *buf, size_t size, const char *fmt, ...) __attribute__ ((format (printf, 3, 4)));
int kprintf(const char *fmt, ...) __attribute__ ((format (printf, 1, 2)));


// used by kprintf
void
early_print_char(const char ch)
{
        putchar(ch);
}

void
serial_print_char(const char ch)
{
        putchar(ch);
}


int main(int argc, char **argv)
{
        // Tests.runTests()
        runTests();

        return 0;
}
