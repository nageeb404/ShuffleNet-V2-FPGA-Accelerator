#include "platform.h"
#include "xil_cache.h"

void init_platform()
{
    Xil_ICacheEnable();
    Xil_DCacheEnable();
}

void cleanup_platform()
{
    Xil_ICacheDisable();
    Xil_DCacheDisable();
}
