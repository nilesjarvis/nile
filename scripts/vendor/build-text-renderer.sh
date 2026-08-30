#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
vendor_root="$repo_root/Vendor/TextRenderer"
output="$vendor_root/NileTextRenderer.xcframework"

freetype_remote="https://android.googlesource.com/platform/external/freetype"
freetype_commit="5ab8c8be9c2ce2c42aaa79752bffc89618d39515"
harfbuzz_remote="https://android.googlesource.com/platform/external/harfbuzz_ng"
harfbuzz_commit="9a50c421c9ca31c44462ce31785f03ff41631ba5"

work_root="$(mktemp -d "${TMPDIR:-/tmp}/nile-text-renderer.XXXXXX")"
trap 'rm -rf "$work_root"' EXIT

fetch_source() {
    local remote="$1"
    local commit="$2"
    local destination="$3"
    git clone --quiet --filter=blob:none --no-checkout "$remote" "$destination"
    git -C "$destination" fetch --quiet --depth=1 origin "$commit"
    git -C "$destination" checkout --quiet --detach "$commit"
    test "$(git -C "$destination" rev-parse HEAD)" = "$commit"
}

freetype_root="$work_root/freetype"
harfbuzz_root="$work_root/harfbuzz"
fetch_source "$freetype_remote" "$freetype_commit" "$freetype_root"
fetch_source "$harfbuzz_remote" "$harfbuzz_commit" "$harfbuzz_root"

freetype_sources=(
    src/autofit/autofit.c
    src/base/ftbase.c
    src/base/ftbbox.c
    src/base/ftbitmap.c
    src/base/ftdebug.c
    src/base/ftfstype.c
    src/base/ftgasp.c
    src/base/ftglyph.c
    src/base/ftinit.c
    src/base/ftmm.c
    src/base/ftstroke.c
    src/base/ftsystem.c
    src/base/fttype1.c
    src/cff/cff.c
    src/cid/type1cid.c
    src/gzip/ftgzip.c
    src/psaux/psaux.c
    src/pshinter/pshinter.c
    src/psnames/psnames.c
    src/raster/raster.c
    src/sdf/sdf.c
    src/sfnt/sfnt.c
    src/smooth/smooth.c
    src/svg/svg.c
    src/truetype/truetype.c
    src/type1/type1.c
)

compile_slice() {
    local sdk="$1"
    local arch="$2"
    local minimum_flag="$3"
    local slice_root="$work_root/$sdk-$arch"
    local object_root="$slice_root/objects"
    mkdir -p "$object_root"

    local common_flags=(
        -arch "$arch"
        "$minimum_flag"
        -O2
        -fPIC
        -ffunction-sections
        -fdata-sections
    )
    local freetype_flags=(
        "${common_flags[@]}"
        -DFT2_BUILD_LIBRARY
        -DDARWIN_NO_CARBON
        -DFT_CONFIG_OPTION_USE_ZLIB
        -DFT_CONFIG_OPTION_SYSTEM_ZLIB
        -Wno-unused-function
        -Wno-unused-parameter
        -Wno-unused-variable
        -I "$freetype_root/include"
    )

    local objects=()
    local source
    for source in "${freetype_sources[@]}"; do
        local object_name="${source//\//_}.o"
        xcrun --sdk "$sdk" clang \
            "${freetype_flags[@]}" \
            -c "$freetype_root/$source" \
            -o "$object_root/$object_name"
        objects+=("$object_root/$object_name")
    done

    xcrun --sdk "$sdk" clang++ \
        "${common_flags[@]}" \
        -std=c++17 \
        -fno-exceptions \
        -fno-rtti \
        -DHAVE_PTHREAD \
        -DHAVE_OT \
        -DHB_NO_PRAGMA_GCC_DIAGNOSTIC \
        -Wno-missing-field-initializers \
        -Wno-unused-parameter \
        -I "$harfbuzz_root/src" \
        -I "$freetype_root/include" \
        -c "$harfbuzz_root/src/harfbuzz.cc" \
        -o "$object_root/harfbuzz.cc.o"
    objects+=("$object_root/harfbuzz.cc.o")

    xcrun --sdk "$sdk" clang++ \
        "${common_flags[@]}" \
        -std=c++17 \
        -fno-exceptions \
        -fno-rtti \
        -I "$vendor_root/include" \
        -I "$harfbuzz_root/src" \
        -I "$freetype_root/include" \
        -c "$vendor_root/src/NileTextRenderer.cc" \
        -o "$object_root/NileTextRenderer.cc.o"
    objects+=("$object_root/NileTextRenderer.cc.o")

    xcrun ar rcs \
        "$slice_root/libNileTextRenderer.a" \
        "${objects[@]}"
}

compile_slice iphoneos arm64 -miphoneos-version-min=17.0
compile_slice iphonesimulator arm64 -mios-simulator-version-min=17.0
compile_slice iphonesimulator x86_64 -mios-simulator-version-min=17.0

simulator_library="$work_root/libNileTextRenderer-simulator.a"
xcrun lipo -create \
    "$work_root/iphonesimulator-arm64/libNileTextRenderer.a" \
    "$work_root/iphonesimulator-x86_64/libNileTextRenderer.a" \
    -output "$simulator_library"

make_framework() {
    local library="$1"
    local destination="$2"
    local supported_platform="$3"
    local platform_variant="${4:-}"
    mkdir -p "$destination/Headers"
    mkdir -p "$destination/Modules"
    mkdir -p "$destination/Resources/ThirdPartyNotices"
    ditto \
        "$vendor_root/include/NileTextRenderer.h" \
        "$destination/Headers/NileTextRenderer.h"
    ditto \
        "$vendor_root/module.modulemap" \
        "$destination/Modules/module.modulemap"
    ditto "$library" "$destination/NileTextRenderer"
    ditto \
        "$freetype_root/docs/FTL.TXT" \
        "$destination/Resources/ThirdPartyNotices/FreeType-FTL.txt"
    ditto \
        "$harfbuzz_root/COPYING" \
        "$destination/Resources/ThirdPartyNotices/HarfBuzz-COPYING.txt"

    local plist="$destination/Info.plist"
    plutil -create xml1 "$plist"
    plutil -insert CFBundleDevelopmentRegion -string en "$plist"
    plutil -insert CFBundleExecutable \
        -string NileTextRenderer "$plist"
    plutil -insert CFBundleIdentifier \
        -string com.niles.NileTextRenderer "$plist"
    plutil -insert CFBundleInfoDictionaryVersion -string 6.0 "$plist"
    plutil -insert CFBundleName \
        -string NileTextRenderer "$plist"
    plutil -insert CFBundlePackageType -string FMWK "$plist"
    plutil -insert CFBundleShortVersionString -string 1.0.0 "$plist"
    plutil -insert CFBundleVersion -string 1 "$plist"
    plutil -insert MinimumOSVersion -string 17.0 "$plist"
    plutil -insert CFBundleSupportedPlatforms -json \
        "[\"$supported_platform\"]" "$plist"
    if test -n "$platform_variant"; then
        plutil -insert CFBundleSupportedPlatformVariant \
            -string "$platform_variant" "$plist"
    fi
}

device_framework="$work_root/device/NileTextRenderer.framework"
simulator_framework="$work_root/simulator/NileTextRenderer.framework"
make_framework \
    "$work_root/iphoneos-arm64/libNileTextRenderer.a" \
    "$device_framework" \
    iPhoneOS
make_framework \
    "$simulator_library" \
    "$simulator_framework" \
    iPhoneSimulator \
    simulator

staged_output="$work_root/NileTextRenderer.xcframework"
xcodebuild -create-xcframework \
    -framework "$device_framework" \
    -framework "$simulator_framework" \
    -output "$staged_output"

rm -rf "$output"
ditto "$staged_output" "$output"

find "$output" -type f -print0 \
    | sort -z \
    | xargs -0 shasum -a 256
