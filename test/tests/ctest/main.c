#define TTY  (*(volatile char *)(-1))
#define STOP (*(volatile unsigned int *)(-16))

static void print_string(const char *str)
{
    while (*str)
	TTY = *str++;
}

int main(void)
{
    print_string("Hello, C world!\n");
    return 0;
}
