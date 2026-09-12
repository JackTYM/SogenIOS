#pragma once

#import <QuartzCore/QuartzCore.h>

#include <platform/ui_backend.hpp>

#include <cstdint>
#include <functional>
#include <mutex>
#include <vector>

namespace sogen
{
    // Presents guest frames into a CALayer and feeds queued host taps back into the emulator.
    //
    // Threading: the emulator's run thread calls present_surface() and pump_events(); the UI
    // thread calls queue_left_click(). deliver_raw_mouse_input() is NOT safe to call from the UI
    // thread (windows_emulator::deliver_raw_input touches process state without kernel_lock_),
    // so taps are queued here and replayed from inside pump_events(), which start()'s run loop
    // invokes on the emulator thread with the kernel lock released.
    class ios_ui_backend final : public ui_backend
    {
      public:
        using raw_mouse_sink = std::function<void(int32_t dx, int32_t dy, uint16_t button_flags, uint16_t button_data)>;
        using log_sink = std::function<void(const char* line)>;

        explicit ios_ui_backend(CALayer* layer);
        ~ios_ui_backend() override;

        void set_event_sink(event_sink sink) override;
        void pump_events() override;
        void present_surface(hwnd window, const ui_surface_desc& surface) override;

        void set_raw_mouse_sink(raw_mouse_sink sink);
        void set_log_sink(log_sink sink);
        void queue_left_click();

        uint64_t presented_frame_count() const;

      private:
        void emit_log(const char* format, ...) const __attribute__((format(printf, 2, 3)));

        CALayer* layer_{};
        event_sink event_sink_{};
        raw_mouse_sink raw_mouse_sink_{};
        log_sink log_sink_{};

        mutable std::mutex mutex_{};
        std::vector<uint16_t> pending_button_flags_{};
        uint64_t presented_frames_{};
    };
}
