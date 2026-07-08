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
# Object UUIDs are made deterministic (see UUIDGenerator below), so
# regenerating without structural changes is a no-op diff and a pure
# build-number bump touches only the two version lines. Source files
# for the app targets live under Apps/TerraCognita-macOS/ and
# Apps/TerraCognita-iOS/ and should be edited directly.

require 'xcodeproj'
require 'xcodeproj/project/uuid_generator'
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
#   CURRENT_PROJECT_VERSION — Build number. Defaults to a static '1'
#                             so the committed project file never
#                             carries a per-build timestamp (which
#                             would churn the build-config UUIDs every
#                             upload). The real monotonic build number
#                             is injected at archive time by
#                             upload_testflight.sh via an xcodebuild
#                             setting override. Override here only if
#                             you need to bake a specific integer in.
#
# Without DEVELOPMENT_TEAM, the project falls back to its dev-mode
# ad-hoc Mac signing + simulator-only iOS signing.
# Default to Paul's Apple Developer Team. Override with
# `DEVELOPMENT_TEAM=… ./generate_xcodeproj.rb` if you ever need to ship
# from a different team.
TEAM_ID              = ENV['DEVELOPMENT_TEAM'] || 'TUMFPT4C67'
MARKETING_VERSION    = ENV['MARKETING_VERSION'] || '1.0.1'
CURRENT_BUILD_NUMBER = ENV['CURRENT_PROJECT_VERSION'] || '1'

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
    # Apple Music binding (per-atlas soundtrack suggestions). Used
    # only when the user opts into chime + accepts a music suggestion.
    # iOS overrides the generated plist with its hand-rolled one and
    # has its own NSAppleMusicUsageDescription entry there; this
    # setting carries the macOS value.
    s['INFOPLIST_KEY_NSAppleMusicUsageDescription'] =
      'Terra Cognita can play Apple Music alongside your atlas — each atlas can suggest a soundtrack that fits its mood, like Joe Hisaishi for the Miyazaki demo. Only used when you opt in.'
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
  # Share the iOS bundle id so iOS + macOS link as a single Universal
  # Purchase in App Store Connect. Two separate ASC app records (one
  # per platform), one customer purchase, one customer-facing identity.
  # The iOS record must have Universal Purchase enabled; the macOS
  # record is created separately under the same bundle id.
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.frostfyre.terracognitaatlas'
  s['INFOPLIST_KEY_LSApplicationCategoryType'] = 'public.app-category.productivity'
  s['ENABLE_HARDENED_RUNTIME'] = 'YES'
  # App Sandbox + microphone + user-selected-file access. Required for
  # Mac App Store distribution; harmless for ad-hoc dev signing too.
  s['CODE_SIGN_ENTITLEMENTS'] = 'Apps/TerraCognita-macOS/TerraCognita-macOS.entitlements'
  # Mac signing is opt-in via MAC_SIGN=1 — requires a Mac Development
  # certificate in your keychain. Without it we keep ad-hoc signing
  # so the Mac app builds locally even when a Developer Team is set
  # for iOS distribution.
  s['CODE_SIGN_IDENTITY'] = ENV['MAC_SIGN'] == '1' ? 'Apple Development' : '-'
  s['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  # Partial Info.plist: GENERATE_INFOPLIST_FILE stays YES (set in
  # shared_build_settings), so Xcode merges the generated keys into this
  # base file. It carries only the custom URL scheme
  # (terracognita://redeem?token=…) used to redeem Pro grant tokens,
  # which the INFOPLIST_KEY_* aliases can't express.
  s['INFOPLIST_FILE'] = 'Apps/TerraCognita-macOS/Info.plist'
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
  # Bundle id is `terracognitaatlas` (one word, no dot before atlas) —
  # that's the exact string registered in App Store Connect under the
  # TUMFPT4C67 team for the iOS app. Don't dot-separate; ASC sees it
  # as a different app.
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.frostfyre.terracognitaatlas'
  s['TARGETED_DEVICE_FAMILY'] = '1,2' # iPhone + iPad
  # iOS uses a hand-rolled Info.plist instead of GENERATE_INFOPLIST_FILE
  # because Xcode 26's INFOPLIST_KEY_* auto-aliasing produced an empty
  # UILaunchScreen dict no matter what spelling we tried (Image,
  # UIImageName, BackgroundColor, UIColorName). The file at
  # Apps/TerraCognita-iOS/Info.plist sets the UILaunchScreen dict
  # directly per Apple's spec, with UIImageName = TerraCognitaLaunch
  # and UIColorName = LaunchBackground.
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['INFOPLIST_FILE'] = 'Apps/TerraCognita-iOS/Info.plist'
  # Sim-only signing during local development; xcodebuild w/ iOS Simulator
  # ignores signing requirements unless CODE_SIGNING_ALLOWED is set.
  s['CODE_SIGN_IDENTITY[sdk=iphoneos*]'] = 'Apple Development'
  s['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
end

# --- Rewrite system framework references to use $(SDKROOT) ---
# The xcodeproj gem hardcodes specific SDK versions into framework
# paths (e.g. MacOSX15.0.sdk/..., iPhoneOS18.0.sdk/...). On a
# machine running a different Xcode (and therefore a different
# installed SDK) those paths don't resolve and the build fails
# with "No such file or directory". Rewrite both system framework
# refs to use the SDKROOT source tree so they resolve against
# whatever SDK is current at build time.
project.files.each do |file|
  next unless file.path

  if file.path =~ %r{Platforms/MacOSX\.platform/Developer/SDKs/MacOSX[\d.]+\.sdk/System/Library/Frameworks/Cocoa\.framework\z}
    file.path = 'System/Library/Frameworks/Cocoa.framework'
    file.source_tree = 'SDKROOT'
  elsif file.path =~ %r{Platforms/iPhoneOS\.platform/Developer/SDKs/iPhoneOS[\d.]+\.sdk/System/Library/Frameworks/Foundation\.framework\z}
    file.path = 'System/Library/Frameworks/Foundation.framework'
    file.source_tree = 'SDKROOT'
  end
end

# --- StoreKit local-testing configuration ---
# A loose file reference so Products.storekit shows in Xcode's navigator.
# The scheme's StoreKitConfigurationFileReference (added below) is what
# actually drives local StoreKit testing; it's path-based, not tied to
# this ref's UUID.
storekit_ref = project.main_group.new_reference('Products.storekit')
storekit_ref.last_known_file_type = 'text'

# --- Deterministic object UUIDs ---
# The xcodeproj gem assigns a random 24-char hex UUID to every object
# on each run, so regeneration rewrote all ~200 object ids (and the
# scheme BlueprintIdentifiers), burying every build-number bump under
# hundreds of lines of churn. This generator — the same one CocoaPods
# uses — derives each UUID from a stable hash of the object's position
# in the tree, so the same project structure always produces the same
# ids. Run before `save` (and before scheme writing) so schemes pick
# up the stable target ids too.
Xcodeproj::Project::UUIDGenerator.new([project]).generate!

# --- Shared schemes so the two apps surface in Xcode's scheme picker ---
project.save

[mac_target, ios_target].each do |target|
  scheme = Xcodeproj::XCScheme.new
  scheme.add_build_target(target)
  scheme.set_launch_target(target)
  # Attach the StoreKit configuration so purchases work against the local
  # Products.storekit (no sandbox account needed) when running from Xcode.
  # xcodeproj 1.27 has no helper for this node, so write it directly. The
  # identifier is the path relative to the .xcodeproj container.
  scheme.launch_action.xml_element.add_element(
    'StoreKitConfigurationFileReference',
    'identifier' => '../Products.storekit'
  )
  scheme.save_as(PROJECT_PATH, target.name, true)
end

puts "Generated: #{PROJECT_PATH}"
