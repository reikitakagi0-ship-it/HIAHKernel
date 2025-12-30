/**
 * PacketTunnelProvider.swift
 * HIAH VPN Extension - Packet Tunnel Provider
 *
 * Provides VPN loopback functionality for JIT enablement.
 * Uses em-proxy for the actual tunnel implementation.
 *
 * Based on SideStore (AGPLv3)
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under AGPLv3
 */

import NetworkExtension
import Foundation

class PacketTunnelProvider: NEPacketTunnelProvider {
    
    private var emProxyProcess: Process?
    
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        NSLog("[HIAHVPNExtension] Starting tunnel...")
        
        // Configure tunnel settings for loopback
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        
        // Configure IPv4 settings for loopback
        let ipv4Settings = NEIPv4Settings(addresses: ["10.7.0.1"], subnetMasks: ["255.255.255.0"])
        ipv4Settings.includedRoutes = [NEIPv4Route.default()]
        ipv4Settings.excludedRoutes = []
        settings.ipv4Settings = ipv4Settings
        
        // DNS settings
        let dnsSettings = NEDNSSettings(servers: ["8.8.8.8", "8.8.4.4"])
        settings.dnsSettings = dnsSettings
        
        // MTU
        settings.mtu = 1500
        
        setTunnelNetworkSettings(settings) { [weak self] error in
            if let error = error {
                NSLog("[HIAHVPNExtension] Failed to set tunnel settings: \(error)")
                completionHandler(error)
                return
            }
            
            NSLog("[HIAHVPNExtension] Tunnel settings configured")
            
            // Start em-proxy binary
            if let self = self {
                let result = self.startEMProxy()
                if result != 0 {
                    let error = NSError(domain: "HIAHVPNExtension", code: result, 
                                       userInfo: [NSLocalizedDescriptionKey: "Failed to start em-proxy (code: \(result))"])
                    NSLog("[HIAHVPNExtension] em-proxy start failed: \(error)")
                    completionHandler(error)
                    return
                }
            }
            
            NSLog("[HIAHVPNExtension] Tunnel started successfully")
            completionHandler(nil)
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        NSLog("[HIAHVPNExtension] Stopping tunnel (reason: \(reason.rawValue))")
        
        stopEMProxy()
        
        completionHandler()
    }
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // Handle messages from the main app
        if let message = String(data: messageData, encoding: .utf8) {
            NSLog("[HIAHVPNExtension] Received message: \(message)")
            
            // Handle specific commands
            if message == "status" {
                let response = "running".data(using: .utf8)
                completionHandler?(response)
                return
            }
        }
        completionHandler?(nil)
    }
    
    // MARK: - em-proxy Management
    
    private func startEMProxy() -> Int {
        // Find em-proxy binary in the extension bundle
        guard let emProxyPath = findEMProxyPath() else {
            NSLog("[HIAHVPNExtension] em-proxy binary not found")
            return -1
        }
        
        NSLog("[HIAHVPNExtension] Starting em-proxy at: \(emProxyPath)")
        
        // Start em-proxy with loopback bind address
        // em-proxy -l 127.0.0.1:65399
        let result = EMProxyBridge.startVPN(withBindAddress: "127.0.0.1:65399")
        
        if result == 0 {
            NSLog("[HIAHVPNExtension] em-proxy started successfully")
        } else {
            NSLog("[HIAHVPNExtension] em-proxy failed to start: \(result)")
        }
        
        return Int(result)
    }
    
    private func stopEMProxy() {
        NSLog("[HIAHVPNExtension] Stopping em-proxy")
        EMProxyBridge.stopVPN()
    }
    
    private func findEMProxyPath() -> String? {
        // Check in extension bundle
        if let path = Bundle.main.path(forResource: "em-proxy", ofType: nil) {
            return path
        }
        
        // Check in bin directory
        let binPath = Bundle.main.bundlePath + "/bin/em-proxy"
        if FileManager.default.fileExists(atPath: binPath) {
            return binPath
        }
        
        // Check in parent app bundle (via app group)
        let fm = FileManager.default
        if let groupURL = fm.containerURL(forSecurityApplicationGroupIdentifier: "group.com.aspauldingcode.HIAHDesktop") {
            let appBinPath = groupURL.appendingPathComponent("bin/em-proxy").path
            if fm.fileExists(atPath: appBinPath) {
                return appBinPath
            }
        }
        
        return nil
    }
}

