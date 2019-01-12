Pod::Spec.new do |s|
    s.name         = 'IMPFileManager'
    s.version      = '0.2.0'
    s.license      = { :type => 'MIT', :file => 'LICENSE' }
    s.author       = { 'Denn Nevera' => 'https://imagemetalling.wordpress.com/' }
    s.homepage     = 'http://www.dehancer.com/'
    s.summary      = 'File Manager Utils'
    s.description  = 'File Manager Utils'
    
    s.source       = { :git => 'https://github.com/dehancer/IMPFileManager', :tag => s.version}
    
    s.osx.deployment_target = "10.12"
    s.swift_version = "4.2"

    s.source_files  = 'System/**/*.{h,m,swift}','Cache/**/*.{swift}'
    s.public_header_files = 'System/**/*.h'
    
    s.requires_arc = true

end
