Pod::Spec.new do |s|
	s.name         = "JYEventSource"
	s.version      = "2.0.0"
	s.summary      = "Server Sent Events for iOS, MacOS and watchOS platforms, implemented in Objective-C, forked from \"neilco/EventSource\"."
	s.homepage     = "https://github.com/MythYing/JYEventSource"
	s.license      = 'MIT (see LICENSE.txt)'
	s.author       = { "Neil Cowburn" => "git@neilcowburn.com", "Jiang Ying" => "1282188232@qq.com" }
	s.source       = { :git => "https://github.com/MythYing/JYEventSource.git", :tag => s.version.to_s }
	s.source_files = 'EventSource', 'EventSource/EventSource.{h,m}'
	s.ios.xcconfig = { 'FRAMEWORK_SEARCH_PATHS' => '$(inherited) "$(SDKROOT)/Developer/Library/Frameworks" "$(DEVELOPER_LIBRARY_DIR)/Frameworks"' }
	s.osx.xcconfig = { 'FRAMEWORK_SEARCH_PATHS' => '$(inherited) "$(DEVELOPER_LIBRARY_DIR)/Frameworks"' }
	s.ios.deployment_target = '7.0'
	s.osx.deployment_target = '10.7'
	s.requires_arc = true
	s.xcconfig = { 'OTHER_LDFLAGS' => '-lObjC' }
end
