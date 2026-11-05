Pod::Spec.new do |s|
  s.name             = 'TieredCache'
  s.version          = '0.1.0'
  s.summary          = 'A tiered (memory + disk) cache for Swift.'
  s.description      = 'TieredCache provides a memory and disk tiered cache with downloader and transformer support.'
  s.homepage         = 'https://github.com/a451019070/TieredCache'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'ZX' => '895843633@qq.com' }
  s.source           = { :git => 'https://github.com/a451019070/TieredCache.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'
  s.swift_version    = '5.9'

  s.source_files     = 'Sources/TieredCache/**/*.swift'
  s.frameworks       = 'Foundation', 'CryptoKit'
end
