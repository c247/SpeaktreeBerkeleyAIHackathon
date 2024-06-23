import SwiftUI

struct WordFrequencyView: View {
    var transcript: String
    let commonWords: Set<String> = ["a", "an", "the", "and", "or", "but", "if", "of", "at", "by", "for", "with", "to", "in", "on", "he", "she", "it", "they", "them"]
    @State private var excludeCommonWords = false

    var topWordFrequencies: [(word: String, count: Int)] {
        let words = transcript.lowercased().split { !$0.isLetter }.map(String.init)
        let filteredWords: [String]
        
        if excludeCommonWords {
            filteredWords = words.filter { word in
                !commonWords.contains(word) && word.count > 3
            }
        } else {
            filteredWords = words
        }
        
        let wordCounts = Dictionary(filteredWords.map { ($0, 1) }, uniquingKeysWith: +)
        let sortedWordCounts = wordCounts.sorted { $0.value > $1.value }
        let topWords = sortedWordCounts.prefix(5)
        return topWords.map { (word: $0.key, count: $0.value) }
    }


    
    var maxCount: Int {
        topWordFrequencies.first?.count ?? 0
    }
    
    var questions: [String] {
        extractQuestions(from: transcript)
        
    }

    var body: some View {
        ScrollView {
            VStack {
               Toggle("Exclude common words", isOn: $excludeCommonWords)
                   .padding()

                Text("Top Word Frequencies")
                    .font(.headline)
                    .padding(.top)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 12) {
                        ForEach(topWordFrequencies, id: \.word) { word, count in
                            BarView(word: word, count: count, maxCount: maxCount)
                        }
                    }
                    .padding()
                }
                
                Text("Recording")
                    .font(.headline)
                    .padding(.top)
                                
                Text(transcript)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(5)
                    .padding(.horizontal)
                
                ScoreDisplayView(score: fleschReadingEase())

            }
        }
        .navigationBarTitle("Analysis", displayMode: .inline)
    }
    
    func extractQuestions(from text: String) -> [String] {
        let pattern = #"[\w\s,'"-]+[?]"#
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let results = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            return results.map {
                String(text[Range($0.range, in: text)!])
            }
        } catch {
            print("Invalid regex: \(error.localizedDescription)")
            return []
        }
    }
}

struct BarView: View {
    var word: String
    var count: Int
    var maxCount: Int
    
    var body: some View {
        VStack {
            Text("\(count)")
                .font(.caption)
            
            Rectangle()
                .fill(Color.blue)
                .frame(width: 100, height: CGFloat(count) / CGFloat(maxCount) * 200)
            
            Text(word)
                .font(.caption)
                .lineLimit(1)
        }
    }
}


extension WordFrequencyView {
    func fleschReadingEase() -> Double {
        let words = transcript.split { !$0.isLetter }.map(String.init)
        let sentenceCount = transcript.components(separatedBy: CharacterSet(charactersIn: ".!?")).filter { !$0.isEmpty }.count
        let syllableCount = words.reduce(0) { $0 + $1.syllableCount() }
        let wordCount = words.count

        let score = 206.835 - 1.015 * (Double(wordCount) / Double(sentenceCount)) - 84.6 * (Double(syllableCount) / Double(wordCount))
        return score
    }
}


extension String {
    func syllableCount() -> Int {
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
        let word = self.lowercased()
        let characters = Array(word)
        var syllableCount = 0
        let length = characters.count

        for i in 0..<length {
            if vowels.contains(characters[i]) {
                if i == length - 1 && characters[i] == "e" {
                    continue
                }
                if i > 0 && vowels.contains(characters[i - 1]) {
                    continue
                }
                syllableCount += 1
            }
        }

        return max(syllableCount, 1)
    }
}

struct ScoreDisplayView: View {
    let score: Double
    
    private func scoreExplanation() -> String {
        switch score {
        case 90...100:
            return "Very Easy - Like listening to a casual conversation. It feels natural and effortless to follow."
        case 80..<90:
            return "Easy - Like hearing a friend explain something clearly. It's comfortable and straightforward to understand."
        case 70..<80:
            return "Fairly Easy - Comparable to a well-told story. Engaging and easy to listen to, without needing much effort."
        case 60..<70:
            return "Standard - Similar to a professional presentation. Clear enough, but requires a bit more focus to grasp everything."
        case 50..<60:
            return "Fairly Difficult - Like a technical discussion in a familiar field. Understandable, but demands attention and some prior knowledge."
        case 30..<50:
            return "Difficult - Equivalent to an academic lecture on a complex topic. It can be challenging and might require additional context to fully appreciate."
        case 0..<30:
            return "Very Difficult - Like listening to an expert speak in highly specialized language. It's dense and requires significant effort or expertise to follow."
        default:
            return "Score out of range - The clarity of the speech cannot be determined without a proper score."
        }

    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Flesch Score: \(score, specifier: "%.2f")")
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .background(Color.blue)
                .cornerRadius(10)
            
            Text(scoreExplanation())
                .padding()
                .background(Color.blue)
                .cornerRadius(10)
                .shadow(radius: 1)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

