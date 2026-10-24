# Copyright 2026 Tom Ballard. MIT License.
gem 'xcodeproj', '1.27.0'
require 'xcodeproj'
require 'fileutils'
require 'json'

root = File.expand_path('../..', __dir__)
utm = File.expand_path(ARGV.fetch(0))
lock = JSON.parse(File.read(File.join(root, 'ios/upstream.json')))
bundle = lock.fetch('bundlePrefix') + '.UTM'
number = (100 + Integer(ENV.fetch('GITHUB_RUN_NUMBER', '1'))).to_s
project = Xcodeproj::Project.open(File.join(utm, 'UTM.xcodeproj'))
app = project.targets.find { |t| t.name == 'iOS' } or abort 'Missing iOS app target'
old_helper = project.targets.find { |t| t.name == 'iOSHelper' } or abort 'Missing original QEMU helper'
abort 'Use a clean UTM checkout' if project.targets.any? { |t| t.name == 'OmarchyJITHelper' }

%w[Integrated JITHelper LocalTunnel Notices].each do |name|
  FileUtils.mkdir_p(File.join(utm, 'Omarchy', name))
  FileUtils.cp_r(File.join(root, 'ios', name, '.'), File.join(utm, 'Omarchy', name))
end
FileUtils.mkdir_p(File.join(utm, 'Omarchy/Pairing'))
FileUtils.cp_r(File.join(root, 'ios/Pairing/include'), File.join(utm, 'Omarchy/Pairing/'))
group = project.main_group.new_group('Omarchy', 'Omarchy')
files = {}
Dir.glob(File.join(utm, 'Omarchy/{Integrated,JITHelper,LocalTunnel}/**/*')).sort.each do |path|
  next unless File.file?(path)
  relative = path.delete_prefix(File.join(utm, 'Omarchy/'))
  files[relative] = group.new_file(relative)
end
Dir.glob(File.join(utm, 'Omarchy/Integrated/*.{swift,c}')).sort.each do |path|
  app.source_build_phase.add_file_reference(files.fetch('Integrated/' + File.basename(path)))
end
bridge = File.join(utm, 'Services/Swift-Bridging-Header.h')
unless File.read(bridge).include?('OmarchyPairing.h')
  File.open(bridge, 'a') { |f| f.puts "\n#include \"../Omarchy/Pairing/include/OmarchyPairing.h\"" }
end
notices = group.new_file('Notices')
notices.last_known_file_type = 'folder'
app.resources_build_phase.add_file_reference(notices)

def settings(target, bundle_id, number)
  target.build_configurations.each do |configuration|
    s = configuration.build_settings
    s['PRODUCT_BUNDLE_IDENTIFIER'] = bundle_id
    s['MARKETING_VERSION'] = '0.2.0'
    s['CURRENT_PROJECT_VERSION'] = number
    s['PRODUCT_NAME'] = '$(TARGET_NAME)'
    s['SWIFT_VERSION'] = '5.0'
    s['SWIFT_APPROACHABLE_CONCURRENCY'] = 'YES'
    s['SWIFT_DEFAULT_ACTOR_ISOLATION'] = 'nonisolated'
    s['IPHONEOS_DEPLOYMENT_TARGET'] = '26.0'
    s['TARGETED_DEVICE_FAMILY'] = '1,2'
    s['SUPPORTED_PLATFORMS'] = 'iphoneos'
    s['SKIP_INSTALL'] = 'YES'
    s['GENERATE_INFOPLIST_FILE'] = 'YES'
    s['CODE_SIGNING_ALLOWED'] = 'NO'
    s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
  end
end

jit = project.new_target(:app_extension, 'OmarchyJITHelper', :ios, '26.0')
jit.product_type = old_helper.product_type
jit.product_reference.explicit_file_type = old_helper.product_reference.explicit_file_type
settings(jit, bundle + '.JITHelper', number)
jit.build_configurations.each do |configuration|
  configuration.build_settings['EX_ENABLE_EXTENSION_POINT_GENERATION'] = 'YES'
  configuration.build_settings['UTM_HOST_BUNDLE_IDENTIFIER'] = bundle
  configuration.build_settings['INFOPLIST_KEY_CFBundleDisplayName'] = 'iPhomarchy Acceleration'
  configuration.build_settings['FRAMEWORK_SEARCH_PATHS'] = ['$(inherited)', '$(SRCROOT)/Omarchy/Dependencies']
end
%w[Integrated/OmarchyJITProtocol.swift JITHelper/OmarchyJITHelper.swift].each do |file|
  jit.source_build_phase.add_file_reference(files.fetch(file))
end
framework = group.new_file('Dependencies/StikJIT.framework')
jit.frameworks_build_phase.add_file_reference(framework)
embed_framework = jit.new_copy_files_build_phase('Embed StikJIT')
embed_framework.dst_subfolder_spec = '10'
embed_framework.add_file_reference(framework).settings = { 'ATTRIBUTES' => %w[CodeSignOnCopy RemoveHeadersOnCopy] }

vpn = project.new_target(:app_extension, 'OmarchyLocalTunnel', :ios, '26.0')
settings(vpn, bundle + '.LocalTunnel', number)
vpn.build_configurations.each do |configuration|
  configuration.build_settings['INFOPLIST_FILE'] = 'Omarchy/LocalTunnel/Info.plist'
  configuration.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Omarchy/LocalTunnel/LocalTunnel.entitlements'
  configuration.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
end
%w[LocalTunnel/OmarchyLoopbackPacket.swift LocalTunnel/OmarchyPacketTunnelProvider.swift].each do |file|
  vpn.source_build_phase.add_file_reference(files.fetch(file))
end
def sdk_framework(project, target, name)
  path = "System/Library/Frameworks/#{name}.framework"
  ref = project.files.find { |file| file.path == path && file.source_tree == 'SDKROOT' }
  unless ref
    ref = project.frameworks_group.new_file(path)
    ref.source_tree = 'SDKROOT'
    ref.last_known_file_type = 'wrapper.framework'
  end
  target.frameworks_build_phase.add_file_reference(ref, true)
end
sdk_framework(project, vpn, 'NetworkExtension')
sdk_framework(project, app, 'NetworkExtension')
sdk_framework(project, app, 'BackgroundTasks')
app.frameworks_build_phase.add_file_reference(group.new_file('Dependencies/libomarchy_pairing.a'))
app.build_configurations.each do |configuration|
  configuration.build_settings['HEADER_SEARCH_PATHS'] = ['$(inherited)', '$(SRCROOT)/Omarchy/Pairing/include']
  configuration.build_settings['EX_ENABLE_EXTENSION_POINT_GENERATION'] = 'YES'
  configuration.build_settings['MARKETING_VERSION'] = '0.2.0'
  configuration.build_settings['CURRENT_PROJECT_VERSION'] = number
end
old_helper.build_configurations.each do |configuration|
  configuration.build_settings['MARKETING_VERSION'] = '0.2.0'
  configuration.build_settings['CURRENT_PROJECT_VERSION'] = number
end
app.add_dependency(jit)
app.add_dependency(vpn)
embed_kit = app.copy_files_build_phases.find { |p| p.name == 'Embed ExtensionKit Extensions' } or abort 'Missing ExtensionKit embedding'
embed_kit.add_file_reference(jit.product_reference).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
embed_vpn = app.new_copy_files_build_phase('Embed Local Tunnel')
embed_vpn.dst_subfolder_spec = '13'
embed_vpn.add_file_reference(vpn.product_reference).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

system('python3', File.join(__dir__, 'configure-bundle.py'), utm, bundle) or abort 'Bundle metadata configuration failed'

# The source build must retain the Omarchy icon used by the installed app.
icon = File.join(utm, 'Platform/AppIcon.icon')
FileUtils.cp(File.join(root, 'ios/Artwork/OmarchyMark.svg'), File.join(icon, 'Assets/OmarchyMark.svg'))
FileUtils.cp(File.join(root, 'ios/Artwork/icon.json'), File.join(icon, 'icon.json'))
legacy_icon = File.join(utm, 'Platform/Assets.xcassets/AppIcon.appiconset')
if File.directory?(legacy_icon)
  FileUtils.cp(File.join(root, 'ios/Artwork/OmarchyAppIcon.png'), File.join(legacy_icon, 'OmarchyAppIcon.png'))
  File.write(File.join(legacy_icon, 'Contents.json'), JSON.pretty_generate({
    'images' => [{ 'filename' => 'OmarchyAppIcon.png', 'idiom' => 'universal', 'platform' => 'ios', 'size' => '1024x1024' }],
    'info' => { 'author' => 'xcode', 'version' => 1 }
  }))
end
project.save
puts 'Integrated pairing, JIT helper, local tunnel, notices and Omarchy artwork.'
