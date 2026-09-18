#import "SogenBridge.h"
#import "IosUiBackend.hpp"

#include <windows_emulator.hpp>
#include <backend_selection.hpp>
#include <utils/ios_device_log.hpp>

#include <TargetConditionals.h>
#include <cstdlib>
#include <exception>
#include <memory>
#include <string>
#include <thread>

@implementation SogenEmulator {
    std::unique_ptr<sogen::windows_emulator> _emulator;
    sogen::ios_ui_backend* _ui;  // owned by _emulator via emulator_interfaces::ui
    std::thread _runThread;
    NSString* _emulationRoot;
    NSString* _guestExecutablePath;
    CALayer* _layer;
    // The guest's CRT stdio implementation writes one byte per NtWriteFile syscall, so on_stdout
    // below accumulates chunks here and only calls appendLog: once a complete line has arrived.
    NSMutableString* _stdoutLineBuffer;
}

- (instancetype)initWithLayer:(CALayer *)layer
                emulationRoot:(NSString *)emulationRoot
          guestExecutablePath:(NSString *)guestExecutablePath
{
    self = [super init];
    if (self)
    {
        _layer = layer;
        _emulationRoot = [emulationRoot copy];
        _guestExecutablePath = [guestExecutablePath copy];
        _ui = nullptr;
        _stdoutLineBuffer = [NSMutableString string];
    }
    return self;
}

- (void)dealloc
{
    [self stop];
}

- (void)appendLog:(NSString *)line
{
    void (^sink)(NSString *) = self.onLogLine;
    if (!sink)
    {
        NSLog(@"%@", line);
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
      sink(line);
    });
}

- (BOOL)validatePaths
{
    NSFileManager* fm = [NSFileManager defaultManager];
    BOOL isDirectory = NO;

    NSString* filesys = [_emulationRoot stringByAppendingPathComponent:@"filesys"];
    NSString* registry = [_emulationRoot stringByAppendingPathComponent:@"registry"];

    if (![fm fileExistsAtPath:filesys isDirectory:&isDirectory] || !isDirectory)
    {
        [self appendLog:[NSString stringWithFormat:@"ERROR: emulation root incomplete, missing %@", filesys]];
        return NO;
    }
    if (![fm fileExistsAtPath:registry isDirectory:&isDirectory] || !isDirectory)
    {
        [self appendLog:[NSString stringWithFormat:@"ERROR: emulation root incomplete, missing %@", registry]];
        return NO;
    }
    if (![fm fileExistsAtPath:_guestExecutablePath])
    {
        [self appendLog:[NSString stringWithFormat:@"ERROR: guest executable missing at %@", _guestExecutablePath]];
        return NO;
    }
    return YES;
}

- (void)start
{
    if (_runThread.joinable())
    {
        return;
    }

    if (![self validatePaths])
    {
        return;
    }

    NSString* root = _emulationRoot;
    NSString* guest = _guestExecutablePath;
    CALayer* layer = _layer;
    __weak SogenEmulator* weakSelf = self;

    _runThread = std::thread([weakSelf, root, guest, layer]() {
        SogenEmulator* strongSelf = weakSelf;
        if (!strongSelf)
        {
            return;
        }

        try
        {
            auto ui = std::make_unique<sogen::ios_ui_backend>(layer);
            auto* ui_raw = ui.get();
            ui_raw->set_log_sink([weakSelf](const char* line) {
                [weakSelf appendLog:[NSString stringWithUTF8String:line]];
            });

            sogen::emulator_interfaces interfaces{};
            interfaces.ui = std::move(ui);
            // Nothing in this app produces audio; the default would be the SDL audio backend,
            // which would spin up an AVAudioSession for no reason.
            interfaces.audio = std::make_unique<sogen::null_audio_backend>();

            sogen::emulator_settings settings{};
            settings.emulation_root = std::filesystem::path(root.UTF8String);
            // The guest .exe ships in the app bundle (read-only), not inside the provisioned
            // emulation root, so map its guest path straight at the bundle resource.
            settings.path_mappings[sogen::windows_path("c:/native-gpu-clear-sample.exe")] =
                std::filesystem::path(guest.UTF8String);

            sogen::application_settings app_settings{};
            app_settings.application = sogen::windows_path("c:/native-gpu-clear-sample.exe");

            sogen::emulator_callbacks callbacks{};
            callbacks.on_stdout = [weakSelf](const std::string_view data) {
                SogenEmulator* strongSelf = weakSelf;
                if (!strongSelf)
                {
                    return;
                }

                NSString* text = [[NSString alloc] initWithBytes:data.data()
                                                          length:data.size()
                                                        encoding:NSUTF8StringEncoding];
                if (!text)
                {
                    return;
                }

                NSMutableString* buffer = strongSelf->_stdoutLineBuffer;
                [buffer appendString:text];

                NSRange newline = [buffer rangeOfString:@"\n"];
                while (newline.location != NSNotFound)
                {
                    NSString* line = [buffer substringToIndex:newline.location];
                    if ([line hasSuffix:@"\r"])
                    {
                        line = [line substringToIndex:line.length - 1];
                    }
                    [strongSelf appendLog:line];
                    [buffer deleteCharactersInRange:NSMakeRange(0, newline.location + 1)];
                    newline = [buffer rangeOfString:@"\n"];
                }
            };

#if defined(SOGEN_IOS_USE_FEX) && TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
            // FEX's TSO memory-ordering modeling emits misaligned STLR/LDAR atomics that fault
            // on real ARM64 hardware; those faults can't be delivered correctly on this device
            // (see the JIT26-debugger-swallows-hardware-exceptions notes elsewhere in
            // fex_x86_64_emulator.cpp). Disabling TSO modeling makes FEX emit plain LDR/STR
            // instead, which don't fault on misalignment, eliminating this whole fault class.
            setenv("EMULATOR_FEX_NO_TSO", "1", 1);
#endif

            sogen::utils::log_ios_device_milestone("[milestone] before create_x86_64_emulator");
#if defined(SOGEN_IOS_USE_FEX)
            const auto backend = sogen::backend_type::fex;
#else
            const auto backend = sogen::backend_type::unicorn;
#endif
            auto emu = sogen::create_x86_64_emulator(backend, 1);
            sogen::utils::log_ios_device_milestone("[milestone] after create_x86_64_emulator");
            [weakSelf appendLog:(backend == sogen::backend_type::fex) ? @"[sogen] backend: fex" : @"[sogen] backend: unicorn"];

            sogen::utils::log_ios_device_milestone("[milestone] before windows_emulator constructor");
            auto win_emu = std::make_unique<sogen::windows_emulator>(
                std::move(emu), std::move(app_settings), settings, std::move(callbacks), std::move(interfaces));
            sogen::utils::log_ios_device_milestone("[milestone] after windows_emulator constructor");

            win_emu->log.set_sink([weakSelf](sogen::color, const std::string_view message) {
                NSString* text = [[NSString alloc] initWithBytes:message.data()
                                                          length:message.size()
                                                        encoding:NSUTF8StringEncoding];
                if (text)
                {
                    [weakSelf appendLog:text];
                }
            });

            auto* emulator_ptr = win_emu.get();
            ui_raw->set_raw_mouse_sink(
                [emulator_ptr](const int32_t dx, const int32_t dy, const uint16_t flags, const uint16_t data) {
                    emulator_ptr->deliver_raw_mouse_input(dx, dy, flags, data);
                });
            ui_raw->set_mouse_move_sink([emulator_ptr](const int32_t x, const int32_t y) {
                emulator_ptr->deliver_mouse_move(x, y);
            });
            ui_raw->set_mouse_button_sink([emulator_ptr](const int32_t x, const int32_t y, const uint32_t message) {
                emulator_ptr->deliver_mouse_button(x, y, message);
            });
            ui_raw->set_frame_size_sink([weakSelf](const int32_t width, const int32_t height) {
                SogenEmulator* strongSelf = weakSelf;
                if (!strongSelf || !strongSelf.onFrameSize)
                {
                    return;
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                  strongSelf.onFrameSize(CGSizeMake(width, height));
                });
            });
            ui_raw->set_cursor_visibility_sink([weakSelf](const bool visible) {
                SogenEmulator* strongSelf = weakSelf;
                if (!strongSelf || !strongSelf.onCursorVisibilityChange)
                {
                    return;
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                  strongSelf.onCursorVisibilityChange(visible ? YES : NO);
                });
            });

            CALayer* currentLayer = nullptr;
            @synchronized(strongSelf)
            {
                strongSelf->_emulator = std::move(win_emu);
                strongSelf->_ui = ui_raw;
                currentLayer = strongSelf->_layer;
            }
            // Picks up whatever attachLayer: call (if any) landed while _ui was still null above.
            ui_raw->set_layer(currentLayer);

            [weakSelf appendLog:@"[sogen] starting guest"];
            sogen::utils::log_ios_device_milestone("[milestone] before windows_emulator::start()");
            strongSelf->_emulator->start();
            sogen::utils::log_ios_device_milestone("[milestone] after windows_emulator::start()");
            [weakSelf appendLog:@"[sogen] guest run finished"];
        }
        catch (const std::exception& e)
        {
            [weakSelf appendLog:[NSString stringWithFormat:@"ERROR: %s", e.what()]];
        }
        catch (...)
        {
            [weakSelf appendLog:@"ERROR: unknown exception on the emulator thread"];
        }
    });
}

- (void)stop
{
    // windows_emulator::should_stop is a std::atomic_bool, so requesting the stop from another
    // thread is safe; the run loop notices it at the top of its next iteration. Everything else
    // (destroying the emulator, clearing the backend pointer) happens only after the join, on
    // whichever thread called stop.
    if (_emulator)
    {
        _emulator->stop();
    }

    if (_runThread.joinable())
    {
        _runThread.join();
    }

    _ui = nullptr;
    _emulator.reset();
}

- (void)deliverTap
{
    // Runs on the main thread. queue_left_click() only touches a mutex-guarded vector; the actual
    // deliver_raw_mouse_input call happens on the emulator thread inside pump_events().
    if (_ui)
    {
        _ui->queue_left_click();
    }
}

- (void)deliverMouseMove:(CGPoint)point
{
    if (_ui)
    {
        _ui->queue_mouse_move(static_cast<int32_t>(point.x), static_cast<int32_t>(point.y));
    }
}

- (void)deliverMouseButton:(CGPoint)point message:(uint32_t)message
{
    if (_ui)
    {
        _ui->queue_mouse_button(static_cast<int32_t>(point.x), static_cast<int32_t>(point.y), message);
    }
}

- (void)deliverMouseDelta:(CGFloat)dx dy:(CGFloat)dy
{
    if (_ui)
    {
        _ui->queue_mouse_delta(static_cast<int32_t>(dx), static_cast<int32_t>(dy));
    }
}

- (void)deliverRightClick
{
    if (_ui)
    {
        _ui->queue_right_click();
    }
}

- (void)attachLayer:(CALayer *)layer
{
    // EmulationView navigates and calls this almost immediately after start() returns, well
    // before the background thread below reaches windows_emulator's own (much slower)
    // construction and assigns _ui -- so _ui is routinely still null here. Remember the layer
    // in _layer regardless, and apply it once _ui exists (see the assignment further down),
    // instead of silently dropping this call forever.
    sogen::ios_ui_backend* ui = nullptr;
    @synchronized(self)
    {
        _layer = layer;
        ui = _ui;
    }
    if (ui)
    {
        ui->set_layer(layer);
    }
}

@end
