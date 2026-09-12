import NetworkExtension

// Adapted from SideStore/StosVPN's TunnelProv (MIT, attribution required —
// see README): a loopback NAT rewrite so the app can reach the device's own
// developer services at a fixed local address instead of installing a
// separate VPN app.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    var tunnelDeviceIp = "10.7.0.0"
    var tunnelFakeIp = "10.7.0.1"
    var tunnelSubnetMask = "255.255.255.0"

    private var deviceIpValue: UInt32 = 0
    private var fakeIpValue: UInt32 = 0

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        if let deviceIp = options?["TunnelDeviceIP"] as? String {
            tunnelDeviceIp = deviceIp
        }
        if let fakeIp = options?["TunnelFakeIP"] as? String {
            tunnelFakeIp = fakeIp
        }

        deviceIpValue = ipToUInt32(tunnelDeviceIp)
        fakeIpValue = ipToUInt32(tunnelFakeIp)

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: tunnelDeviceIp)
        let ipv4 = NEIPv4Settings(addresses: [tunnelDeviceIp], subnetMasks: [tunnelSubnetMask])
        ipv4.includedRoutes = [NEIPv4Route(destinationAddress: tunnelDeviceIp, subnetMask: tunnelSubnetMask)]
        ipv4.excludedRoutes = [.default()]
        settings.ipv4Settings = ipv4

        setTunnelNetworkSettings(settings) { error in
            guard error == nil else { return completionHandler(error) }
            self.readAndRewritePackets()
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    private func readAndRewritePackets() {
        packetFlow.readPackets { [self] packets, protocols in
            let fakeIp = fakeIpValue
            let deviceIp = deviceIpValue
            var modified = packets
            for i in modified.indices where protocols[i].int32Value == AF_INET && modified[i].count >= 20 {
                modified[i].withUnsafeMutableBytes { bytes in
                    guard let ptr = bytes.baseAddress?.assumingMemoryBound(to: UInt32.self) else { return }
                    let src = UInt32(bigEndian: ptr[3])
                    let dst = UInt32(bigEndian: ptr[4])
                    if src == deviceIp { ptr[3] = fakeIp.bigEndian }
                    if dst == fakeIp { ptr[4] = deviceIp.bigEndian }
                }
            }
            self.packetFlow.writePackets(modified, withProtocols: protocols)
            readAndRewritePackets()
        }
    }

    private func ipToUInt32(_ ipString: String) -> UInt32 {
        let components = ipString.split(separator: ".")
        guard components.count == 4,
              let b1 = UInt32(components[0]),
              let b2 = UInt32(components[1]),
              let b3 = UInt32(components[2]),
              let b4 = UInt32(components[3])
        else {
            return 0
        }
        return (b1 << 24) | (b2 << 16) | (b3 << 8) | b4
    }
}
