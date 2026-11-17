Pod::Spec.new do |s|
  s.name = 'DshEmbeddedNode'
  s.version = '0.1.0'
  s.summary = 'In-process iOS Node runtime compatibility probe for DeepSeek harness.'
  s.description = 'Links a pinned NodeMobile XCFramework. No Linux binaries, child process, or remote engine.'
  s.homepage = 'https://github.com/wanan8396/deepseek-harness-app'
  s.license = { :type => 'AGPL-3.0', :file => '../../../LICENSE' }
  s.author = { 'wanan8396' => 'wanan8396@users.noreply.github.com' }
  s.source = { :path => '.' }
  s.platform = :ios, '16.0'
  s.dependency 'Flutter'
  s.source_files = 'Sources/**/*.{h,mm,swift}'
  s.public_header_files = 'Sources/DshEmbeddedNode.h'
  s.vendored_frameworks = 'Vendor/NodeMobile.xcframework'
  s.resources = 'Resources/*'
  s.swift_version = '5.0'
  s.pod_target_xcconfig = { 'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17', 'DEFINES_MODULE' => 'YES' }
end
