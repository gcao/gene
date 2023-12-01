#!/usr/bin/env osascript

set _output to ""
set sep to tab
set newline to "
"
-- CSV header row
set _output to _output & "window" & sep & "tab" & sep & "url" & sep & "title" & newline
tell application "Google Chrome"
  set _window_index to 1
  repeat with _window in windows
    try
      set _tab_count to (count of tabs in _window)
      set _tab_index to 1
      repeat with _tab in tabs of _window
        set _output to _output & (_window_index as string) & sep & (_tab_index as string) & sep & url of _tab & sep & title of _tab & newline
        set _tab_index to _tab_index + 1
      end repeat
    end try
    set _window_index to _window_index + 1
  end repeat
end tell

_output
