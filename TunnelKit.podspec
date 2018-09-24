Pod::Spec.new do |s|
    s.name              = "TunnelKit"
    s.version           = File.read("ci/VERSION")
    s.summary           = "Non-official OpenVPN client for Apple platforms."

    s.homepage          = "https://github.com/keeshux/tunnelkit"
    s.license           = { :type => "GPLv3", :file => "LICENSE" }
    s.author            = { "Davide De Rosa" => "keeshux@gmail.com" }
    s.source            = { :git => "https://github.com/keeshux/tunnelkit.git", :tag => "v#{s.version}" }

    s.ios.deployment_target = "9.0"
    s.osx.deployment_target = "10.11"

    s.subspec "Core" do |p|
        p.source_files          = "TunnelKit/Sources/Core/**/*.{h,m,swift}"
        p.private_header_files  = "TunnelKit/Sources/Core/**/*.h"
        p.preserve_paths        = "TunnelKit/Sources/Core/*.modulemap"
        p.pod_target_xcconfig   = { "SWIFT_INCLUDE_PATHS" => "${PODS_TARGET_SRCROOT}/TunnelKit/Sources/Core",
                                    "APPLICATION_EXTENSION_API_ONLY" => "YES" }
        p.dependency "SwiftyBeaver"
        p.dependency "OpenSSL-Apple", "~> 1.1.0h"
    end

    s.subspec "AppExtension" do |p|
        p.source_files          = "TunnelKit/Sources/AppExtension/**/*.swift"
        p.frameworks            = "NetworkExtension"
        p.pod_target_xcconfig   = { "APPLICATION_EXTENSION_API_ONLY" => "YES" }

        p.dependency "TunnelKit/Core"
        p.dependency "SwiftyBeaver"
    end
end
