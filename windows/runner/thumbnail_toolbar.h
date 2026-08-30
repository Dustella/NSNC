#ifndef RUNNER_THUMBNAIL_TOOLBAR_H_
#define RUNNER_THUMBNAIL_TOOLBAR_H_

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>
#include <string>

struct ITaskbarList3;
struct IWICImagingFactory;

class ThumbnailToolbar {
 public:
  ThumbnailToolbar(HWND window, flutter::BinaryMessenger* messenger);
  ~ThumbnailToolbar();

  ThumbnailToolbar(const ThumbnailToolbar&) = delete;
  ThumbnailToolbar& operator=(const ThumbnailToolbar&) = delete;

  void Update(bool enabled, bool playing, const std::wstring& cover_path);
  bool HandleMessage(UINT message, WPARAM wparam, LPARAM lparam,
                     LRESULT* result);

 private:
  void AddButtons();
  void UpdateButtons();
  void SendAction(const char* action);
  HBITMAP CreateThumbnail(UINT max_width, UINT max_height);

  HWND window_;
  UINT taskbar_button_created_;
  bool taskbar_ready_ = false;
  bool buttons_added_ = false;
  bool enabled_ = false;
  bool playing_ = false;
  std::wstring cover_path_;
  ITaskbarList3* taskbar_ = nullptr;
  IWICImagingFactory* wic_factory_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_THUMBNAIL_TOOLBAR_H_
