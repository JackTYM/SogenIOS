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

@end

NS_ASSUME_NONNULL_END
