source 'https://github.com/CocoaPods/Specs.git'
use_frameworks!

def shared_pods
    pod 'SwiftyBeaver'
    pod 'OpenSSL-Apple', '~> 1.1.1l.11'
end

def demo_pods
    pod 'SwiftyBeaver'
end

abstract_target 'ios' do
    platform :ios, '12.0'
    target 'TunnelKit-iOS' do
        shared_pods
    end
    target 'TunnelKitTests-iOS' do
    end
    target 'TunnelKitHost' do
    end
    target 'TunnelKitDemo-iOS' do
        demo_pods
    end
    target 'TunnelKitDemoTunnel-iOS' do
    end
end

abstract_target 'macos' do
    platform :osx, '10.15'
    target 'TunnelKit-macOS' do
        shared_pods
    end
    target 'TunnelKitTests-macOS' do
    end
    target 'TunnelKitDemo-macOS' do
        demo_pods
    end
    target 'TunnelKitDemoTunnel-macOS' do
    end
end
