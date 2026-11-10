#
# Run `pod lib lint store_update.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'store_update'
  s.version          = '0.1.0'
  s.summary          = 'In-app update prompt that opens the App Store page inside the app.'
  s.description      = <<-DESC
Shows the app's App Store page over the app (SKStoreProductViewController) when a newer version is available.
                       DESC
  s.homepage         = 'https://github.com/Hamza-Shewa/store_update'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Hamza Aboshhiwa' => '42789638+Hamza-Shewa@users.noreply.github.com' }
  s.source           = { :path => '.' }
  s.source_files = 'store_update/Sources/store_update/**/*.swift'
  s.dependency 'Flutter'
  s.frameworks = 'StoreKit'
  s.resource_bundles = { 'store_update_privacy' => ['store_update/Sources/store_update/PrivacyInfo.xcprivacy'] }
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
