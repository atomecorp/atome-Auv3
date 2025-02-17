//
//  AudioControllerProtocol.swift
//  atome
//
//  Created by jeezs on 16/02/2025.
//

import Foundation

public protocol AudioControllerProtocol: AnyObject {
    var isMuted: Bool { get }
    func toggleMute()
    func setMute(_ muted: Bool)
}
