//
//  AudioUnitViewController.swift
//  auv3
//
//  Created by jeezs on 26/04/2022.
//

import CoreAudioKit
import WebKit

public class AudioUnitViewController: AUViewController, AUAudioUnitFactory {
    var audioUnit: AUAudioUnit?
    @IBOutlet var webView: WKWebView!
    
   
    private var isMuted: Bool = false
    
    public override func viewDidLoad() {
        super.viewDidLoad()
      
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(webView)
        WebViewManager.setupWebView(for: webView)
    }

    public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        audioUnit = try auv3Utils(componentDescription: componentDescription, options: [])
        
        // Mute by default 
        if let au = audioUnit as? auv3Utils {
            au.mute = true
        }

        return audioUnit!
    }

    // function to catch sample rate
    func getHostSampleRate() -> Double? {
        guard let au = audioUnit, au.outputBusses.count > 0 else {
            print("No output busses available")
            return nil
        }
        return au.outputBusses[0].format.sampleRate
    }
    
    // function to control mute
    public func toggleMute() {
        if let au = audioUnit as? auv3Utils {
            au.mute.toggle()
            isMuted = au.mute
            print("Audio is now \(isMuted ? "muted" : "unmuted")")
        }
    }
    
    // function to define  mute state
    public func setMute(_ muted: Bool) {
        if let au = audioUnit as? auv3Utils {
            au.mute = muted
            isMuted = muted
            print("Audio is now \(muted ? "muted" : "unmuted")")
        }
    }
}
