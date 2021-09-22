Pod::Spec.new do |s|
  s.name             = 'DVTNetwork'
  s.version          = '1.0.1'
  s.summary          = 'DVTNetwork'

  s.description      = <<-DESC
  TODO: 基于Alamofire的一个网络框架，利用文件对get请求进行缓存
                       DESC

  s.homepage         = 'https://github.com/darvintang/DVTNetwork'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'xt-input' => 'input@tcoding.cn' }
  s.source           = { :git => 'https://github.com/darvintang/DVTNetwork.git', :tag => s.version.to_s }

  s.ios.deployment_target = '10.0'
  s.osx.deployment_target = '10.12'
  s.tvos.deployment_target = '10.0'
  s.watchos.deployment_target = '3.0'

  s.source_files = 'Source/**/*.swift'

  s.swift_version = '5'
  s.requires_arc  = true

  s.dependency 'Alamofire', '>= 5.4.0'
  s.dependency 'DVTLoger', '>= 1.0.0'
  s.dependency 'DVTObjectMapper', '>= 4.2.0'
  
end