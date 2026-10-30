import Foundation
import RecommenderCore

// Offline evaluation: reads an exported EngineInput (JSON), hides the last N completed titles, and reports
// Recall@20 / NDCG@10 per source and for the blend against the baselines. Usage: RecEval input.json [--holdout 30]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

var path: String?
var holdout = 30
var arguments = CommandLine.arguments.dropFirst()[...]
while let argument = arguments.popFirst() {
    switch argument {
    case "--holdout":
        guard let value = arguments.popFirst().flatMap({ Int($0) }), value > 0 else {
            fail("--holdout: нужно положительное число")
        }
        holdout = value
    case "-h", "--help":
        print("Использование: RecEval input.json [--holdout 30]")
        exit(0)
    default:
        if argument.hasPrefix("-") { fail("Неизвестный флаг: \(argument)") }
        path = argument
    }
}
guard let path else { fail("Использование: RecEval input.json [--holdout 30]") }

let data: Data
do {
    data = try Data(contentsOf: URL(fileURLWithPath: path))
} catch {
    fail("Не удалось прочитать \(path): \(error.localizedDescription)")
}
let input: EngineInput
do {
    input = try JSONDecoder().decode(EngineInput.self, from: data)
} catch {
    fail("Файл не похож на EngineInput: \(error)")
}

let report = Evaluator.evaluate(input, holdout: holdout)

func pad(_ text: String, _ width: Int, right: Bool = false) -> String {
    let count = text.count
    guard count < width else { return text }
    let space = String(repeating: " ", count: width - count)
    return right ? space + text : text + space
}

func number(_ value: Double, _ digits: Int = 3) -> String {
    String(format: "%.\(digits)f", value)
}

print("RecEval · пул \(report.poolSize) · отложено \(report.heldOut.count) из \(holdout)")
if report.heldOut.isEmpty {
    print("Нет досмотренных тайтлов из пула: проверять нечего.")
    exit(0)
}
let header = [
    pad("Метод", 30), pad("Recall@\(report.recallK)", 10, right: true), pad("NDCG@\(report.ndcgK)", 9, right: true),
    pad("Coverage", 9, right: true), pad("Novelty", 8, right: true), pad("ILD", 6, right: true),
    pad("Список", 7, right: true),
].joined(separator: " ")
print(header)
print(String(repeating: "─", count: header.count))
for row in report.rows {
    print([
        pad(row.name, 30), pad(number(row.recall), 10, right: true), pad(number(row.ndcg), 9, right: true),
        pad(number(row.coverage), 9, right: true), pad(number(row.novelty, 1), 8, right: true),
        pad(number(row.diversity, 2), 6, right: true), pad(String(row.listSize), 7, right: true),
    ].joined(separator: " "))
}
let stages = report.timings.sorted { $0.key < $1.key }.map { "\($0.key) \(number($0.value, 1))" }
print("\nВремя, мс: " + stages.joined(separator: " · "))
if let blend = report.row(Evaluator.blend), let popular = report.row(Evaluator.popularity),
   let watchAlso = report.row(Evaluator.watchAlso)
{
    let beats = blend.ndcg > popular.ndcg && blend.ndcg > watchAlso.ndcg
    print(beats ? "Смесь лучше обоих бейзлайнов по NDCG@\(report.ndcgK)." : "Смесь НЕ лучше бейзлайнов по NDCG@\(report.ndcgK): нужна настройка весов.")
}
