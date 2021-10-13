Pod::Spec.new do |s|
    s.name              = "TunnelKit"
    s.version           = "3.5.0"
    s.summary           = "VPN client library for Apple platforms."

    s.homepage          = "https://github.com/passepartoutvpn/tunnelkit"
    s.license           = { :type => "GPLv3", :file => "LICENSE" }
    s.author            = { "Davide De Rosa" => "me@davidederosa.com" }
    s.source            = { :git => "https://github.com/passepartoutvpn/tunnelkit.git", :tag => "v#{s.version}" }
    s.swift_version     = "5.1"

    s.ios.deployment_target = "12.0"
    s.osx.deployment_target = "10.15"

    s.default_subspecs = "Protocols/OpenVPN"

    s.subspec "Core" do |p|
        p.source_files          = "TunnelKit/Sources/Core/**/*.{h,m,swift}"
        p.private_header_files  = "TunnelKit/Sources/Core/**/*.h"
        p.preserve_paths        = "TunnelKit/Sources/Core/*.modulemap"
        p.pod_target_xcconfig   = { "SWIFT_INCLUDE_PATHS" => "${PODS_TARGET_SRCROOT}/TunnelKit/Sources/Core",
                                    "APPLICATION_EXTENSION_API_ONLY" => "YES" }
        p.dependency "SwiftyBeaver"
        p.libraries = "resolv"
    end

    s.subspec "AppExtension" do |p|
        p.source_files          = "TunnelKit/Sources/AppExtension/**/*.swift"
        p.frameworks            = "NetworkExtension"
        p.pod_target_xcconfig   = { "APPLICATION_EXTENSION_API_ONLY" => "YES" }

        p.dependency "SwiftyBeaver"
        p.dependency "TunnelKit/Core"
    end

    s.subspec "Manager" do |p|
        p.source_files          = "TunnelKit/Sources/Manager/**/*.swift"
        p.frameworks            = "NetworkExtension"

        p.dependency "SwiftyBeaver"
    end

    s.subspec "Protocols" do |t|
        t.subspec "OpenVPN" do |p|
            p.source_files          = "TunnelKit/Sources/Protocols/OpenVPN/**/*.{h,m,swift}"
            p.private_header_files  = "TunnelKit/Sources/Protocols/OpenVPN/**/*.h"
            p.preserve_paths        = "TunnelKit/Sources/Protocols/OpenVPN/*.modulemap"
            p.pod_target_xcconfig   = { "OTHER_LDFLAGS" => "-framework openssl",
                                        "SWIFT_INCLUDE_PATHS" => "${PODS_TARGET_SRCROOT}/TunnelKit/Sources/Protocols/OpenVPN",
                                        "APPLICATION_EXTENSION_API_ONLY" => "YES" }

            p.dependency "OpenSSL-Apple", "~> 1.1.1l.11"
            p.dependency "TunnelKit/Core"
            p.dependency "TunnelKit/AppExtension"
            p.dependency "TunnelKit/Manager"
        end
    end

    s.subspec "Extra" do |t|
        t.subspec "LZO" do |p|
            p.source_files          = "TunnelKit/Sources/Core/LZO.h",
                                      "TunnelKit/Sources/Core/Errors.{h,m}",
                                      "TunnelKit/Sources/Extra/LZO/*.{h,m}",
                                      "TunnelKit/Sources/Extra/LZO/lib/*lzo*.{h,m,c}"
            p.private_header_files  = "TunnelKit/Sources/Core/LZO.h",
                                      "TunnelKit/Sources/Core/Errors.h",
                                      "TunnelKit/Sources/Extra/LZO/*.h",
                                      "TunnelKit/Sources/Extra/LZO/lib/*lzo*.h"
            p.pod_target_xcconfig   = { "APPLICATION_EXTENSION_API_ONLY" => "YES" }
        end
    end
end
