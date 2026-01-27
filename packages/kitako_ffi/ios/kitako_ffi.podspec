#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint kitako_ffi.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'kitako_ffi'
  s.version          = '0.0.1'
  s.summary          = 'KitaKo FFI plugin with HNSW ANN support.'
  s.description      = <<-DESC
KitaKo FFI plugin providing native ANN (Approximate Nearest Neighbor) search
using HNSW algorithm for on-device multimodal image retrieval.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }

  # This will ensure the source files in Classes/ are included in the native
  # builds of apps using this FFI plugin. Podspec does not support relative
  # paths, so Classes contains a forwarder C file that relatively imports
  # `../src/*` so that the C sources can be shared among all target platforms.
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*', '../src/**/*.{h,c,cpp}'
  s.public_header_files = '../src/*.h'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # C++ settings for hnswlib
  s.libraries = 'c++'
  s.xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++14',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'OTHER_CPLUSPLUSFLAGS' => '-fvisibility=default'
  }

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 
    'DEFINES_MODULE' => 'YES', 
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/../src" "${PODS_TARGET_SRCROOT}/../src/hnswlib"'
  }
  s.swift_version = '5.0'
end
