use_frameworks!

target 'DITranquillity-iOS' do
    platform :ios, '8.0'
    pod 'SwiftLazy', :git => 'https://github.com/ivlevAstef/SwiftLazy'

    target 'DITranquillityTests' do
    	inherit! :search_paths
    	pod 'SwiftLazy', :git => 'https://github.com/ivlevAstef/SwiftLazy'
    end 
end

target 'DITranquillity-OSX' do
    platform :osx, '10.10'
    pod 'SwiftLazy', :git => 'https://github.com/ivlevAstef/SwiftLazy'
end

target 'DITranquillity-tvOS' do
    platform :tvos, '9.0'
    pod 'SwiftLazy', :git => 'https://github.com/ivlevAstef/SwiftLazy'
end


post_install do |installer|
    installer.pods_project.targets.each do |target|
        target.build_configurations.each do |config|
            config.build_settings['SWIFT_VERSION'] = '4.2'
        end
    end
end