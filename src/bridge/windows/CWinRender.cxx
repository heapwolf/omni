// src/bridge/windows/CWinRender.cxx: see CWinRender.h.
#include "CWinRender.h"

// std::min and std::max, not windows.h's macros.
#define NOMINMAX

#include <windows.h>
#include <d2d1.h>
#include <d2d1helper.h>
#include <dwrite.h>
#include <dwrite_3.h>
#include <wincodec.h>
#include <wrl/client.h>
#include <string>
#include <vector>
#include <unordered_map>
#include <algorithm>
#include <cfloat>

#pragma comment(lib, "d2d1.lib")
#pragma comment(lib, "dwrite.lib")
#pragma comment(lib, "windowscodecs.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "dispatch.lib")
// What src/ui/windows calls through WinSDK: the common controls (task dialogs,
// visual styles), DWM (dark title bars, rounded sheets), UxTheme (dark controls).
#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "dwmapi.lib")
#pragma comment(lib, "uxtheme.lib")
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "gdi32.lib")
#pragma comment(lib, "advapi32.lib")

using Microsoft::WRL::ComPtr;

// libdispatch's main-queue SPI, which CoreFoundation's run loop uses. Exported
// by dispatch.dll on Windows; there the handle is an event.
extern "C" __declspec(dllimport) HANDLE _dispatch_get_main_queue_handle_4CF(void);
extern "C" __declspec(dllimport) void _dispatch_main_queue_callback_4CF(void*);

namespace {

ComPtr<ID2D1Factory> d2d;
ComPtr<IDWriteFactory> dwrite;
ComPtr<IWICImagingFactory> wic;
// Fonts the app registered (Font.register), before the system's.
ComPtr<IDWriteFontCollection1> appFonts;
std::vector<std::wstring> appFontFiles;

void ensureFactories() {
    if (!d2d) D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, d2d.GetAddressOf());
    if (!dwrite) {
        DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory),
                            reinterpret_cast<IUnknown**>(dwrite.GetAddressOf()));
    }
    if (!wic) {
        CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
        CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(wic.GetAddressOf()));
    }
}

D2D1_COLOR_F color(float r, float g, float b, float a) { return D2D1::ColorF(r, g, b, a); }

struct Target {
    HWND hwnd;
    ComPtr<ID2D1HwndRenderTarget> rt;
    ComPtr<ID2D1SolidColorBrush> brush;
    // What each push was, so each pop undoes the right one.
    std::vector<int> clips; // 0 axis-aligned, 1 layer
    UINT32 width = 0, height = 0;
    uint64_t generation = 0;

    bool ensure() {
        if (rt) return true;
        static uint64_t generations = 0;
        generation = ++generations;
        ensureFactories();
        RECT rc;
        GetClientRect(hwnd, &rc);
        width = std::max<UINT32>(1, rc.right - rc.left);
        height = std::max<UINT32>(1, rc.bottom - rc.top);
        auto props = D2D1::RenderTargetProperties(D2D1_RENDER_TARGET_TYPE_DEFAULT,
            D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED));
        auto hwndProps = D2D1::HwndRenderTargetProperties(hwnd, D2D1::SizeU(width, height),
                                                          D2D1_PRESENT_OPTIONS_NONE);
        if (FAILED(d2d->CreateHwndRenderTarget(props, hwndProps, rt.GetAddressOf()))) return false;
        rt->SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE);
        rt->CreateSolidColorBrush(color(0, 0, 0, 1), brush.GetAddressOf());
        return true;
    }

    ID2D1SolidColorBrush* paint(float r, float g, float b, float a) {
        brush->SetColor(color(r, g, b, a));
        return brush.Get();
    }
};

Target* T(void* p) { return static_cast<Target*>(p); }

ComPtr<ID2D1Geometry> roundedGeometry(float x, float y, float w, float h, float radius) {
    ComPtr<ID2D1Geometry> geometry;
    if (radius > 0) {
        ComPtr<ID2D1RoundedRectangleGeometry> rounded;
        float r = std::min(radius, std::min(w, h) / 2);
        d2d->CreateRoundedRectangleGeometry(D2D1::RoundedRect(D2D1::RectF(x, y, x + w, y + h), r, r),
                                            rounded.GetAddressOf());
        geometry = rounded;
    } else {
        ComPtr<ID2D1RectangleGeometry> rect;
        d2d->CreateRectangleGeometry(D2D1::RectF(x, y, x + w, y + h), rect.GetAddressOf());
        geometry = rect;
    }
    return geometry;
}

// MARK: Paths

struct Path {
    ComPtr<ID2D1PathGeometry> geometry;
    ComPtr<ID2D1GeometrySink> sink;
    bool open = false;
    D2D1_POINT_2F current{0, 0};

    void end(bool closed) {
        if (open) {
            sink->EndFigure(closed ? D2D1_FIGURE_END_CLOSED : D2D1_FIGURE_END_OPEN);
            open = false;
        }
    }
    void begin(D2D1_POINT_2F at) {
        end(false);
        sink->BeginFigure(at, D2D1_FIGURE_BEGIN_FILLED);
        open = true;
        current = at;
    }
    void ensureOpen() { if (!open) begin(current); }
    ID2D1Geometry* finish() {
        if (sink) {
            end(false);
            sink->Close();
            sink.Reset();
        }
        return geometry.Get();
    }
};

Path* P(void* p) { return static_cast<Path*>(p); }

// MARK: Images

struct Image {
    ComPtr<IWICBitmapSource> source;
    UINT width = 0, height = 0;
    // Device bitmaps, one per render target that drew this.
    // Keyed by the target's generation: a target made again (device lost) at the
    // same address must not draw the old one's bitmaps.
    std::unordered_map<uint64_t, ComPtr<ID2D1Bitmap>> bitmaps;
};

Image* imageFrom(ComPtr<IWICBitmapDecoder> decoder, uint32_t* w, uint32_t* h) {
    ComPtr<IWICBitmapFrameDecode> frame;
    if (FAILED(decoder->GetFrame(0, frame.GetAddressOf()))) return nullptr;
    ComPtr<IWICFormatConverter> converter;
    if (FAILED(wic->CreateFormatConverter(converter.GetAddressOf()))) return nullptr;
    if (FAILED(converter->Initialize(frame.Get(), GUID_WICPixelFormat32bppPBGRA, WICBitmapDitherTypeNone,
                                     nullptr, 0, WICBitmapPaletteTypeMedianCut))) return nullptr;
    // Decoded once, here, rather than every time a target makes its bitmap.
    ComPtr<IWICBitmap> bitmap;
    if (FAILED(wic->CreateBitmapFromSource(converter.Get(), WICBitmapCacheOnLoad, bitmap.GetAddressOf()))) return nullptr;
    auto image = new Image();
    image->source = bitmap;
    bitmap->GetSize(&image->width, &image->height);
    if (w) *w = image->width;
    if (h) *h = image->height;
    return image;
}

// MARK: Text

ComPtr<IDWriteTextFormat> format(const wchar_t* family, float size, int weight, int italic) {
    static std::unordered_map<std::wstring, ComPtr<IDWriteTextFormat>> cache;
    std::wstring key = std::wstring(family) + L"|" + std::to_wstring(size) + L"|" + std::to_wstring(weight)
        + L"|" + std::to_wstring(italic);
    auto found = cache.find(key);
    if (found != cache.end()) return found->second;

    IDWriteFontCollection* collection = nullptr;
    if (appFonts) {
        UINT32 index;
        BOOL exists = FALSE;
        appFonts->FindFamilyName(family, &index, &exists);
        if (exists) collection = appFonts.Get();
    }
    ComPtr<IDWriteTextFormat> made;
    dwrite->CreateTextFormat(family, collection, static_cast<DWRITE_FONT_WEIGHT>(weight),
                             italic ? DWRITE_FONT_STYLE_ITALIC : DWRITE_FONT_STYLE_NORMAL,
                             DWRITE_FONT_STRETCH_NORMAL, size, L"", made.GetAddressOf());
    cache[key] = made;
    return made;
}

// Segoe UI Variable is Windows 11's; Segoe UI is everywhere else.
const wchar_t* defaultFamily() {
    static std::wstring family;
    if (family.empty()) {
        ensureFactories();
        ComPtr<IDWriteFontCollection> system;
        dwrite->GetSystemFontCollection(system.GetAddressOf());
        UINT32 index;
        BOOL exists = FALSE;
        if (system) system->FindFamilyName(L"Segoe UI Variable Text", &index, &exists);
        family = exists ? L"Segoe UI Variable Text" : L"Segoe UI";
    }
    return family.c_str();
}

} // namespace

extern "C" {

// MARK: Targets

void* omni_r_target_create(void* hwnd) {
    auto t = new Target();
    t->hwnd = static_cast<HWND>(hwnd);
    t->ensure();
    return t;
}

void omni_r_target_destroy(void* target) { delete T(target); }

void omni_r_target_resize(void* target, uint32_t pw, uint32_t ph) {
    auto t = T(target);
    t->width = std::max<uint32_t>(1, pw);
    t->height = std::max<uint32_t>(1, ph);
    if (t->rt) t->rt->Resize(D2D1::SizeU(t->width, t->height));
}

void omni_r_begin(void* target, float dpi) {
    auto t = T(target);
    t->ensure();
    t->rt->SetDpi(dpi, dpi);
    t->rt->BeginDraw();
    t->rt->SetTransform(D2D1::Matrix3x2F::Identity());
    t->clips.clear();
}

int omni_r_end(void* target) {
    auto t = T(target);
    while (!t->clips.empty()) omni_r_pop_clip(target);
    HRESULT hr = t->rt->EndDraw();
    if (hr == D2DERR_RECREATE_TARGET) {
        t->brush.Reset();
        t->rt.Reset();
        return 1;
    }
    return 0;
}

void omni_r_clear(void* target, float r, float g, float b, float a) {
    T(target)->rt->Clear(color(r, g, b, a));
}

void omni_r_set_transform(void* target, float a, float b, float c, float d, float tx, float ty) {
    T(target)->rt->SetTransform(D2D1::Matrix3x2F(a, b, c, d, tx, ty));
}

void omni_r_push_clip(void* target, float x, float y, float w, float h, float radius) {
    auto t = T(target);
    if (radius <= 0) {
        t->rt->PushAxisAlignedClip(D2D1::RectF(x, y, x + w, y + h), D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
        t->clips.push_back(0);
        return;
    }
    auto geometry = roundedGeometry(x, y, w, h, radius);
    t->rt->PushLayer(D2D1::LayerParameters(D2D1::InfiniteRect(), geometry.Get()), nullptr);
    t->clips.push_back(1);
}

void omni_r_pop_clip(void* target) {
    auto t = T(target);
    if (t->clips.empty()) return;
    if (t->clips.back() == 0) t->rt->PopAxisAlignedClip(); else t->rt->PopLayer();
    t->clips.pop_back();
}

void omni_r_push_opacity(void* target, float opacity) {
    auto t = T(target);
    t->rt->PushLayer(D2D1::LayerParameters(D2D1::InfiniteRect(), nullptr, D2D1_ANTIALIAS_MODE_PER_PRIMITIVE,
                                           D2D1::IdentityMatrix(), opacity), nullptr);
    t->clips.push_back(1);
}

void omni_r_pop_opacity(void* target) { omni_r_pop_clip(target); }

// MARK: Shapes

void omni_r_fill_rrect(void* target, float x, float y, float w, float h, float radius,
                       float r, float g, float b, float a) {
    auto t = T(target);
    if (w <= 0 || h <= 0 || a <= 0) return;
    auto rect = D2D1::RectF(x, y, x + w, y + h);
    if (radius > 0) {
        float rr = std::min(radius, std::min(w, h) / 2);
        t->rt->FillRoundedRectangle(D2D1::RoundedRect(rect, rr, rr), t->paint(r, g, b, a));
    } else {
        t->rt->FillRectangle(rect, t->paint(r, g, b, a));
    }
}

void omni_r_stroke_rrect(void* target, float x, float y, float w, float h, float radius, float width,
                         float r, float g, float b, float a) {
    auto t = T(target);
    if (w <= 0 || h <= 0 || a <= 0 || width <= 0) return;
    // Inside the bounds, as SwiftUI's .border and strokeBorder draw.
    float inset = width / 2;
    auto rect = D2D1::RectF(x + inset, y + inset, x + w - inset, y + h - inset);
    if (radius > 0) {
        float rr = std::max(0.0f, std::min(radius, std::min(w, h) / 2) - inset);
        t->rt->DrawRoundedRectangle(D2D1::RoundedRect(rect, rr, rr), t->paint(r, g, b, a), width);
    } else {
        t->rt->DrawRectangle(rect, t->paint(r, g, b, a), width);
    }
}

void omni_r_fill_ellipse(void* target, float cx, float cy, float rx, float ry,
                         float r, float g, float b, float a) {
    auto t = T(target);
    t->rt->FillEllipse(D2D1::Ellipse(D2D1::Point2F(cx, cy), rx, ry), t->paint(r, g, b, a));
}

void omni_r_stroke_ellipse(void* target, float cx, float cy, float rx, float ry, float width,
                           float r, float g, float b, float a) {
    auto t = T(target);
    t->rt->DrawEllipse(D2D1::Ellipse(D2D1::Point2F(cx, cy), rx, ry), t->paint(r, g, b, a), width);
}

void omni_r_line(void* target, float x1, float y1, float x2, float y2, float width,
                 float r, float g, float b, float a) {
    auto t = T(target);
    t->rt->DrawLine(D2D1::Point2F(x1, y1), D2D1::Point2F(x2, y2), t->paint(r, g, b, a), width);
}

void omni_r_gradient_rrect(void* target, float x, float y, float w, float h, float radius,
                           float x0, float y0, float x1, float y1, const float* stops, int count) {
    auto t = T(target);
    if (count < 1 || w <= 0 || h <= 0) return;
    std::vector<D2D1_GRADIENT_STOP> list(count);
    for (int i = 0; i < count; i++) {
        const float* s = stops + i * 5;
        list[i].position = s[0];
        list[i].color = color(s[1], s[2], s[3], s[4]);
    }
    ComPtr<ID2D1GradientStopCollection> collection;
    if (FAILED(t->rt->CreateGradientStopCollection(list.data(), count, collection.GetAddressOf()))) return;
    ComPtr<ID2D1LinearGradientBrush> brush;
    if (FAILED(t->rt->CreateLinearGradientBrush(
            D2D1::LinearGradientBrushProperties(D2D1::Point2F(x0, y0), D2D1::Point2F(x1, y1)),
            collection.Get(), brush.GetAddressOf()))) return;
    auto rect = D2D1::RectF(x, y, x + w, y + h);
    if (radius > 0) {
        float rr = std::min(radius, std::min(w, h) / 2);
        t->rt->FillRoundedRectangle(D2D1::RoundedRect(rect, rr, rr), brush.Get());
    } else {
        t->rt->FillRectangle(rect, brush.Get());
    }
}

// MARK: Paths

void* omni_r_path_create(void) {
    ensureFactories();
    auto p = new Path();
    d2d->CreatePathGeometry(p->geometry.GetAddressOf());
    p->geometry->Open(p->sink.GetAddressOf());
    p->sink->SetFillMode(D2D1_FILL_MODE_WINDING);
    return p;
}

void omni_r_path_move(void* path, float x, float y) {
    auto p = P(path);
    if (p->sink) p->begin(D2D1::Point2F(x, y));
}

void omni_r_path_line(void* path, float x, float y) {
    auto p = P(path);
    if (!p->sink) return;
    p->ensureOpen();
    p->sink->AddLine(D2D1::Point2F(x, y));
    p->current = D2D1::Point2F(x, y);
}

void omni_r_path_quad(void* path, float cx, float cy, float x, float y) {
    auto p = P(path);
    if (!p->sink) return;
    p->ensureOpen();
    p->sink->AddQuadraticBezier(D2D1::QuadraticBezierSegment(D2D1::Point2F(cx, cy), D2D1::Point2F(x, y)));
    p->current = D2D1::Point2F(x, y);
}

void omni_r_path_cubic(void* path, float c1x, float c1y, float c2x, float c2y, float x, float y) {
    auto p = P(path);
    if (!p->sink) return;
    p->ensureOpen();
    p->sink->AddBezier(D2D1::BezierSegment(D2D1::Point2F(c1x, c1y), D2D1::Point2F(c2x, c2y), D2D1::Point2F(x, y)));
    p->current = D2D1::Point2F(x, y);
}

void omni_r_path_arc(void* path, float x, float y, float rx, float ry, float rotation, int large, int clockwise) {
    auto p = P(path);
    if (!p->sink) return;
    p->ensureOpen();
    p->sink->AddArc(D2D1::ArcSegment(D2D1::Point2F(x, y), D2D1::SizeF(rx, ry), rotation,
                                     clockwise ? D2D1_SWEEP_DIRECTION_CLOCKWISE : D2D1_SWEEP_DIRECTION_COUNTER_CLOCKWISE,
                                     large ? D2D1_ARC_SIZE_LARGE : D2D1_ARC_SIZE_SMALL));
    p->current = D2D1::Point2F(x, y);
}

void omni_r_path_close(void* path) {
    auto p = P(path);
    if (p->sink) p->end(true);
}

void omni_r_path_fill(void* target, void* path, float r, float g, float b, float a) {
    auto t = T(target);
    t->rt->FillGeometry(P(path)->finish(), t->paint(r, g, b, a));
}

void omni_r_path_stroke(void* target, void* path, float width, float r, float g, float b, float a) {
    auto t = T(target);
    t->rt->DrawGeometry(P(path)->finish(), t->paint(r, g, b, a), width);
}

void omni_r_path_release(void* path) { delete P(path); }

// MARK: Text

void* omni_t_layout(const uint16_t* text, int length, const uint16_t* family, float size, int weight,
                    int italic, float max_width, int align, int wrap, int line_limit, int trim,
                    float letter_spacing, float line_spacing, int strikethrough, int underline) {
    ensureFactories();
    const wchar_t* name = family && *family ? reinterpret_cast<const wchar_t*>(family) : defaultFamily();
    auto fmt = format(name, size, weight, italic);
    if (!fmt) fmt = format(defaultFamily(), size, weight, italic);
    if (!fmt) return nullptr;

    float width = max_width > 0 ? max_width : 100000.0f;
    ComPtr<IDWriteTextLayout> layout;
    if (FAILED(dwrite->CreateTextLayout(reinterpret_cast<const wchar_t*>(text), length, fmt.Get(),
                                        width, 100000.0f, layout.GetAddressOf()))) return nullptr;

    layout->SetWordWrapping(wrap ? DWRITE_WORD_WRAPPING_WRAP : DWRITE_WORD_WRAPPING_NO_WRAP);
    layout->SetTextAlignment(align == 1 ? DWRITE_TEXT_ALIGNMENT_CENTER
                             : align == 2 ? DWRITE_TEXT_ALIGNMENT_TRAILING : DWRITE_TEXT_ALIGNMENT_LEADING);
    DWRITE_TEXT_RANGE all{0, static_cast<UINT32>(length)};
    if (strikethrough) layout->SetStrikethrough(TRUE, all);
    if (underline) layout->SetUnderline(TRUE, all);
    if (letter_spacing != 0) {
        ComPtr<IDWriteTextLayout1> layout1;
        if (SUCCEEDED(layout.As(&layout1))) layout1->SetCharacterSpacing(0, letter_spacing, 0, all);
    }
    if (line_spacing > 0) {
        // Extra space between lines: the font's own line height plus it.
        DWRITE_LINE_METRICS line{};
        UINT32 count = 0;
        layout->GetLineMetrics(&line, 1, &count);
        if (count > 0) {
            float height = line.height + line_spacing;
            layout->SetLineSpacing(DWRITE_LINE_SPACING_METHOD_UNIFORM, height, line.baseline + line_spacing / 2);
        }
    }

    if (trim != 0 && max_width > 0) {
        DWRITE_TRIMMING trimming{DWRITE_TRIMMING_GRANULARITY_CHARACTER, 0, 0};
        ComPtr<IDWriteInlineObject> ellipsis;
        dwrite->CreateEllipsisTrimmingSign(fmt.Get(), ellipsis.GetAddressOf());
        layout->SetTrimming(&trimming, ellipsis.Get());
    }

    // At most line_limit lines: the layout's height ends after the last, and
    // the trimming sign goes on it.
    if (line_limit > 0) {
        UINT32 count = 0;
        layout->GetLineMetrics(nullptr, 0, &count);
        if (count > static_cast<UINT32>(line_limit)) {
            std::vector<DWRITE_LINE_METRICS> lines(count);
            layout->GetLineMetrics(lines.data(), count, &count);
            float height = 0;
            for (int i = 0; i < line_limit; i++) height += lines[i].height;
            layout->SetMaxHeight(height);
            if (trim == 0) {
                DWRITE_TRIMMING trimming{DWRITE_TRIMMING_GRANULARITY_CHARACTER, 0, 0};
                ComPtr<IDWriteInlineObject> ellipsis;
                dwrite->CreateEllipsisTrimmingSign(fmt.Get(), ellipsis.GetAddressOf());
                layout->SetTrimming(&trimming, ellipsis.Get());
            }
        }
    }
    return layout.Detach();
}

void omni_t_metrics(void* layout, float* width, float* height, float* baseline) {
    auto l = static_cast<IDWriteTextLayout*>(layout);
    DWRITE_TEXT_METRICS m{};
    l->GetMetrics(&m);
    // widthIncludingTrailingWhitespace keeps "a " wider than "a", as on Apple.
    if (width) *width = m.widthIncludingTrailingWhitespace;
    float h = m.height;
    if (l->GetMaxHeight() < h) h = l->GetMaxHeight();
    if (height) *height = h;
    if (baseline) {
        DWRITE_LINE_METRICS line{};
        UINT32 count = 0;
        l->GetLineMetrics(&line, 1, &count);
        *baseline = count > 0 ? line.baseline : 0;
    }
}

void omni_t_draw(void* target, void* layout, float x, float y, float r, float g, float b, float a) {
    auto t = T(target);
    t->rt->DrawTextLayout(D2D1::Point2F(x, y), static_cast<IDWriteTextLayout*>(layout), t->paint(r, g, b, a),
                          D2D1_DRAW_TEXT_OPTIONS_ENABLE_COLOR_FONT | D2D1_DRAW_TEXT_OPTIONS_CLIP);
}

void omni_t_release(void* layout) {
    if (layout) static_cast<IDWriteTextLayout*>(layout)->Release();
}

int omni_t_register_font(const uint16_t* path) {
    ensureFactories();
    ComPtr<IDWriteFactory5> factory5;
    if (FAILED(dwrite.As(&factory5))) return 0;
    std::wstring file(reinterpret_cast<const wchar_t*>(path));
    if (GetFileAttributesW(file.c_str()) == INVALID_FILE_ATTRIBUTES) return 0;
    appFontFiles.push_back(file);

    // A collection can't be added to: made again from every file so far.
    ComPtr<IDWriteFontSetBuilder1> builder;
    if (FAILED(factory5->CreateFontSetBuilder(builder.GetAddressOf()))) return 0;
    for (auto& f : appFontFiles) {
        ComPtr<IDWriteFontFile> fontFile;
        if (SUCCEEDED(factory5->CreateFontFileReference(f.c_str(), nullptr, fontFile.GetAddressOf()))) {
            builder->AddFontFile(fontFile.Get());
        }
    }
    ComPtr<IDWriteFontSet> set;
    if (FAILED(builder->CreateFontSet(set.GetAddressOf()))) return 0;
    ComPtr<IDWriteFontCollection1> collection;
    if (FAILED(factory5->CreateFontCollectionFromFontSet(set.Get(), collection.GetAddressOf()))) return 0;
    appFonts = collection;
    return 1;
}

// MARK: Images

void* omni_i_load_file(const uint16_t* path, uint32_t* width, uint32_t* height) {
    ensureFactories();
    if (!wic) return nullptr;
    ComPtr<IWICBitmapDecoder> decoder;
    if (FAILED(wic->CreateDecoderFromFilename(reinterpret_cast<const wchar_t*>(path), nullptr, GENERIC_READ,
                                              WICDecodeMetadataCacheOnDemand, decoder.GetAddressOf()))) return nullptr;
    return imageFrom(decoder, width, height);
}

void* omni_i_load_memory(const void* data, uint32_t length, uint32_t* width, uint32_t* height) {
    ensureFactories();
    if (!wic) return nullptr;
    ComPtr<IWICStream> stream;
    if (FAILED(wic->CreateStream(stream.GetAddressOf()))) return nullptr;
    // WIC reads the bytes where they are: copied, so the caller's may go.
    auto copy = new BYTE[length];
    memcpy(copy, data, length);
    if (FAILED(stream->InitializeFromMemory(copy, length))) { delete[] copy; return nullptr; }
    ComPtr<IWICBitmapDecoder> decoder;
    if (FAILED(wic->CreateDecoderFromStream(stream.Get(), nullptr, WICDecodeMetadataCacheOnLoad,
                                            decoder.GetAddressOf()))) { delete[] copy; return nullptr; }
    auto image = imageFrom(decoder, width, height);
    // CacheOnLoad: decoded into the WIC bitmap, so the bytes are no longer read.
    delete[] copy;
    return image;
}

void* omni_i_from_rgba(const void* pixels, uint32_t width, uint32_t height) {
    ensureFactories();
    if (!wic || width == 0 || height == 0) return nullptr;
    // Premultiplied BGRA, as D2D draws it.
    std::vector<BYTE> bgra(static_cast<size_t>(width) * height * 4);
    auto src = static_cast<const BYTE*>(pixels);
    for (size_t i = 0; i < static_cast<size_t>(width) * height; i++) {
        BYTE r = src[i * 4], g = src[i * 4 + 1], b = src[i * 4 + 2], a = src[i * 4 + 3];
        bgra[i * 4] = static_cast<BYTE>(b * a / 255);
        bgra[i * 4 + 1] = static_cast<BYTE>(g * a / 255);
        bgra[i * 4 + 2] = static_cast<BYTE>(r * a / 255);
        bgra[i * 4 + 3] = a;
    }
    ComPtr<IWICBitmap> bitmap;
    if (FAILED(wic->CreateBitmapFromMemory(width, height, GUID_WICPixelFormat32bppPBGRA, width * 4,
                                           static_cast<UINT>(bgra.size()), bgra.data(),
                                           bitmap.GetAddressOf()))) return nullptr;
    auto image = new Image();
    image->source = bitmap;
    image->width = width;
    image->height = height;
    return image;
}

void omni_i_draw(void* target, void* image, float x, float y, float w, float h, float opacity, int smooth) {
    auto t = T(target);
    auto img = static_cast<Image*>(image);
    if (!img || w <= 0 || h <= 0) return;
    auto& bitmap = img->bitmaps[t->generation];
    if (!bitmap) {
        if (FAILED(t->rt->CreateBitmapFromWicBitmap(img->source.Get(), nullptr, bitmap.GetAddressOf()))) return;
    }
    t->rt->DrawBitmap(bitmap.Get(), D2D1::RectF(x, y, x + w, y + h), opacity,
                      smooth ? D2D1_BITMAP_INTERPOLATION_MODE_LINEAR : D2D1_BITMAP_INTERPOLATION_MODE_NEAREST_NEIGHBOR);
}

void omni_i_release(void* image) { delete static_cast<Image*>(image); }

// MARK: The main queue

void* omni_main_queue_handle(void) { return _dispatch_get_main_queue_handle_4CF(); }
void omni_main_queue_drain(void) { _dispatch_main_queue_callback_4CF(nullptr); }

} // extern "C"
