import 'package:flutter/foundation.dart';

/// Adds the tools Ftube runs or bundles to the licenses page. Dart and
/// Flutter packages are listed there automatically.
void registerThirdPartyLicenses() {
  LicenseRegistry.addLicense(
    () => Stream.fromIterable(const [
      LicenseEntryWithLineBreaks(
        ['yt-dlp'],
        '''
yt-dlp is released into the public domain under the Unlicense.
https://github.com/yt-dlp/yt-dlp/blob/master/LICENSE

The standalone yt-dlp binaries are built with PyInstaller and include
components under other licenses, some of them GPL.''',
      ),
      LicenseEntryWithLineBreaks(
        ['FFmpeg'],
        '''
FFmpeg is licensed under the GNU General Public License version 3 for the
builds Ftube downloads on desktop, and under the GNU Lesser General Public
License version 3 for the FFmpegKit audio build on Android.
Source code: https://ffmpeg.org/download.html''',
      ),
      LicenseEntryWithLineBreaks(
        ['Deno'],
        '''
Deno is licensed under the MIT License.
https://github.com/denoland/deno/blob/main/LICENSE.md''',
      ),
    ]),
  );
}
