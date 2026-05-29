#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates TerraCognita.xcodeproj from scratch.
#
# The project has two app targets — TerraCognita-macOS and
# TerraCognita-iOS — each depending on the TerraCognitaKit Swift
# package product defined in Package.swift at the same directory.
#
# Regenerate (e.g. after adding new build settings or files) with:
#
#     ruby scripts/generate_xcodeproj.rb
#
# UUIDs are randomized by xcodeproj, so regeneration produces churn —
# only run when needed. Source files for the app targets live under
# Apps/TerraCognita-macOS/ and Apps/TerraCognita-iOS/ and should be
# edited directly.

require 'xcodeproj'
require 'fileutils'

ROOT = File.expand_path(File.join(__dir__, '..'))
PROJECT_PATH = File.join(ROOT, 'TerraCognita.xcodeproj')

# Distribution-tier knobs, all overridable via env so the script
# doesn't carry secrets in git:
#
#   DEVELOPMENT_TEAM      — Apple Developer Team ID (10-char alphanum).
#                           Required for installs on real iOS devices,
#                           TestFlight uploads, and signed Mac builds.
#   MARKETING_VERSION     — User-facing version (e.g. "1.0").
#   CURRENT_PROJECT_VERSION — Build number. Defaults to a YYMMDDHHMM
#                             timestamp so every regen is automatically
#                             greater than the last — TestFlight rejects
#                             a build whose CFBundleVersion isn't strictly
#                             higher than the previous upload. Override
#                             only if you need a specific integer.
#
# Without DEVELOPMENT_TEAM, the project falls back to its dev-mode
# ad-hoc Mac signing + simulator-only iOS signing.
TEAM_ID              = ENV['DEVELOPMENT_TEAM']
MARKETING_VERSION    = ENV['MARKETING_VERSION'] || '1.0'
CURRENT_BUILD_NUMBER = ENV['CURRENT_PROJECT_VERSION'] || Time.now.strftime('%y%m%d%H%M')

# Wipe any previous project so generation is idempotent.
FileUtils.rm_rf(PROJECT_PATH)

project = Xcodeproj::Project.new(PROJECT_PATH)

# --- Local Swift package reference (the TerraCognitaKit library) ---
local_package = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
local_package.relative_path = '.'
project.root_object.package_references << local_package

def add_terra_cognita_kit_dependency(target, local_package)
  product = target.project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  product.package = local_package
  product.product_name = 'TerraCognitaKit'
  target.package_product_dependencies << product

  build_file = target.project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = product
  target.frameworks_build_phase.files << build_file
end

def shared_build_settings(target, deployment_setting_key, deployment_value)
  target.build_configurations.each do |config|
    s = config.build_settings
    s[deployment_setting_key] = deployment_value
    s['SWIFT_VERSION'] = '6.0'
    s['GENERATE_INFOPLIST_FILE'] = 'YES'
    s['INFOPLIST_KEY_CFBundleDisplayName'] = 'Terra Cognita'
    s['CODE_SIGN_STYLE'] = 'Automatic'
    s['ASSETCATALOG_COMPILER_GENERATE_ASSET_SYMBOLS'] = 'NO'
    # Version + build — CURRENT_PROJECT_VERSION defaults to a timestamp
    # so each regen is monotonically greater than the previous upload.
    s['MARKETING_VERSION'] = MARKETING_VERSION
    s['CURRENT_PROJECT_VERSION'] = CURRENT_BUILD_NUMBER
    # Tell TestFlight we don't ship custom encryption (URLSession's
    # built-in HTTPS is exempt). Skips the per-upload prompt.
    s['INFOPLIST_KEY_ITSAppUsesNonExemptEncryption'] = 'NO'
    # Apple Developer Team — required for on-device installs +
    # TestFlight. Empty string leaves it unmanaged (Xcode UI can fill
    # it in for personal-team development).
    s['DEVELOPMENT_TEAM'] = TEAM_ID if TEAM_ID
    # Capture feature: voice dictation uses on-device SFSpeechRecognizer
    # and the microphone. Both purposes are personal — no audio leaves
    # the device, no transcripts are uploaded.
    s['INFOPLIST_KEY_NSSpeechRecognitionUsageDescription'] =
      'Terra Cognita uses on-device speech recognition to capture spoken notes. Audio stays on this device.'
    s['INFOPLIST_KEY_NSMicrophoneUsageDescription'] =
      'Terra Cognita uses the microphone for voice capture. Audio is transcribed on-device and never uploaded.'
  end
end

# Helper — adds an .xcassets folder reference to the target as a
# Resources build phase entry. The folder is referenced as a group,
# so all of its files (Contents.json plus the .appiconset) are
# carried along automatically.
def attach_assets(target, group, asset_dir_name)
  asset_ref = group.new_reference(asset_dir_name)
  asset_ref.last_known_file_type = 'folder.assetcatalog'
  target.resources_build_phase.add_file_reference(asset_ref)
end

# --- macOS app target ---
mac_target = project.new_target(:application, 'TerraCognita-macOS', :osx, '14.0', nil, :swift)
mac_group = project.new_group('TerraCognita-macOS', 'Apps/TerraCognita-macOS')
mac_app_file = mac_group.new_reference('TerraCognitaMacApp.swift')
mac_target.source_build_phase.add_file_reference(mac_app_file)
attach_assets(mac_target, mac_group, 'Assets.xcassets')
add_terra_cognita_kit_dependency(mac_target, local_package)
shared_build_settings(mac_target, 'MACOSX_DEPLOYMENT_TARGET', '14.0')
mac_target.build_configurations.each do |config|
  s = config.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.frostfyre.terracognita.mac'
  s['INFOPLIST_KEY_LSApplicationCategoryType'] = 'public.app-category.productivity'
  s['ENABLE_HARDENED_RUNTIME'] = 'YES'
  # Mac signing is opt-in via MAC_SIGN=1 — requires a Mac Development
  # certificate in your keychain. Without it we keep ad-hoc signing
  # so the Mac app builds locally even when a Developer Team is set
  # for iOS distribution.
  s['CODE_SIGN_IDENTITY'] = ENV['MAC_SIGN'] == '1' ? 'Apple Development' : '-'
  s['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
end

# --- iOS app target (universal: iPhone + iPad) ---
ios_target = project.new_target(:application, 'TerraCognita-iOS', :ios, '17.0', nil, :swift)
ios_group = project.new_group('TerraCognita-iOS', 'Apps/TerraCognita-iOS')
ios_app_file = ios_group.new_reference('TerraCognitaIOSApp.swift')
ios_target.source_build_phase.add_file_reference(ios_app_file)
attach_assets(ios_target, ios_group, 'Assets.xcassets')
add_terra_cognita_kit_dependency(ios_target, local_package)
shared_build_settings(ios_target, 'IPHONEOS_DEPLOYMENT_TARGET', '17.0')
ios_target.build_configurations.each do |config|
  s = config.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.frostfyre.terracognita.ios'
  s['TARGETED_DEVICE_FAMILY'] = '1,2' # iPhone + iPad
  s['INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents'] = 'YES'
  s['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
  # Match the canvas's inner indigo so the launch screen reads as
  # the same scene the app is about to show. The color lives in
  # Apps/TerraCognita-iOS/Assets.xcassets/LaunchBackground.colorset.
  s['INFOPLIST_KEY_UILaunchScreen_BackgroundColor'] = 'LaunchBackground'
  # Gold core + six orbital sparks centered on the launch surface so
  # the cold-start reads as "Terra Cognita is launching" rather than a
  # flat-color void. Asset at
  # Apps/TerraCognita-iOS/Assets.xcassets/LaunchLogo.imageset.
  s['INFOPLIST_KEY_UILaunchScreen_Image'] = 'LaunchLogo'
  s['INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone'] =
    'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight'
  s['INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad'] =
    'UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight'
  # Sim-only signing during local development; xcodebuild w/ iOS Simulator
  # ignores signing requirements unless CODE_SIGNING_ALLOWED is set.
  s['CODE_SIGN_IDENTITY[sdk=iphoneos*]'] = 'Apple Development'
  s['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
end

# --- Shared schemes so the two apps surface in Xcode's scheme picker ---
project.save

[mac_target, ios_target].each do |target|
  scheme = Xcodeproj::XCScheme.new
  scheme.add_build_target(target)
  scheme.set_launch_target(target)
  scheme.save_as(PROJECT_PATH, target.name, true)
end

puts "Generated: #{PROJECT_PATH}"
