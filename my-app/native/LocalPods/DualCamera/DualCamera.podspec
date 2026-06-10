Pod::Spec.new do |s|
  s.name         = "DualCamera"
  s.version      = "1.0.3"
  s.summary      = "Dual camera module for React Native"
  s.description  = "Native dual camera module using two AVCaptureSessions"
  s.homepage     = "https://github.com/example/DualCamera"
  s.license      = { :type => "MIT" }
  s.author       = { "Author" => "author@example.com" }
  s.platform     = :ios, "13.0"
  s.source       = { :path => "." }
  s.source_files = "*.{h,m,mm,swift}"
  s.swift_version = "5.0"
  s.frameworks   = "AVFoundation", "UIKit", "Photos", "StoreKit", "CoreMedia", "CoreVideo", "OpenGLES"
  s.libraries    = "c++"
  gpupixel_framework = "Frameworks/gpupixel.framework"
  if File.exist?(File.join(__dir__, gpupixel_framework))
    s.vendored_frameworks = gpupixel_framework
    s.pod_target_xcconfig = {
      "CLANG_CXX_LANGUAGE_STANDARD" => "c++17",
      "CLANG_CXX_LIBRARY" => "libc++"
    }
  end
  s.dependency "React-Core"
end
