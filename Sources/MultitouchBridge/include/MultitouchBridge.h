// small c bridge to the private MultitouchSupport.framework.
// listens to ALL connected multitouch devices (built-in trackpad + magic trackpad).
#ifndef MultitouchBridge_h
#define MultitouchBridge_h

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int32_t identifier;
    int32_t state;      // 0 notTracking … 7 outOfRange (MTTouchState)
    float x, y;         // normalized 0...1, y grows upward
    float vx, vy;       // normalized units / s
    float pressure;
    float majorAxis, minorAxis;
    float angle;
    float total;        // total capacitance
    float density;
} MTBTouch;

typedef struct {
    uint64_t deviceID;
    int32_t familyID;
    bool builtIn;
    int32_t surfaceWidth;   // 0.01 mm
    int32_t surfaceHeight;
} MTBDeviceInfo;

/// called for every frame. calls are serialized with a lock but the thread isn't fixed
/// (may differ per device). `touches` is only valid during the call.
typedef void (*MTBFrameHandler)(void *context, uint64_t deviceID, const MTBTouch *touches,
                                int count, double timestamp, int frame);

/// called on the main queue when a device is added or removed.
typedef void (*MTBDevicesChangedHandler)(void *context);

/// false if the framework can't be loaded.
bool MTBIsAvailable(void);

/// starts listening to every current device (stops running ones first). returns how many started.
int MTBStart(MTBFrameHandler handler, void *context);

/// stops every device. once it returns the handler isn't called anymore.
void MTBStop(void);

/// writes the devices being listened to into `out`, returns the total count.
int MTBGetDevices(MTBDeviceInfo *out, int capacity);

/// turns on iokit plug/unplug notifications. call once.
void MTBObserveDeviceChanges(MTBDevicesChangedHandler handler, void *context);

#ifdef __cplusplus
}
#endif

#endif
