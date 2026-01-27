#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint kitako_ffi.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'kitako_ffi'
  s.version          = '0.0.1'
  s.summary          = 'KitaKo FFI plugin with HNSW ANN support'
  s.description      = <<-DESC
Native FFI plugin for KitaKo providing HNSW-based ANN search.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }

  s.source           = { :path => '.' }
  s.source_files     = '../src/**/*.{h,c,cpp}'
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.14'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++14',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/../src" "${PODS_TARGET_SRCROOT}/../src/hnswlib"',
    'GCC_PREPROCESSOR_DEFINITIONS' => 'DART_SHARED_LIB=1'
  }
  s.swift_version = '5.0'
end
