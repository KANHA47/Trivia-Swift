//
//  OCRVC.swift
//  Trivia Swift
//
//  Created by Nino Vitale on 6/26/18.
//  Copyright © 2018 Gordon Jacobs. All rights reserved.
//

import Cocoa
import Alamofire
import SwiftyJSON

class OCRVC: NSViewController {
    @IBOutlet private weak var nextGameInfoLabel: NSTextField!
    @IBOutlet private weak var fixedQuestionLabel: NSTextField!
    @IBOutlet private weak var fixedAnswer1Label: NSTextField!
    @IBOutlet private weak var fixedAnswer2Label: NSTextField!
    @IBOutlet private weak var fixedAnswer3Label: NSTextField!
    @IBOutlet private weak var fixedBestAnswerLabel: NSTextField!
    @IBOutlet private weak var questionLabel: NSTextField!
    @IBOutlet private weak var answer1Label: NSTextField!
    @IBOutlet private weak var answer2Label: NSTextField!
    @IBOutlet private weak var answer3Label: NSTextField!
    @IBOutlet private weak var bestAnswerLabel: NSTextField!
    @IBOutlet private weak var discordSV: NSStackView!
    
    private var fixedLabels: [NSTextField] = []
    private var answerLabels: [NSTextField] = []
    private var discordVoteBoxes: [NSBox] = []
    
    lazy var dialog = NSOpenPanel()
    let requestURL = "https://vision.googleapis.com/v1/images:annotate?key=\(Config.googleAPIKey)"
    
    let headers: HTTPHeaders = [
        "Content-Type": "application/json",
        "X-Ios-Bundle-Identifier": Bundle.main.bundleIdentifier ?? ""
    ]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        fixedLabels = [fixedQuestionLabel, fixedAnswer1Label, fixedAnswer2Label, fixedAnswer3Label, fixedBestAnswerLabel]
        answerLabels = [answer1Label, answer2Label, answer3Label]
        
        discordVoteBoxes = discordSV.arrangedSubviews as! [NSBox]
        
        SiteEncoding.addGoogleAPICredentials(apiKeys: [Config.googleAPIKey],
                                             searchEngineID: Config.googleSearchEngineID)
    }
    
    @IBAction func takeScreenshot(_ sender: NSButton) {
        let path = "/usr/sbin/screencapture"
        let arguments = ["-i", "-x", "-c"] // region capture, disable sounds and copy selection to clipboard
        
        let task = Process.launchedProcess(launchPath: path, arguments: arguments)
        task.waitUntilExit()
        
        guard let imageBase64String = NSPasteboard.general.pasteboardItems?.last?.data(forType: .png)?.base64EncodedString() else {
            return
        }
        
        self.uploadImageToVisionAPI(with: imageBase64String)
    }
    
    func uploadImageToVisionAPI(with base64Image: String) {
        let requestBody: [String: Any] = [
            "requests": [
                "image": [
                    "content": base64Image
                ],
                "features": [
                    "type": "TEXT_DETECTION"
                ]
            ]
        ]
        
        Alamofire.request(requestURL,
                          method: .post,
                          parameters: requestBody,
                          encoding: JSONEncoding.default,
                          headers: headers)
            .responseJSON { [unowned self] response in
                guard let result = response.result.value else { return }
                let json = JSON(result)
                
                let parsedText = json["responses"][0]["textAnnotations"][0]["description"].stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // 1. remove "prize for this question" stuff for CS
                // 2. start from the end of the string, then flip 1 and 3 in the array of answers
                // 3. the rest is the question
                // 4. ???
                // 5. profit!!!
                
                let prizePattern = "Prize for this question: *[\\$\\£\\€][0-9,.]+"
                let noPrizeString = parsedText.replacingOccurrences(of: prizePattern, with: "", options: .regularExpression)
                var separatedString = noPrizeString.components(separatedBy: "\n")
                var answers: [Answer] = []
                for index in stride(from: 3, through: 1, by: -1) {
                    answers.append(Answer(id: UInt64(index),
                                          text: separatedString.popLast()!))
                }
                answers.reverse()
                let question = separatedString.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                
                print(question)
            
                self.questionLabel.stringValue = question
                for (index, label) in self.answerLabels.enumerated() {
                    label.stringValue = answers[index].text
                }
                
                let answerText = answers.compactMap { ($0.id, $0.text ) }
                AnswerController.answer(for: question, answers: answerText, completion: { answerResult in
                    answerResult.forEach { answers[$0.id]?.updateProbability(prob: $0.probability) }
                    
                    let formattedAnswers = answers.compactMap { String(describing: $0) }
                    print(formattedAnswers)
                    
                    for (index, label) in self.answerLabels.enumerated() {
                        label.stringValue = formattedAnswers[index]
                    }
                    
                    self.bestAnswerLabel.stringValue = answers.highest!.text + " (\(answers.highest!.probability.rounded)% confidence)"
                    
                })
        }
    }
}
