#include "CSMART.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/storage/ata/ATASMARTLib.h>

int csmart_check_service(io_service_t service) {
    if (service == IO_OBJECT_NULL) {
        return 0;
    }

    IOCFPlugInInterface **plugInInterface = NULL;
    IOATASMARTInterface **smartInterface = NULL;
    SInt32 score = 0;

    kern_return_t kr = IOCreatePlugInInterfaceForService(
        service,
        kIOATASMARTUserClientTypeID,
        kIOCFPlugInInterfaceID,
        &plugInInterface,
        &score
    );

    if (kr != kIOReturnSuccess || plugInInterface == NULL) {
        return 0;
    }

    HRESULT res = (*plugInInterface)->QueryInterface(
        plugInInterface,
        CFUUIDGetUUIDBytes(kIOATASMARTInterfaceID),
        (LPVOID *)&smartInterface
    );

    int status = 0;

    if (res == S_OK && smartInterface != NULL) {
        Boolean conditionExceeded = false;
        IOReturn smartErr = (*smartInterface)->SMARTReturnStatus(smartInterface, &conditionExceeded);
        if (smartErr == kIOReturnSuccess) {
            status = conditionExceeded ? 2 : 1;
        }
        (*smartInterface)->Release(smartInterface);
    }

    IODestroyPlugInInterface(plugInInterface);
    return status;
}
