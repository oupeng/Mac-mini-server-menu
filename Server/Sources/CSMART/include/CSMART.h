#ifndef CSMART_H
#define CSMART_H

#include <IOKit/IOKitLib.h>

// 返回值: 1 = 良好 (Verified), 2 = 故障 (Failing), 0 = 不支持或读取失败
int csmart_check_service(io_service_t service);

#endif
