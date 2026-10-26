#include "MultitouchBridge.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <pthread.h>

// MTTouch layout taken from OpenMultitouchSupport (OpenMTInternal.h); verified on macos 26.
typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint position, velocity; } MTVector;
typedef struct {
    int frame;
    double timestamp;
    int identifier;
    int state;
    int fingerId;
    int handId;
    MTVector normalizedPosition;
    float total;
    float pressure;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absolutePosition;
    int field14;
    int field15;
    float density;
} MTTouch;

typedef void *MTDeviceRef;
typedef void (*MTContactCallback)(MTDeviceRef, MTTouch *, int, double, int);

// the sdk has no .tbd for the private framework, so symbols are loaded at runtime.
static struct {
    bool loaded;
    CFMutableArrayRef (*createList)(void);
    void (*registerCallback)(MTDeviceRef, MTContactCallback);
    void (*unregisterCallback)(MTDeviceRef, MTContactCallback);
    int (*start)(MTDeviceRef, int);
    int (*stop)(MTDeviceRef);
    bool (*isRunning)(MTDeviceRef);
    bool (*isBuiltIn)(MTDeviceRef);
    int (*getDeviceID)(MTDeviceRef, uint64_t *);
    int (*getFamilyID)(MTDeviceRef, int *);
    int (*getSurfaceDimensions)(MTDeviceRef, int *, int *);
} MT;

static void loadFramework(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *h = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW);
        if (!h) return;
        MT.createList = dlsym(h, "MTDeviceCreateList");
        MT.registerCallback = dlsym(h, "MTRegisterContactFrameCallback");
        MT.unregisterCallback = dlsym(h, "MTUnregisterContactFrameCallback");
        MT.start = dlsym(h, "MTDeviceStart");
        MT.stop = dlsym(h, "MTDeviceStop");
        MT.isRunning = dlsym(h, "MTDeviceIsRunning");
        MT.isBuiltIn = dlsym(h, "MTDeviceIsBuiltIn");
        MT.getDeviceID = dlsym(h, "MTDeviceGetDeviceID");
        MT.getFamilyID = dlsym(h, "MTDeviceGetFamilyID");
        MT.getSurfaceDimensions = dlsym(h, "MTDeviceGetSensorSurfaceDimensions");
        MT.loaded = MT.createList && MT.registerCallback && MT.unregisterCallback && MT.start && MT.stop;
    });
}

#define MAX_DEVICES 8
#define MAX_TOUCHES 32

// `lock` guards the handler, the device table and callback calls.
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static MTBFrameHandler frameHandler;
static void *frameContext;
static CFMutableArrayRef deviceList;  // holds the MTDeviceRefs
static MTDeviceRef devices[MAX_DEVICES];
static MTBDeviceInfo infos[MAX_DEVICES];
static int deviceCount;

static void contactCallback(MTDeviceRef device, MTTouch *touches, int count, double timestamp, int frame) {
    pthread_mutex_lock(&lock);
    if (frameHandler) {
        uint64_t deviceID = 0;
        for (int i = 0; i < deviceCount; i++) {
            if (devices[i] == device) { deviceID = infos[i].deviceID; break; }
        }
        MTBTouch out[MAX_TOUCHES];
        int n = count < 0 ? 0 : (count < MAX_TOUCHES ? count : MAX_TOUCHES);
        for (int i = 0; i < n; i++) {
            const MTTouch *t = &touches[i];
            out[i] = (MTBTouch){
                .identifier = t->identifier,
                .state = t->state,
                .x = t->normalizedPosition.position.x,
                .y = t->normalizedPosition.position.y,
                .vx = t->normalizedPosition.velocity.x,
                .vy = t->normalizedPosition.velocity.y,
                .pressure = t->pressure,
                .majorAxis = t->majorAxis,
                .minorAxis = t->minorAxis,
                .angle = t->angle,
                .total = t->total,
                .density = t->density,
            };
        }
        frameHandler(frameContext, deviceID, out, n, timestamp, frame);
    }
    pthread_mutex_unlock(&lock);
}

bool MTBIsAvailable(void) {
    loadFramework();
    return MT.loaded;
}

void MTBStop(void) {
    if (!MTBIsAvailable()) return;

    // empty the table first, then call MTDeviceStop outside the lock, otherwise it can deadlock
    // with a callback waiting on the lock.
    pthread_mutex_lock(&lock);
    CFMutableArrayRef list = deviceList;
    MTDeviceRef stopping[MAX_DEVICES];
    int n = deviceCount;
    for (int i = 0; i < n; i++) stopping[i] = devices[i];
    deviceList = NULL;
    deviceCount = 0;
    frameHandler = NULL;
    frameContext = NULL;
    pthread_mutex_unlock(&lock);

    for (int i = 0; i < n; i++) {
        MT.unregisterCallback(stopping[i], contactCallback);
        if (!MT.isRunning || MT.isRunning(stopping[i])) MT.stop(stopping[i]);
    }
    if (list) CFRelease(list);
}

int MTBStart(MTBFrameHandler handler, void *context) {
    if (!MTBIsAvailable()) return 0;
    MTBStop();

    CFMutableArrayRef list = MT.createList();
    if (!list) return 0;
    int total = (int)CFArrayGetCount(list);
    int n = 0;

    pthread_mutex_lock(&lock);
    deviceList = list;
    for (int i = 0; i < total && n < MAX_DEVICES; i++) {
        MTDeviceRef d = (MTDeviceRef)CFArrayGetValueAtIndex(list, i);
        MTBDeviceInfo info = {0};
        if (MT.getDeviceID) MT.getDeviceID(d, &info.deviceID);
        if (MT.getFamilyID) MT.getFamilyID(d, &info.familyID);
        // a magic mouse is a multitouch device too; fingers resting on it shouldn't count as trackpad gestures.
        if (info.familyID == 112 || info.familyID == 113) continue;
        if (MT.isBuiltIn) info.builtIn = MT.isBuiltIn(d);
        if (MT.getSurfaceDimensions) MT.getSurfaceDimensions(d, &info.surfaceWidth, &info.surfaceHeight);
        devices[n] = d;
        infos[n] = info;
        n++;
    }
    deviceCount = n;
    frameHandler = handler;
    frameContext = context;
    pthread_mutex_unlock(&lock);

    for (int i = 0; i < n; i++) {
        MT.registerCallback(devices[i], contactCallback);
        MT.start(devices[i], 0);
    }
    return n;
}

int MTBGetDevices(MTBDeviceInfo *out, int capacity) {
    pthread_mutex_lock(&lock);
    int n = deviceCount;
    for (int i = 0; i < n && i < capacity; i++) out[i] = infos[i];
    pthread_mutex_unlock(&lock);
    return n;
}

// MARK: - plug/unplug

static MTBDevicesChangedHandler changedHandler;
static void *changedContext;

static void serviceCallback(void *refcon, io_iterator_t iterator) {
    // the iterator has to be drained to re-arm the notification.
    bool changed = false;
    io_object_t service;
    while ((service = IOIteratorNext(iterator))) {
        IOObjectRelease(service);
        changed = true;
    }
    if (changed && changedHandler && refcon) changedHandler(changedContext);
}

void MTBObserveDeviceChanges(MTBDevicesChangedHandler handler, void *context) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        changedHandler = handler;
        changedContext = context;
        IONotificationPortRef port = IONotificationPortCreate(kIOMainPortDefault);
        IONotificationPortSetDispatchQueue(port, dispatch_get_main_queue());

        io_iterator_t added, removed;
        // refcon is NULL on the first drain: no handler call for devices already present.
        IOServiceAddMatchingNotification(port, kIOFirstMatchNotification,
                                         IOServiceMatching("AppleMultitouchDevice"),
                                         serviceCallback, (void *)1, &added);
        serviceCallback(NULL, added);
        IOServiceAddMatchingNotification(port, kIOTerminatedNotification,
                                         IOServiceMatching("AppleMultitouchDevice"),
                                         serviceCallback, (void *)1, &removed);
        serviceCallback(NULL, removed);
    });
}
