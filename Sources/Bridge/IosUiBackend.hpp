#pragma once

#import <QuartzCore/QuartzCore.h>

#include <platform/ui_backend.hpp>

#include <cstdint>
#include <functional>
#include <mutex>
#include <vector>

namespace sogen
{
    // Presents guest frames into a CALayer and feeds queued host input back into the emulator.
    //
    // Threading: the emulator's run thread calls present_surface() and pump_events(); the UI
    // thread calls the queue_*() methods below. Calling deliver_raw_mouse_input/
    // deliver_mouse_move/deliver_mouse_button directly from the UI thread is NOT safe
    // (windows_emulator's delivery functions touch process state without kernel_lock_), so every
    // host input event is queued here and replayed from inside pump_events(), which start()'s
    // run loop invokes on the emulator thread with the kernel lock released.
    class ios_ui_backend final : public ui_backend
    {
      public:
        using raw_mouse_sink = std::function<void(int32_t dx, int32_t dy, uint16_t button_flags, uint16_t button_data)>;
        using mouse_move_sink = std::function<void(int32_t x, int32_t y)>;
        using mouse_button_sink = std::function<void(int32_t x, int32_t y, uint32_t message)>;
        using log_sink = std::function<void(const char* line)>;
        using frame_size_sink = std::function<void(int32_t width, int32_t height)>;

        explicit ios_ui_backend(CALayer* layer);
        ~ios_ui_backend() override;

        void set_event_sink(event_sink sink) override;
        void pump_events() override;
        void present_surface(hwnd window, const ui_surface_desc& surface) override;

        void set_raw_mouse_sink(raw_mouse_sink sink);
        void set_mouse_move_sink(mouse_move_sink sink);
        void set_mouse_button_sink(mouse_button_sink sink);
        void set_log_sink(log_sink sink);
        void set_frame_size_sink(frame_size_sink sink);
        void set_layer(CALayer* layer);

        // Existing raw-input queuing (trackpad mode / games).
        void queue_left_click();
        void queue_right_click();
        void queue_mouse_delta(int32_t dx, int32_t dy);

        // New positioned queuing (touchscreen mode).
        void queue_mouse_move(int32_t x, int32_t y);
        void queue_mouse_button(int32_t x, int32_t y, uint32_t message);

        uint64_t presented_frame_count() const;

      private:
        void emit_log(const char* format, ...) const __attribute__((format(printf, 2, 3)));

        struct queued_input_event
        {
            enum class kind : uint8_t
            {
                raw_button,
                raw_delta,
                absolute_move,
                absolute_button,
            } type;
            int32_t dx{};
            int32_t dy{};
            uint16_t button_flags{};
            uint16_t button_data{};
            int32_t x{};
            int32_t y{};
            uint32_t message{};
        };

        CALayer* layer_{};
        event_sink event_sink_{};
        raw_mouse_sink raw_mouse_sink_{};
        mouse_move_sink mouse_move_sink_{};
        mouse_button_sink mouse_button_sink_{};
        log_sink log_sink_{};
        frame_size_sink frame_size_sink_{};

        mutable std::mutex mutex_{};
        std::vector<queued_input_event> pending_events_{};
        uint64_t presented_frames_{};
        int32_t last_frame_width_{};
        int32_t last_frame_height_{};
    };
}
