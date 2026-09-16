#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN

/// Objective-C facade over sogen::windows_emulator. Every method is main-thread safe;
/// the emulator itself runs on a private background thread owned by this object.
@interface SogenEmulator : NSObject

/// `layer` receives every frame the guest presents. `emulationRoot` is the directory holding
/// filesys/ and registry/. `guestExecutablePath` is the host path of the bundled .exe, which is
/// mapped into the guest as c:\native-gpu-clear-sample.exe.
- (instancetype)initWithLayer:(CALayer *)layer
                emulationRoot:(NSString *)emulationRoot
          guestExecutablePath:(NSString *)guestExecutablePath NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

/// Invoked on the main queue for every emulator log line and every byte of guest stdout.
@property (nonatomic, copy, nullable) void (^onLogLine)(NSString *line);

/// Starts the guest on a background thread and returns immediately.
- (void)start;

/// Requests that the run loop stop. Safe to call more than once.
- (void)stop;

/// Queues one left-button click. Delivered on the emulator thread at the next event pump.
- (void)deliverTap;

/// Delivers a positioned mouse move (touchscreen mode). `point` is in guest-frame pixel
/// coordinates, already transformed from view space by the caller.
- (void)deliverMouseMove:(CGPoint)point;

/// Delivers a positioned mouse button event (touchscreen mode). `message` is one of the
/// WM_LBUTTONDOWN/WM_LBUTTONUP/WM_RBUTTONDOWN/WM_RBUTTONUP constants.
- (void)deliverMouseButton:(CGPoint)point message:(uint32_t)message;

/// Delivers a relative mouse movement delta (trackpad mode) via the existing raw-input path.
- (void)deliverMouseDelta:(CGFloat)dx dy:(CGFloat)dy;

/// Queues one right-button click via the existing raw-input path (trackpad mode).
- (void)deliverRightClick;

/// Re-points frame presentation at a new layer -- used when a later-created view produces its
/// own CALayer after the emulator was already constructed/started against a placeholder.
- (void)attachLayer:(CALayer *)layer;

/// Invoked on the main queue whenever the guest's presented frame size changes.
@property (nonatomic, copy, nullable) void (^onFrameSize)(CGSize size);

@end

NS_ASSUME_NONNULL_END
