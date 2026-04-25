// src/lib/CWindows/CWinBridge.cxx
#include "CWinBridge.h"
#include <windows.h>
#include <string>
#include <d2d1.h>
#include <unordered_map>
#include <wrl/client.h>
#include <commctrl.h>

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "d2d1.lib")

using Microsoft::WRL::ComPtr;

// D2D factory and render targets, keyed by HWND.
static ComPtr<ID2D1Factory> g_d2dFactory;
static std::unordered_map<HWND, ComPtr<ID2D1HwndRenderTarget>> g_renderTargets;

// Helper to initialize D2D Factory once
static void EnsureD2DFactory() {
    if (!g_d2dFactory) {
        D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, g_d2dFactory.GetAddressOf());
    }
}

// UTF-8 to UTF-16.
static std::wstring utf8_to_utf16(const char* utf8_str) {
    if (!utf8_str || !*utf8_str) return L"";
    int size_needed = MultiByteToWideChar(CP_UTF8, 0, utf8_str, -1, NULL, 0);
    if (size_needed <= 0) return L"";
    std::wstring result(size_needed, 0);
    MultiByteToWideChar(CP_UTF8, 0, utf8_str, -1, &result[0], size_needed);
    return result;
}

const wchar_t* OMNI_CLASS_NAME = L"OmniSwiftWindow";

// Routes Win32 messages back to Swift.
LRESULT CALLBACK OmniWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    OmniWindowEventCallback callback = nullptr;

    // Get or set the Swift callback pointer.
    if (msg == WM_NCCREATE) {
        CREATESTRUCTW* create = reinterpret_cast<CREATESTRUCTW*>(lParam);
        callback = reinterpret_cast<OmniWindowEventCallback>(create->lpCreateParams);
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(callback));
    } else {
        callback = reinterpret_cast<OmniWindowEventCallback>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    }

    if (callback) {
        switch (msg) {
            case WM_CLOSE:
                callback(hwnd, OMNI_WM_CLOSE, wParam, lParam);
                return 0; // Return 0 so Swift handles when to call omni_win_destroy

            case WM_DESTROY:
                PostQuitMessage(0);
                return 0;

            case WM_SIZE:
                callback(hwnd, OMNI_WM_SIZE, wParam, lParam);
                break; // Fall through for OS layout logic

            case WM_PAINT:
                callback(hwnd, OMNI_WM_PAINT, wParam, lParam);
                break;

            case WM_HSCROLL:
            case WM_VSCROLL:
                if (lParam != 0) { // If lParam is non-zero, it contains the HWND of the control
                    callback(hwnd, OMNI_WM_COMMAND, wParam, lParam);
                }
                break;

            case WM_COMMAND:
                // Control events.
                callback(hwnd, OMNI_WM_COMMAND, wParam, lParam);
                break;
        }
    }

    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

const wchar_t* OMNI_HSTACK_CLASS = L"OmniHStackWindow";

// Custom WndProc for the HStack Container
LRESULT CALLBACK OmniHStackWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    if (msg == WM_SIZE) {
        // Spacing, from the window's user data.
        int spacing = static_cast<int>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));

        RECT clientRect;
        GetClientRect(hwnd, &clientRect);
        int totalWidth = clientRect.right - clientRect.left;
        int height = clientRect.bottom - clientRect.top;

        // 1. Count visible children
        int childCount = 0;
        HWND child = GetWindow(hwnd, GW_CHILD);
        while (child) {
            if (IsWindowVisible(child)) childCount++;
            child = GetWindow(child, GW_HWNDNEXT);
        }

        // Distribute width (.fill).
        if (childCount > 0) {
            int totalSpacing = spacing * (childCount - 1);
            int childWidth = (totalWidth - totalSpacing) / childCount;
            if (childWidth < 0) childWidth = 0;

            int currentX = 0;
            child = GetWindow(hwnd, GW_CHILD);

            // 3. Apply layout to all children
            HDWP defer = BeginDeferWindowPos(childCount);
            while (child) {
                if (IsWindowVisible(child)) {
                    defer = DeferWindowPos(defer, child, NULL,
                        currentX, 0, childWidth, height,
                        SWP_NOZORDER | SWP_NOACTIVATE);
                    currentX += childWidth + spacing;
                }
                child = GetWindow(child, GW_HWNDNEXT);
            }
            EndDeferWindowPos(defer);
        }
        return 0;
    }

    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

const wchar_t* OMNI_SCROLL_CLASS = L"OmniScrollWindow";

LRESULT CALLBACK OmniScrollWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    bool isVertical = (GetWindowLongPtrW(hwnd, GWL_STYLE) & WS_VSCROLL) != 0;
    int bar = isVertical ? SB_VERT : SB_HORZ;

    auto updateScroll = [&](int action, int thumbPos) {
        SCROLLINFO si = { sizeof(si), SIF_ALL };
        GetScrollInfo(hwnd, bar, &si);
        int oldPos = si.nPos;

        switch (action) {
            case SB_LINEUP: si.nPos -= 20; break;
            case SB_LINEDOWN: si.nPos += 20; break;
            case SB_PAGEUP: si.nPos -= si.nPage; break;
            case SB_PAGEDOWN: si.nPos += si.nPage; break;
            case SB_THUMBTRACK: si.nPos = thumbPos; break;
        }

        // Clamp the scroll position
        int maxScroll = si.nMax - (int)si.nPage + 1;
        if (si.nPos > maxScroll) si.nPos = maxScroll;
        if (si.nPos < si.nMin) si.nPos = si.nMin;

        if (si.nPos != oldPos) {
            SetScrollPos(hwnd, bar, si.nPos, TRUE);

            // Move the child opposite the scroll.
            HWND child = GetWindow(hwnd, GW_CHILD);
            if (child) {
                int dx = isVertical ? 0 : -(si.nPos - oldPos);
                int dy = isVertical ? -(si.nPos - oldPos) : 0;

                RECT rc;
                GetWindowRect(child, &rc);
                MapWindowPoints(HWND_DESKTOP, hwnd, (LPPOINT)&rc, 2);
                SetWindowPos(child, NULL, rc.left + dx, rc.top + dy, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
            }

            // Scroll event, through the WM_COMMAND router; the HWND is the lParam.
            OmniWindowEventCallback callback = reinterpret_cast<OmniWindowEventCallback>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
            if (callback) callback(hwnd, OMNI_WM_COMMAND, 0, reinterpret_cast<LPARAM>(hwnd));
        }
    };

    switch (msg) {
        case WM_VSCROLL:
        case WM_HSCROLL:
            updateScroll(LOWORD(wParam), HIWORD(wParam));
            return 0;

        case WM_MOUSEWHEEL: {
            if (isVertical) {
                int delta = GET_WHEEL_DELTA_WPARAM(wParam);
                updateScroll(delta > 0 ? SB_LINEUP : SB_LINEDOWN, 0);
            }
            return 0;
        }
    }

    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

const wchar_t* OMNI_CLIP_CLASS = L"OmniClipWindow";

LRESULT CALLBACK OmniClipWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    if (msg == WM_SIZE) {
        // Packed state: bit 0 is_circular, bits 1+ radius.
        LONG_PTR state = GetWindowLongPtrW(hwnd, GWLP_USERDATA);
        bool is_circular = (state & 1) != 0;
        int radius = static_cast<int>(state >> 1);

        RECT rc;
        GetClientRect(hwnd, &rc);
        int width = rc.right - rc.left;
        int height = rc.bottom - rc.top;

        HRGN hRgn = NULL;
        if (is_circular) {
            int diameter = min(width, height);
            // Centre the circle in a non-square frame.
            int dx = (width - diameter) / 2;
            int dy = (height - diameter) / 2;
            hRgn = CreateEllipticRgn(dx, dy, dx + diameter, dy + diameter);
        } else if (radius > 0) {
            // CreateRoundRectRgn takes diameter, not radius.
            hRgn = CreateRoundRectRgn(0, 0, width + 1, height + 1, radius * 2, radius * 2);
        } else {
            // NULL clears the region.
            hRgn = NULL;
        }

        // The OS takes ownership of hRgn; do not delete it.
        SetWindowRgn(hwnd, hRgn, TRUE);

        // Resize children to match.
        HWND child = GetWindow(hwnd, GW_CHILD);
        if (child) {
            SetWindowPos(child, NULL, 0, 0, width, height, SWP_NOZORDER | SWP_NOACTIVATE);
        }

        return 0;
    }

    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

const wchar_t* OMNI_SPACER_CLASS = L"OmniSpacerWindow";

LRESULT CALLBACK OmniSpacerWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    // Transparent layout view; requires no custom message handling
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

const wchar_t* OMNI_SPLIT_CLASS = L"OmniSplitWindow";

struct SplitViewData {
    bool isVertical;      // true = vertical divider (left/right panes)
    float ratio;         // split ratio, 0.0 to 1.0 (default 0.5)
    bool isDragging;
    int dividerThickness;
};

LRESULT CALLBACK OmniSplitWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    SplitViewData* data = reinterpret_cast<SplitViewData*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));

    switch (msg) {
        case WM_SIZE: {
            if (!data) break;

            RECT rc;
            GetClientRect(hwnd, &rc);
            int totalWidth = rc.right - rc.left;
            int totalHeight = rc.bottom - rc.top;

            HWND child1 = GetWindow(hwnd, GW_CHILD);
            HWND child2 = child1 ? GetWindow(child1, GW_HWNDNEXT) : NULL;

            if (child1 && child2) {
                HDWP defer = BeginDeferWindowPos(2);

                if (data->isVertical) {
                    int splitX = static_cast<int>(totalWidth * data->ratio);
                    int pane1Width = splitX - (data->dividerThickness / 2);
                    int pane2X = splitX + (data->dividerThickness / 2);
                    int pane2Width = totalWidth - pane2X;

                    if (pane1Width < 0) pane1Width = 0;
                    if (pane2Width < 0) pane2Width = 0;

                    defer = DeferWindowPos(defer, child1, NULL, 0, 0, pane1Width, totalHeight, SWP_NOZORDER | SWP_NOACTIVATE);
                    defer = DeferWindowPos(defer, child2, NULL, pane2X, 0, pane2Width, totalHeight, SWP_NOZORDER | SWP_NOACTIVATE);
                } else {
                    int splitY = static_cast<int>(totalHeight * data->ratio);
                    int pane1Height = splitY - (data->dividerThickness / 2);
                    int pane2Y = splitY + (data->dividerThickness / 2);
                    int pane2Height = totalHeight - pane2Y;

                    if (pane1Height < 0) pane1Height = 0;
                    if (pane2Height < 0) pane2Height = 0;

                    defer = DeferWindowPos(defer, child1, NULL, 0, 0, totalWidth, pane1Height, SWP_NOZORDER | SWP_NOACTIVATE);
                    defer = DeferWindowPos(defer, child2, NULL, 0, pane2Y, totalWidth, pane2Height, SWP_NOZORDER | SWP_NOACTIVATE);
                }

                EndDeferWindowPos(defer);
            }
            return 0;
        }

        case WM_SETCURSOR: {
            if (!data) break;
            RECT rc;
            GetClientRect(hwnd, &rc);
            POINT pt;
            GetCursorPos(&pt);
            ScreenToClient(hwnd, &pt);

            int pos = data->isVertical ? pt.x : pt.y;
            int total = data->isVertical ? (rc.right - rc.left) : (rc.bottom - rc.top);
            int splitPos = static_cast<int>(total * data->ratio);

            // Check if cursor is over the divider bar
            if (abs(pos - splitPos) <= data->dividerThickness + 2) {
                SetCursor(LoadCursorW(NULL, data->isVertical ? IDC_SIZEWE : IDC_SIZENS));
                return TRUE;
            }
            break;
        }

        case WM_LBUTTONDOWN: {
            if (!data) break;
            SetCapture(hwnd);
            data->isDragging = true;
            return 0;
        }

        case WM_MOUSEMOVE: {
            if (data && data->isDragging) {
                RECT rc;
                GetClientRect(hwnd, &rc);
                int mousePos = data->isVertical ? GET_X_LPARAM(lParam) : GET_Y_LPARAM(lParam);
                int totalSize = data->isVertical ? (rc.right - rc.left) : (rc.bottom - rc.top);

                if (totalSize > 0) {
                    float newRatio = static_cast<float>(mousePos) / static_cast<float>(totalSize);
                    if (newRatio < 0.05f) newRatio = 0.05f;
                    if (newRatio > 0.95f) newRatio = 0.95f;

                    data->ratio = newRatio;
                    SendMessageW(hwnd, WM_SIZE, 0, MAKELPARAM(rc.right, rc.bottom));
                }
            }
            return 0;
        }

        case WM_LBUTTONUP: {
            if (data && data->isDragging) {
                ReleaseCapture();
                data->isDragging = false;
            }
            return 0;
        }

        case WM_NCDESTROY: {
            if (data) {
                delete data;
                SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
            }
            break;
        }
    }

    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

const wchar_t* OMNI_SWIPE_CLASS = L"OmniSwipeWindow";

struct SwipeViewData {
    bool isDragging = false;
    int startX = 0;
    int threshold = 50; // Minimum drag displacement in pixels to register a swipe
};

LRESULT CALLBACK OmniSwipeWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    SwipeViewData* data = reinterpret_cast<SwipeViewData*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));

    switch (msg) {
        case WM_SIZE: {
            // Forward resize bounds directly to child views
            RECT rc;
            GetClientRect(hwnd, &rc);
            HWND child = GetWindow(hwnd, GW_CHILD);
            if (child) {
                SetWindowPos(child, NULL, 0, 0, rc.right - rc.left, rc.bottom - rc.top, SWP_NOZORDER | SWP_NOACTIVATE);
            }
            return 0;
        }

        case WM_LBUTTONDOWN: {
            if (!data) break;
            SetCapture(hwnd);
            data->isDragging = true;
            data->startX = GET_X_LPARAM(lParam);
            return 0;
        }

        case WM_LBUTTONUP: {
            if (data && data->isDragging) {
                ReleaseCapture();
                data->isDragging = false;

                int currentX = GET_X_LPARAM(lParam);
                int deltaX = currentX - data->startX;

                OmniWindowEventCallback callback = reinterpret_cast<OmniWindowEventCallback>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));

                if (callback) {
                    if (deltaX < -data->threshold) {
                        // Dragged left -> swipe left action
                        callback(hwnd, OMNI_WM_COMMAND, 1, reinterpret_cast<LPARAM>(hwnd));
                    } else if (deltaX > data->threshold) {
                        // Dragged right -> swipe right action
                        callback(hwnd, OMNI_WM_COMMAND, 2, reinterpret_cast<LPARAM>(hwnd));
                    }
                }
            }
            return 0;
        }

        case WM_NCDESTROY: {
            if (data) {
                delete data;
                SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
            }
            break;
        }
    }

    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

// MARK: - Swift C-ABI Exports
// Prevents C++ name mangling so Swift can link to these exact function names
extern "C" {

  void omni_win_init(void) {
      static bool initialized = false;
      if (initialized) return;

      // Enable Per-Monitor DPI Awareness V2 for crisp rendering on high-res displays
      HMODULE hUser32 = GetModuleHandleW(L"user32.dll");
      if (hUser32) {
          typedef BOOL(WINAPI *SetProcessDpiProc)(HANDLE);
          if (auto setDpiAwareness = reinterpret_cast<SetProcessDpiProc>(GetProcAddress(hUser32, "SetProcessDpiAwarenessContext"))) {
              setDpiAwareness(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
          }
      }

      // Initialize Windows Common Controls for UI elements like Progress Bars
      INITCOMMONCONTROLSEX icex;
      icex.dwSize = sizeof(INITCOMMONCONTROLSEX);
      icex.dwICC = ICC_PROGRESS_CLASS | ICC_STANDARD_CLASSES | ICC_BAR_CLASSES;
      InitCommonControlsEx(&icex);

      WNDCLASSEXW wc = {0};
      wc.cbSize = sizeof(WNDCLASSEXW);
      wc.style = CS_HREDRAW | CS_VREDRAW;
      wc.lpfnWndProc = OmniWndProc;
      wc.hInstance = GetModuleHandleW(NULL);
      wc.hCursor = LoadCursorW(NULL, reinterpret_cast<LPCWSTR>(IDC_ARROW));
      wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
      wc.lpszClassName = OMNI_CLASS_NAME;

      RegisterClassExW(&wc);
      initialized = true;
  }

  void* omni_win_create_window(const char* title, int width, int height, OmniWindowEventCallback callback) {
      omni_win_init();

      std::wstring wTitle = utf8_to_utf16(title);

      // Use CreateWindowExW (Wide string variant)
      HWND hwnd = CreateWindowExW(
          0,
          OMNI_CLASS_NAME,
          wTitle.c_str(),
          WS_OVERLAPPEDWINDOW,
          CW_USEDEFAULT, CW_USEDEFAULT, width, height,
          NULL,
          NULL,
          GetModuleHandleW(NULL),
          reinterpret_cast<void*>(callback)
      );

      return hwnd;
  }

  // Without a sizing frame or maximize button, the window keeps its size.
  void omni_win_set_resizable(void* hwnd, int resizable) {
      if (!hwnd) return;
      HWND window = static_cast<HWND>(hwnd);
      LONG_PTR style = GetWindowLongPtrW(window, GWL_STYLE);
      if (resizable) style |= (WS_THICKFRAME | WS_MAXIMIZEBOX);
      else style &= ~(static_cast<LONG_PTR>(WS_THICKFRAME) | WS_MAXIMIZEBOX);
      SetWindowLongPtrW(window, GWL_STYLE, style);
      SetWindowPos(window, NULL, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
  }

  void omni_win_show(void* hwnd) {
      if (!hwnd) return;
      ShowWindow(static_cast<HWND>(hwnd), SW_SHOWDEFAULT);
      UpdateWindow(static_cast<HWND>(hwnd));
  }

  void omni_win_hide(void* hwnd) {
      if (!hwnd) return;
      ShowWindow(static_cast<HWND>(hwnd), SW_HIDE);
  }

  void omni_win_destroy(void* hwnd) {
      if (!hwnd) return;
      DestroyWindow(static_cast<HWND>(hwnd));
  }

  void omni_win_run_loop(void) {
      MSG msg;
      // GetMessageW strictly handles UTF-16 message character translations
      while (GetMessageW(&msg, NULL, 0, 0) > 0) {
          TranslateMessage(&msg);
          DispatchMessageW(&msg);
      }
  }

  void omni_win_quit_loop(void) {
      PostQuitMessage(0);
  }

  void* omni_win_create_button(void* parent_hwnd, const char* title, int x, int y, int w, int h, int control_id) {
      std::wstring wTitle = utf8_to_utf16(title);

      HWND btn = CreateWindowExW(
          0,
          L"BUTTON",
          wTitle.c_str(),
          WS_TABSTOP | WS_VISIBLE | WS_CHILD | BS_DEFPUSHBUTTON,
          x, y, w, h,
          static_cast<HWND>(parent_hwnd),
          reinterpret_cast<HMENU>(static_cast<INT_PTR>(control_id)),
          GetModuleHandleW(NULL),
          NULL
      );

      // Set standard UI font (prevents ugly legacy Windows 95 font rendering on controls)
      if (btn) {
          SendMessageW(btn, WM_SETFONT, reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT)), TRUE);
      }

      return btn;
  }

  void omni_win_set_text(void* hwnd, const char* text) {
      if (!hwnd) return;
      std::wstring wText = utf8_to_utf16(text);
      SetWindowTextW(static_cast<HWND>(hwnd), wText.c_str());
  }

  void omni_win_add_child(void* parent_hwnd, void* child_hwnd) {
      if (!parent_hwnd || !child_hwnd) return;

      HWND parent = static_cast<HWND>(parent_hwnd);
      HWND child = static_cast<HWND>(child_hwnd);

      SetParent(child, parent);

      LONG_PTR style = GetWindowLongPtrW(child, GWL_STYLE);
      SetWindowLongPtrW(child, GWL_STYLE, style | WS_CHILD);
  }

  void* omni_win_create_canvas(void* parent_hwnd, int x, int y, int w, int h, int control_id) {
      // A canvas is just a generic window class that we will draw on
      HWND canvas = CreateWindowExW(
          0, OMNI_CLASS_NAME, L"",
          WS_VISIBLE | WS_CHILD | WS_CLIPSIBLINGS,
          x, y, w, h,
          static_cast<HWND>(parent_hwnd),
          reinterpret_cast<HMENU>(static_cast<INT_PTR>(control_id)),
          GetModuleHandleW(NULL), NULL
      );
      return canvas;
  }

  void omni_win2d_attach(void* hwnd) {
      if (!hwnd) return;
      EnsureD2DFactory();

      HWND h = static_cast<HWND>(hwnd);
      RECT rc;
      GetClientRect(h, &rc);

      ComPtr<ID2D1HwndRenderTarget> pRT;
      g_d2dFactory->CreateHwndRenderTarget(
          D2D1::RenderTargetProperties(),
          D2D1::HwndRenderTargetProperties(h, D2D1::SizeU(rc.right - rc.left, rc.bottom - rc.top)),
          pRT.GetAddressOf()
      );

      g_renderTargets[h] = pRT;
  }

  void omni_win2d_detach(void* hwnd) {
      if (!hwnd) return;
      g_renderTargets.erase(static_cast<HWND>(hwnd));
  }

  void omni_win2d_begin_draw(void* hwnd) {
      if (!hwnd) return;
      HWND h = static_cast<HWND>(hwnd);

      auto it = g_renderTargets.find(h);
      if (it != g_renderTargets.end()) {
          it->second->BeginDraw();
      }
  }

  void omni_win2d_end_draw(void* hwnd) {
      if (!hwnd) return;
      HWND h = static_cast<HWND>(hwnd);

      auto it = g_renderTargets.find(h);
      if (it != g_renderTargets.end()) {
          HRESULT hr = it->second->EndDraw();
          // If the GPU resets, we must drop the render target so it gets recreated next frame
          if (hr == D2DERR_RECREATE_TARGET) {
              g_renderTargets.erase(h);
              omni_win2d_attach(hwnd);
          }
      }

      // Validate the rectangle so Windows stops spamming WM_PAINT
      ValidateRect(h, NULL);
  }

  void omni_win2d_clear(void* hwnd, float r, float g, float b, float a) {
      if (!hwnd) return;
      auto it = g_renderTargets.find(static_cast<HWND>(hwnd));
      if (it != g_renderTargets.end()) {
          it->second->Clear(D2D1::ColorF(r, g, b, a));
      }
  }

  void omni_win2d_fill_rect(void* hwnd, float x, float y, float w, float h, float r, float g, float b, float a) {
      if (!hwnd) return;
      auto it = g_renderTargets.find(static_cast<HWND>(hwnd));
      if (it != g_renderTargets.end()) {
          ComPtr<ID2D1SolidColorBrush> pBrush;
          it->second->CreateSolidColorBrush(D2D1::ColorF(r, g, b, a), pBrush.GetAddressOf());
          if (pBrush) {
              it->second->FillRectangle(D2D1::RectF(x, y, x + w, y + h), pBrush.Get());
          }
      }
  }

  void omni_win2d_draw_rect(void* hwnd, float x, float y, float w, float h, float r, float g, float b, float a, float stroke_width) {
      if (!hwnd) return;
      auto it = g_renderTargets.find(static_cast<HWND>(hwnd));
      if (it != g_renderTargets.end()) {
          ComPtr<ID2D1SolidColorBrush> pBrush;
          it->second->CreateSolidColorBrush(D2D1::ColorF(r, g, b, a), pBrush.GetAddressOf());
          if (pBrush) {
              it->second->DrawRectangle(D2D1::RectF(x, y, x + w, y + h), pBrush.Get(), stroke_width);
          }
      }
  }

  void* omni_win_create_divider(void* parent_hwnd, int x, int y, int w, int h, bool is_vertical) {
      // SS_ETCHEDVERT and SS_ETCHEDHORZ provide the native Windows sunken divider look
      DWORD orientationStyle = is_vertical ? SS_ETCHEDVERT : SS_ETCHEDHORZ;

      HWND divider = CreateWindowExW(
          0,
          L"STATIC",
          NULL,
          WS_VISIBLE | WS_CHILD | orientationStyle,
          x, y, w, h,
          static_cast<HWND>(parent_hwnd),
          NULL,
          GetModuleHandleW(NULL),
          NULL
      );

      return divider;
  }

  void* omni_win_create_frame(void* parent_hwnd, double width, double height) {
      // Create a standard transparent child window to act as the Frame container
      HWND frame = CreateWindowExW(
          WS_EX_TRANSPARENT, // Let clicks pass through if we don't have events bound
          OMNI_CLASS_NAME,
          L"",
          WS_VISIBLE | WS_CHILD | WS_CLIPSIBLINGS,
          0, 0, (int)width, (int)height,
          static_cast<HWND>(parent_hwnd),
          NULL, GetModuleHandleW(NULL), NULL
      );
      return frame;
  }

  void omni_win_set_frame(void* hwnd, double width, double height) {
      if (!hwnd) return;
      UINT flags = SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE;
      SetWindowPos(static_cast<HWND>(hwnd), NULL, 0, 0, (int)width, (int)height, flags);
  }

  void omni_win_fill_parent(void* child_hwnd, void* parent_hwnd) {
      if (!child_hwnd || !parent_hwnd) return;
      RECT rc;
      GetClientRect(static_cast<HWND>(parent_hwnd), &rc);
      SetWindowPos(
          static_cast<HWND>(child_hwnd), NULL,
          0, 0, rc.right - rc.left, rc.bottom - rc.top,
          SWP_NOZORDER | SWP_NOACTIVATE
      );
  }

  void* omni_win_create_geometry_reader(void* parent_hwnd) {
      // A transparent child window that receives WM_SIZE messages when the layout engine resizes it
      HWND reader = CreateWindowExW(
          WS_EX_TRANSPARENT,
          OMNI_CLASS_NAME,
          L"",
          WS_VISIBLE | WS_CHILD | WS_CLIPSIBLINGS,
          0, 0, 0, 0,
          static_cast<HWND>(parent_hwnd),
          NULL, GetModuleHandleW(NULL), NULL
      );
      return reader;
  }

  void omni_win_get_bounds(void* hwnd, double* width, double* height) {
      if (!hwnd) return;
      RECT rc;
      GetClientRect(static_cast<HWND>(hwnd), &rc);
      if (width) *width = static_cast<double>(rc.right - rc.left);
      if (height) *height = static_cast<double>(rc.bottom - rc.top);
  }

  void* omni_win_create_hstack(void* parent_hwnd, double spacing) {
      static bool stackRegistered = false;
      if (!stackRegistered) {
          WNDCLASSEXW wc = {0};
          wc.cbSize = sizeof(WNDCLASSEXW);
          wc.lpfnWndProc = OmniHStackWndProc;
          wc.hInstance = GetModuleHandleW(NULL);
          wc.hCursor = LoadCursorW(NULL, reinterpret_cast<LPCWSTR>(IDC_ARROW));
          wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1); // Transparent/Default bg
          wc.lpszClassName = OMNI_HSTACK_CLASS;
          RegisterClassExW(&wc);
          stackRegistered = true;
      }

      HWND stack = CreateWindowExW(
          WS_EX_CONTROLPARENT, // Allows tab navigation to pass through to children
          OMNI_HSTACK_CLASS,
          L"",
          WS_VISIBLE | WS_CHILD | WS_CLIPSIBLINGS,
          0, 0, 100, 100,
          static_cast<HWND>(parent_hwnd),
          NULL, GetModuleHandleW(NULL), NULL
      );

      // Store the spacing value in the HWND's user data for the layout pass
      SetWindowLongPtrW(stack, GWLP_USERDATA, static_cast<LONG_PTR>(spacing));

      return stack;
  }

  void omni_win_set_stack_spacing(void* hwnd, double spacing) {
      if (!hwnd) return;
      HWND h = static_cast<HWND>(hwnd);
      SetWindowLongPtrW(h, GWLP_USERDATA, static_cast<LONG_PTR>(spacing));

      // Force a layout recalculation
      RECT rc;
      GetClientRect(h, &rc);
      SendMessageW(h, WM_SIZE, 0, MAKELPARAM(rc.right, rc.bottom));
  }

  void* omni_win_create_image(void* parent_hwnd, const char* name, bool is_system) {
      std::wstring wName = utf8_to_utf16(name);

      HWND imgControl = CreateWindowExW(
          0,
          L"STATIC",
          NULL,
          WS_VISIBLE | WS_CHILD | SS_CENTERIMAGE, // Centers image inside its layout frame
          0, 0, 100, 100,
          static_cast<HWND>(parent_hwnd),
          NULL,
          GetModuleHandleW(NULL),
          NULL
      );

      if (is_system) {
          // Map common cross-platform system names to Win32 IDI constants
          LPCWSTR iconId = IDI_APPLICATION;
          if (wName == L"warning" || wName == L"exclamationmark.triangle") iconId = IDI_WARNING;
          else if (wName == L"info.circle" || wName == L"info") iconId = IDI_INFORMATION;
          else if (wName == L"xmark.circle" || wName == L"error" || wName == L"xmark.octagon") iconId = IDI_ERROR;
          else if (wName == L"questionmark") iconId = IDI_QUESTION;

          LONG_PTR style = GetWindowLongPtrW(imgControl, GWL_STYLE);
          SetWindowLongPtrW(imgControl, GWL_STYLE, style | SS_ICON);

          HANDLE hIcon = LoadImageW(NULL, iconId, IMAGE_ICON, 0, 0, LR_SHARED | LR_DEFAULTSIZE);
          SendMessageW(imgControl, STM_SETICON, reinterpret_cast<WPARAM>(hIcon), 0);
      } else {
          LONG_PTR style = GetWindowLongPtrW(imgControl, GWL_STYLE);
          SetWindowLongPtrW(imgControl, GWL_STYLE, style | SS_BITMAP);

          // Native Win32 LoadImageW natively supports .bmp.
          // (Note: Loading .png / .jpg requires WIC - Windows Imaging Component, which can be added later).
          HANDLE hBmp = LoadImageW(NULL, wName.c_str(), IMAGE_BITMAP, 0, 0, LR_LOADFROMFILE | LR_CREATEDIBSECTION);
          SendMessageW(imgControl, STM_SETIMAGE, IMAGE_BITMAP, reinterpret_cast<LPARAM>(hBmp));
      }

      return imgControl;
  }

  void* omni_win_create_picker(void* parent_hwnd, int x, int y, int w, int h, int control_id) {
      HWND picker = CreateWindowExW(
          0,
          L"COMBOBOX",
          NULL,
          WS_VISIBLE | WS_CHILD | WS_TABSTOP | WS_VSCROLL | CBS_DROPDOWNLIST,
          x, y, w, h > 0 ? h : 200,
          static_cast<HWND>(parent_hwnd),
          reinterpret_cast<HMENU>(static_cast<INT_PTR>(control_id)),
          GetModuleHandleW(NULL),
          NULL
      );

      if (picker) {
          SendMessageW(picker, WM_SETFONT, reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT)), TRUE);
      }

      return picker;
  }

  void omni_win_picker_clear(void* hwnd) {
      if (!hwnd) return;
      SendMessageW(static_cast<HWND>(hwnd), CB_RESETCONTENT, 0, 0);
  }

  void omni_win_picker_add_item(void* hwnd, const char* label) {
      if (!hwnd) return;
      std::wstring wLabel = utf8_to_utf16(label);
      SendMessageW(static_cast<HWND>(hwnd), CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(wLabel.c_str()));
  }

  void omni_win_picker_set_selection(void* hwnd, int index) {
      if (!hwnd) return;
      SendMessageW(static_cast<HWND>(hwnd), CB_SETCURSEL, index, 0);
  }

  int omni_win_picker_get_selection(void* hwnd) {
      if (!hwnd) return -1;
      return static_cast<int>(SendMessageW(static_cast<HWND>(hwnd), CB_GETCURSEL, 0, 0));
  }

  void* omni_win_create_progress(void* parent_hwnd, int x, int y, int w, int h) {
      HWND progress = CreateWindowExW(
          0,
          PROGRESS_CLASSW, // Win32 constant for L"msctls_progress32"
          NULL,
          WS_VISIBLE | WS_CHILD | PBS_MARQUEE,
          x, y, w > 0 ? w : 100, h > 0 ? h : 15,
          static_cast<HWND>(parent_hwnd),
          NULL,
          GetModuleHandleW(NULL),
          NULL
      );

      // Start the indeterminate sliding animation immediately
      if (progress) {
          SendMessageW(progress, PBM_SETMARQUEE, 1, 0); // 1 = Enable, 0 = Time delay (default)
      }

      return progress;
  }

  void* omni_win_create_scrollview(void* parent_hwnd, bool is_vertical) {
      static bool registered = false;
      if (!registered) {
          WNDCLASSEXW wc = {0};
          wc.cbSize = sizeof(WNDCLASSEXW);
          wc.lpfnWndProc = OmniScrollWndProc;
          wc.hInstance = GetModuleHandleW(NULL);
          wc.hCursor = LoadCursorW(NULL, reinterpret_cast<LPCWSTR>(IDC_ARROW));
          wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
          wc.lpszClassName = OMNI_SCROLL_CLASS;
          RegisterClassExW(&wc);
          registered = true;
      }

      DWORD scrollStyle = is_vertical ? WS_VSCROLL : WS_HSCROLL;

      HWND scroll = CreateWindowExW(
          WS_EX_CONTROLPARENT,
          OMNI_SCROLL_CLASS,
          L"",
          WS_VISIBLE | WS_CHILD | WS_CLIPCHILDREN | scrollStyle,
          0, 0, 200, 200,
          static_cast<HWND>(parent_hwnd),
          NULL, GetModuleHandleW(NULL), NULL
      );

      return scroll;
  }

  void omni_win_scrollview_update_content_size(void* hwnd, double content_width, double content_height) {
      if (!hwnd) return;
      HWND h = static_cast<HWND>(hwnd);
      bool isVertical = (GetWindowLongPtrW(h, GWL_STYLE) & WS_VSCROLL) != 0;

      RECT rc;
      GetClientRect(h, &rc);

      SCROLLINFO si = { sizeof(si), SIF_RANGE | SIF_PAGE };
      si.nMin = 0;
      si.nMax = isVertical ? static_cast<int>(content_height) : static_cast<int>(content_width);
      si.nPage = isVertical ? (rc.bottom - rc.top) : (rc.right - rc.left);

      SetScrollInfo(h, isVertical ? SB_VERT : SB_HORZ, &si, TRUE);
  }

  double omni_win_scrollview_get_offset(void* hwnd) {
      if (!hwnd) return 0.0;
      HWND h = static_cast<HWND>(hwnd);
      bool isVertical = (GetWindowLongPtrW(h, GWL_STYLE) & WS_VSCROLL) != 0;
      return static_cast<double>(GetScrollPos(h, isVertical ? SB_VERT : SB_HORZ));
  }

  void omni_win_scrollview_set_offset(void* hwnd, double offset) {
      // Basic programmatic scroll offset assignment
      if (!hwnd) return;
      HWND h = static_cast<HWND>(hwnd);
      bool isVertical = (GetWindowLongPtrW(h, GWL_STYLE) & WS_VSCROLL) != 0;
      SetScrollPos(h, isVertical ? SB_VERT : SB_HORZ, static_cast<int>(offset), TRUE);
  }

  void* omni_win_create_textfield(void* parent_hwnd, const char* placeholder, bool is_secure) {
      DWORD style = WS_VISIBLE | WS_CHILD | WS_TABSTOP | WS_BORDER | ES_AUTOHSCROLL;
      if (is_secure) style |= ES_PASSWORD;

      HWND tf = CreateWindowExW(
          WS_EX_CLIENTEDGE, // Provides the standard sunken 3D border for text fields
          L"EDIT",
          L"",
          style,
          0, 0, 150, 24, // Default sizing, engine handles real layout
          static_cast<HWND>(parent_hwnd),
          NULL,
          GetModuleHandleW(NULL),
          NULL
      );

      if (tf) {
          SendMessageW(tf, WM_SETFONT, reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT)), TRUE);

          if (placeholder && *placeholder) {
              std::wstring wPlaceholder = utf8_to_utf16(placeholder);
              // EM_SETCUEBANNER sets the placeholder text. 'FALSE' means it disappears when focused.
              SendMessageW(tf, EM_SETCUEBANNER, FALSE, reinterpret_cast<LPARAM>(wPlaceholder.c_str()));
          }
      }
      return tf;
  }

  void omni_win_textfield_get_text(void* hwnd, char* buffer, int buffer_size) {
      if (!hwnd || !buffer || buffer_size <= 0) return;
      HWND h = static_cast<HWND>(hwnd);

      int len = GetWindowTextLengthW(h);
      if (len == 0) {
          buffer[0] = '\0';
          return;
      }

      std::wstring wText(len + 1, L'\0');
      GetWindowTextW(h, &wText[0], len + 1);

      // Convert back from Win16 WideChars to Swift-compatible UTF-8
      WideCharToMultiByte(CP_UTF8, 0, wText.c_str(), -1, buffer, buffer_size, NULL, NULL);
  }

  void* omni_win_create_clip_view(void* parent_hwnd) {
      static bool registered = false;
      if (!registered) {
          WNDCLASSEXW wc = {0};
          wc.cbSize = sizeof(WNDCLASSEXW);
          wc.lpfnWndProc = OmniClipWndProc;
          wc.hInstance = GetModuleHandleW(NULL);
          wc.hCursor = LoadCursorW(NULL, reinterpret_cast<LPCWSTR>(IDC_ARROW));
          wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
          wc.lpszClassName = OMNI_CLIP_CLASS;
          RegisterClassExW(&wc);
          registered = true;
      }

      HWND clipView = CreateWindowExW(
          WS_EX_CONTROLPARENT,
          OMNI_CLIP_CLASS,
          L"",
          WS_VISIBLE | WS_CHILD | WS_CLIPCHILDREN,
          0, 0, 100, 100, // Sizing handled by layout engine
          static_cast<HWND>(parent_hwnd),
          NULL, GetModuleHandleW(NULL), NULL
      );

      return clipView;
  }

  void omni_win_set_clip_radius(void* hwnd, double radius, bool is_circular) {
      if (!hwnd) return;
      HWND h = static_cast<HWND>(hwnd);

      // Pack the parameters into a single LONG_PTR
      // Bit 0 stores boolean, the rest stores the integer radius
      int intRadius = static_cast<int>(radius);
      LONG_PTR state = (static_cast<LONG_PTR>(intRadius) << 1) | (is_circular ? 1 : 0);

      GetWindowLongPtrW(h, GWLP_USERDATA); // Clear error state
      SetWindowLongPtrW(h, GWLP_USERDATA, state);

      // Force a WM_SIZE message to recalculate the clipping region
      RECT rc;
      GetClientRect(h, &rc);
      SendMessageW(h, WM_SIZE, 0, MAKELPARAM(rc.right - rc.left, rc.bottom - rc.top));
  }

  void* omni_win_create_slider(void* parent_hwnd, int x, int y, int w, int h) {
      HWND slider = CreateWindowExW(
          0,
          TRACKBAR_CLASSW, // L"msctls_trackbar32"
          NULL,
          WS_VISIBLE | WS_CHILD | WS_TABSTOP | TBS_HORZ | TBS_AUTOTICKS,
          x, y, w > 0 ? w : 150, h > 0 ? h : 30,
          static_cast<HWND>(parent_hwnd),
          NULL,
          GetModuleHandleW(NULL),
          NULL
      );
      return slider;
  }

  void omni_win_slider_set_range(void* hwnd, int min_val, int max_val) {
      if (hwnd) SendMessageW(static_cast<HWND>(hwnd), TBM_SETRANGE, TRUE, MAKELPARAM(min_val, max_val));
  }

  void omni_win_slider_set_value(void* hwnd, int value) {
      if (hwnd) SendMessageW(static_cast<HWND>(hwnd), TBM_SETPOS, TRUE, value);
  }

  int omni_win_slider_get_value(void* hwnd) {
      if (hwnd) return static_cast<int>(SendMessageW(static_cast<HWND>(hwnd), TBM_GETPOS, 0, 0));
      return 0;
  }

  void* omni_win_create_spacer(void* parent_hwnd, double min_length) {
      static bool registered = false;
      if (!registered) {
          WNDCLASSEXW wc = {0};
          wc.cbSize = sizeof(WNDCLASSEXW);
          wc.lpfnWndProc = OmniSpacerWndProc;
          wc.hInstance = GetModuleHandleW(NULL);
          // No background brush needed; it remains entirely invisible
          wc.lpszClassName = OMNI_SPACER_CLASS;
          RegisterClassExW(&wc);
          registered = true;
      }

      HWND spacer = CreateWindowExW(
          WS_EX_TRANSPARENT,
          OMNI_SPACER_CLASS,
          L"",
          WS_VISIBLE | WS_CHILD,
          0, 0, static_cast<int>(min_length), static_cast<int>(min_length),
          static_cast<HWND>(parent_hwnd),
          NULL, GetModuleHandleW(NULL), NULL
      );

      // Store min_length so the Stack layout loops can extract it during WM_SIZE
      SetWindowLongPtrW(spacer, GWLP_USERDATA, static_cast<LONG_PTR>(min_length));

      return spacer;
  }

  void omni_win_spacer_set_min_length(void* hwnd, double min_length) {
      if (hwnd) {
          SetWindowLongPtrW(static_cast<HWND>(hwnd), GWLP_USERDATA, static_cast<LONG_PTR>(min_length));
      }
  }

  void* omni_win_create_splitview(void* parent_hwnd, bool is_vertical) {
      static bool registered = false;
      if (!registered) {
          WNDCLASSEXW wc = {0};
          wc.cbSize = sizeof(WNDCLASSEXW);
          wc.lpfnWndProc = OmniSplitWndProc;
          wc.hInstance = GetModuleHandleW(NULL);
          wc.hCursor = LoadCursorW(NULL, reinterpret_cast<LPCWSTR>(IDC_ARROW));
          wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
          wc.lpszClassName = OMNI_SPLIT_CLASS;
          RegisterClassExW(&wc);
          registered = true;
      }

      HWND splitView = CreateWindowExW(
          WS_EX_CONTROLPARENT,
          OMNI_SPLIT_CLASS,
          L"",
          WS_VISIBLE | WS_CHILD | WS_CLIPCHILDREN,
          0, 0, 200, 200,
          static_cast<HWND>(parent_hwnd),
          NULL, GetModuleHandleW(NULL), NULL
      );

      SplitViewData* data = new SplitViewData();
      data->isVertical = is_vertical;
      data->ratio = 0.5f;
      data->isDragging = false;
      data->dividerThickness = 6;

      SetWindowLongPtrW(splitView, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(data));

      return splitView;
  }

  void omni_win_splitview_set_orientation(void* hwnd, bool is_vertical) {
      if (!hwnd) return;
      HWND h = static_cast<HWND>(hwnd);
      SplitViewData* data = reinterpret_cast<SplitViewData*>(GetWindowLongPtrW(h, GWLP_USERDATA));
      if (data) {
          data->isVertical = is_vertical;
          RECT rc;
          GetClientRect(h, &rc);
          SendMessageW(h, WM_SIZE, 0, MAKELPARAM(rc.right, rc.bottom));
      }
  }

  void* omni_win_create_swipe_view(void* parent_hwnd) {
      static bool registered = false;
      if (!registered) {
          WNDCLASSEXW wc = {0};
          wc.cbSize = sizeof(WNDCLASSEXW);
          wc.lpfnWndProc = OmniSwipeWndProc;
          wc.hInstance = GetModuleHandleW(NULL);
          wc.hCursor = LoadCursorW(NULL, reinterpret_cast<LPCWSTR>(IDC_ARROW));
          wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
          wc.lpszClassName = OMNI_SWIPE_CLASS;
          RegisterClassExW(&wc);
          registered = true;
      }

      HWND swipeView = CreateWindowExW(
          WS_EX_CONTROLPARENT,
          OMNI_SWIPE_CLASS,
          L"",
          WS_VISIBLE | WS_CHILD | WS_CLIPCHILDREN,
          0, 0, 100, 100,
          static_cast<HWND>(parent_hwnd),
          NULL, GetModuleHandleW(NULL), NULL
      );

      SwipeViewData* data = new SwipeViewData();
      SetWindowLongPtrW(swipeView, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(data));

      return swipeView;
  }

  void omni_win_swipe_view_set_threshold(void* hwnd, double threshold_pixels) {
      if (!hwnd) return;
      HWND h = static_cast<HWND>(hwnd);
      SwipeViewData* data = reinterpret_cast<SwipeViewData*>(GetWindowLongPtrW(h, GWLP_USERDATA));
      if (data) {
          data->threshold = static_cast<int>(threshold_pixels);
      }
  }

} // end extern "C"
