// Viewer-based neighbours from MovieLens: «those who liked X also liked Y», for the recommender's data pack.
//
//   unzip -p movielens/ml-32m.zip ml-32m/ratings.csv | swift -O scripts/datapack/neighbours.swift \
//       movielens/links.csv build/datapack/neighbours.tsv
//
// A rating of 4 or more is a like. The most liked films (up to `itemLimit`) get up to `keep` neighbours each, by
// cosine over the users who liked both, each user weighted 1/log₂(2 + their likes) (someone who likes two thousand
// films says less about any two of them), shrunk by the number of such users (n / (n + shrink)) so that a pair
// a dozen people share doesn't outrank one thousands share. Out: one line per film,
//   imdb  likes  meanRating  other:score,other:score…
// with IMDb ids as numbers (no «tt»). MovieLens data stays on this Mac: only these lists go into the pack.

import Foundation

let itemLimit = 15_000
let keep = 50
let minShared = 8
let shrink = 40.0

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: … | neighbours.swift links.csv out.tsv\n".utf8))
    exit(1)
}

// links.csv: movieId,imdbId,tmdbId
var imdbOf: [Int32: Int32] = [:]
for line in try String(contentsOfFile: arguments[1], encoding: .utf8).split(whereSeparator: \.isNewline).dropFirst() {
    let parts = line.split(separator: ",", omittingEmptySubsequences: false)
    if parts.count >= 2, let movie = Int32(parts[0]), let imdb = Int32(parts[1]) { imdbOf[movie] = imdb }
}

// ratings.csv from stdin: userId,movieId,rating,timestamp (sorted by user).
var likesByUser: [[Int32]] = []
var current: [Int32] = []
var currentUser: Int32 = -1
var likeCount: [Int32: Int32] = [:]
var ratingSum: [Int32: Double] = [:]
var ratingCount: [Int32: Int32] = [:]
var lines = 0

func flush() {
    if !current.isEmpty { likesByUser.append(current) }
    current = []
}

while let line = readLine(strippingNewline: true) {
    lines += 1
    if lines == 1, line.hasPrefix("userId") { continue }
    var fields = line.split(separator: ",", maxSplits: 3, omittingEmptySubsequences: false).makeIterator()
    guard let u = fields.next().flatMap({ Int32($0) }), let m = fields.next().flatMap({ Int32($0) }),
          let r = fields.next().flatMap({ Double($0) }) else { continue }
    if u != currentUser {
        flush()
        currentUser = u
    }
    ratingSum[m, default: 0] += r
    ratingCount[m, default: 0] += 1
    if r >= 4 {
        current.append(m)
        likeCount[m, default: 0] += 1
    }
    if lines % 5_000_000 == 0 { FileHandle.standardError.write(Data("  \(lines / 1_000_000)M ratings\n".utf8)) }
}
flush()
FileHandle.standardError.write(Data("\(lines) ratings, \(likesByUser.count) users with likes\n".utf8))

// The most liked films that have an IMDb id, as dense indices.
let items = likeCount.filter { imdbOf[$0.key] != nil }.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
    .prefix(itemLimit).map(\.key)
var index: [Int32: Int32] = [:]
for (i, movie) in items.enumerated() { index[movie] = Int32(i) }
let n = items.count

// Users → liked items (indices), and each item's users, with each user's weight.
var userItems: [[Int32]] = []
var userWeight: [Float] = []
var itemUsers = [[Int32]](repeating: [], count: n)
for likes in likesByUser {
    let mapped = likes.compactMap { index[$0] }
    guard mapped.count >= 2 else { continue }
    let user = Int32(userItems.count)
    userItems.append(mapped)
    userWeight.append(Float(1 / log2(2 + Double(mapped.count))))
    for item in mapped { itemUsers[Int(item)].append(user) }
}
likesByUser = []

// Each item's weighted norm.
var norm = [Float](repeating: 0, count: n)
for i in 0..<n {
    var sum: Float = 0
    for user in itemUsers[i] { sum += userWeight[Int(user)] * userWeight[Int(user)] }
    norm[i] = sum.squareRoot()
}

var out = ""
out.reserveCapacity(n * 600)
var dot = [Float](repeating: 0, count: n)
var shared = [Int32](repeating: 0, count: n)
var touched: [Int32] = []
for i in 0..<n {
    touched.removeAll(keepingCapacity: true)
    for user in itemUsers[i] {
        let w = userWeight[Int(user)]
        for j in userItems[Int(user)] where j != Int32(i) {
            if shared[Int(j)] == 0 { touched.append(j) }
            shared[Int(j)] += 1
            dot[Int(j)] += w * w
        }
    }
    var scored: [(Int32, Float)] = []
    scored.reserveCapacity(touched.count)
    for j in touched {
        let c = shared[Int(j)]
        if c >= minShared, norm[i] > 0, norm[Int(j)] > 0 {
            let cosine = dot[Int(j)] / (norm[i] * norm[Int(j)])
            let confidence = Float(Double(c) / (Double(c) + shrink))
            scored.append((j, cosine * confidence))
        }
        shared[Int(j)] = 0
        dot[Int(j)] = 0
    }
    scored.sort { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
    let movie = items[i]
    let imdb = imdbOf[movie] ?? 0
    let mean = Double(ratingSum[movie] ?? 0) / Double(max(1, ratingCount[movie] ?? 1))
    let list = scored.prefix(keep).map { "\(imdbOf[items[Int($0.0)]] ?? 0):\(String(format: "%.4f", $0.1))" }.joined(separator: ",")
    out += "\(imdb)\t\(likeCount[movie] ?? 0)\t\(String(format: "%.2f", mean))\t\(list)\n"
    if i % 1000 == 0 { FileHandle.standardError.write(Data("  \(i)/\(n)\n".utf8)) }
}
try out.write(toFile: arguments[2], atomically: true, encoding: .utf8)
FileHandle.standardError.write(Data("\(n) films → \(arguments[2])\n".utf8))
