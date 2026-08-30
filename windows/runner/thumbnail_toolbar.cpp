#include "thumbnail_toolbar.h"

#include <dwmapi.h>
#include <shobjidl.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <algorithm>
#include <array>
#include <cstdint>
#include <string>

namespace {
using Microsoft::WRL::ComPtr;

constexpr UINT kPreviousButton = 0x3101;
constexpr UINT kToggleButton = 0x3102;
constexpr UINT kNextButton = 0x3103;

enum class IconKind { kPrevious, kPlay, kPause, kNext };

std::wstring Utf16FromUtf8(const std::string& value) {
  if (value.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                       value.c_str(), -1, nullptr, 0);
  if (size <= 1) return {};
  std::wstring result(static_cast<size_t>(size), L'\0');
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.c_str(), -1,
                          result.data(), size) == 0) {
    return {};
  }
  result.pop_back();
  return result;
}

HICON CreateToolbarIcon(IconKind kind) {
  const int width = std::max(16, GetSystemMetrics(SM_CXSMICON));
  const int height = std::max(16, GetSystemMetrics(SM_CYSMICON));
  BITMAPV5HEADER header{};
  header.bV5Size = sizeof(header);
  header.bV5Width = width;
  header.bV5Height = -height;
  header.bV5Planes = 1;
  header.bV5BitCount = 32;
  header.bV5Compression = BI_BITFIELDS;
  header.bV5RedMask = 0x00ff0000;
  header.bV5GreenMask = 0x0000ff00;
  header.bV5BlueMask = 0x000000ff;
  header.bV5AlphaMask = 0xff000000;

  void* raw_pixels = nullptr;
  HDC screen = GetDC(nullptr);
  HBITMAP color = CreateDIBSection(screen, reinterpret_cast<BITMAPINFO*>(&header),
                                   DIB_RGB_COLORS, &raw_pixels, nullptr, 0);
  ReleaseDC(nullptr, screen);
  if (color == nullptr || raw_pixels == nullptr) return nullptr;

  auto* pixels = static_cast<uint32_t*>(raw_pixels);
  std::fill_n(pixels, static_cast<size_t>(width * height), 0u);
  const auto paint = [&](int x, int y) {
    if (x >= 0 && x < width && y >= 0 && y < height) {
      pixels[y * width + x] = 0xffffffffu;
    }
  };
  const int left = width / 4;
  const int right = width - left - 1;
  const int top = height / 4;
  const int bottom = height - top - 1;
  const int middle = height / 2;
  const int stroke = std::max(1, width / 12);

  if (kind == IconKind::kPause) {
    for (int y = top; y <= bottom; ++y) {
      for (int offset = 0; offset < stroke + 1; ++offset) {
        paint(left + offset, y);
        paint(right - offset, y);
      }
    }
  } else {
    const bool points_left = kind == IconKind::kPrevious;
    const bool has_bar = kind == IconKind::kPrevious || kind == IconKind::kNext;
    const int tip = points_left ? left + stroke : right - stroke;
    const int base = points_left ? right - stroke : left + stroke;
    for (int x = std::min(tip, base); x <= std::max(tip, base); ++x) {
      const double progress = static_cast<double>(std::abs(x - tip)) /
                              std::max(1, std::abs(base - tip));
      const int half_height = static_cast<int>(progress * (bottom - top) / 2);
      for (int y = middle - half_height; y <= middle + half_height; ++y) {
        paint(x, y);
      }
    }
    if (has_bar) {
      const int bar_x = points_left ? left : right;
      for (int x = bar_x - stroke; x <= bar_x + stroke; ++x) {
        for (int y = top; y <= bottom; ++y) paint(x, y);
      }
    }
  }

  HBITMAP mask = CreateBitmap(width, height, 1, 1, nullptr);
  ICONINFO info{};
  info.fIcon = TRUE;
  info.hbmColor = color;
  info.hbmMask = mask;
  HICON icon = CreateIconIndirect(&info);
  DeleteObject(mask);
  DeleteObject(color);
  return icon;
}

THUMBBUTTON MakeButton(UINT id, HICON icon, const wchar_t* tooltip,
                       bool disabled) {
  THUMBBUTTON button{};
  button.dwMask =
      static_cast<THUMBBUTTONMASK>(THB_ICON | THB_TOOLTIP | THB_FLAGS);
  button.iId = id;
  button.hIcon = icon;
  wcsncpy_s(button.szTip, tooltip, _TRUNCATE);
  button.dwFlags = disabled ? THBF_DISABLED : THBF_ENABLED;
  return button;
}

bool ReadBool(const flutter::EncodableMap& args, const char* key) {
  const auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) return false;
  const auto* value = std::get_if<bool>(&it->second);
  return value != nullptr && *value;
}

std::string ReadString(const flutter::EncodableMap& args, const char* key) {
  const auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) return {};
  const auto* value = std::get_if<std::string>(&it->second);
  return value == nullptr ? std::string() : *value;
}
}  // namespace

ThumbnailToolbar::ThumbnailToolbar(HWND window,
                                   flutter::BinaryMessenger* messenger)
    : window_(window),
      taskbar_button_created_(RegisterWindowMessageW(L"TaskbarButtonCreated")) {
  if (SUCCEEDED(CoCreateInstance(CLSID_TaskbarList, nullptr,
                                 CLSCTX_INPROC_SERVER,
                                 IID_PPV_ARGS(&taskbar_))) &&
      FAILED(taskbar_->HrInit())) {
    taskbar_->Release();
    taskbar_ = nullptr;
  }
  CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
                   IID_PPV_ARGS(&wic_factory_));

  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "com.dustella.nsnc/thumbnail_toolbar",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() != "update") {
      result->NotImplemented();
      return;
    }
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (args == nullptr) {
      result->Error("invalid_arguments", "Expected a map");
      return;
    }
    Update(ReadBool(*args, "enabled"), ReadBool(*args, "playing"),
           Utf16FromUtf8(ReadString(*args, "coverPath")));
    result->Success();
  });
}

ThumbnailToolbar::~ThumbnailToolbar() {
  if (taskbar_ != nullptr) taskbar_->Release();
  if (wic_factory_ != nullptr) wic_factory_->Release();
}

void ThumbnailToolbar::Update(bool enabled, bool playing,
                              const std::wstring& cover_path) {
  const bool cover_changed = cover_path_ != cover_path;
  enabled_ = enabled;
  playing_ = playing;
  cover_path_ = cover_path;
  if (taskbar_ready_) {
    if (!buttons_added_) AddButtons();
    UpdateButtons();
  }
  if (cover_changed) {
    const BOOL use_iconic = cover_path_.empty() ? FALSE : TRUE;
    DwmSetWindowAttribute(window_, DWMWA_FORCE_ICONIC_REPRESENTATION,
                          &use_iconic, sizeof(use_iconic));
    DwmSetWindowAttribute(window_, DWMWA_HAS_ICONIC_BITMAP, &use_iconic,
                          sizeof(use_iconic));
    DwmInvalidateIconicBitmaps(window_);
  }
}

void ThumbnailToolbar::AddButtons() {
  if (taskbar_ == nullptr || buttons_added_) return;
  const std::array<HICON, 3> icons{
      CreateToolbarIcon(IconKind::kPrevious),
      CreateToolbarIcon(playing_ ? IconKind::kPause : IconKind::kPlay),
      CreateToolbarIcon(IconKind::kNext),
  };
  std::array<THUMBBUTTON, 3> buttons{
      MakeButton(kPreviousButton, icons[0], L"Previous", !enabled_),
      MakeButton(kToggleButton, icons[1], playing_ ? L"Pause" : L"Play",
                 !enabled_),
      MakeButton(kNextButton, icons[2], L"Next", !enabled_),
  };
  buttons_added_ = SUCCEEDED(taskbar_->ThumbBarAddButtons(
      window_, static_cast<UINT>(buttons.size()), buttons.data()));
  for (const auto icon : icons) {
    if (icon != nullptr) DestroyIcon(icon);
  }
}

void ThumbnailToolbar::UpdateButtons() {
  if (taskbar_ == nullptr || !buttons_added_) return;
  const std::array<HICON, 3> icons{
      CreateToolbarIcon(IconKind::kPrevious),
      CreateToolbarIcon(playing_ ? IconKind::kPause : IconKind::kPlay),
      CreateToolbarIcon(IconKind::kNext),
  };
  std::array<THUMBBUTTON, 3> buttons{
      MakeButton(kPreviousButton, icons[0], L"Previous", !enabled_),
      MakeButton(kToggleButton, icons[1], playing_ ? L"Pause" : L"Play",
                 !enabled_),
      MakeButton(kNextButton, icons[2], L"Next", !enabled_),
  };
  taskbar_->ThumbBarUpdateButtons(window_, static_cast<UINT>(buttons.size()),
                                  buttons.data());
  for (const auto icon : icons) {
    if (icon != nullptr) DestroyIcon(icon);
  }
}

void ThumbnailToolbar::SendAction(const char* action) {
  if (channel_ != nullptr) {
    channel_->InvokeMethod(
        "action", std::make_unique<flutter::EncodableValue>(action));
  }
}

bool ThumbnailToolbar::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam,
                                     LRESULT* result) {
  if (message == taskbar_button_created_) {
    taskbar_ready_ = true;
    AddButtons();
    UpdateButtons();
    *result = 0;
    return true;
  }
  if (message == WM_COMMAND && HIWORD(wparam) == THBN_CLICKED) {
    switch (LOWORD(wparam)) {
      case kPreviousButton:
        SendAction("previous");
        break;
      case kToggleButton:
        SendAction("toggle");
        break;
      case kNextButton:
        SendAction("next");
        break;
      default:
        return false;
    }
    *result = 0;
    return true;
  }
  if (message == WM_DWMSENDICONICTHUMBNAIL && !cover_path_.empty()) {
    HBITMAP bitmap = CreateThumbnail(HIWORD(lparam), LOWORD(lparam));
    if (bitmap != nullptr) {
      DwmSetIconicThumbnail(window_, bitmap, 0);
      DeleteObject(bitmap);
    }
    *result = 0;
    return true;
  }
  return false;
}

HBITMAP ThumbnailToolbar::CreateThumbnail(UINT max_width, UINT max_height) {
  if (wic_factory_ == nullptr || cover_path_.empty() || max_width == 0 ||
      max_height == 0) {
    return nullptr;
  }

  ComPtr<IWICBitmapDecoder> decoder;
  ComPtr<IWICBitmapFrameDecode> frame;
  ComPtr<IWICBitmapScaler> scaler;
  ComPtr<IWICFormatConverter> converter;
  if (FAILED(wic_factory_->CreateDecoderFromFilename(
          cover_path_.c_str(), nullptr, GENERIC_READ, WICDecodeMetadataCacheOnLoad,
          &decoder)) ||
      FAILED(decoder->GetFrame(0, &frame))) {
    return nullptr;
  }

  UINT width = 0;
  UINT height = 0;
  if (FAILED(frame->GetSize(&width, &height)) || width == 0 || height == 0) {
    return nullptr;
  }
  const double scale =
      std::min({1.0, static_cast<double>(max_width) / width,
                static_cast<double>(max_height) / height});
  const UINT target_width =
      std::max(1u, static_cast<UINT>(width * scale));
  const UINT target_height =
      std::max(1u, static_cast<UINT>(height * scale));
  if (FAILED(wic_factory_->CreateBitmapScaler(&scaler)) ||
      FAILED(scaler->Initialize(frame.Get(), target_width, target_height,
                                WICBitmapInterpolationModeFant)) ||
      FAILED(wic_factory_->CreateFormatConverter(&converter)) ||
      FAILED(converter->Initialize(scaler.Get(), GUID_WICPixelFormat32bppPBGRA,
                                   WICBitmapDitherTypeNone, nullptr, 0,
                                   WICBitmapPaletteTypeCustom))) {
    return nullptr;
  }

  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = static_cast<LONG>(target_width);
  info.bmiHeader.biHeight = -static_cast<LONG>(target_height);
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  void* pixels = nullptr;
  HBITMAP bitmap =
      CreateDIBSection(nullptr, &info, DIB_RGB_COLORS, &pixels, nullptr, 0);
  if (bitmap == nullptr || pixels == nullptr) return nullptr;
  if (FAILED(converter->CopyPixels(nullptr, target_width * 4,
                                   target_width * target_height * 4,
                                   static_cast<BYTE*>(pixels)))) {
    DeleteObject(bitmap);
    return nullptr;
  }
  return bitmap;
}
