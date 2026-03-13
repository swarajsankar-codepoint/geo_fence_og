# ios/Podfile
# Add Firebase Remote Config pod

platform :ios, '14.0'  # minimum iOS 13 for BGTaskScheduler

# ... your existing content ...

target 'Runner' do
  use_frameworks!
  use_modular_headers!

  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))

  # Firebase — add these
  pod 'Firebase/Core'
  pod 'Firebase/RemoteConfig'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
    end
  end
end
