# Third-Party Notices

EspBluFiNext is an independent iOS diagnostic client for Espressif
BluFi-compatible ESP32 devices. This file records licenses and provenance for
third-party material used by the project or consulted for protocol
interoperability.

The current source tree does not bundle the Java or Objective-C source files,
OpenSSL headers/libraries, or ESP-IDF example source from Espressif's reference
applications. The Espressif notice below is retained for protocol provenance
and applies if material from those reference projects is added in the future.

## BigInt

Source: <https://github.com/attaswift/BigInt>

BigInt is used by `BluFiKit` for the BluFi security implementation. BigInt is
distributed under the MIT License:

```text
Copyright (c) 2016-2017 Károly Lőrentey

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Espressif BluFi reference projects

Sources:

- <https://github.com/EspressifApp/EspBlufiForAndroid>
- <https://github.com/EspressifApp/EspBlufiForiOS>

The reference projects publish the following ESPRESSIF MIT License. It permits
use, modification, distribution, sublicensing, and sale when the software is
used for, controls, or connects to Espressif ESP8266/ESP32 products. The
copyright and permission notice must remain in copies or substantial portions
of covered software.

```text
ESPRSSIF MIT License

Copyright © 2019 <ESPRESSIF SYSTEMS (SHANGHAI) PTE LTD>

Permission is hereby granted for use of, for control of and/or for use in conjunction with ESPRESSIF SYSTEMS ESP8266/ESP32 only, in which case, it is free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

EspBluFiNext does not use the Espressif name or logo as an indication of
official sponsorship. See [`docs/BRANDING.md`](docs/BRANDING.md) for the
project's compatibility wording and asset rules.

## Material not bundled by EspBluFiNext

- The `EspBlufiForiOS` repository's OpenSSL headers and static libraries are
  not part of this app. The app uses Apple's `CryptoKit`/`CommonCrypto` and
  BigInt instead.
- The `xiaozhi-esp32` firmware repository is a separate project and is not
  bundled with this iOS app. Its license applies to that firmware when it is
  distributed separately.
- ESP-IDF source is not bundled. If a future change adds an ESP-IDF file, keep
  its file-level SPDX header and add the applicable notice here.
