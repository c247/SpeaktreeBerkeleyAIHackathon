import SwiftUI
import SwiftOpenAI
import Speech
import AVFoundation

enum APIProvider: String, CaseIterable {
    case openAI = "OpenAI"
    case cohere = "Cohere"
}

struct ContentView: View {
    @State private var isRecording = false
    @State private var recognizedText = ""
    @State private var gpt3ResponseLines: [String] = []
    @State private var isLoading = false
    @State private var textID = UUID()
    @State private var lastQueriedWordCount = 0
    @State private var showWordFrequencyView = false
    @State private var speechRate: Double = 0
    @State private var fullTranscript = ""
    @State private var sessionManager = RecordingSessionManager()
    @State private var showAlert = false
    @State private var recognitionTask: SFSpeechRecognitionTask?
    @State private var recordingStopped = false
    @State private var selectedAPIProvider: APIProvider = .openAI
    @State private var showQuestionPopup = false
    @State private var questionText = ""

    private let speechRecognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    public var openAI = SwiftOpenAI(apiKey: "")
    
    var body: some View {
        VStack(spacing: 20) {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.5)
            }
            
            Picker("Select API", selection: $selectedAPIProvider) {
                ForEach(APIProvider.allCases, id: \.self) { provider in
                    Text(provider.rawValue).tag(provider)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()

            ScrollView {
                VStack(spacing: 20) {
                    ForEach(Array(gpt3ResponseLines.prefix(5)).indices, id: \.self) { index in
                        Text(gpt3ResponseLines[index])
                            .lineLimit(3)
                            .padding()
                            .background(Color.white.opacity(0.5))
                            .cornerRadius(10)
                            .padding(.horizontal)
                            .padding(.bottom, 5)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack {
                ScrollViewReader { scrollView in
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(recognizedText)
                            .id(textID)
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.2)))
                            .onChange(of: recognizedText) { _ in
                                withAnimation {
                                    scrollView.scrollTo(textID, anchor: .trailing)
                                }
                                textID = UUID()
                            }
                    }
                    .frame(height: 150)
                    .padding(.horizontal)
                }

                HStack(spacing: 20) {
                    if !isRecording {
                        Button(action: startRecording) {
                            Label("Record", systemImage: "mic.fill")
                                .labelStyle(.iconOnly)
                                .foregroundColor(.white)
                                .padding()
                                .background(LinearGradient(gradient: Gradient(colors: [Color.green, Color.cyan]), startPoint: .leading, endPoint: .trailing))
                                .cornerRadius(10)
                                .clipShape(Circle())
                                .shadow(radius: 10)
                        }
                    }
                    if isRecording {
                        Button(action: stopRecording) {
                            Label("Stop", systemImage: "stop.fill")
                                .labelStyle(.iconOnly)
                                .foregroundColor(.white)
                                .padding()
                                .background(LinearGradient(gradient: Gradient(colors: [Color.red, Color.orange]), startPoint: .leading, endPoint: .trailing))
                                .cornerRadius(10)
                                .clipShape(Circle())
                                .shadow(radius: 10)
                        }
                    }
                    Button("Analysis") {
                        self.showWordFrequencyView = true
                    }
                    .buttonStyle(GradientButtonStyle(startColor: Color.purple, endColor: Color.blue, isEnabled: recordingStopped))
                    .disabled(!recordingStopped)
                    Button("Get Question") {
                        Task {
                            await showQuestionPopupPrompt()
                        }
                    }
                    .buttonStyle(GradientButtonStyle(startColor: Color.orange, endColor: Color.yellow))
                }
                .padding(.bottom, 5)
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .alert("Limit Reached", isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("You have reached your daily limit of 5 recording sessions.")
            }
            .sheet(isPresented: $showQuestionPopup) {
                QuestionPopupView(questionText: questionText, isPresented: $showQuestionPopup)
            }
        }
        
        NavigationLink(destination: WordFrequencyView(transcript: fullTranscript), isActive: $showWordFrequencyView) {
            EmptyView()
        }
    }

    private func getLastFiveWords(_ text: String) -> String {
        let words = text.split(separator: " ")
        if words.count >= 15 {
            let lastFive = words.suffix(15)
            return lastFive.joined(separator: " ")
        } else {
            return text
        }
    }

    func extractQuestion(from text: String) -> String {
        let questionRegex = #"([^?!.]*\?)"#
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        
        if let questionRange = try? NSRegularExpression(pattern: questionRegex)
            .firstMatch(in: text, options: [], range: range)?.range {
            return (text as NSString).substring(with: questionRange)
        }
        
        return ""
    }

    private func generateResponseAndUpdateUI(inputText: String) {
        isLoading = true
        
        let words = inputText.split(separator: " ").map(String.init)
        let lastFiftyWords = words.suffix(50).joined(separator: " ")
        
        Task {
            let response: String
            switch selectedAPIProvider {
            case .openAI:
                response = await generateChatResponse(inputText: lastFiftyWords)
            case .cohere:
                response = await callSpeechHelpAPI(inputText: lastFiftyWords)
            }
            let lines = response.split(separator: "\n").map(String.init)
            let cleanedLines = lines.map(cleanLine)

            DispatchQueue.main.async {
                withAnimation {
                    self.gpt3ResponseLines.removeAll()
                    self.gpt3ResponseLines.append(contentsOf: cleanedLines)
                    self.isLoading = false
                }
            }
        }
    }

    func cleanLine(_ line: String) -> String {
        let cleanedLine = line.removePrefix("- ")
        let numberPrefixRemoved = cleanedLine.replacingOccurrences(of: #"^\d+\.\s"#, with: "", options: .regularExpression)
        return numberPrefixRemoved
    }

    private func startRecording() {
        if !sessionManager.canRecordNewSession() {
            showAlert = true
            return
        }

        isRecording = true
        recognizedText = ""
        gpt3ResponseLines = []
        lastQueriedWordCount = 0
        speechRate = 0

        let request = SFSpeechAudioBufferRecognitionRequest()
        let inputNode = audioEngine.inputNode
        let recognitionRequest = request

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.addsPunctuation = true

        try? audioEngine.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 180) {
            if self.isRecording == true {
                self.stopRecording()
            }
        }

        var wordCounts: [(time: Date, count: Int)] = []
        sessionManager.recordNewSession()
        SFSpeechRecognizer.requestAuthorization { [self] authStatus in
            if authStatus == .authorized {
                recognitionTask = self.speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
                    if let result = result {
                        let text = result.bestTranscription.formattedString
                        DispatchQueue.main.async {
                            self.recognizedText = text
                            let totalWords = text.split(separator: " ").count
                            let currentTime = Date()
                            wordCounts.append((time: currentTime, count: totalWords))

                            wordCounts = wordCounts.filter { currentTime.timeIntervalSince($0.time) <= 10 }

                            if let firstCount = wordCounts.first {
                                let wordsInWindow = totalWords - firstCount.count
                                self.speechRate = Double((wordsInWindow * 60) / 10)
                            }

                            if totalWords > lastQueriedWordCount && totalWords % 15 == 0 {
                                self.generateResponseAndUpdateUI(inputText: text)
                                self.lastQueriedWordCount = totalWords
                            }
                        }
                    }
                    if error != nil || result?.isFinal == true {
                        self.audioEngine.stop()
                        inputNode.removeTap(onBus: 0)
                        self.isRecording = false
                    }
                }

                let recordingFormat = inputNode.outputFormat(forBus: 0)
                inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                    recognitionRequest.append(buffer)
                }
            } else {
                self.isRecording = false
            }
        }
    }

    private func normalize(text: String) -> String {
        return text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { !$0.isPunctuation }
    }

    private func callSpeechHelpAPI(inputText: String) async -> String {
        guard let url = URL(string: "https://jf7n4wdqn1.execute-api.us-east-1.amazonaws.com/dev/speechHelp?prompt=\(inputText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") else {
            return ""
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let jsonResponse = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let body = jsonResponse["body"] as? [String: Any],
               let generations = body["generations"] as? [[String: Any]],
               let text = generations.first?["text"] as? String {
                return text
            }
        } catch {
            print("Error: \(error)")
        }
        
        return ""
    }

    func generateChatResponse(inputText: String) async -> String {
        let messages: [MessageChatGPT] = [
            MessageChatGPT(text: "You are a helpful assistant. Confidently give a straightforward response to the speaker, even if you don't understand them. DO NOT ask to repeat, and DO NOT ask for clarification. Just answer the speaker directly.", role: .system),
            MessageChatGPT(text: "You are a helpful assistant. Given the context of a conversation, list topics or ideas that can help take the conversation forward. Each topic or idea (keep it concise) should be on a new line. Here is the transcription of the conversation: \(inputText)", role: .user)
        ]
        
        let optionalParameters = ChatCompletionsOptionalParameters(
            temperature: 0.7,
            maxTokens: 50
        )
        
        do {
            let chatCompletions = try await openAI.createChatCompletions(
                model: .gpt4(.base),
                messages: messages,
                optionalParameters: optionalParameters
            )
            
            if let assistantReply = chatCompletions!.choices.first?.message.content {
                return assistantReply
            } else {
                return ""
            }
        } catch {
            print("Error: \(error)")
            return ""
        }
    }
    
    private func cancelRecognitionTask() {
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    func generateImageResponse(prompt: String) async -> String {
        do {
            let image = try await openAI.createImages(
                model: .dalle(.dalle3),
                prompt: prompt,
                numberOfImages: 1,
                size: .s1024
            )
            return image?.data[0].url ?? ""
        } catch {
            print("Error: \(error)")
            return ""
        }
    }

    private func stopRecording() {
        fullTranscript = recognizedText
        recognizedText = ""
        gpt3ResponseLines.removeAll()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isRecording = false
        isLoading = false
        showWordFrequencyView = true
        cancelRecognitionTask()
        lastQueriedWordCount = 0
        textID = UUID()
        recordingStopped = true
    }

    func labelColor(for rate: Double) -> Color {
        let optimalRate = 140.0
        let acceptableRange = 120.0...160.0
        let fadeStart = 40.0
        
        if acceptableRange.contains(rate) {
            let proximity = abs(rate - optimalRate)
            if proximity == 0 {
                return .green
            } else {
                let alpha = max(0, 1 - proximity / fadeStart)
                return Color.yellow.opacity(Double(alpha) * 0.5 + 0.5)
            }
        } else {
            let distance = min(abs(rate - acceptableRange.lowerBound), abs(rate - acceptableRange.upperBound))
            let alpha = max(0, 1 - distance / fadeStart)
            return Color.red.opacity(Double(alpha) * 0.5 + 0.5)
        }
    }

    private func showQuestionPopupPrompt() async {
        let prompt = "return me one interview question that I can answer to help me improve my speaking and have no other text in the output except that sentence"
        let response: String
        switch selectedAPIProvider {
        case .openAI:
            response = await generateChatResponse(inputText: prompt)
        case .cohere:
            response = await callSpeechHelpAPI(inputText: prompt)
        }
        questionText = response
        showQuestionPopup = true
    }
}

struct QuestionPopupView: View {
    var questionText: String
    @Binding var isPresented: Bool

    var body: some View {
        VStack {
            Text("Suggested Question")
                .font(.headline)
                .padding()
            Text(questionText)
                .foregroundColor(.black)
                .padding()
            Button("OK") {
                isPresented = false
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(radius: 20)
        .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

struct RecordingSessionManager {
    private let userDefaults = UserDefaults.standard
    private let sessionCountKey = "recordingSessionCount"
    private let lastSessionDateKey = "lastRecordingSessionDate"
    
    var sessionCount: Int {
        get {
            return userDefaults.integer(forKey: sessionCountKey)
        }
        set {
            userDefaults.set(newValue, forKey: sessionCountKey)
        }
    }
    
    var lastSessionDate: Date? {
        get {
            return userDefaults.object(forKey: lastSessionDateKey) as? Date
        }
        set {
            userDefaults.set(newValue, forKey: lastSessionDateKey)
        }
    }
    
    mutating func canRecordNewSession() -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        
        if let lastSessionDate = lastSessionDate, Calendar.current.isDate(lastSessionDate, inSameDayAs: today) {
            return sessionCount < 5
        } else {
            self.lastSessionDate = today
            sessionCount = 0
            return true
        }
    }
    
    mutating func recordNewSession() {
        sessionCount += 1
    }
}

extension RecordingSessionManager {
    var remainingSessions: Int {
        return max(0, 3 - sessionCount)
    }
}

struct GradientButtonStyle: ButtonStyle {
    var startColor: Color
    var endColor: Color
    var disabledColor: Color = Color.gray
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .padding()
            .background(LinearGradient(gradient: Gradient(colors: isEnabled ? [startColor, endColor] : [disabledColor, disabledColor]), startPoint: .leading, endPoint: .trailing))
            .cornerRadius(10)
            .shadow(radius: isEnabled ? 10 : 0)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(isEnabled ? 1 : 0.5)
    }
}

extension String {
    func removePrefix(_ prefix: String) -> String {
        guard self.hasPrefix(prefix) else { return self }
        return String(self.dropFirst(prefix.count))
    }
}
