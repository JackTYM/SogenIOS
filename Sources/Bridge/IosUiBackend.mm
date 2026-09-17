#import "IosUiBackend.hpp"

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace sogen
{
    namespace
    {
        void release_pixel_copy(void* /*info*/, const void* data, size_t /*size*/)
        {
            std::free(const_cast<void*>(data));
        }
    }

    ios_ui_backend::ios_ui_backend(CALayer* layer)
        : layer_(layer)
    {
    }

    ios_ui_backend::~ios_ui_backend()
    {
        if (this->last_image_ != nullptr)
        {
            CGImageRelease(this->last_image_);
        }
    }

    void ios_ui_backend::set_event_sink(event_sink sink)
    {
        this->event_sink_ = std::move(sink);
    }

    void ios_ui_backend::set_raw_mouse_sink(raw_mouse_sink sink)
    {
        this->raw_mouse_sink_ = std::move(sink);
    }

    void ios_ui_backend::set_mouse_move_sink(mouse_move_sink sink)
    {
        this->mouse_move_sink_ = std::move(sink);
    }

    void ios_ui_backend::set_mouse_button_sink(mouse_button_sink sink)
    {
        this->mouse_button_sink_ = std::move(sink);
    }

    void ios_ui_backend::set_log_sink(log_sink sink)
    {
        this->log_sink_ = std::move(sink);
    }

    void ios_ui_backend::set_frame_size_sink(frame_size_sink sink)
    {
        this->frame_size_sink_ = std::move(sink);
    }

    void ios_ui_backend::set_layer(CALayer* layer)
    {
        CGImageRef cached_image = nullptr;
        {
            const std::lock_guard<std::mutex> lock(this->mutex_);
            this->layer_ = layer;
            cached_image = this->last_image_;
            if (cached_image != nullptr)
            {
                CGImageRetain(cached_image);
            }
        }

        this->emit_log("[ios-ui] set_layer layer=%p cached_image=%s", (__bridge void*)layer,
                       cached_image != nullptr ? "yes" : "no");

        if (cached_image == nullptr)
        {
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
          [CATransaction begin];
          [CATransaction setDisableActions:YES];
          layer.magnificationFilter = kCAFilterNearest;
          layer.contents = (__bridge id)cached_image;
          [CATransaction commit];
          CGImageRelease(cached_image);
        });
    }

    void ios_ui_backend::emit_log(const char* format, ...) const
    {
        char buffer[512];
        va_list args;
        va_start(args, format);
        std::vsnprintf(buffer, sizeof(buffer), format, args);
        va_end(args);

        if (this->log_sink_)
        {
            this->log_sink_(buffer);
        }
        else
        {
            std::fprintf(stderr, "%s\n", buffer);
        }
    }

    uint64_t ios_ui_backend::presented_frame_count() const
    {
        const std::lock_guard<std::mutex> lock(this->mutex_);
        return this->presented_frames_;
    }

    void ios_ui_backend::queue_left_click()
    {
        const std::lock_guard<std::mutex> lock(this->mutex_);
        this->pending_events_.push_back(
            {.type = queued_input_event::kind::raw_button, .button_flags = RI_MOUSE_LEFT_BUTTON_DOWN});
        this->pending_events_.push_back(
            {.type = queued_input_event::kind::raw_button, .button_flags = RI_MOUSE_LEFT_BUTTON_UP});
    }

    void ios_ui_backend::queue_right_click()
    {
        const std::lock_guard<std::mutex> lock(this->mutex_);
        this->pending_events_.push_back(
            {.type = queued_input_event::kind::raw_button, .button_flags = RI_MOUSE_RIGHT_BUTTON_DOWN});
        this->pending_events_.push_back(
            {.type = queued_input_event::kind::raw_button, .button_flags = RI_MOUSE_RIGHT_BUTTON_UP});
    }

    void ios_ui_backend::queue_mouse_delta(const int32_t dx, const int32_t dy)
    {
        const std::lock_guard<std::mutex> lock(this->mutex_);
        this->pending_events_.push_back({.type = queued_input_event::kind::raw_delta, .dx = dx, .dy = dy});
    }

    void ios_ui_backend::queue_mouse_move(const int32_t x, const int32_t y)
    {
        const std::lock_guard<std::mutex> lock(this->mutex_);
        this->pending_events_.push_back({.type = queued_input_event::kind::absolute_move, .x = x, .y = y});
    }

    void ios_ui_backend::queue_mouse_button(const int32_t x, const int32_t y, const uint32_t message)
    {
        const std::lock_guard<std::mutex> lock(this->mutex_);
        this->pending_events_.push_back(
            {.type = queued_input_event::kind::absolute_button, .x = x, .y = y, .message = message});
    }

    void ios_ui_backend::pump_events()
    {
        std::vector<queued_input_event> events{};
        {
            const std::lock_guard<std::mutex> lock(this->mutex_);
            events.swap(this->pending_events_);
        }

        for (const auto& event : events)
        {
            switch (event.type)
            {
            case queued_input_event::kind::raw_button:
                this->emit_log("[ios-ui] delivering raw mouse input flags=0x%04X", event.button_flags);
                if (this->raw_mouse_sink_)
                {
                    // dx/dy are 0: this is a button transition, not motion. button_data is the
                    // wheel delta in RAWMOUSE and is 0 for every non-wheel transition.
                    this->raw_mouse_sink_(0, 0, event.button_flags, 0);
                }
                break;
            case queued_input_event::kind::raw_delta:
                if (this->raw_mouse_sink_)
                {
                    this->raw_mouse_sink_(event.dx, event.dy, 0, 0);
                }
                break;
            case queued_input_event::kind::absolute_move:
                this->emit_log("[ios-ui] delivering positioned mouse move x=%d y=%d", event.x, event.y);
                if (this->mouse_move_sink_)
                {
                    this->mouse_move_sink_(event.x, event.y);
                }
                break;
            case queued_input_event::kind::absolute_button:
                this->emit_log("[ios-ui] delivering positioned mouse button message=0x%04X x=%d y=%d", event.message,
                               event.x, event.y);
                if (this->mouse_button_sink_)
                {
                    this->mouse_button_sink_(event.x, event.y, event.message);
                }
                break;
            }
        }
    }

    void ios_ui_backend::present_surface(const hwnd window, const ui_surface_desc& surface)
    {
        if (surface.pixels == nullptr || surface.width <= 0 || surface.height <= 0 ||
            surface.stride < surface.width * 4)
        {
            this->emit_log("[ios-ui] skipping malformed surface %dx%d stride=%d pixels=%p", surface.width,
                           surface.height, surface.stride, surface.pixels);
            return;
        }

        CGBitmapInfo bitmap_info = 0;
        switch (surface.format)
        {
        case ui_surface_format::bgra8:
            // Memory order B,G,R,A == a little-endian 0xAARRGGBB word; the alpha byte is ignored.
            bitmap_info = kCGBitmapByteOrder32Little |
                          static_cast<CGBitmapInfo>(kCGImageAlphaNoneSkipFirst);
            break;
        case ui_surface_format::rgba8:
            bitmap_info = kCGBitmapByteOrder32Big |
                          static_cast<CGBitmapInfo>(kCGImageAlphaNoneSkipLast);
            break;
        default:
            this->emit_log("[ios-ui] skipping frame with unsupported format %d",
                           static_cast<int>(surface.format));
            return;
        }

        const auto stride = static_cast<size_t>(surface.stride);
        const auto byte_count = stride * static_cast<size_t>(surface.height);

        auto* copy = static_cast<uint8_t*>(std::malloc(byte_count));
        if (copy == nullptr)
        {
            this->emit_log("[ios-ui] out of memory copying %zu-byte frame", byte_count);
            return;
        }
        std::memcpy(copy, surface.pixels, byte_count);

        uint64_t frame_index = 0;
        bool size_changed = false;
        {
            const std::lock_guard<std::mutex> lock(this->mutex_);
            frame_index = this->presented_frames_++;
            size_changed = surface.width != this->last_frame_width_ || surface.height != this->last_frame_height_;
            this->last_frame_width_ = surface.width;
            this->last_frame_height_ = surface.height;
        }

        if (size_changed && this->frame_size_sink_)
        {
            this->frame_size_sink_(surface.width, surface.height);
        }

        this->emit_log("[ios-ui] frame %llu hwnd=0x%llX %dx%d stride=%d fmt=%d first_pixel=%02X%02X%02X%02X",
                       static_cast<unsigned long long>(frame_index),
                       static_cast<unsigned long long>(window), surface.width, surface.height,
                       surface.stride, static_cast<int>(surface.format), copy[0], copy[1], copy[2], copy[3]);

        CGDataProviderRef provider =
            CGDataProviderCreateWithData(nullptr, copy, byte_count, &release_pixel_copy);
        CGColorSpaceRef color_space = CGColorSpaceCreateDeviceRGB();
        CGImageRef image = CGImageCreate(static_cast<size_t>(surface.width), static_cast<size_t>(surface.height),
                                         8, 32, stride, color_space, bitmap_info, provider, nullptr, false,
                                         kCGRenderingIntentDefault);
        CGColorSpaceRelease(color_space);
        CGDataProviderRelease(provider);

        if (image == nullptr)
        {
            this->emit_log("[ios-ui] CGImageCreate failed for frame %llu",
                           static_cast<unsigned long long>(frame_index));
            return;
        }

        CALayer* layer;
        CGImageRef previous_last_image;
        {
            // set_layer() can re-point layer_ from the UI thread while this runs on the emulator
            // thread -- must read/write both under mutex_.
            const std::lock_guard<std::mutex> lock(this->mutex_);
            layer = this->layer_;
            previous_last_image = this->last_image_;
            this->last_image_ = image;
            CGImageRetain(this->last_image_);
        }
        if (previous_last_image != nullptr)
        {
            CGImageRelease(previous_last_image);
        }

        dispatch_async(dispatch_get_main_queue(), ^{
          [CATransaction begin];
          [CATransaction setDisableActions:YES];
          layer.magnificationFilter = kCAFilterNearest;
          layer.contents = (__bridge id)image;
          [CATransaction commit];
          CGImageRelease(image);
        });
    }
}
