Pod::Spec.new do |s|
  s.name             = 'DVTNetwork'
  s.version          = '2.0.0'
  s.summary          = 'DVTNetwork'

  s.description      = <<-DESC
  TODO:
    基于Alamofire的一个网络框架，利用文件对get请求进行缓存
  DESC

  s.homepage         = 'https://github.com/darvintang/DVTNetwork'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'darvin' => 'darvin@tcoding.cn' }
  s.source           = { :git => 'https://github.com/darvintang/DVTNetwork.git', :tag => s.version.to_s }

  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '11'

  s.source_files = 'Sources/**/*.swift'

  s.swift_version = '5'
  s.requires_arc  = true

  s.dependency 'Alamofire', '~> 5.6.0'
  s.dependency 'DVTLoger', '~> 2.0.0'
  
end
