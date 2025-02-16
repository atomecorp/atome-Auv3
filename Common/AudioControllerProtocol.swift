//
//  AudioControllerProtocol.swift
//  atome
//
//  Created by jeezs on 16/02/2025.
//

import Foundation

public protocol AudioControllerProtocol: AnyObject {
    func toggleMute()
    func setMute(_ muted: Bool)
    var isMuted: Bool { get }
}
