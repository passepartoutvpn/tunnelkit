source 'https://github.com/CocoaPods/Specs.git'
use_frameworks!

def shared_pods
    pod 'SwiftyBeaver'
    pod 'OpenSSL-Apple', '~> 1.1.1d.5a'
    #pod 'OpenSSL-Apple', :path => '../../personal/openssl-apple'
end

abstract_target 'TunnelKit' do
    target 'TunnelKit-iOS' do
        platform :ios, '11.0'
        shared_pods
    end
    target 'TunnelKitTests-iOS' do
        platform :ios, '11.0'
    end
    target 'TunnelKitHost' do
        platform :ios, '11.0'
    end

    target 'TunnelKit-macOS' do
        platform :osx, '10.11'
        shared_pods
    end
    target 'TunnelKitTests-macOS' do
        platform :osx, '10.11'
    end
end
