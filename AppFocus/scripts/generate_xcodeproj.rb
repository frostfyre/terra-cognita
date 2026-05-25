#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates TerraCognita.xcodeproj from scratch.
#
# The project has two app targets — TerraCognita-macOS and
# TerraCognita-iOS — each depending on the AppFocusKit Swift package
# product defined in Package.swift at the same directory.
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

# Wipe any previous project so generation is idempotent.
FileUtils.rm_rf(PROJECT_PATH)

project = Xcodeproj::Project.new(PROJECT_PATH)

# --- Local Swift package reference (the AppFocusKit library) ---
local_package = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
local_package.relative_path = '.'
project.root_object.package_references << local_package

def add_appfocus_kit_dependency(target, local_package)
  product = target.project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  product.package = local_package
  product.product_name = 'AppFocusKit'
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
add_appfocus_kit_dependency(mac_target, local_package)
shared_build_settings(mac_target, 'MACOSX_DEPLOYMENT_TARGET', '14.0')
mac_target.build_configurations.each do |config|
  s = config.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.frostfyre.terracognita.mac'
  s['INFOPLIST_KEY_LSApplicationCategoryType'] = 'public.app-category.productivity'
  s['ENABLE_HARDENED_RUNTIME'] = 'YES'
  s['CODE_SIGN_IDENTITY'] = '-' # ad-hoc, no team required for local builds
  s['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
end

# --- iOS app target (universal: iPhone + iPad) ---
ios_target = project.new_target(:application, 'TerraCognita-iOS', :ios, '17.0', nil, :swift)
ios_group = project.new_group('TerraCognita-iOS', 'Apps/TerraCognita-iOS')
ios_app_file = ios_group.new_reference('TerraCognitaIOSApp.swift')
ios_target.source_build_phase.add_file_reference(ios_app_file)
attach_assets(ios_target, ios_group, 'Assets.xcassets')
add_appfocus_kit_dependency(ios_target, local_package)
shared_build_settings(ios_target, 'IPHONEOS_DEPLOYMENT_TARGET', '17.0')
ios_target.build_configurations.each do |config|
  s = config.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.frostfyre.terracognita.ios'
  s['TARGETED_DEVICE_FAMILY'] = '1,2' # iPhone + iPad
  s['INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents'] = 'YES'
  s['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
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
